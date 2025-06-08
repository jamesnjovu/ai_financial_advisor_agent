defmodule App.AI.Agent do
  @moduledoc """
  Core AI Agent that handles conversations, tool calling, and task management
  """

  alias App.Chat
  alias App.AI.{OpenAI, Tools, KnowledgeBase}
  alias App.Tasks
  alias App.Accounts.User

  def process_message(conversation, user_message, %User{} = user) do
    # Get conversation history
    messages = Chat.get_conversation_messages(conversation)

    # Search relevant knowledge
    {:ok, context} = KnowledgeBase.search_relevant_content(user, user_message, limit: 5)

    # Get user instructions for context
    instructions = Tasks.get_active_instructions(user)

    # Build system message with context
    system_message = build_system_message(context, instructions)

    # Build conversation history for OpenAI
    conversation_messages = build_conversation_messages(messages, system_message)

    # Call OpenAI with tool calling enabled
    case OpenAI.chat_completion(conversation_messages, tools: get_available_tools()) do
      {:ok, %{"choices" => [%{"message" => ai_message}]} = response} ->
        handle_ai_response(conversation, ai_message, user)

      {:error, reason} ->
        {:error, "AI processing failed: #{inspect(reason)}"}
    end
  end

  defp build_system_message(context, instructions) do
    context_text = Enum.map_join(
      context,
      "\n\n",
      fn entry ->
        "#{entry.source_type} (#{entry.title}): #{entry.content}"
      end
    )

    instructions_text = Enum.map_join(
      instructions,
      "\n",
      fn inst ->
        "- #{inst.instruction}"
      end
    )

    """
    You are an AI Financial Advisor assistant. You help manage client relationships through Gmail, Google Calendar, and HubSpot CRM.

    AVAILABLE CONTEXT:
    #{context_text}

    ACTIVE USER INSTRUCTIONS:
    #{instructions_text}

    CAPABILITIES:
    - Search emails and contacts to answer questions about clients
    - Schedule meetings by checking calendar availability and sending emails
    - Create and update HubSpot contacts
    - Send emails on behalf of the user
    - Create tasks and reminders
    - Set up ongoing automation instructions

    Always be helpful, professional, and proactive. When scheduling meetings or contacting people, use the available tools to actually perform the actions.
    """
  end

  defp build_conversation_messages(messages, system_message) do
    system_msg = %{role: "system", content: system_message}

    conversation_msgs = Enum.map(
      messages,
      fn msg ->
        %{role: msg.role, content: msg.content}
      end
    )

    [system_msg | conversation_msgs]
  end

  defp handle_ai_response(conversation, %{"tool_calls" => tool_calls} = ai_message, user) when is_list(tool_calls) do
    # Handle tool calls
    tool_results = Enum.map(
      tool_calls,
      fn tool_call ->
        execute_tool_call(tool_call, user)
      end
    )

    # Serialize tool results for JSON storage
    serialized_results = Enum.map(tool_results, &serialize_tool_result/1)

    # Create assistant message with tool calls
    {:ok, assistant_msg} = Chat.create_message(
      conversation,
      %{
        role: "assistant",
        content: ai_message["content"] || "I'll help you with that.",
        metadata: %{
          tool_calls: tool_calls,
          tool_results: serialized_results
        }
      }
    )

    # If all tools succeeded, create a follow-up response
    if Enum.all?(tool_results, &match?({:ok, _}, &1)) do
      # Build follow-up message with tool results
      results_context = build_tool_results_context(tool_calls, tool_results)

      follow_up_messages = build_conversation_messages(
                             Chat.get_conversation_messages(conversation),
                             build_system_message([], [])
                           ) ++ [
                             %{
                               role: "user",
                               content: "Tool results: #{
                                 results_context
                               }. Please provide a summary of what was accomplished."
                             }
                           ]

      case OpenAI.chat_completion(follow_up_messages) do
        {
          :ok,
          %{
            "choices" => [
              %{
                "message" => %{
                  "content" => summary
                }
              }
            ]
          }
        } ->
          {:ok, summary_msg} = Chat.create_message(
            conversation,
            %{
              role: "assistant",
              content: summary
            }
          )
          {:ok, summary_msg}

        _ ->
          {:ok, assistant_msg}
      end
    else
      {:ok, assistant_msg}
    end
  end

  defp handle_ai_response(conversation, %{"content" => content}, _user) do
    # Regular response without tool calls
    {:ok, assistant_msg} = Chat.create_message(
      conversation,
      %{
        role: "assistant",
        content: content
      }
    )
    {:ok, assistant_msg}
  end

  defp execute_tool_call(
         %{
           "function" => %{
             "name" => tool_name,
             "arguments" => args_json
           }
         },
         user
       ) do
    try do
      args = Jason.decode!(args_json)
      Tools.execute_tool(tool_name, args, user)
    rescue
      e -> {:error, "Tool execution failed: #{Exception.message(e)}"}
    end
  end

  defp build_tool_results_context(tool_calls, tool_results) do
    tool_calls
    |> Enum.zip(tool_results)
    |> Enum.map_join(
         "\n",
         fn {call, result} ->
           tool_name = call["function"]["name"]
           case result do
             {:ok, data} -> "#{tool_name}: SUCCESS - #{inspect(data)}"
             {:error, error} -> "#{tool_name}: ERROR - #{error}"
           end
         end
       )
  end

  # Add helper function to serialize tool results for JSON storage
  defp serialize_tool_result({:ok, data}), do: %{status: "success", data: data}
  defp serialize_tool_result({:error, error}), do: %{status: "error", error: to_string(error)}

  defp get_available_tools do
    [
      %{
        type: "function",
        function: %{
          name: "search_emails",
          description: "Search through emails to find information about clients or topics",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "Search query for emails"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "search_contacts",
          description: "Search for contacts in HubSpot and Gmail",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "Name or email to search for"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "schedule_meeting",
          description: "Schedule a meeting with someone by checking availability and sending invite",
          parameters: %{
            type: "object",
            properties: %{
              contact_email: %{
                type: "string",
                description: "Email of person to meet with"
              },
              subject: %{
                type: "string",
                description: "Meeting subject"
              },
              duration_minutes: %{
                type: "integer",
                description: "Meeting duration in minutes",
                default: 60
              },
              preferred_times: %{
                type: "array",
                items: %{
                  type: "string"
                },
                description: "Preferred time slots"
              }
            },
            required: ["contact_email", "subject"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "send_email",
          description: "Send an email to someone",
          parameters: %{
            type: "object",
            properties: %{
              to: %{
                type: "string",
                description: "Recipient email"
              },
              subject: %{
                type: "string",
                description: "Email subject"
              },
              body: %{
                type: "string",
                description: "Email body"
              }
            },
            required: ["to", "subject", "body"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_hubspot_contact",
          description: "Create or update a contact in HubSpot",
          parameters: %{
            type: "object",
            properties: %{
              email: %{
                type: "string",
                description: "Contact email"
              },
              firstname: %{
                type: "string",
                description: "First name"
              },
              lastname: %{
                type: "string",
                description: "Last name"
              },
              company: %{
                type: "string",
                description: "Company name"
              },
              phone: %{
                type: "string",
                description: "Phone number"
              },
              notes: %{
                type: "string",
                description: "Notes about the contact"
              }
            },
            required: ["email"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "add_instruction",
          description: "Add an ongoing instruction for automated behavior",
          parameters: %{
            type: "object",
            properties: %{
              instruction: %{
                type: "string",
                description: "The instruction for automated behavior"
              },
              triggers: %{
                type: "array",
                items: %{
                  type: "string"
                },
                description: "When to trigger this instruction"
              }
            },
            required: ["instruction", "triggers"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "setup_calendar_webhook",
          description: "Set up real-time calendar notifications",
          parameters: %{
            type: "object",
            properties: %{},
            required: []
          }
        }
      }
    ]
  end
end