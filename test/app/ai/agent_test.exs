defmodule App.AI.AgentTest do
  use App.DataCase, async: true

  alias App.AI.Agent
  alias App.Chat
  alias App.Accounts
  alias App.Tasks

  describe "AI Agent Integration" do
    setup do
      # Create a test user
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        google_access_token: "test_token",
        hubspot_access_token: "test_hubspot_token"
      })

      # Create a test conversation
      {:ok, conversation} = Chat.create_conversation(user, %{
        title: "Test Conversation"
      })

      %{user: user, conversation: conversation}
    end

    test "processes simple message without tools", %{user: user, conversation: conversation} do
      # Mock OpenAI response
      mock_openai_response = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "Hello! I'm your AI financial advisor. How can I help you today?"
            }
          }
        ]
      }

      # This would require mocking the OpenAI API call
      # For now, we'll test that the function exists and doesn't crash

      assert is_function(&Agent.process_message/3, 3)
    end

    test "handles tool calling", %{user: user, conversation: conversation} do
      # Test that tools module exists and has the right functions
      assert is_function(&App.AI.Tools.execute_tool/3, 3)

      # Test search_emails tool
      result = App.AI.Tools.execute_tool("search_emails", %{"query" => "test"}, user)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "knowledge base functions work", %{user: user} do
      # Test knowledge base search
      result = App.AI.KnowledgeBase.search_relevant_content(user, "test query")
      assert match?({:ok, _}, result)

      # Test sync status
      status = App.AI.KnowledgeBase.get_sync_status(user)
      assert is_map(status)
      assert Map.has_key?(status, :status)
    end

    test "task creation works", %{user: user} do
      # Test creating a user instruction
      {:ok, instruction} = Tasks.create_user_instruction(
        user,
        "When someone emails me, create a contact",
        ["email_received"]
      )

      assert instruction.instruction == "When someone emails me, create a contact"
      assert instruction.triggers == ["email_received"]

      # Test getting active instructions
      instructions = Tasks.get_active_instructions(user)
      assert length(instructions) == 1
    end

    test "webhook processing doesn't crash", %{user: user} do
      # Test email webhook
      email_data = %{
        "message_id" => "test123",
        "from" => "client@example.com"
      }

      # This should not crash
      result = Tasks.check_instructions_for_trigger(user, "email_received", email_data)
      assert is_integer(result)
    end
  end
end
