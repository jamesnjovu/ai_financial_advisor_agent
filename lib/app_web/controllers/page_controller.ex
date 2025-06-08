defmodule AppWeb.PageController do
  use AppWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end

  def devtools(conn, _params) do
    send_resp(conn, 404, "")
  end
end
