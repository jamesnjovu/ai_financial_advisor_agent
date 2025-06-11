defmodule App.Webhooks do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Webhooks.GmailChannel

  def expiring_channels(expiring_soon) do
    GmailChannel
    |> where([c], c.expiration < ^expiring_soon and c.active == true)
    |> preload(:user)
    |> App.Repo.all()
  end

end
