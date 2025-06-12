defmodule AppWeb.SettingsLive do
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Get all data needed for different tabs
    {instructions_count, active_instructions_count, user_instructions} = get_instructions_data(user)
    {recent_tasks, pending_tasks_count, task_stats} = get_tasks_data(user)
    sync_status = get_sync_status(user)
    integration_status = get_integration_status(user)

    socket
    |> assign(user: user)
    |> assign(active_tab: "integrations")  # Default to integrations tab
    |> assign(instructions_count: instructions_count)
    |> assign(active_instructions_count: active_instructions_count)
    |> assign(user_instructions: user_instructions)
    |> assign(recent_tasks: recent_tasks)
    |> assign(pending_tasks_count: pending_tasks_count)
    |> assign(task_stats: task_stats)
    |> assign(sync_status: sync_status)
    |> assign(integration_status: integration_status)
    |> assign(:page_title, "Settings")
    |> ok()
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

    # Update user in database
    App.Accounts.update_user(user, %{
      hubspot_access_token: nil,
      hubspot_refresh_token: nil,
      hubspot_portal_id: nil
    })

    case App.Auth.HubSpotOAuth.revoke_token(user) do
      {:ok, _} ->
        integration_status = get_integration_status(user)
        socket
        |> assign(integration_status: integration_status)
        |> put_flash(:info, "HubSpot disconnected successfully")
        |> noreply()

      {:error, reason} ->
        integration_status = get_integration_status(user)
        socket
        |> assign(integration_status: integration_status)
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
            updated_instructions = Enum.reject(socket.assigns.user_instructions, &(&1.id == instruction_id))
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
    {recent_tasks, pending_tasks_count, task_stats} = get_tasks_data(user)

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
            {recent_tasks, pending_tasks_count, task_stats} = get_tasks_data(user)

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

  @impl true
  def handle_event("sync_knowledge_base", _params, socket) do
    user = socket.assigns.current_user

    # Trigger background sync
    Task.start(fn ->
      App.AI.KnowledgeBase.sync_user_data(user)
    end)

    socket
    |> put_flash(:info, "Knowledge base sync started in background")
    |> noreply()
  end

  # Helper functions
  defp get_instructions_data(user) do
    instructions_count = App.Tasks.count_user_instructions(user)
    active_instructions_count = App.Tasks.count_active_instructions(user)
    user_instructions = App.Tasks.list_user_instructions(user)

    {instructions_count, active_instructions_count, user_instructions}
  end

  defp get_tasks_data(user) do
    recent_tasks = App.Tasks.list_user_tasks(user, limit: 20)
    pending_tasks_count = length(App.Tasks.list_pending_tasks(user))
    task_stats = App.Tasks.get_task_stats(user)

    {recent_tasks, pending_tasks_count, task_stats}
  end

  defp get_sync_status(user) do
    App.AI.KnowledgeBase.get_sync_status(user)
  end

  defp get_integration_status(user) do
    %{
      gmail_connected: !is_nil(user.google_access_token),
      hubspot_connected: !is_nil(user.hubspot_access_token),
      gmail_webhook_active: gmail_webhook_active?(user),
      calendar_webhook_active: calendar_webhook_active?(user)
    }
  end

  defp gmail_webhook_active?(user) do
    # Check if Gmail webhook is active
    case App.Repo.get_by(App.Webhooks.GmailChannel, user_id: user.id) do
      nil -> false
      %{active: active, expiration: exp} ->
        active && DateTime.compare(exp, DateTime.utc_now()) == :gt
    end
  end

  defp calendar_webhook_active?(user) do
    # Check if any calendar webhook is active
    import Ecto.Query

    App.Repo.exists?(
      from c in App.Webhooks.CalendarChannel,
      where: c.user_id == ^user.id and c.active == true and c.expiration > ^DateTime.utc_now()
    )
  end

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

  defp tab_class(current_tab, tab_name) do
    base_classes = "relative px-6 py-3 text-sm font-medium rounded-lg transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-gray-900"

    if current_tab == tab_name do
      "#{base_classes} bg-blue-600 text-white shadow-lg"
    else
      "#{base_classes} text-gray-400 hover:text-white hover:bg-gray-700"
    end
  end

  defp tab_indicator_class(current_tab, tab_name) do
    if current_tab == tab_name do
      "absolute inset-x-0 bottom-0 h-0.5 bg-blue-400 rounded-full"
    else
      "absolute inset-x-0 bottom-0 h-0.5 bg-transparent"
    end
  end
end
