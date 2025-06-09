defmodule AppWeb.ChatLive do
  use AppWeb, :live_view

  alias App.Chat
  alias App.AI.{Agent, KnowledgeBase}
  alias App.Tasks

  @impl true
  def mount(%{"conversation_id" => conversation_id}, _session, socket) do
    user = socket.assigns.current_user
    conversation = Chat.get_conversation(conversation_id, user)

    if conversation do
      messages = Chat.get_conversation_messages(conversation)
      conversations = Chat.list_conversations(user)

      socket
      |> assign(:page_title, "Chat")
      |> assign(:sidebar_open, false)
      |> assign(:conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:conversations, conversations)
      |> assign(:message_input, "")
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:sync_status, get_sync_status(user))
      |> assign(:pending_tasks, Tasks.list_pending_tasks(user))
      |> ok()
    else
      push_navigate(socket, to: ~p"/chat")
      |> ok()
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    conversations = Chat.list_conversations(user)

    socket
    |> assign(:page_title, "Chat")
    |> assign(:sidebar_open, false)
    |> assign(:conversation, nil)
    |> assign(:messages, [])
    |> assign(:conversations, conversations)
    |> assign(:message_input, "")
    |> assign(:loading, false)
    |> assign(:error, nil)
    |> assign(:sync_status, get_sync_status(user))
    |> assign(:pending_tasks, Tasks.list_pending_tasks(user))
    |> ok()
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    assign(socket, sidebar_open: !socket.assigns.sidebar_open)
    |> noreply()
  end

  @impl true
  def handle_event("select_conversation", %{"id" => conversation_id}, socket) do
    push_navigate(socket, to: ~p"/chat/#{conversation_id}")
    |> noreply()
  end

  @impl true
  def handle_event("validate", %{"message" => %{"content" => content}}, socket) do
    assign(socket, message_input: content)
    |> noreply()
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    user = socket.assigns.current_user
    push_navigate(socket, to: ~p"/chat")
    |> noreply()
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    if String.trim(content) != "" do
      user = socket.assigns.current_user

      # Create conversation if it doesn't exist (first message scenario)
      conversation = case socket.assigns.conversation do
        nil ->
          {:ok, conv} = Chat.create_conversation(user, %{title: generate_title(content)})
          conv

        existing_conv ->
          existing_conv
      end

      # Create user message
      {:ok, user_message} = Chat.create_message(conversation, %{
        role: "user",
        content: String.trim(content)
      })

      # Update messages list
      messages = socket.assigns.messages ++ [user_message]

      # Update conversations list if we just created a new conversation
      conversations = if socket.assigns.conversation == nil do
        Chat.list_conversations(user)
      else
        socket.assigns.conversations
      end

      # Send to AI agent asynchronously
      send(self(), {:generate_ai_response, conversation, String.trim(content)})

      assign(socket,
        conversation: conversation,
        conversations: conversations,
        messages: messages,
        message_input: "",
        loading: true,
        error: nil
      )
      |> noreply()
    else
      noreply(socket)
    end
  end

  @impl true
  def handle_info({:generate_ai_response, conversation, message}, socket) do
    user = socket.assigns.current_user

    case Agent.process_message(conversation, message, user) do
      {:ok, ai_message} ->
        # Refresh messages and update UI
        updated_messages = Chat.get_conversation_messages(conversation)
        updated_pending_tasks = Tasks.list_pending_tasks(user)

        socket
        |> assign(:messages, updated_messages)
        |> assign(:pending_tasks, updated_pending_tasks)
        |> assign(:loading, false)
        |> assign(:error, nil)
        |> noreply()

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, reason)
        |> noreply()
    end
  end

  defp get_sync_status(user) do
    knowledge_status = KnowledgeBase.get_sync_status(user)

    %{
      gmail: if(user.google_access_token && knowledge_status.email_entries > 0, do: knowledge_status.status, else: "not_connected"),
      hubspot: if(user.hubspot_access_token && knowledge_status.hubspot_entries > 0, do: knowledge_status.status, else: "not_connected")
    }
  end

  defp generate_title(content) do
    # Generate a simple title from the first part of the message
    content
    |> String.slice(0, 50)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
         "" -> "New Conversation"
         title -> title <> if String.length(content) > 50, do: "...", else: ""
       end
  end

  defp format_date(datetime) do
    case datetime do
      %NaiveDateTime{} = naive_dt ->
        naive_dt
        |> NaiveDateTime.to_date()
        |> format_date_string()

      %DateTime{} = dt ->
        dt
        |> DateTime.to_date()
        |> format_date_string()

      _ ->
        "Unknown date"
    end
  end

  defp format_date_string(date) do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    cond do
      Date.compare(date, today) == :eq -> "Today"
      Date.compare(date, yesterday) == :eq -> "Yesterday"
      true -> Calendar.strftime(date, "%b %d")
    end
  end

  defp format_time(datetime) do
    case datetime do
      %NaiveDateTime{} = naive_dt ->
        naive_dt
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_time()
        |> format_time_string()

      %DateTime{} = dt ->
        dt
        |> DateTime.truncate(:second)
        |> DateTime.to_time()
        |> format_time_string()

      _ ->
        "Unknown time"
    end
  end

  defp format_time_string(time) do
    Calendar.strftime(time, "%I:%M %p")
  end

end
