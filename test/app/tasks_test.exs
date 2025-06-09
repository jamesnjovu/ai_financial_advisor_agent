defmodule App.TasksTest do
  use App.DataCase, async: true

  alias App.Tasks
  alias App.Tasks.{Task, UserInstruction}
  alias App.Accounts

  describe "user instructions" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })
      %{user: user}
    end

    test "create_user_instruction/3 creates instruction", %{user: user} do
      instruction = "When someone emails me, create a contact"
      triggers = ["email_received"]

      assert {:ok, %UserInstruction{} = user_instruction} =
               Tasks.create_user_instruction(user, instruction, triggers)

      assert user_instruction.instruction == instruction
      assert user_instruction.triggers == triggers
      assert user_instruction.active == true
      assert user_instruction.user_id == user.id
    end

    test "get_active_instructions/1 returns only active instructions", %{user: user} do
      {:ok, active} = Tasks.create_user_instruction(user, "Active instruction", ["trigger1"])
      {:ok, inactive} = Tasks.create_user_instruction(user, "Inactive instruction", ["trigger2"])

      # Deactivate one instruction
      Tasks.update_instruction(inactive, %{active: false})

      instructions = Tasks.get_active_instructions(user)
      assert length(instructions) == 1
      assert hd(instructions).id == active.id
    end

    test "check_instructions_for_trigger/3 creates tasks for matching triggers", %{user: user} do
      {:ok, _instruction} = Tasks.create_user_instruction(
        user,
        "Create contact for new emailers",
        ["email_received"]
      )

      # Trigger the instruction
      context = %{from: "newclient@example.com", subject: "Investment inquiry"}
      count = Tasks.check_instructions_for_trigger(user, "email_received", context)

      assert count == 1

      # Check that a task was created
      tasks = Tasks.list_pending_tasks(user)
      assert length(tasks) == 1
      assert hd(tasks).task_type == "execute_instruction"
    end
  end

  describe "tasks" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })
      %{user: user}
    end

    test "create_task/2 creates a task", %{user: user} do
      attrs = %{
        title: "Schedule meeting with John",
        task_type: "schedule_meeting",
        context: %{contact_email: "john@example.com"}
      }

      assert {:ok, %Task{} = task} = Tasks.create_task(user, attrs)
      assert task.title == "Schedule meeting with John"
      assert task.task_type == "schedule_meeting"
      assert task.status == "pending"
      assert task.user_id == user.id
    end

    test "list_pending_tasks/1 returns pending tasks", %{user: user} do
      {:ok, pending} = Tasks.create_task(user, %{
        title: "Pending task",
        task_type: "send_email"
      })

      {:ok, completed} = Tasks.create_task(user, %{
        title: "Completed task",
        task_type: "send_email"
      })

      Tasks.complete_task(completed, %{result: "success"})

      pending_tasks = Tasks.list_pending_tasks(user)
      assert length(pending_tasks) == 1
      assert hd(pending_tasks).id == pending.id
    end

    test "complete_task/2 marks task as completed", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{
        title: "Test task",
        task_type: "send_email"
      })

      result = %{message_id: "123", status: "sent"}
      assert {:ok, completed_task} = Tasks.complete_task(task, result)

      assert completed_task.status == "completed"
      assert completed_task.completed_at != nil
      assert completed_task.metadata.result == result
    end

    test "fail_task/2 marks task as failed", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{
        title: "Test task",
        task_type: "send_email"
      })

      error = "Network timeout"
      assert {:ok, failed_task} = Tasks.fail_task(task, error)

      assert failed_task.status == "failed"
      assert failed_task.metadata.error == error
    end
  end
end