defmodule App.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :google_id, :string
    field :google_access_token, :string
    field :google_refresh_token, :string
    field :hubspot_access_token, :string
    field :hubspot_refresh_token, :string
    field :hubspot_portal_id, :string

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :google_id, :google_access_token, :google_refresh_token,
      :hubspot_access_token, :hubspot_refresh_token, :hubspot_portal_id])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]{2,}$/)
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
  end
end
