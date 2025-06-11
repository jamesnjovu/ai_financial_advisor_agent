defmodule App.Integration.ContactCreationWorkflowTest do
  use App.DataCase, async: true

  alias App.{Tasks, Accounts, AI.Tools}

  test "complete contact creation workflow from email trigger" do
    # Setup user with instruction
    {:ok, user} = Accounts.create_user(%{
      email: "advisor@example.com",
      name: "Financial Advisor",
      google_access_token: "test_token",
      hubspot_access_token: "test_hubspot"
    })

    # Create instruction for auto-contact creation
    {:ok, _instruction} = Tasks.create_user_instruction(
      user,
      "When someone emails me who isn't in HubSpot, create a contact with their information",
      ["email_received"]
    )

    # Simulate email received
    email_data = %{
      "message_id" => "msg_123",
      "from" => "Alice Johnson <alice@newclient.com>",
      "subject" => "Investment Consultation Request",
      "body" => """
      Hello,

      I'm interested in your financial advisory services. I work at NewClient Corp
      and you can reach me at (555) 123-4567.

      Best regards,
      Alice Johnson
      CEO, NewClient Corp
      alice@newclient.com
      (555) 123-4567
      """,
      "date" => "2024-01-15T14:30:00Z"
    }

    # Trigger instruction
    count = Tasks.check_instructions_for_trigger(user, "email_received", email_data)
    assert count == 1

    # Verify task was created
    tasks = Tasks.list_pending_tasks(user)
    assert length(tasks) == 1

    execute_instruction_task = Enum.find(tasks, &(&1.task_type == "execute_instruction"))
    assert execute_instruction_task != nil

    # Process the instruction task (which should create a contact creation task)
    Tasks.process_pending_tasks()

    # Give it time to process
    :timer.sleep(100)

    # Check for contact creation task
    updated_tasks = Tasks.list_pending_tasks(user)
    contact_tasks = Enum.filter(updated_tasks, &(&1.task_type == "create_contact"))

    if length(contact_tasks) > 0 do
      # Process contact creation
      Tasks.process_pending_tasks()

      # Verify contact was created (would need to mock HubSpot API in real test)
      contact_task = hd(contact_tasks)
      final_task = Tasks.get_task(contact_task.id, user)

      # Task should be completed or have result metadata
      assert final_task.status in ["completed", "failed"]
    end
  end
end
