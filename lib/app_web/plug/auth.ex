defmodule AppWeb.Plugs.Auth do
  use AppWeb, :verified_routes
  import Plug.Conn
  import Phoenix.Controller
  alias App.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :current_user_id) do
      nil ->
        conn

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> clear_session()

          user ->
            assign(conn, :current_user, user)
        end
    end
  end


  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session["current_user_id"] do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Please sign in to access this page")
          |> redirect(to: "/")
        {:halt, socket}

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            socket =
              socket
              |> put_flash(:error, "User not found")
              |> redirect(to: "/")
            {:halt, socket}

          user ->
            {:cont, Phoenix.Component.assign(socket, :current_user, user)}
        end
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Please sign in to access this page")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: ~p"/chat")
      |> halt()
    else
      conn
    end
  end

end