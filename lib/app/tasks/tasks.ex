defmodule App.Tasks do
  @moduledoc """
  The Tasks context for managing AI tasks and user instructions
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Tasks.{
    ContactCreationHelpers,
    Task,
    ScheduleMeetingHelper,
    UserInstruction,
  }
  alias App.Accounts.User

  # User Instructions
  def create_user_instruction(%User{} = user, instruction, triggers) do
    %UserInstruction{}
    |> UserInstruction.changeset(%{
      user_id: user.id,
      instruction: instruction,
      triggers: triggers
    })
    |> Repo.insert()
  end

  def get_active_instructions(%User{} = user) do
    UserInstruction
    |> where([i], i.user_id == ^user.id and i.active == true)
    |> order_by([i], desc: i.priority)
    |> Repo.all()
  end

  def list_user_instructions(%User{} = user) do
    UserInstruction
    |> where([i], i.user_id == ^user.id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  def update_instruction(%UserInstruction{} = instruction, attrs) do
    instruction
    |> UserInstruction.changeset(attrs)
    |> Repo.update()
  end

  def delete_instruction(%UserInstruction{} = instruction) do
    Repo.delete(instruction)
  end

  # Tasks
  def create_task(%User{} = user, attrs) do
    %Task{}
    |> Task.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  def get_task(id, %User{} = user) do
    Task
    |> where([t], t.id == ^id and t.user_id == ^user.id)
    |> Repo.one()
  end

  def list_pending_tasks(%User{} = user) do
    Task
    |> where([t], t.user_id == ^user.id and t.status in ["pending", "in_progress", "waiting"])
    |> order_by([t], asc: :next_action_at)
    |> Repo.all()
  end

  def list_user_tasks(%User{} = user, opts \\ []) do
    query = Task
            |> where([t], t.user_id == ^user.id)

    query = if status = opts[:status] do
      where(query, [t], t.status == ^status)
    else
      query
    end

    query
    |> order_by([t], desc: t.inserted_at)
    |> limit(^(opts[:limit] || 50))
    |> Repo.all()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_instruction(%UserInstruction{} = instruction) do
    Repo.delete(instruction)
  end

  def get_instruction(id, %User{} = user) do
    UserInstruction
    |> where([i], i.id == ^id and i.user_id == ^user.id)
    |> Repo.one()
  end

  def count_tasks_by_status(%User{} = user) do
    Task
    |> where([t], t.user_id == ^user.id)
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  def get_task_stats(%User{} = user) do
    total_tasks =
      Task
      |> where([t], t.user_id == ^user.id)
      |> Repo.aggregate(:count, :id)

    completed_tasks =
      Task
      |> where([t], t.user_id == ^user.id and t.status == "completed")
      |> Repo.aggregate(:count, :id)

    failed_tasks =
      Task
      |> where([t], t.user_id == ^user.id and t.status == "failed")
      |> Repo.aggregate(:count, :id)

    pending_tasks =
      Task
      |> where([t], t.user_id == ^user.id and t.status in ["pending", "waiting", "in_progress"])
      |> Repo.aggregate(:count, :id)

    %{
      total: total_tasks,
      completed: completed_tasks,
      failed: failed_tasks,
      pending: pending_tasks,
      success_rate: if(total_tasks > 0, do: Float.round(completed_tasks / total_tasks * 100, 1), else: 0)
    }
  end

  def count_user_instructions(%User{} = user) do
    UserInstruction
    |> where([i], i.user_id == ^user.id)
    |> Repo.aggregate(:count, :id)
  end

  def count_active_instructions(%User{} = user) do
    UserInstruction
    |> where([i], i.user_id == ^user.id and i.active == true)
    |> Repo.aggregate(:count, :id)
  end

  def get_recent_instructions(%User{} = user, limit \\ 5) do
    UserInstruction
    |> where([i], i.user_id == ^user.id)
    |> order_by([i], desc: i.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def complete_task(%Task{} = task, result \\ %{}) do
    update_task(task, %{
      status: "completed",
      completed_at: DateTime.utc_now(),
      metadata: Map.merge(task.metadata, %{result: result})
    })
  end

  def fail_task(%Task{} = task, error) do
    update_task(task, %{
      status: "failed",
      metadata: Map.merge(task.metadata, %{error: error})
    })
  end

  # Background task processing
  def process_pending_tasks do
    # Get all tasks that need processing
    tasks =
      Task
      |> where([t], t.status in ["pending", "waiting"])
      |> where([t], is_nil(t.next_action_at) or t.next_action_at <= ^DateTime.utc_now())
      |> preload(:user)
      |> Repo.all()

    Enum.each(tasks, &process_task/1)
  end

  defp process_task(%Task{task_type: "schedule_meeting"} = task) do
    # Implementation for scheduling meetings
    # This would integrate with the AI agent to continue the conversation
    try do
      # Update task status
      update_task(task, %{status: "in_progress"})

      # Process the task based on context
      result = execute_schedule_meeting_task(task)

      complete_task(task, result)
    rescue
      e ->
        fail_task(task, Exception.message(e))
    end
  end

  defp process_task(%Task{task_type: "process_meeting_response"} = task) do
    try do
      update_task(task, %{status: "in_progress"})

      # Execute the meeting response processing tool
      result = App.AI.Tools.execute_tool("process_meeting_response", task.context, task.user)

      case result do
        {:ok, response_data} ->
          complete_task(task, response_data)

        {:error, reason} ->
          fail_task(task, reason)
      end
    rescue
      e ->
        fail_task(task, Exception.message(e))
    end
  end

  defp process_task(%Task{task_type: "send_email"} = task) do
    try do
      update_task(task, %{status: "in_progress"})

      result = execute_send_email_task(task)

      case result do
        %{success: true} = success_result ->
          complete_task(task, success_result)

        %{success: false} = failure_result ->
          fail_task(task, failure_result.message)

        {:error, reason} ->
          fail_task(task, reason)
      end
    rescue
      e ->
        fail_task(task, Exception.message(e))
    end
  end

  defp process_task(%Task{task_type: "create_contact"} = task) do
    try do
      update_task(task, %{status: "in_progress"})

      result = execute_create_contact_task(task)

      case result do
        %{success: true} = success_result ->
          complete_task(task, success_result)

        %{success: false} = failure_result ->
          fail_task(task, failure_result.message)
      end
    rescue
      e ->
        fail_task(task, Exception.message(e))
    end
  end

  defp process_task(task) do
    # Unknown task type
    fail_task(task, "Unknown task type: #{task.task_type}")
  end

  defp execute_send_email_task(%Task{context: context, user: user}) do
    # Extract email parameters from task context
    to = context["to"] || context[:to]
    subject = context["subject"] || context[:subject]
    body = context["body"] || context[:body]

    # Validate required parameters
    cond do
      is_nil(to) or to == "" ->
        {:error, "Email recipient (to) is required"}

      is_nil(subject) or subject == "" ->
        {:error, "Email subject is required"}

      is_nil(body) or body == "" ->
        {:error, "Email body is required"}

      true ->
        case App.Integrations.GmailClient.send_email(user, to, subject, body) do
          {:ok, gmail_response} ->
            %{
              success: true,
              message: "Email sent successfully",
              message_id: gmail_response["id"],
              to: to,
              subject: subject
            }

          {:error, reason} ->
            %{
              success: false,
              message: "Failed to send email: #{inspect(reason)}",
              to: to,
              subject: subject,
              error: reason
            }
        end
    end
  end

  def execute_create_contact_task(%Task{context: context, user: user}) do
    try do
      # Extract contact information from context using helpers
      case ContactCreationHelpers.build_contact_data_from_context(context) do
        {:ok, valid_contact_data} ->
          # Create contact in HubSpot
          case App.Integrations.HubSpotClient.create_or_update_contact(user, valid_contact_data) do
            {:ok, hubspot_contact} ->
              contact_id = hubspot_contact["id"]

              # Add note to contact if there's additional context
              if context["note"] || context["source_info"] do
                note_content = ContactCreationHelpers.build_contact_note(context)
                App.Integrations.HubSpotClient.create_note(user, contact_id, note_content)
              end

              # Sync to knowledge base for future AI reference
              sync_result = ContactCreationHelpers.sync_contact_to_knowledge_base(user, hubspot_contact, context)

              %{
                success: true,
                message: "Contact created successfully in HubSpot",
                contact_id: contact_id,
                email: valid_contact_data["email"],
                sync_result: sync_result,
                hubspot_contact: hubspot_contact
              }

            {:error, reason} ->
              %{
                success: false,
                message: "Failed to create HubSpot contact: #{inspect(reason)}",
                fallback_created: ContactCreationHelpers.create_local_contact_fallback(user, valid_contact_data, context)
              }
          end

        {:error, reason} ->
          %{
            success: false,
            message: "Invalid contact data: #{reason}",
            raw_context: context
          }
      end
    rescue
      e ->
        %{
          success: false,
          message: "Contact creation failed: #{Exception.message(e)}",
          error_type: e.__struct__
        }
    end
  end

  def execute_schedule_meeting_task(%Task{context: context, user: user}) do
    try do
      # Extract meeting parameters from context
      case ScheduleMeetingHelper.extract_meeting_parameters(context) do
        {:ok, meeting_params} ->
          # Find available time slots
          case ScheduleMeetingHelper.find_meeting_time_slot(user, meeting_params) do
            {:ok, time_slot} ->
              # Create calendar event
              case ScheduleMeetingHelper.create_calendar_event(user, meeting_params, time_slot) do
                {:ok, calendar_event} ->
                  # Send meeting invitations
                  case ScheduleMeetingHelper.send_meeting_notifications(user, meeting_params, calendar_event, time_slot) do
                    {:ok, notification_results} ->
                      # Update contact records
                    ScheduleMeetingHelper.update_contact_interaction(user, meeting_params, calendar_event)

                      %{
                        success: true,
                        message: "Meeting scheduled successfully",
                        meeting_details: %{
                          event_id: calendar_event["id"],
                          attendee: meeting_params.contact_email,
                          subject: meeting_params.subject,
                          scheduled_time: DateTime.to_iso8601(time_slot.start_time),
                          end_time: DateTime.to_iso8601(time_slot.end_time),
                          calendar_link: calendar_event["htmlLink"],
                          notifications_sent: notification_results
                        }
                      }

                    {:error, notification_error} ->
                      # Meeting created but notifications failed
                      %{
                        success: true,
                        message: "Meeting scheduled but notification failed",
                        warning: "Calendar event created but email notification failed: #{notification_error}",
                        meeting_details: %{
                          event_id: calendar_event["id"],
                          scheduled_time: DateTime.to_iso8601(time_slot.start_time),
                          notification_error: notification_error
                        }
                      }
                  end

                {:error, calendar_error} ->
                  %{
                    success: false,
                    message: "Failed to create calendar event: #{calendar_error}",
                    attempted_time: time_slot && DateTime.to_iso8601(time_slot.start_time)
                  }
              end

            {:error, :no_available_slots} ->
              # No slots available, suggest alternatives
              case ScheduleMeetingHelper.suggest_alternative_times(user, meeting_params) do
                {:ok, suggestions} ->
                ScheduleMeetingHelper.send_availability_update(user, meeting_params, suggestions)

                  %{
                    success: false,
                    message: "No available slots found for requested time",
                    alternatives_suggested: true,
                    suggested_times: suggestions,
                    action_taken: "Sent alternative time suggestions to attendee"
                  }

                {:error, _} ->
                  %{
                    success: false,
                    message: "No available slots found and unable to suggest alternatives",
                    requested_time: meeting_params.preferred_time
                  }
              end

            {:error, time_error} ->
              %{
                success: false,
                message: "Error finding meeting time: #{time_error}",
                context: meeting_params
              }
          end

        {:error, param_error} ->
          %{
            success: false,
            message: "Invalid meeting parameters: #{param_error}",
            raw_context: context
          }
      end
    rescue
      e ->
        %{
          success: false,
          message: "Meeting scheduling failed: #{Exception.message(e)}",
          error_type: e.__struct__,
          context: context
        }
    end
  end

  def create_meeting_response_task(%User{} = user, email_data) do
    create_task(user, %{
      title: "Process meeting response from #{email_data.from}",
      task_type: "process_meeting_response",
      context: %{
        message_id: email_data.id,
        from: email_data.from,
        subject: email_data.subject,
        content: email_data.body,
        thread_id: email_data.thread_id
      }
    })
  end

  # Instruction matching for proactive behaviors
  def check_instructions_for_trigger(%User{} = user, trigger, context \\ %{}) do
    instructions =
      UserInstruction
      |> where([i], i.user_id == ^user.id and i.active == true)
      |> where([i], ^trigger in i.triggers)
      |> Repo.all()

    Enum.each(instructions, fn instruction ->
      create_task(user, %{
        title: "Execute instruction: #{String.slice(instruction.instruction, 0, 50)}...",
        description: instruction.instruction,
        task_type: "execute_instruction",
        context: %{
          instruction_id: instruction.id,
          instruction: instruction.instruction,
          trigger: trigger,
          trigger_context: context
        }
      })
    end)

    length(instructions)
  end

  defp build_contact_from_email(email_data) do
    email = email_data["from"] || email_data[:from]

    if valid_email?(email) do
      # Parse name from email if available
      {parsed_email, name} = parse_email_with_name(email)

      contact_data = %{
                       "email" => parsed_email,
                       "firstname" => extract_first_name(name),
                       "lastname" => extract_last_name(name)
                     }
                     |> add_optional_fields(%{
        "phone" => extract_phone_from_content(email_data["body"]),
        "company" => extract_company_from_email(email_data)
      })

      {:ok, contact_data}
    else
      {:error, "Invalid email address: #{email}"}
    end
  end

  defp build_contact_from_info(contact_info) do
    required_email = contact_info["email"] || contact_info[:email]

    if valid_email?(required_email) do
      contact_data = %{
                       "email" => required_email,
                       "firstname" => contact_info["firstname"] || contact_info[:firstname] ||
                         contact_info["first_name"] || contact_info[:first_name],
                       "lastname" => contact_info["lastname"] || contact_info[:lastname] ||
                         contact_info["last_name"] || contact_info[:last_name],
                       "company" => contact_info["company"] || contact_info[:company],
                       "phone" => contact_info["phone"] || contact_info[:phone]
                     }
                     |> clean_contact_data()

      {:ok, contact_data}
    else
      {:error, "Invalid or missing email address"}
    end
  end

  defp build_contact_from_basic_info(email, name, context) do
    if valid_email?(email) do
      contact_data = %{
                       "email" => email,
                       "firstname" => extract_first_name(name),
                       "lastname" => extract_last_name(name)
                     }
                     |> add_optional_fields(%{
        "company" => context["company"],
        "phone" => context["phone"],
        "website" => context["website"]
      })

      {:ok, contact_data}
    else
      {:error, "Invalid email address: #{email}"}
    end
  end

  defp build_contact_from_email_only(email, context) do
    if valid_email?(email) do
      # Try to infer name from email prefix
      name = email |> String.split("@") |> List.first() |> humanize_email_name()

      contact_data = %{
                       "email" => email,
                       "firstname" => extract_first_name(name),
                       "lastname" => extract_last_name(name)
                     }
                     |> add_optional_fields(%{
        "company" => infer_company_from_email(email) || context["company"],
        "phone" => context["phone"]
      })

      {:ok, contact_data}
    else
      {:error, "Invalid email address: #{email}"}
    end
  end

  defp build_contact_from_email_only(email, context) do
    if valid_email?(email) do
      # Try to infer name from email prefix
      name = email |> String.split("@") |> List.first() |> humanize_email_name()

      contact_data = %{
                       "email" => email,
                       "firstname" => extract_first_name(name),
                       "lastname" => extract_last_name(name)
                     }
                     |> add_optional_fields(%{
        "company" => infer_company_from_email(email) || context["company"],
        "phone" => context["phone"]
      })

      {:ok, contact_data}
    else
      {:error, "Invalid email address: #{email}"}
    end
  end

  defp valid_email?(email) when is_binary(email) do
    email_regex = ~r/^[^\s]+@[^\s]+\.[^\s]{2,}$/
    String.match?(email, email_regex)
  end

  defp valid_email?(_), do: false

  defp parse_email_with_name(email_string) do
    # Handle formats like "John Smith <john@example.com>" or just "john@example.com"
    case Regex.run(~r/^(.+?)\s*<(.+?)>$/, String.trim(email_string)) do
      [_, name, email] ->
        {String.trim(email), String.trim(name)}

      nil ->
        {String.trim(email_string), nil}
    end
  end

  defp extract_first_name(nil), do: nil
  defp extract_first_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.split()
    |> List.first()
    |> case do
         first when byte_size(first) > 0 -> first
         _ -> nil
       end
  end

  defp extract_last_name(nil), do: nil
  defp extract_last_name(name) when is_binary(name) do
    parts = name |> String.trim() |> String.split()

    case length(parts) do
      0 -> nil
      1 -> nil
      _ -> Enum.drop(parts, 1) |> Enum.join(" ")
    end
  end

  defp humanize_email_name(email_prefix) do
    email_prefix
    |> String.replace(~r/[._-]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp infer_company_from_email(email) do
    case String.split(email, "@") do
      [_, domain] ->
        domain
        |> String.split(".")
        |> List.first()
        |> String.replace(~r/[^a-zA-Z0-9]/, "")
        |> String.capitalize()

      _ -> nil
    end
  end

  defp extract_phone_from_content(nil), do: nil
  defp extract_phone_from_content(content) when is_binary(content) do
    # Look for phone numbers in various formats
    phone_patterns = [
      ~r/(\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})/,
      ~r/(\+?[0-9]{1,4}[-.\s]?)?(\(?[0-9]{2,4}\)?[-.\s]?){1,4}[0-9]{2,4}/
    ]

    Enum.find_value(phone_patterns, fn pattern ->
      case Regex.run(pattern, content) do
        [phone | _] -> String.trim(phone)
        nil -> nil
      end
    end)
  end

  defp extract_company_from_email(email_data) do
    # Look for company info in email signature or domain
    content = email_data["body"] || email_data[:body] || ""

    # Check signature patterns
    signature_company = extract_company_from_signature(content)

    # Fallback to domain inference
    domain_company = case email_data["from"] do
      email when is_binary(email) -> infer_company_from_email(email)
      _ -> nil
    end

    signature_company || domain_company
  end

  defp extract_company_from_signature(content) when is_binary(content) do
    # Look for common signature patterns
    patterns = [
      ~r/(?:^|\n)(.+?)\s*\n.*?(?:phone|tel|mobile|office):/i,
      ~r/(?:^|\n)(.+?)\s*\n.*?@.+?\..+/i,
      ~r/\n(.+?)\s*\n.*?(?:www\.|http)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, content) do
        [_, company] ->
          company
          |> String.trim()
          |> String.replace(~r/[^\w\s&.-]/, "")
          |> case do
               trimmed when byte_size(trimmed) > 2 and byte_size(trimmed) < 100 -> trimmed
               _ -> nil
             end

        nil -> nil
      end
    end)
  end

  defp add_optional_fields(base_data, optional_fields) do
    Enum.reduce(optional_fields, base_data, fn {key, value}, acc ->
      if value && String.trim(to_string(value)) != "" do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp clean_contact_data(contact_data) do
    contact_data
    |> Enum.reject(fn {_key, value} ->
      is_nil(value) || (is_binary(value) && String.trim(value) == "")
    end)
    |> Map.new()
  end

  defp format_trigger_context(trigger_context) do
    case trigger_context do
      %{"from" => from, "subject" => subject} ->
        "Triggered by email from #{from} with subject: #{subject}"

      %{"source" => source} ->
        "Triggered by: #{source}"

      _ ->
        "Triggered by automated workflow"
    end
  end

  defp format_email_context(email_data) do
    "Email details:\n" <>
    "From: #{email_data["from"]}\n" <>
    "Subject: #{email_data["subject"]}\n" <>
    "Date: #{email_data["date"] || "Unknown"}"
  end

  defp format_sync_context(context) do
    case context do
      %{"instruction" => instruction} -> "Created via instruction: #{instruction}"
      %{"trigger" => trigger} -> "Triggered by: #{trigger}"
      _ -> "Automated creation"
    end
  end

  # Helper function to create contact creation tasks from various triggers
  def create_contact_creation_task(%User{} = user, contact_context, opts \\ []) do
    title = opts[:title] || "Create contact from #{contact_context["source"] || "automated trigger"}"

    create_task(user, %{
      title: title,
      task_type: "create_contact",
      context: contact_context,
      next_action_at: opts[:delay] && DateTime.add(DateTime.utc_now(), opts[:delay], :second)
    })
  end

  # Function to intelligently create contact from email data
  def create_contact_from_email(%User{} = user, email_data, instruction_context \\ %{}) do
    contact_context = %{
      "email_data" => email_data,
      "source_info" => "Email from #{email_data["from"]} - #{email_data["subject"]}",
      "trigger_context" => instruction_context,
      "note" => "Contact created automatically from email communication"
    }

    create_contact_creation_task(user, contact_context, title: "Create contact from #{email_data["from"]}")
  end

  # Function to handle contact creation from user instructions
  def handle_contact_creation_instruction(%User{} = user, instruction, trigger_context) do
    case trigger_context do
      %{"from" => from_email} = email_context ->
        # Check if contact already exists
        case check_existing_contact(user, from_email) do
          {:not_found} ->
            # Create new contact
            create_contact_from_email(user, email_context, %{
              "instruction" => instruction.instruction,
              "instruction_id" => instruction.id
            })

          {:found, existing_contact} ->
            # Optionally update existing contact or create note
            update_existing_contact_context(user, existing_contact, email_context, instruction)
        end

      _ ->
        {:error, "No email context found for contact creation"}
    end
  end

  defp check_existing_contact(user, email) do
    # Check HubSpot first
    case App.Integrations.HubSpotClient.search_contacts(user, email) do
      {:ok, %{"results" => [contact | _]}} ->
        {:found, {:hubspot, contact}}

      {:ok, %{"results" => []}} ->
        # Check local contacts as fallback
        case App.Repo.get_by(App.Contacts.Contact, user_id: user.id, email: email) do
          nil -> {:not_found}
          local_contact -> {:found, {:local, local_contact}}
        end

      {:error, _} ->
        # If HubSpot search fails, check local only
        case App.Repo.get_by(App.Contacts.Contact, user_id: user.id, email: email) do
          nil -> {:not_found}
          local_contact -> {:found, {:local, local_contact}}
        end
    end
  end

  defp update_existing_contact_context(user, existing_contact, email_context, instruction) do
    case existing_contact do
      {:hubspot, hubspot_contact} ->
        # Add note to existing HubSpot contact
        note_content = """
        New email interaction: #{email_context["subject"]}
        From: #{email_context["from"]}
        Date: #{email_context["date"] || DateTime.utc_now() |> DateTime.to_string()}

      Triggered by instruction: #{instruction.instruction}
        """

        App.Integrations.HubSpotClient.create_note(user, hubspot_contact["id"], note_content)

      {:local, local_contact} ->
        # Update local contact metadata
        updated_metadata = Map.merge(local_contact.metadata || %{}, %{
          "last_email_interaction" => %{
            "subject" => email_context["subject"],
            "date" => email_context["date"] || DateTime.utc_now() |> DateTime.to_string(),
            "instruction_triggered" => instruction.id
          }
        })

        App.Repo.update(
          App.Contacts.Contact.changeset(local_contact, %{
            metadata: updated_metadata,
            last_contact_at: DateTime.utc_now()
          })
        )
    end
  end

  # Function for users to manually trigger contact creation
  def manual_contact_creation(%User{} = user, contact_details) do
    contact_context = %{
      "contact_info" => contact_details,
      "source_info" => "Manually created by user",
      "note" => "Contact created via manual request to AI assistant"
    }

    create_contact_creation_task(user, contact_context, title: "Create contact: #{contact_details["email"]}")
  end

end