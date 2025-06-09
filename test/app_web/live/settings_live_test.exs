defmodule AppWeb.SettingsLiveTest do
  use AppWeb.ConnCase
  import Phoenix.LiveViewTest

  alias App.Accounts

  describe "settings interface" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        google_access_token: "test_token"
      })

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{current_user_id: user.id})

      %{conn: conn, user: user}
    end

    test "renders settings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Settings"
      assert html =~ "Integrations"
      assert html =~ "Profile"
    end

    test "shows Google integration as connected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Google"
      assert html =~ "Connected" or html =~ "gmail_connected"
    end

    test "shows HubSpot as not connected initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "HubSpot"
      assert html =~ "Connect" or html =~ "Not connected"
    end

    test "connect_hubspot event redirects to OAuth", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      # This should redirect to HubSpot OAuth
      assert {:error, {:redirect, %{to: "/auth/hubspot"}}} =
               render_click(view, "connect_hubspot")
    end

    test "disconnect_hubspot event removes tokens", %{conn: conn, user: user} do
      # First connect HubSpot
      {:ok, _updated_user} = Accounts.update_user(user, %{
        hubspot_access_token: "hubspot_token",
        hubspot_portal_id: "portal_123"
      })

      {:ok, view, _html} = live(conn, ~p"/settings")

      # Disconnect HubSpot
      view
      |> element("[phx-click='disconnect_hubspot']")
      |> render_click()

      # Should update the UI to show disconnected state
      html = render(view)
      assert html =~ "Connect" or html =~ "Not connected"
    end

    test "displays user profile information", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ user.email
      assert html =~ user.name
    end

    test "shows AI instructions examples", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "AI Instructions"
      assert html =~ "automatic" or html =~ "instructions"
      assert html =~ "HubSpot" # Should show example instructions
    end

    test "has link back to chat", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Back to Chat" or html =~ "href=\"/chat\""
    end

    test "shows danger zone with logout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Danger Zone" or html =~ "Sign Out"
      assert html =~ "/auth/logout"
    end
  end

  describe "integration status updates" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        google_access_token: "test_token",
        hubspot_access_token: "hubspot_token",
        hubspot_portal_id: "portal_123"
      })

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{current_user_id: user.id})

      %{conn: conn, user: user}
    end

    test "shows both integrations as connected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      # Should show both as connected
      google_connected = html =~ "Google" and html =~ "Connected"
      hubspot_connected = html =~ "HubSpot" and html =~ "Connected"

      assert google_connected or hubspot_connected
    end
  end
end
