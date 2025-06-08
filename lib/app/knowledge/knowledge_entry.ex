defmodule App.Knowledge.KnowledgeEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "knowledge_entries" do
    field :source_type, :string
    field :source_id, :string
    field :title, :string
    field :content, :string
    field :metadata, :map, default: %{}
    field :embedding, Pgvector.Ecto.Vector
    field :last_synced_at, :utc_datetime

    belongs_to :user, App.Accounts.User

    timestamps()
  end

  def changeset(knowledge_entry, attrs) do
    knowledge_entry
    |> cast(attrs, [:user_id, :source_type, :source_id, :title, :content, :metadata, :embedding, :last_synced_at])
    |> validate_required([:user_id, :source_type, :source_id, :content])
    |> validate_inclusion(:source_type, ["email", "hubspot_contact", "hubspot_note", "calendar_event"])
    |> unique_constraint([:user_id, :source_type, :source_id], name: :knowledge_entries_user_source_unique_index)
  end
end