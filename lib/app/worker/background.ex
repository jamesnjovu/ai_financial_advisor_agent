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
end
