defmodule AppWeb.AuthController do
  use AppWeb, :controller

  alias App.Accounts
  alias App.Auth.{GoogleOAuth, HubSpotOAuth}

  def login(conn, _params) do
    state = Base.encode64(:crypto.strong_rand_bytes(32))
    conn = put_session(conn, :oauth_state, state)

    google_auth_url = GoogleOAuth.authorize_url(state)
    redirect(conn, external: google_auth_url)
  end

  def google_callback(conn, %{"code" => code, "state" => state}) do
    stored_state = get_session(conn, :oauth_state)

    if state == stored_state do
      case Accounts.authenticate_with_google(code) do
        {:ok, user} ->
          conn
          |> put_session(:current_user_id, user.id)
          |> delete_session(:oauth_state)
          |> put_flash(:info, "Successfully signed in!")
          |> redirect(to: ~p"/chat")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Authentication failed. Please try again.")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "Invalid state parameter")
      |> redirect(to: ~p"/")
    end
  end

  def connect_hubspot(conn, _params) do
    user = get_current_user(conn)

    if user do
      state = Base.encode64(:crypto.strong_rand_bytes(32))
      conn = put_session(conn, :hubspot_oauth_state, state)

      hubspot_auth_url = HubSpotOAuth.authorize_url(state)
      redirect(conn, external: hubspot_auth_url)
    else
      conn
      |> put_flash(:error, "Please sign in first")
      |> redirect(to: ~p"/")
    end
  end

  def hubspot_callback(conn, %{"code" => code, "state" => state}) do
    stored_state = get_session(conn, :hubspot_oauth_state)
    user = get_current_user(conn)

    if state == stored_state and user do
      case Accounts.connect_hubspot(user, code) do
        {:ok, _updated_user} ->
          conn
          |> delete_session(:hubspot_oauth_state)
          |> put_flash(:info, "HubSpot connected successfully!")
          |> redirect(to: ~p"/chat")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Failed to connect HubSpot. Please try again.")
          |> redirect(to: ~p"/chat")
      end
    else
      conn
      |> put_flash(:error, "Invalid request")
      |> redirect(to: ~p"/chat")
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: ~p"/")
  end

  defp get_current_user(conn) do
    case get_session(conn, :current_user_id) do
      nil -> nil
      user_id -> Accounts.get_user(user_id)
    end
  end
end
