defmodule App.AI.Tools do
  @moduledoc """
  Tool execution for AI agent actions
  """

  alias App.Integrations.{
    GmailClient,
    CalendarClient,
    HubSpotClient
  }

  alias App.AI.KnowledgeBase
  alias App.Tasks
  alias App.Accounts.User

  def execute_tool("search_emails", %{"query" => query}, %User{} = user) do
    case GmailClient.search_emails(user, query) do
      {:ok, %{"messages" => messages}} when is_list(messages) and length(messages) > 0 ->
        # Get detailed message info for first few results
        detailed_messages =
          messages
          |> Enum.take(5)
          |> Enum.map(fn %{"id" => id} ->
            case GmailClient.get_message(user, id) do
              {:ok, message} -> GmailClient.extract_email_data(message)
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, %{found: length(detailed_messages), emails: detailed_messages}}

      {:ok, %{"messages" => []}} ->
        {:ok, %{found: 0, emails: []}}

      {:ok, %{"resultSizeEstimate" => 0}} ->
        {:ok, %{found: 0, emails: []}}

      {:error, reason} ->
        {:error, "Email search failed: #{inspect(reason)}"}
    end
  end

  def execute_tool("setup_calendar_webhook", _params, %User{} = user) do
    case App.Webhooks.CalendarManager.setup_calendar_webhook(user) do
      {:ok, channel} ->
        {:ok, %{
          channel_id: channel.channel_id,
          expires_at: channel.expiration,
          message: "Calendar webhook setup successfully"
        }}

      {:error, reason} ->
        {:error, "Failed to setup calendar webhook: #{inspect(reason)}"}
    end
  end

  def execute_tool("setup_gmail_webhook", _params, %User{} = user) do
    case App.Integrations.GmailClient.setup_gmail_webhook(user) do
      {:ok, response} ->
        {:ok, %{
          history_id: response["historyId"],
          expires_at: response["expiration"],
          message: "Gmail webhook setup successfully - will now receive email notifications"
        }}

      {:error, reason} ->
        {:error, "Failed to setup Gmail webhook: #{inspect(reason)}"}
    end
  end

  def execute_tool("search_contacts", %{"query" => query}, %User{} = user) do
    # Search both HubSpot and knowledge base
    hubspot_results = case HubSpotClient.search_contacts(user, query) do
      {:ok, %{"results" => contacts}} -> contacts
      _ -> []
    end

    knowledge_results = case KnowledgeBase.search_relevant_content(user, query, limit: 3) do
      {:ok, results} -> results
      _ -> []
    end

    {:ok, %{
      hubspot_contacts: hubspot_results,
      knowledge_matches: knowledge_results,
      total_found: length(hubspot_results) + length(knowledge_results)
    }}
  end

  def execute_tool("schedule_meeting", params, %User{} = user) do
    %{
      "contact_email" => contact_email,
      "subject" => subject
    } = params

    duration = params["duration_minutes"] || 60
    preferred_times = params["preferred_times"] || []

    # Use preferred times if provided, otherwise find available slots
    available_slots = if Enum.any?(preferred_times) do
      # Parse preferred times and validate availability
      preferred_times
      |> Enum.map(&parse_datetime/1)
      |> Enum.reject(&is_nil/1)
      |> validate_availability(user, contact_email)
    else
      # Find available slots automatically
      case CalendarClient.find_available_slots(user, duration, [contact_email]) do
        {:ok, slots} -> slots
        _ -> []
      end
    end

    case available_slots do
      [slot_start | _] ->
        slot_end = DateTime.add(slot_start, duration * 60, :second)

        # Create calendar event
        event_data = CalendarClient.build_event(
          subject,
          slot_start,
          slot_end,
          attendees: [contact_email],
          description: "Meeting scheduled via AI Assistant"
        )

        case CalendarClient.create_event(user, event_data) do
          {:ok, event} ->
            # Send email with ACTUAL scheduled time, not preferred times
            email_body = """
            Hi,

            I've scheduled a meeting with you:

            Subject: #{subject}
            Date: #{format_date(slot_start)}
            Time: #{format_time(slot_start)} - #{format_time(slot_end)}

            The calendar invite has been sent. Looking forward to our meeting!

            Best regards,
            #{user.name || user.email}
            """

            case GmailClient.send_email(user, contact_email, "Meeting Scheduled: #{subject}", email_body) do
              {:ok, _} ->
                {:ok, %{
                  event_id: event["id"],
                  scheduled_time: slot_start,
                  end_time: slot_end,
                  email_sent: true,
                  message: "Meeting scheduled for #{format_datetime(slot_start)}"
                }}

              {:error, email_error} ->
                {:ok, %{
                  event_id: event["id"],
                  scheduled_time: slot_start,
                  end_time: slot_end,
                  email_sent: false,
                  email_error: email_error
                }}
            end

          {:error, reason} ->
            {:error, "Failed to create calendar event: #{inspect(reason)}"}
        end

      [] ->
        {:error, "No available time slots found for the requested times"}
    end
  end

  def execute_tool("send_email", params, %User{} = user) do
    %{
      "to" => to,
      "subject" => subject,
      "body" => body
    } = params

    case GmailClient.send_email(user, to, subject, body) do
      {:ok, message} ->
        {:ok, %{message_id: message["id"], sent_to: to}}

      {:error, reason} ->
        {:error, "Failed to send email: #{inspect(reason)}"}
    end
  end

  def execute_tool("create_hubspot_contact", params, %User{} = user) do
    contact_data = %{
                     "email" => params["email"],
                     "firstname" => params["firstname"],
                     "lastname" => params["lastname"],
                     "company" => params["company"],
                     "phone" => params["phone"]
                   }
                   |> Enum.reject(fn {_k, v} -> is_nil(v) end)
                   |> Map.new()

    case HubSpotClient.create_or_update_contact(user, contact_data) do
      {:ok, contact} ->
        # Add note if provided
        if notes = params["notes"] do
          HubSpotClient.create_note(user, contact["id"], notes)
        end

        {:ok, %{contact_id: contact["id"], email: contact_data["email"]}}

      {:error, reason} ->
        {:error, "Failed to create contact: #{inspect(reason)}"}
    end
  end

  def execute_tool("add_instruction", params, %User{} = user) do
    %{
      "instruction" => instruction,
      "triggers" => triggers
    } = params

    case Tasks.create_user_instruction(user, instruction, triggers) do
      {:ok, user_instruction} ->
        {:ok, %{instruction_id: user_instruction.id, instruction: instruction}}

      {:error, changeset} ->
        {:error, "Failed to add instruction: #{inspect(changeset.errors)}"}
    end
  end

  def execute_tool(tool_name, _params, _user) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp validate_availability(preferred_times, user, contact_email) do
    # Check if preferred times are actually available
    Enum.filter(preferred_times, fn preferred_time ->
      time_min = DateTime.add(preferred_time, -1 * 60 * 60, :second)
      time_max = DateTime.add(preferred_time, 2 * 60 * 60, :second)

      case CalendarClient.get_free_busy(user, [contact_email],
             DateTime.to_iso8601(time_min),
             DateTime.to_iso8601(time_max)) do
        {:ok, free_busy} ->
          # Check if the time slot is actually free
          is_time_available?(preferred_time, free_busy)

        _ ->
          false
      end
    end)
  end

  defp is_time_available?(preferred_time, free_busy) do
    # Simple check - in a real app you'd parse the free_busy response
    # For now, assume the time is available if no errors
    true
  end

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end

  defp format_time(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
  end

  defp format_datetime(datetime) do
    "#{format_date(datetime)} at #{format_time(datetime)}"
  end
end