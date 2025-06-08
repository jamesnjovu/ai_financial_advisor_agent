defmodule App.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :conversation, App.Chat.Conversation

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :metadata, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
  end
end
