defmodule App.Contacts.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contacts" do
    field :email, :string
    field :name, :string
    field :phone, :string
    field :company, :string
    field :hubspot_id, :string
    field :gmail_thread_ids, {:array, :string}, default: []
    field :last_contact_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user, App.Accounts.User

    timestamps()
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:user_id, :email, :name, :phone, :company, :hubspot_id, :gmail_thread_ids, :last_contact_at, :metadata])
    |> validate_required([:user_id, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]{2,}$/)
    |> unique_constraint([:user_id, :email])
  end
end
