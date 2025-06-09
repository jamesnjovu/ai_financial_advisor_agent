defmodule App.AI.KnowledgeBaseTest do
  use App.DataCase, async: true

  alias App.AI.KnowledgeBase
  alias App.Knowledge.KnowledgeEntry
  alias App.Accounts

  describe "knowledge base operations" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        google_access_token: "test_token"
      })

      {:ok, conversation} = Chat.create_conversation(user, %{title: "Test Chat"})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{current_user_id: user.id})

      %{conn: conn, user: user, conversation: conversation}
    end

    test "updates UI when AI responds", %{conn: conn, conversation: conversation} do
      {:ok, view, _html} = live(conn, ~p"/chat/#{conversation.id}")

      # Send message
      view
      |> form("#message-form", message: %{content: "What's my portfolio status?"})
      |> render_submit()

      # Should show loading state
      html = render(view)
      assert html =~ "AI is analyzing" or html =~ "loading"
    end

    test "handles AI processing errors gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")

      # This would normally trigger AI processing
      # In test, it might fail due to missing API keys
      view
      |> form("#message-form", message: %{content: "Schedule a meeting"})
      |> render_submit()

      # Should not crash the LiveView
      assert Process.alive?(view.pid)
    end
  end
end
