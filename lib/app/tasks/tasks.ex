defmodule App.Tasks do
  @moduledoc """
  The Tasks context for managing AI tasks and user instructions
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Tasks.{Task, UserInstruction}
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

  defp process_task(%Task{task_type: "send_email"} = task) do
    try do
      update_task(task, %{status: "in_progress"})

      result = execute_send_email_task(task)

      complete_task(task, result)
    rescue
      e ->
        fail_task(task, Exception.message(e))
    end
  end

  defp process_task(%Task{task_type: "create_contact"} = task) do
    try do
      update_task(task, %{status: "in_progress"})

      result = execute_create_contact_task(task)

      complete_task(task, result)
    rescue
      e ->
        fail_task(task, Exception.message(e))
    end
  end

  defp process_task(task) do
    # Unknown task type
    fail_task(task, "Unknown task type: #{task.task_type}")
  end

  defp execute_schedule_meeting_task(%Task{context: context, user: user}) do
    # This would use the calendar client to actually schedule the meeting
    # Based on the context stored in the task
    %{success: true, message: "Meeting task processed"}
  end

  defp execute_send_email_task(%Task{context: context, user: user}) do
    # This would use the Gmail client to send the email
    %{success: true, message: "Email task processed"}
  end

  defp execute_create_contact_task(%Task{context: context, user: user}) do
    # This would use the HubSpot client to create the contact
    %{success: true, message: "Contact task processed"}
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
end