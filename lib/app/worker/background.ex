defmodule App.BackgroundWorker do
  @moduledoc """
  Background worker for processing tasks and handling webhooks
  """

  use GenServer
  alias App.Tasks
  alias App.Accounts
  alias App.AI.KnowledgeBase
  alias App.Webhooks.CalendarManager

  # Start the worker
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Client API
  def process_email_webhook(user_id, email_data) do
    GenServer.cast(__MODULE__, {:email_webhook, user_id, email_data})
  end

  def process_calendar_webhook(user_id, calendar_data) do
    GenServer.cast(__MODULE__, {:calendar_webhook, user_id, calendar_data})
  end

  def process_hubspot_webhook(portal_id, contact_data) do
    GenServer.cast(__MODULE__, {:hubspot_webhook, portal_id, contact_data})
  end

  @doc """
  Process Gmail history webhook - gets the actual changed messages
  """
  def process_gmail_history_webhook(user_id, pubsub_data) do
    GenServer.cast(__MODULE__, {:gmail_history_webhook, user_id, pubsub_data})
  end

  # Server callbacks
  def init(_opts) do
    # Schedule periodic task processing
    schedule_task_processing()
    schedule_webhook_maintenance()
    {:ok, %{}}
  end

  def handle_cast({:email_webhook, user_id, email_data}, state) do
    case Accounts.get_user(user_id) do
      %App.Accounts.User{} = user ->
        # Check for relevant instructions
        Tasks.check_instructions_for_trigger(user, "email_received", email_data)

        # Sync this specific email to knowledge base
        if email_id = email_data["message_id"] do
          spawn(fn -> sync_single_email(user, email_id) end)
        end

      nil ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:gmail_history_webhook, user_id, pubsub_data}, state) do
    case Accounts.get_user(user_id) do
      %App.Accounts.User{} = user ->
        # Get the history changes to find new messages
        spawn(fn -> process_gmail_history_changes(user, pubsub_data) end)

      nil ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(:gmail_webhook_maintenance, state) do
    # Refresh Gmail webhooks that are expiring
    spawn(fn -> refresh_gmail_webhooks() end)

    # Schedule next maintenance
    Process.send_after(self(), :gmail_webhook_maintenance, 60 * 60 * 1000)

    {:noreply, state}
  end

  def handle_cast({:calendar_webhook, user_id, calendar_data}, state) do
    case Accounts.get_user(user_id) do
      %App.Accounts.User{} = user ->
        # Check for relevant instructions
        Tasks.check_instructions_for_trigger(user, "calendar_event_created", calendar_data)

      nil ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:hubspot_webhook, portal_id, contact_data}, state) do
    case Accounts.get_user_by_hubspot_portal(portal_id) do
      %App.Accounts.User{} = user ->
        # Check for relevant instructions
        event_type = contact_data["event_type"] || "contact_updated"
        Tasks.check_instructions_for_trigger(user, "hubspot_#{event_type}", contact_data)

        # Sync this contact to knowledge base
        if contact_id = contact_data["contact_id"] do
          spawn(fn -> sync_single_hubspot_contact(user, contact_id) end)
        end

      nil ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(:process_tasks, state) do
    # Process pending tasks
    spawn(fn -> Tasks.process_pending_tasks() end)

    # Schedule next processing
    schedule_task_processing()

    {:noreply, state}
  end

  def handle_info(:webhook_maintenance, state) do
    # Clean up expired calendar webhook channels
    spawn(fn ->
      CalendarManager.cleanup_expired_channels()
      CalendarManager.refresh_channel_subscriptions()
    end)

    # Schedule next maintenance
    schedule_webhook_maintenance()

    {:noreply, state}
  end

  # Private functions
  defp schedule_task_processing do
    # Process tasks every 30 seconds
    Process.send_after(self(), :process_tasks, 30_000)
  end

  defp schedule_webhook_maintenance do
    # Run webhook maintenance every hour
    Process.send_after(self(), :webhook_maintenance, 60 * 60 * 1000)
  end

  defp sync_single_email(user, email_id) do
    case App.Integrations.GmailClient.get_message(user, email_id) do
      {:ok, message} ->
        email_data = App.Integrations.GmailClient.extract_email_data(message)

        content = """
        From: #{email_data.from}
        To: #{email_data.to}
        Subject: #{email_data.subject}
        Date: #{email_data.date}

        #{email_data.body}
        """

        case App.AI.OpenAI.create_embedding(content) do
          {:ok, embedding} ->
            attrs = %{
              user_id: user.id,
              source_type: "email",
              source_id: email_id,
              title: email_data.subject || "No Subject",
              content: content,
              metadata: %{
                from: email_data.from,
                to: email_data.to,
                date: email_data.date,
                thread_id: email_data.thread_id
              },
              embedding: embedding,
              last_synced_at: DateTime.utc_now()
            }

            %App.Knowledge.KnowledgeEntry{}
            |> App.Knowledge.KnowledgeEntry.changeset(attrs)
            |> App.Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :source_type, :source_id])

          {:error, _} ->
            :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp sync_single_hubspot_contact(user, contact_id) do
    case App.Integrations.HubSpotClient.get_contact(user, contact_id) do
      {:ok, contact} ->
        properties = contact["properties"] || %{}

        content = """
        HubSpot Contact: #{properties["firstname"] || ""} #{properties["lastname"] || ""}
        Email: #{properties["email"] || ""}
        Company: #{properties["company"] || ""}
        Phone: #{properties["phone"] || ""}
        Created: #{properties["createdate"] || ""}
        Last Modified: #{properties["lastmodifieddate"] || ""}
        """

        case App.AI.OpenAI.create_embedding(content) do
          {:ok, embedding} ->
            attrs = %{
              user_id: user.id,
              source_type: "hubspot_contact",
              source_id: contact_id,
              title: "#{properties["firstname"] || ""} #{properties["lastname"] || ""}".trim(),
              content: content,
              metadata: properties,
              embedding: embedding,
              last_synced_at: DateTime.utc_now()
            }

            %App.Knowledge.KnowledgeEntry{}
            |> App.Knowledge.KnowledgeEntry.changeset(attrs)
            |> App.Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :source_type, :source_id])

          {:error, _} ->
            :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp process_history_changes(_user, _), do: :ok

  defp process_potential_meeting_response(user, message_id) do
    case App.Integrations.GmailClient.get_message(user, message_id) do
      {:ok, message} ->
        email_data = App.Integrations.GmailClient.extract_email_data(message)

        # Check if this looks like a meeting response
        if is_meeting_response?(email_data) do
          # Create a task to parse and handle the meeting response
          Tasks.create_task(user, %{
            title: "Process meeting response from #{email_data.from}",
            task_type: "process_meeting_response",
            context: %{
              message_id: message_id,
              from: email_data.from,
              subject: email_data.subject,
              content: email_data.body,
              thread_id: email_data.thread_id
            }
          })
        end

      {:error, reason} ->
        Logger.error("Failed to get message #{message_id}: #{inspect(reason)}")
    end
  end

  defp process_history_changes(user, %{"history" => history_list}) when is_list(history_list) do
    # Process each history item for new messages
    Enum.each(history_list, fn history_item ->
      if messages_added = history_item["messagesAdded"] do
        Enum.each(messages_added, fn %{"message" => message} ->
          # Check if this is a reply to a scheduling email
          process_potential_meeting_response(user, message["id"])

          # Also trigger general email_received instructions
          Tasks.check_instructions_for_trigger(user, "email_received", %{
            message_id: message["id"],
            thread_id: message["threadId"]
          })
        end)
      end
    end)
  end

  defp process_gmail_history_changes(user, pubsub_data) do
    history_id = pubsub_data["historyId"]

    # Get stored history ID to see what's new
    case App.Repo.get_by(App.Webhooks.GmailChannel, user_id: user.id) do
      %{history_id: last_history_id} = channel ->
        # Get history changes since last known history ID
        case get_gmail_history_changes(user, last_history_id, history_id) do
          {:ok, changes} ->
            process_history_changes(user, changes)

            # Update stored history ID
            App.Repo.update!(
              App.Webhooks.GmailChannel.changeset(channel, %{history_id: history_id})
            )

          {:error, reason} ->
            Logger.error("Failed to get Gmail history: #{inspect(reason)}")
        end

      nil ->
        Logger.warning("No Gmail webhook channel found for user #{user.id}")
    end
  end

  defp get_gmail_history_changes(user, start_history_id, end_history_id) do
    case App.Auth.GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]

        url = "https://gmail.googleapis.com/gmail/v1/users/me/history" <>
              "?startHistoryId=#{start_history_id}&historyTypes=messageAdded"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
            {:error, "Gmail API error #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end

      error ->
        error
    end
  end

  defp is_meeting_response?(email_data) do
    subject = String.downcase(email_data.subject || "")
    body = String.downcase(email_data.body || "")

    # Check for meeting-related keywords
    meeting_keywords = ["meeting", "schedule", "time", "available", "appointment", "calendar"]
    response_keywords = ["re:", "works for me", "sounds good", "confirm", "available"]

    has_meeting_keyword = Enum.any?(meeting_keywords, &String.contains?(subject <> " " <> body, &1))
    has_response_keyword = Enum.any?(response_keywords, &String.contains?(subject <> " " <> body, &1))

    has_meeting_keyword && has_response_keyword
  end

  defp refresh_gmail_webhooks do
    # Find Gmail webhooks expiring in the next 24 hours
    expiring_soon = DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second)

    expiring_channels = App.Webhooks.expiring_channels(expiring_soon)

    Enum.each(expiring_channels, fn channel ->
      # Refresh the Gmail webhook
      case App.Integrations.GmailClient.setup_gmail_webhook(channel.user) do
        {:ok, _} ->
          Logger.info("Refreshed Gmail webhook for user #{channel.user_id}")

        {:error, reason} ->
          Logger.error("Failed to refresh Gmail webhook for user #{channel.user_id}: #{inspect(reason)}")
      end
    end)
  end
end
