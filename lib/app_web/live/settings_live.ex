defmodule AppWeb.SettingsLive do
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    socket
    |> assign(hubspot_connected: !is_nil(user.hubspot_access_token))
    |> assign(gmail_connected: !is_nil(user.google_access_token))
    |> assign(:page_title, "Settings")
    |> ok()
  end

  @impl true
  def handle_event("connect_hubspot", _params, socket) do
    redirect(socket, to: ~p"/auth/hubspot")
    |> noreply()
  end
end
