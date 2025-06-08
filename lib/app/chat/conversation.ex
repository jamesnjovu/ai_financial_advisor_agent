defmodule App.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    field :title, :string
    field :status, :string, default: "active"

    belongs_to :user, App.Accounts.User
    has_many :messages, App.Chat.Message

    timestamps()
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :status, :user_id])
    |> validate_required([:user_id])
    |> validate_inclusion(:status, ["active", "archived"])
  end
end