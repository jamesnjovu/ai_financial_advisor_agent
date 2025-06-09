defmodule AppWeb.SettingsLive do
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    instructions_count = App.Tasks.count_user_instructions(user)
    active_instructions_count = App.Tasks.count_active_instructions(user)

    socket
    |> assign(hubspot_connected: !is_nil(user.hubspot_access_token))
    |> assign(gmail_connected: !is_nil(user.google_access_token))
    |> assign(instructions_count: instructions_count)
    |> assign(active_instructions_count: active_instructions_count)
    |> assign(:page_title, "Settings")
    |> ok()
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
end
