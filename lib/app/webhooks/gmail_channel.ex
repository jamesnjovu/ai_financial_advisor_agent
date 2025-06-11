defmodule App.Webhooks.GmailChannel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gmail_webhook_channels" do
    field :history_id, :string
    field :expiration, :utc_datetime
    field :active, :boolean, default: true

    belongs_to :user, App.Accounts.User

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:user_id, :history_id, :expiration, :active])
    |> validate_required([:user_id, :history_id, :expiration])
    |> unique_constraint(:user_id)
  end
end
