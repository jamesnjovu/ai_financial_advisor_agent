defmodule AppWeb.AuthControllerTest do
  use AppWeb.ConnCase

  describe "authentication flow" do
    test "GET /auth/login redirects to Google OAuth", %{conn: conn} do
      conn = get(conn, ~p"/auth/login")

      assert redirected_to(conn) =~ "accounts.google.com"
      assert get_session(conn, :oauth_state) != nil
    end

    test "GET /auth/google/callback with invalid state returns error", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{oauth_state: "valid_state"})
        |> get(~p"/auth/google/callback", %{code: "test_code", state: "invalid_state"})

      assert redirected_to(conn) == ~p"/"
      assert get_flash(conn, :error) =~ "Invalid state"
    end

    test "logout clears session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{current_user_id: 123})
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :current_user_id) == nil
      assert get_flash(conn, :info) =~ "Logged out"
    end
  end

  describe "hubspot integration" do
    test "GET /auth/hubspot requires authenticated user", %{conn: conn} do
      conn = get(conn, ~p"/auth/hubspot")

      assert redirected_to(conn) == ~p"/"
      assert get_flash(conn, :error) =~ "Please sign in first"
    end

    test "GET /auth/hubspot with authenticated user redirects to HubSpot", %{conn: conn} do
      {:ok, user} = App.Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })

      conn =
        conn
        |> init_test_session(%{current_user_id: user.id})
        |> get(~p"/auth/hubspot")

      assert redirected_to(conn) =~ "app.hubspot.com"
    end
  end
end
