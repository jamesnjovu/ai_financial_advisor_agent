defmodule AppWeb.ChatLive do
  use AppWeb, :live_view

  alias App.Chat
  alias App.AI.{Agent, KnowledgeBase}
  alias App.Tasks
  import Ecto.Query

  @impl true
  def mount(%{"conversation_id" => conversation_id}, _session, socket) do
    user = socket.assigns.current_user
    conversation = Chat.get_conversation(conversation_id, user)

    if conversation do
      messages = Chat.get_conversation_messages(conversation)

      socket
      |> assign(:page_title, "Chat")
      |> assign(:sidebar_open, false)
      |> assign(:conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:message_input, "")
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:current_page, :chat)
      |> assign(:current_conversation_id, conversation.id)
      |> ok()
    else
      push_navigate(socket, to: ~p"/chat")
      |> ok()
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(:page_title, "Chat")
    |> assign(:sidebar_open, false)
    |> assign(:conversation, nil)
    |> assign(:messages, [])
    |> assign(:message_input, "")
    |> assign(:loading, false)
    |> assign(:error, nil)
    |> assign(:current_page, :chat)
    |> assign(:current_conversation_id, nil)
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
  def handle_event("validate", %{"message" => %{"content" => content}}, socket) do
    assign(socket, message_input: content)
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

      # Send to AI agent asynchronously
      send(self(), {:generate_ai_response, conversation, String.trim(content)})

      assign(socket,
        conversation: conversation,
        messages: messages,
        message_input: "",
        loading: true,
        error: nil,
        current_conversation_id: conversation.id
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

        socket
        |> assign(:messages, updated_messages)
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