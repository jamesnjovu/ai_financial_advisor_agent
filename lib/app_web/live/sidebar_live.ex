defmodule AppWeb.SidebarLive do
  use AppWeb, :live_component
  alias App.{Chat, Tasks}

  @impl true
  def update(assigns, socket) do
    user = assigns.current_user
    conversations = Chat.list_conversations(user)
    pending_tasks = Tasks.list_pending_tasks(user)
    knowledge_stats = get_knowledge_stats(user)

    socket
    |> assign(assigns)
    |> assign(:conversations, conversations)
    |> assign(:pending_tasks, pending_tasks)
    |> assign(:knowledge_stats, knowledge_stats)
    |> assign(:sidebar_open, assigns[:sidebar_open] || false)
    |> ok()
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    send(self(), {:sidebar_toggle, !socket.assigns.sidebar_open})
    noreply(socket)
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    send(self(), :new_conversation)
    noreply(socket)
  end

  @impl true
  def handle_event("select_conversation", %{"id" => conversation_id}, socket) do
    send(self(), {:select_conversation, conversation_id})
    noreply(socket)
  end

  defp render_sidebar_content(assigns) do
    ~H"""
    <!-- Header -->
    <div class="p-6 border-b border-gray-700/50 bg-gradient-to-r from-gray-800/50 to-gray-700/30">
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-3">
          <div class="w-10 h-10 bg-gradient-to-br from-blue-500 to-blue-600 rounded-xl flex items-center justify-center shadow-lg lg:w-12 lg:h-12">
            <svg
              class="w-6 h-6 text-white lg:w-7 lg:h-7"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
              >
              </path>
            </svg>
          </div>
          <div>
            <h1 class="text-lg lg:text-xl font-bold text-white">AI Financial Advisor</h1>
            <p class="text-xs lg:text-sm text-gray-400">Intelligent Assistant</p>
          </div>
        </div>
        <button
          phx-click="toggle_sidebar"
          phx-target={@myself}
          class="lg:hidden p-2 rounded-lg text-gray-400 hover:text-white hover:bg-gray-700/50 transition-all duration-200"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            >
            </path>
          </svg>
        </button>
      </div>

      <button
        phx-click="new_conversation"
        phx-target={@myself}
        class="mt-4 w-full inline-flex items-center justify-center px-4 py-3 bg-gradient-to-r from-gray-700 to-gray-600 hover:from-gray-600 hover:to-gray-500 text-white text-sm font-medium rounded-xl transition-all duration-200 shadow-lg hover:shadow-xl transform hover:scale-[1.02] border border-gray-600/50"
      >
        <svg class="w-4 h-4 lg:w-5 lg:h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 4v16m8-8H4"
          >
          </path>
        </svg>
        New Conversation
      </button>
    </div>

    <!-- Pending Tasks -->
    <%= if Enum.any?(@pending_tasks) do %>
      <div class="p-4 border-b border-gray-700/50">
        <div class="flex items-center justify-between mb-3">
          <h3 class="text-sm font-semibold text-gray-200">Active Tasks</h3>
          <span class="bg-blue-500/20 text-blue-400 text-xs font-medium px-2 py-1 rounded-full">
            {length(@pending_tasks)}
          </span>
        </div>
        <div class="space-y-2 max-h-32 overflow-y-auto">
          <%= for task <- Enum.take(@pending_tasks, 3) do %>
            <div class="p-3 bg-gray-800/60 rounded-lg border border-gray-700/50">
              <div class="font-medium text-white text-sm mb-1">{task.title}</div>
              <div class="flex items-center justify-between">
                <span class="text-xs text-gray-400">{task.status}</span>
                <div class="w-2 h-2 bg-blue-400 rounded-full animate-pulse"></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <!-- Conversations List -->
    <div class="flex-1 overflow-y-auto">
      <div class="p-2">
        <%= if Enum.any?(@conversations) do %>
          <%= for conv <- @conversations do %>
            <div
              phx-click="select_conversation"
              phx-value-id={conv.id}
              phx-target={@myself}
              class={[
                "group p-4 rounded-xl cursor-pointer mb-2 transition-all duration-200",
                if(@current_conversation_id && conv.id == @current_conversation_id,
                  do:
                    "bg-gradient-to-r from-blue-600/20 to-blue-500/10 border border-blue-500/30 shadow-lg",
                  else: "hover:bg-gray-800/60 border border-transparent"
                )
              ]}
            >
              <div class="flex items-start justify-between">
                <div class="flex-1 min-w-0">
                  <div class="font-medium text-sm text-white truncate group-hover:text-blue-300 transition-colors">
                    {conv.title || "New Conversation"}
                  </div>
                  <div class="text-xs text-gray-400 mt-1 flex items-center">
                    <svg
                      class="w-3 h-3 mr-1"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                      >
                      </path>
                    </svg>
                    {format_date(conv.updated_at)}
                  </div>
                </div>
                <%= if @current_conversation_id && conv.id == @current_conversation_id do %>
                  <div class="w-2 h-2 bg-blue-400 rounded-full animate-pulse ml-2"></div>
                <% end %>
              </div>
            </div>
          <% end %>
        <% else %>
          <div class="p-4 text-center text-gray-500">
            <svg
              class="w-8 h-8 mx-auto mb-2 opacity-50"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-3.582 8-8 8a8.955 8.955 0 01-4.126-.98L3 21l1.98-5.874A8.955 8.955 0 013 12c0-4.418 3.582-8 8-8s8 3.582 8 8z"
              >
              </path>
            </svg>
            <p class="text-sm">No conversations yet</p>
          </div>
        <% end %>
      </div>
    </div>

    <!-- User Info -->
    <div class="p-4 border-t border-gray-700/50 bg-gray-800/30">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="w-10 h-10 bg-gradient-to-br from-blue-500 to-purple-600 rounded-xl flex items-center justify-center shadow-lg">
            <span class="text-white text-sm font-bold">
              {String.first(@current_user.name || @current_user.email) |> String.upcase()}
            </span>
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-medium text-white truncate">
              {@current_user.name || @current_user.email}
            </div>
            <div class="text-xs text-gray-400 flex items-center">
              <%= if @current_user.hubspot_access_token do %>
                <div class="w-2 h-2 bg-emerald-400 rounded-full mr-1"></div>
                All integrations active
              <% else %>
                <div class="w-2 h-2 bg-yellow-400 rounded-full mr-1"></div>
                Setup pending
              <% end %>
            </div>
          </div>
        </div>
        <.link
          navigate={if @current_page == :settings, do: ~p"/chat", else: ~p"/settings"}
          class="p-2 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-lg transition-all duration-200"
          title={if @current_page == :settings, do: "Back to Chat", else: "Settings"}
        >
          <%= if @current_page == :settings do %>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-3.582 8-8 8a8.955 8.955 0 01-4.126-.98L3 21l1.98-5.874A8.955 8.955 0 013 12c0-4.418 3.582-8 8-8s8 3.582 8 8z"
              >
              </path>
            </svg>
          <% else %>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              >
              </path>
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              >
              </path>
            </svg>
          <% end %>
        </.link>
      </div>
    </div>
    """
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

  defp get_knowledge_stats(user) do
    %{
      user_instruction: App.Tasks.count_user_instructions(user)
    }
  end
end