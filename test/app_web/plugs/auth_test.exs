defmodule AppWeb.Plugs.AuthTest do
  use AppWeb.ConnCase
  import Phoenix.LiveViewTest

  alias AppWeb.Plugs.Auth
  alias App.Accounts

  describe "authentication plug" do
    test "assigns current_user when session has valid user_id", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })

      conn =
        conn
        |> init_test_session(%{current_user_id: user.id})
        |> Auth.call([])

      assert conn.assigns.current_user.id == user.id
    end

    test "does not assign current_user when no session", %{conn: conn} do
      conn = Auth.call(conn, [])

      refute Map.has_key?(conn.assigns, :current_user)
    end

    test "clears session when user_id is invalid", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{current_user_id: 999999})
        |> Auth.call([])

      assert get_session(conn, :current_user_id) == nil
    end
  end

  describe "require_authenticated_user" do
    test "allows access for authenticated user", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com"})

      conn =
        conn
        |> assign(:current_user, user)
        |> Auth.require_authenticated_user([])

      refute conn.halted
    end

    test "redirects unauthenticated user", %{conn: conn} do
      conn = Auth.require_authenticated_user(conn, [])

      assert redirected_to(conn) == ~p"/"
      assert get_flash(conn, :error) =~ "Please sign in"
      assert conn.halted
    end
  end

  describe "redirect_if_user_is_authenticated" do
    test "redirects authenticated user to chat", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com"})

      conn =
        conn
        |> assign(:current_user, user)
        |> Auth.redirect_if_user_is_authenticated([])

      assert redirected_to(conn) == ~p"/chat"
      assert conn.halted
    end

    test "allows access for unauthenticated user", %{conn: conn} do
      conn = Auth.redirect_if_user_is_authenticated(conn, [])

      refute conn.halted
    end
  end

  describe "on_mount authentication" do
    test "ensures authenticated access to live views" do
      # This would be tested in live view tests with proper setup
      assert {:ensure_authenticated, _params, _session, _socket} =
               Auth.on_mount(:ensure_authenticated, %{}, %{}, %Phoenix.LiveView.Socket{})
    end
  end
end
