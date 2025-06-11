defmodule AppWeb.SettingsLive do
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    instructions_count = App.Tasks.count_user_instructions(user)
    active_instructions_count = App.Tasks.count_active_instructions(user)

    # Get all user instructions for management
    user_instructions = App.Tasks.list_user_instructions(user)

    # Get recent tasks with status
    recent_tasks = App.Tasks.list_user_tasks(user, limit: 20)
    pending_tasks_count = length(App.Tasks.list_pending_tasks(user))

    # Get task statistics
    task_stats = App.Tasks.get_task_stats(user)

    socket
    |> assign(hubspot_connected: !is_nil(user.hubspot_access_token))
    |> assign(gmail_connected: !is_nil(user.google_access_token))
    |> assign(instructions_count: instructions_count)
    |> assign(active_instructions_count: active_instructions_count)
    |> assign(user_instructions: user_instructions)
    |> assign(recent_tasks: recent_tasks)
    |> assign(pending_tasks_count: pending_tasks_count)
    |> assign(task_stats: task_stats)
    |> assign(active_tab: "profile")  # Default tab
    |> assign(:page_title, "Settings")
    |> assign(:current_page, :settings)
    |> assign(:sidebar_open, false)
    |> ok()
  end

  @impl true
  def handle_info({:sidebar_toggle, open}, socket) do
    assign(socket, sidebar_open: open)
    |> noreply()
  end

  @impl true
  def handle_info(:new_conversation, socket) do
    push_navigate(socket, to: ~p"/chat")
    |> noreply()
  end

  @impl true
  def handle_info({:select_conversation, conversation_id}, socket) do
    push_navigate(socket, to: ~p"/chat/#{conversation_id}")
    |> noreply()
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket
    |> assign(active_tab: tab)
    |> noreply()
  end

  @impl true
  def handle_event("connect_hubspot", _params, socket) do
    redirect(socket, to: ~p"/auth/hubspot")
    |> noreply()
  end

  @impl true
  def handle_event("disconnect_hubspot", _params, socket) do
    user = socket.assigns.current_user
    App.Accounts.update_user(user, %{
      hubspot_access_token: nil,
      hubspot_refresh_token: nil,
      hubspot_portal_id: nil
    })
    case App.Auth.HubSpotOAuth.revoke_token(user) do
      {:ok, _} ->
        socket
        |> assign(hubspot_connected: false)
        |> put_flash(:info, "HubSpot disconnected successfully")
        |> noreply()

      {:error, reason} ->
        # Token revocation failed, but still remove from database
        socket
        |> assign(hubspot_connected: false)
        |> put_flash(:warning, "HubSpot disconnected, but token revocation failed: #{reason}")
        |> noreply()
    end
  end

  @impl true
  def handle_event("toggle_instruction", %{"id" => instruction_id}, socket) do
    instruction_id = String.to_integer(instruction_id)

    case Enum.find(socket.assigns.user_instructions, &(&1.id == instruction_id)) do
      nil ->
        socket
        |> put_flash(:error, "Instruction not found")
        |> noreply()

      instruction ->
        case App.Tasks.update_instruction(instruction, %{active: !instruction.active}) do
          {:ok, updated_instruction} ->
            # Update the instructions list
            updated_instructions =
              Enum.map(socket.assigns.user_instructions, fn instr ->
                if instr.id == instruction_id, do: updated_instruction, else: instr
              end)

            active_count = Enum.count(updated_instructions, & &1.active)

            socket
            |> assign(user_instructions: updated_instructions)
            |> assign(active_instructions_count: active_count)
            |> put_flash(:info, if(updated_instruction.active, do: "Instruction activated", else: "Instruction deactivated"))
            |> noreply()

          {:error, _changeset} ->
            socket
            |> put_flash(:error, "Failed to update instruction")
            |> noreply()
        end
    end
  end

  @impl true
  def handle_event("delete_instruction", %{"id" => instruction_id}, socket) do
    instruction_id = String.to_integer(instruction_id)

    case Enum.find(socket.assigns.user_instructions, &(&1.id == instruction_id)) do
      nil ->
        socket
        |> put_flash(:error, "Instruction not found")
        |> noreply()

      instruction ->
        case App.Tasks.delete_instruction(instruction) do
          {:ok, _} ->
            # Remove from the list
            updated_instructions =
              Enum.reject(socket.assigns.user_instructions, &(&1.id == instruction_id))

            active_count = Enum.count(updated_instructions, & &1.active)
            total_count = length(updated_instructions)

            socket
            |> assign(user_instructions: updated_instructions)
            |> assign(instructions_count: total_count)
            |> assign(active_instructions_count: active_count)
            |> put_flash(:info, "Instruction deleted successfully")
            |> noreply()

          {:error, _changeset} ->
            socket
            |> put_flash(:error, "Failed to delete instruction")
            |> noreply()
        end
    end
  end

  @impl true
  def handle_event("refresh_tasks", _params, socket) do
    user = socket.assigns.current_user
    recent_tasks = App.Tasks.list_user_tasks(user, limit: 20)
    pending_tasks_count = length(App.Tasks.list_pending_tasks(user))
    task_stats = App.Tasks.get_task_stats(user)

    socket
    |> assign(recent_tasks: recent_tasks)
    |> assign(pending_tasks_count: pending_tasks_count)
    |> assign(task_stats: task_stats)
    |> put_flash(:info, "Tasks refreshed")
    |> noreply()
  end

  @impl true
  def handle_event("retry_failed_task", %{"id" => task_id}, socket) do
    user = socket.assigns.current_user
    task_id = String.to_integer(task_id)

    case App.Tasks.get_task(task_id, user) do
      nil ->
        socket
        |> put_flash(:error, "Task not found")
        |> noreply()

      task ->
        case App.Tasks.update_task(task, %{status: "pending", next_action_at: DateTime.utc_now()}) do
          {:ok, _updated_task} ->
            # Refresh the tasks list
            recent_tasks = App.Tasks.list_user_tasks(user, limit: 20)
            pending_tasks_count = length(App.Tasks.list_pending_tasks(user))
            task_stats = App.Tasks.get_task_stats(user)

            socket
            |> assign(recent_tasks: recent_tasks)
            |> assign(pending_tasks_count: pending_tasks_count)
            |> assign(task_stats: task_stats)
            |> put_flash(:info, "Task queued for retry")
            |> noreply()

          {:error, _changeset} ->
            socket
            |> put_flash(:error, "Failed to retry task")
            |> noreply()
        end
    end
  end

  # Helper functions
  defp format_datetime(datetime) do
    case datetime do
      %NaiveDateTime{} = naive_dt ->
        naive_dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
      %DateTime{} = dt ->
        dt |> DateTime.truncate(:second) |> DateTime.to_string()
      _ ->
        "Unknown"
    end
  end

  defp status_class(status) do
    case status do
      "completed" -> "bg-green-100 text-green-800 border-green-200"
      "failed" -> "bg-red-100 text-red-800 border-red-200"
      "in_progress" -> "bg-blue-100 text-blue-800 border-blue-200"
      "pending" -> "bg-yellow-100 text-yellow-800 border-yellow-200"
      "waiting" -> "bg-gray-100 text-gray-800 border-gray-200"
      _ -> "bg-gray-100 text-gray-800 border-gray-200"
    end
  end

  defp status_icon(status) do
    case status do
      "completed" -> "hero-check-circle"
      "failed" -> "hero-x-circle"
      "in_progress" -> "hero-arrow-path"
      "pending" -> "hero-clock"
      "waiting" -> "hero-pause-circle"
      _ -> "hero-question-mark-circle"
    end
  end

  defp truncate_text(text, max_length \\ 50) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp format_triggers(triggers) when is_list(triggers) do
    triggers
    |> Enum.map(&String.replace(&1, "_", " "))
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(", ")
  end

  defp format_triggers(_), do: "No triggers"
end