defmodule App.AI.Tools do
  @moduledoc """
  Tool execution for AI agent actions
  """

  alias App.Integrations.{GmailClient, CalendarClient, HubSpotClient}
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

    # Find available slots
    case CalendarClient.find_available_slots(user, duration, [contact_email]) do
      {:ok, available_slots} when length(available_slots) > 0 ->
        # Take first available slot
        [slot_start | _] = available_slots
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
            # Send email notification
            email_body = """
            Hi,

            I've scheduled a meeting with you:

            Subject: #{subject}
            Date: #{DateTime.to_date(slot_start)}
            Time: #{DateTime.to_time(slot_start)} - #{DateTime.to_time(slot_end)}

            The calendar invite has been sent.

            Best regards,
            #{user.name || user.email}
            """

            case GmailClient.send_email(user, contact_email, "Meeting Scheduled: #{subject}", email_body) do
              {:ok, _} ->
                {:ok, %{
                  event_id: event["id"],
                  start_time: slot_start,
                  end_time: slot_end,
                  email_sent: true
                }}

              {:error, email_error} ->
                {:ok, %{
                  event_id: event["id"],
                  start_time: slot_start,
                  end_time: slot_end,
                  email_sent: false,
                  email_error: email_error
                }}
            end

          {:error, reason} ->
            {:error, "Failed to create calendar event: #{inspect(reason)}"}
        end

      {:ok, []} ->
        {:error, "No available time slots found"}

      {:error, reason} ->
        {:error, "Failed to check availability: #{inspect(reason)}"}
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
end