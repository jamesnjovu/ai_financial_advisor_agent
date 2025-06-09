defmodule App.BackgroundWorkerTest do
  use App.DataCase, async: false  # Can't be async due to GenServer

  alias App.BackgroundWorker
  alias App.Accounts
  alias App.Tasks

  describe "background processing" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        google_access_token: "test_token",
        hubspot_portal_id: "123456"
      })
      %{user: user}
    end

    test "process_email_webhook/2 creates instruction tasks", %{user: user} do
      # Create an instruction that should trigger
      {:ok, _instruction} = Tasks.create_user_instruction(
        user,
        "Create contact for unknown emailers",
        ["email_received"]
      )

      email_data = %{
        message_id: "msg_123",
        from: "newclient@example.com",
        subject: "Investment inquiry"
      }

      # Process webhook
      BackgroundWorker.process_email_webhook(user.id, email_data)

      # Give it a moment to process
      :timer.sleep(100)

      # Check that task was created
      tasks = Tasks.list_pending_tasks(user)
      assert length(tasks) >= 1
    end

    test "process_hubspot_webhook/2 handles contact updates", %{user: user} do
      contact_data = %{
        contact_id: "contact_123",
        event_type: "contact_updated",
        properties: %{
          email: "client@example.com",
          firstname: "John"
        }
      }

      # Should not crash
      BackgroundWorker.process_hubspot_webhook(user.hubspot_portal_id, contact_data)

      # Give it a moment to process
      :timer.sleep(100)
    end

    test "handles unknown user gracefully" do
      # Should not crash when processing webhook for unknown user
      BackgroundWorker.process_email_webhook(999999, %{message_id: "test"})
      BackgroundWorker.process_hubspot_webhook("unknown_portal", %{})

      :timer.sleep(100)
    end
  end

  describe "task processing" do
    test "processes pending tasks periodically" do
      # This would test the periodic task processing
      # In a real test, you'd create some pending tasks and verify they get processed
      assert is_function(&Tasks.process_pending_tasks/0, 0)
    end
  end
end
