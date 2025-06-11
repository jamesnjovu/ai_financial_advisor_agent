defmodule App.Tasks.ScheduleMeetingHelper do
  alias App.Tasks.{Task, UserInstruction}

  # Helper functions for meeting scheduling
  defp extract_meeting_parameters(context) do
    try do
      # Handle different context formats
      case context do
        %{"meeting_request" => meeting_data} ->
          parse_structured_meeting_request(meeting_data)

        %{"contact_email" => email, "subject" => subject} = ctx ->
          parse_basic_meeting_context(ctx)

        %{"email_response" => email_response} ->
          parse_meeting_response_context(email_response)

        %{"instruction_context" => instruction_ctx} ->
          parse_instruction_meeting_context(instruction_ctx)

        _ ->
          parse_fallback_context(context)
      end
    rescue
      _ -> {:error, "Unable to parse meeting context"}
    end
  end

  defp parse_structured_meeting_request(meeting_data) do
    required_fields = ["contact_email", "subject"]

    if Enum.all?(required_fields, &Map.has_key?(meeting_data, &1)) do
      params = %{
        contact_email: meeting_data["contact_email"],
        contact_name: meeting_data["contact_name"] || extract_name_from_email(meeting_data["contact_email"]),
        subject: meeting_data["subject"],
        duration_minutes: meeting_data["duration_minutes"] || 60,
        preferred_time: parse_preferred_time(meeting_data["preferred_time"]),
        description: meeting_data["description"] || "Meeting scheduled via AI assistant",
        location: meeting_data["location"],
        meeting_type: meeting_data["meeting_type"] || "consultation",
        priority: meeting_data["priority"] || "normal"
      }

      {:ok, params}
    else
      {:error, "Missing required fields: #{inspect(required_fields -- Map.keys(meeting_data))}"}
    end
  end

  defp parse_basic_meeting_context(context) do
    params = %{
      contact_email: context["contact_email"],
      contact_name: context["contact_name"] || extract_name_from_email(context["contact_email"]),
      subject: context["subject"],
      duration_minutes: context["duration_minutes"] || 60,
      preferred_time: parse_preferred_time(context["preferred_time"]),
      description: context["description"] || "Meeting scheduled via AI assistant",
      location: context["location"],
      meeting_type: "consultation",
      priority: "normal"
    }

    {:ok, params}
  end

  defp parse_meeting_response_context(email_response) do
    # Parse meeting confirmation from email response
    contact_email = email_response["from"]
    subject = "Meeting: #{email_response["subject"]}"

    # Extract confirmed time from email content
    confirmed_time = extract_confirmed_time_from_response(email_response["content"])

    params = %{
      contact_email: contact_email,
      contact_name: extract_name_from_email(contact_email),
      subject: subject,
      duration_minutes: 60,
      preferred_time: confirmed_time,
      description: "Meeting confirmed via email response",
      meeting_type: "confirmed_meeting",
      priority: "high",
      original_thread_id: email_response["thread_id"]
    }

    {:ok, params}
  end

  defp parse_instruction_meeting_context(instruction_ctx) do
    # Handle meeting requests from user instructions
    params = %{
      contact_email: instruction_ctx["contact_email"] || instruction_ctx["email"],
      contact_name: instruction_ctx["contact_name"] || instruction_ctx["name"],
      subject: instruction_ctx["subject"] || "Meeting Request",
      duration_minutes: instruction_ctx["duration"] || 60,
      preferred_time: parse_preferred_time(instruction_ctx["when"]),
      description: instruction_ctx["description"] || "Meeting scheduled via automated instruction",
      meeting_type: instruction_ctx["type"] || "consultation",
      priority: instruction_ctx["priority"] || "normal"
    }

    {:ok, params}
  end

  defp parse_fallback_context(context) do
    # Try to extract meeting info from any available context
    contact_email = context["email"] || context["contact"] || context["attendee"]

    if contact_email && String.contains?(contact_email, "@") do
      params = %{
        contact_email: contact_email,
        contact_name: context["name"] || extract_name_from_email(contact_email),
        subject: context["title"] || context["subject"] || "Meeting",
        duration_minutes: context["duration"] || 60,
        preferred_time: parse_preferred_time(context["time"] || context["when"]),
        description: context["description"] || "Meeting scheduled via AI assistant",
        meeting_type: "general",
        priority: "normal"
      }

      {:ok, params}
    else
      {:error, "No valid contact email found in context"}
    end
  end

  # Time slot finding and scheduling

  defp find_meeting_time_slot(user, meeting_params) do
    case meeting_params.preferred_time do
      nil ->
        # Find next available slot
        find_next_available_slot(user, meeting_params)

      preferred_time ->
        # Check if preferred time is available
        case check_time_availability(user, preferred_time, meeting_params) do
          {:available, time_slot} ->
            {:ok, time_slot}

          {:unavailable, conflicts} ->
            # Try to find nearby slots
            case find_nearby_available_slots(user, preferred_time, meeting_params) do
              {:ok, alternative_slots} when length(alternative_slots) > 0 ->
                {:ok, hd(alternative_slots)}

              _ ->
                {:error, :no_available_slots}
            end
        end
    end
  end

  defp find_next_available_slot(user, meeting_params) do
    # Start from tomorrow, find first available slot
    start_search = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.beginning_of_day()
    end_search = DateTime.add(start_search, 14, :day) # Search next 2 weeks

    case App.Integrations.CalendarClient.find_available_slots(
           user,
           meeting_params.duration_minutes,
           [meeting_params.contact_email],
           start_time: start_search,
           end_time: end_search
         ) do
      {:ok, [first_slot | _]} ->
        {:ok, %{
          start_time: first_slot,
          end_time: DateTime.add(first_slot, meeting_params.duration_minutes * 60, :second)
        }}

      {:ok, []} ->
        {:error, :no_available_slots}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_time_availability(user, preferred_time, meeting_params) do
    duration_seconds = meeting_params.duration_minutes * 60
    end_time = DateTime.add(preferred_time, duration_seconds, :second)

    # Check free/busy for the preferred time
    case App.Integrations.CalendarClient.get_free_busy(
           user,
           [user.email, meeting_params.contact_email],
           DateTime.to_iso8601(preferred_time),
           DateTime.to_iso8601(end_time)
         ) do
      {:ok, free_busy_data} ->
        if is_time_slot_free?(free_busy_data, preferred_time, end_time) do
          {:available, %{start_time: preferred_time, end_time: end_time}}
        else
          conflicts = extract_conflicts(free_busy_data, preferred_time, end_time)
          {:unavailable, conflicts}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_nearby_available_slots(user, preferred_time, meeting_params) do
    # Look for slots within 2 hours before/after preferred time
    search_start = DateTime.add(preferred_time, -2 * 60 * 60, :second)
    search_end = DateTime.add(preferred_time, 2 * 60 * 60, :second)

    App.Integrations.CalendarClient.find_available_slots(
      user,
      meeting_params.duration_minutes,
      [meeting_params.contact_email],
      start_time: search_start,
      end_time: search_end
    )
  end

  # Calendar event creation

  defp create_calendar_event(user, meeting_params, time_slot) do
    event_data = App.Integrations.CalendarClient.build_event(
      meeting_params.subject,
      time_slot.start_time,
      time_slot.end_time,
      attendees: [meeting_params.contact_email],
      description: build_meeting_description(meeting_params, time_slot),
      location: meeting_params.location
    )

    App.Integrations.CalendarClient.create_event(user, event_data)
  end

  defp build_meeting_description(meeting_params, time_slot) do
    base_description = meeting_params.description || "Meeting scheduled via AI assistant"

    additional_info = [
      "Meeting Details:",
      "- Type: #{String.capitalize(meeting_params.meeting_type)}",
      "- Duration: #{meeting_params.duration_minutes} minutes",
      "- Priority: #{String.capitalize(meeting_params.priority)}"
    ]

    if meeting_params.original_thread_id do
      additional_info = additional_info ++ ["- Reference: Email thread #{meeting_params.original_thread_id}"]
    end

    [base_description, "", Enum.join(additional_info, "\n")]
    |> Enum.join("\n")
  end

  # Notification and communication

  defp send_meeting_notifications(user, meeting_params, calendar_event, time_slot) do
    # Send confirmation email to attendee
    confirmation_email = build_meeting_confirmation_email(user, meeting_params, calendar_event, time_slot)

    case App.Integrations.GmailClient.send_email(
           user,
           meeting_params.contact_email,
           confirmation_email.subject,
           confirmation_email.body
         ) do
      {:ok, email_result} ->
        # Optionally send calendar invite (if not automatically sent)
        notifications = %{
          email_sent: true,
          email_id: email_result["id"],
          calendar_invite: calendar_event["htmlLink"]
        }

        {:ok, notifications}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_meeting_confirmation_email(user, meeting_params, calendar_event, time_slot) do
    subject = "Meeting Confirmed: #{meeting_params.subject}"

    body = """
    Hi #{meeting_params.contact_name},

    Great! I've confirmed our meeting:

    📅 Date: #{format_date(time_slot.start_time)}
    🕐 Time: #{format_time(time_slot.start_time)} - #{format_time(time_slot.end_time)}
    📍 Location: #{meeting_params.location || "Virtual/Phone"}
    ⏱️ Duration: #{meeting_params.duration_minutes} minutes

    #{if calendar_event["htmlLink"], do: "Calendar Link: #{calendar_event["htmlLink"]}", else: ""}

    The calendar invitation has been sent to your email. Please accept it to add the meeting to your calendar.

    If you need to reschedule or have any questions, please let me know as soon as possible.

    Looking forward to our meeting!

    Best regards,
    #{user.name || user.email}

    ---
    This meeting was scheduled automatically by my AI assistant.
    Meeting ID: #{calendar_event["id"]}
    """

    %{subject: subject, body: body}
  end

  defp suggest_alternative_times(user, meeting_params) do
    # Find alternative slots over next week
    start_time = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.beginning_of_day()
    end_time = DateTime.add(start_time, 7, :day)

    case App.Integrations.CalendarClient.find_available_slots(
           user,
           meeting_params.duration_minutes,
           [meeting_params.contact_email],
           start_time: start_time,
           end_time: end_time
         ) do
      {:ok, slots} when length(slots) > 0 ->
        # Take first 3-5 alternative slots
        alternative_slots = Enum.take(slots, 5)
        {:ok, alternative_slots}

      _ ->
        {:error, :no_alternatives_found}
    end
  end

  defp send_availability_update(user, meeting_params, suggested_times) do
    subject = "Alternative Meeting Times Available"

    time_options = suggested_times
                   |> Enum.with_index(1)
                   |> Enum.map(fn {time, index} ->
      "#{index}. #{format_full_datetime(time)}"
    end)
                   |> Enum.join("\n")

    body = """
    Hi #{meeting_params.contact_name},

    Unfortunately, the requested meeting time is not available due to scheduling conflicts.

    Here are some alternative times that work for both of us:

    #{time_options}

    Please let me know which option works best for you, and I'll send you the calendar invitation right away.

    If none of these times work, please suggest some alternative times that suit your schedule.

    Best regards,
    #{user.name || user.email}
    """

    App.Integrations.GmailClient.send_email(
      user,
      meeting_params.contact_email,
      subject,
      body
    )
  end

  # Contact and interaction tracking

  defp update_contact_interaction(user, meeting_params, calendar_event) do
    # Update contact record with meeting information
    interaction_data = %{
      type: "meeting_scheduled",
      meeting_id: calendar_event["id"],
      subject: meeting_params.subject,
      scheduled_time: calendar_event["start"]["dateTime"],
      contact_email: meeting_params.contact_email,
      created_via: "ai_assistant"
    }

    # Try to find and update existing contact
    case find_contact_by_email(user, meeting_params.contact_email) do
      {:found, contact_info} ->
        update_existing_contact_with_meeting(user, contact_info, interaction_data)

      {:not_found} ->
        # Create contact if it doesn't exist
        create_contact_from_meeting(user, meeting_params, interaction_data)
    end
  end

  defp find_contact_by_email(user, email) do
    # Check HubSpot first
    case App.Integrations.HubSpotClient.search_contacts(user, email) do
      {:ok, %{"results" => [contact | _]}} ->
        {:found, {:hubspot, contact}}

      _ ->
        # Check local contacts
        case App.Repo.get_by(App.Contacts.Contact, user_id: user.id, email: email) do
          nil -> {:not_found}
          local_contact -> {:found, {:local, local_contact}}
        end
    end
  end

  defp update_existing_contact_with_meeting(user, contact_info, interaction_data) do
    case contact_info do
      {:hubspot, hubspot_contact} ->
        # Add note to HubSpot contact
        note_content = """
        Meeting Scheduled: #{interaction_data.subject}
        Date/Time: #{interaction_data.scheduled_time}
        Meeting ID: #{interaction_data.meeting_id}
        Scheduled via: AI Assistant
        """

        App.Integrations.HubSpotClient.create_note(user, hubspot_contact["id"], note_content)

      {:local, local_contact} ->
        # Update local contact metadata
        meetings = local_contact.metadata["meetings"] || []
        updated_meetings = [interaction_data | meetings]

        updated_metadata = Map.put(local_contact.metadata, "meetings", updated_meetings)

        App.Repo.update(
          App.Contacts.Contact.changeset(local_contact, %{
            metadata: updated_metadata,
            last_contact_at: DateTime.utc_now()
          })
        )
    end
  end

  defp create_contact_from_meeting(user, meeting_params, interaction_data) do
    # Create a contact creation task
    contact_context = %{
      "email" => meeting_params.contact_email,
      "name" => meeting_params.contact_name,
      "source_info" => "Created from meeting scheduling: #{meeting_params.subject}",
      "meeting_info" => interaction_data
    }

    Tasks.create_contact_creation_task(
      user,
      contact_context,
      title: "Create contact from meeting: #{meeting_params.contact_name}"
    )
  end

  # Utility functions

  defp extract_name_from_email(email) when is_binary(email) do
    case String.split(email, "@") do
      [name_part | _] ->
        name_part
        |> String.replace(~r/[._-]/, " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      _ -> "Contact"
    end
  end

  defp extract_name_from_email(_), do: "Contact"

  defp parse_preferred_time(nil), do: nil
  defp parse_preferred_time(time_string) when is_binary(time_string) do
    case DateTime.from_iso8601(time_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  defp parse_preferred_time(%DateTime{} = datetime), do: datetime
  defp parse_preferred_time(_), do: nil

  defp extract_confirmed_time_from_response(content) when is_binary(content) do
    # Look for time patterns in email response
    time_patterns = [
      ~r/(\d{1,2}):(\d{2})\s*(AM|PM)/i,
      ~r/(\d{1,2})\s*(AM|PM)/i,
    ]

    Enum.find_value(time_patterns, fn pattern ->
      case Regex.run(pattern, content) do
        nil -> nil
        matches -> parse_time_from_matches(matches)
      end
    end)
  end

  defp extract_confirmed_time_from_response(_), do: nil

  defp parse_time_from_matches([_, hour, minute, ampm]) do
    hour = String.to_integer(hour)
    minute = String.to_integer(minute)

    hour = if String.upcase(ampm) == "PM" and hour != 12, do: hour + 12, else: hour
    hour = if String.upcase(ampm) == "AM" and hour == 12, do: 0, else: hour

    # Assume tomorrow for meeting scheduling
    tomorrow = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_date()
    DateTime.new!(tomorrow, Time.new!(hour, minute, 0))
  end

  defp parse_time_from_matches([_, hour, ampm]) do
    parse_time_from_matches([nil, hour, "00", ampm])
  end

  defp is_time_slot_free?(free_busy_data, start_time, end_time) do
    App.Integrations.CalendarAvailability.is_time_slot_free?(free_busy_data, start_time, end_time)
  end

  defp extract_conflicts(free_busy_data, start_time, end_time) do
    App.Integrations.CalendarAvailability.extract_conflicts(free_busy_data, start_time, end_time)
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%A, %B %d, %Y")
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp format_full_datetime(datetime) do
    "#{format_date(datetime)} at #{format_time(datetime)}"
  end

end
