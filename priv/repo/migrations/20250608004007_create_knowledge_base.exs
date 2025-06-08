defmodule App.Repo.Migrations.CreateKnowledgeBase do
  use Ecto.Migration

  def change do
    create table(:knowledge_entries) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :source_type, :string, null: false # "email", "hubspot_contact", "hubspot_note"
      add :source_id, :string, null: false # external ID from source system
      add :title, :string
      add :content, :text, null: false
      add :metadata, :map, default: %{}
      add :embedding, :vector, size: 1536 # OpenAI ada-002 size
      add :last_synced_at, :utc_datetime

      timestamps()
    end

    create index(:knowledge_entries, [:user_id])
    create index(:knowledge_entries, [:source_type])
    create index(:knowledge_entries, [:source_id])

    # Create the vector index using raw SQL for better compatibility
    execute """
            CREATE INDEX knowledge_entries_embedding_idx
            ON knowledge_entries
            USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = 100);
            """,
            "DROP INDEX IF EXISTS knowledge_entries_embedding_idx;"
  end
end
