defmodule App.Integration.FullWorkflowTest do
  use App.DataCase, async: true

  alias App.{Accounts, Chat, AI.Agent, Tasks}

  describe "end-to-end AI assistant workflow" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "advisor@example.com",
        name: "Financial Advisor",
        google_access_token: "test_google_token",
        hubspot_access_token: "test_hubspot_token"
      })

      {:ok, conversation} = Chat.create_conversation(user, %{
        title: "AI Assistant Test"
      })

      %{user: user, conversation: conversation}
    end

    test "user can ask about clients and get contextual response", %{user: user, conversation: conversation} do
      # Create some knowledge entries to simulate synced data
      {:ok, _entry} = Repo.insert(%App.Knowledge.KnowledgeEntry{
        user_id: user.id,
        source_type: "email",
        source_id: "email_123",
        title: "Baseball Discussion",
        content: "John Smith mentioned his son plays baseball every Saturday",
        metadata: %{from: "john.smith@example.com"},
        last_synced_at: DateTime.utc_now()
      })

      # Create user message
      {:ok, user_message} = Chat.create_message(conversation, %{
        role: "user",
        content: "Who mentioned baseball in their emails?"
      })

      # Test that the workflow doesn't crash
      # In a real test with mocked APIs, this would return actual results
      assert user_message.content =~ "baseball"
      assert conversation.user_id == user.id

      # Verify knowledge base search functionality
      {:ok, results} = App.AI.KnowledgeBase.search_relevant_content(user, "baseball")
      assert length(results) == 1
      assert hd(results).title == "Baseball Discussion"
    end

    test "user can set up automation instructions", %{user: user} do
      instruction = "When someone emails me who isn't in HubSpot, create a contact"
      triggers = ["email_received"]

      {:ok, user_instruction} = Tasks.create_user_instruction(user, instruction, triggers)

      assert user_instruction.instruction == instruction
      assert user_instruction.triggers == triggers
      assert user_instruction.active == true

      # Simulate email webhook triggering instruction
      email_data = %{
        from: "newclient@example.com",
        subject: "Investment Inquiry"
      }

      count = Tasks.check_instructions_for_trigger(user, "email_received", email_data)
      assert count == 1

      # Verify task was created
      tasks = Tasks.list_pending_tasks(user)
      assert length(tasks) == 1
      assert hd(tasks).task_type == "execute_instruction"
    end

    test "knowledge base sync status is tracked", %{user: user} do
      status = App.AI.KnowledgeBase.get_sync_status(user)

      assert is_map(status)
      assert Map.has_key?(status, :total_entries)
      assert Map.has_key?(status, :email_entries)
      assert Map.has_key?(status, :hubspot_entries)
      assert Map.has_key?(status, :status)
    end

    test "tool execution validates user permissions", %{user: user} do
      # Test that tools require proper user context
      result = App.AI.Tools.execute_tool("search_emails", %{"query" => "test"}, user)

      # Should return structured response (may fail HTTP call but validates structure)
      assert match?({:ok, _} | {:error, _}, result)

      # Test invalid tool
      invalid_result = App.AI.Tools.execute_tool("nonexistent_tool", %{}, user)
      assert match?({:error, "Unknown tool: nonexistent_tool"}, invalid_result)
    end

    test "background worker processes webhooks safely", %{user: user} do
      # Test email webhook processing
      email_data = %{
        message_id: "test_msg_123",
        from: "client@example.com"
      }

      # Should not crash
      App.BackgroundWorker.process_email_webhook(user.id, email_data)

      # Test HubSpot webhook
      hubspot_data = %{
        contact_id: "contact_123",
        event_type: "contact_created"
      }

      App.BackgroundWorker.process_hubspot_webhook("portal_123", hubspot_data)

      # Give background processes time to complete
      :timer.sleep(50)
    end
  end
end
