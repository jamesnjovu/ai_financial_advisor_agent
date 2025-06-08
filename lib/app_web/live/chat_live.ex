defmodule AppWeb.ChatLive do
  use AppWeb, :live_view

  alias App.Chat

  @impl true
  def mount(%{"conversation_id" => conversation_id}, _session, socket) do
    user = socket.assigns.current_user
    conversation = Chat.get_conversation(conversation_id, user)

    if conversation do
      messages = Chat.get_conversation_messages(conversation)
      conversations = Chat.list_conversations(user)

      socket
      |> assign(:sidebar_open, false)
      |> assign(:conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:conversations, conversations)
      |> assign(:message_input, "")
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:sync_status, get_sync_status(user))
      |> assign(:pending_tasks, [])
      |> ok()
    else
      {:ok, push_navigate(socket, to: ~p"/chat")}
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    conversations = Chat.list_conversations(user)

    conversation = case conversations do
      [] ->
        {:ok, conv} = Chat.create_conversation(user, %{title: "New Conversation"})
        conv

      [latest | _] ->
        latest
    end

    messages = Chat.get_conversation_messages(conversation)

    socket
    |> assign(:sidebar_open, false)
    |> assign(:conversation, conversation)
    |> assign(:messages, messages)
    |> assign(:conversations, conversations)
    |> assign(:message_input, "")
    |> assign(:loading, false)
    |> assign(:error, nil)
    |> assign(:sync_status, get_sync_status(user))
    |> assign(:pending_tasks, [])
    |> ok()
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => conversation_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/chat/#{conversation_id}")}
  end

  @impl true
  def handle_event("validate", %{"message" => %{"content" => content}}, socket) do
    {:noreply, assign(socket, message_input: content)}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    user = socket.assigns.current_user
    {:ok, conversation} = Chat.create_conversation(user, %{title: "New Conversation"})

    {:noreply, push_navigate(socket, to: ~p"/chat/#{conversation.id}")}
  end

  @impl true
  def handle_event("sync_data", _params, socket) do
    user = socket.assigns.current_user

    # Start background sync
    send(self(), :sync_data)

    socket =
      socket
      |> assign(:sync_status, %{gmail: "syncing", hubspot: "syncing"})
      |> put_flash(:info, "Syncing your data...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_instruction", %{"instruction" => instruction}, socket) do
    user = socket.assigns.current_user

    case Tasks.create_user_instruction(user, instruction, ["email_received", "calendar_event_created"]) do
      {:ok, _instruction} ->
        socket = put_flash(socket, :info, "Instruction added successfully!")
        {:noreply, socket}
      {:error, _changeset} ->
        socket = put_flash(socket, :error, "Failed to add instruction")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    if String.trim(content) != "" do
      user = socket.assigns.current_user
      conversation = socket.assigns.conversation

      # Create user message
      {:ok, user_message} = Chat.create_message(conversation, %{
        role: "user",
        content: String.trim(content)
      })

      # Update messages list
      messages = socket.assigns.messages ++ [user_message]

      # Send to AI agent asynchronously
      send(self(), {:generate_ai_response, String.trim(content)})

      {:noreply, assign(socket,
        messages: messages,
        message_input: "",
        loading: true,
        error: nil
      )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:generate_ai_response, message}, socket) do

  end

  defp get_sync_status(user) do
    %{
      gmail: if(user.google_access_token, do: "connected", else: "not_connected"),
      hubspot: if(user.hubspot_access_token, do: "connected", else: "not_connected")
    }
  end

  defp format_date(datetime) do
    case datetime do
      %NaiveDateTime{} = naive_dt ->
        naive_dt
        |> NaiveDateTime.to_date()
        |> Date.to_string()

      %DateTime{} = dt ->
        dt
        |> DateTime.to_date()
        |> Date.to_string()

      _ ->
        "Unknown date"
    end
  end

  defp format_time(datetime) do
    case datetime do
      %NaiveDateTime{} = naive_dt ->
        naive_dt
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_time()
        |> Time.to_string()

      %DateTime{} = dt ->
        dt
        |> DateTime.truncate(:second)
        |> DateTime.to_time()
        |> Time.to_string()

      _ ->
        "Unknown time"
    end
  end
end