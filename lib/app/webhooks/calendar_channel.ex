defmodule App.Webhooks.CalendarChannel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calendar_webhook_channels" do
    field :channel_id, :string
    field :resource_id, :string
    field :calendar_id, :string
    field :expiration, :utc_datetime
    field :token, :string
    field :active, :boolean, default: true

    belongs_to :user, App.Accounts.User

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:user_id, :channel_id, :resource_id, :calendar_id, :expiration, :token, :active])
    |> validate_required([:user_id, :channel_id, :resource_id, :calendar_id, :expiration])
    |> unique_constraint(:channel_id)
  end
end