defmodule App.Repo.Migrations.AddUniqueConstraintToKnowledgeEntries do
  use Ecto.Migration

  def up do
    # Add the unique constraint that was missing
    create unique_index(:knowledge_entries, [:user_id, :source_type, :source_id],
             name: :knowledge_entries_user_source_unique_index)
  end

  def down do
    drop index(:knowledge_entries, [:user_id, :source_type, :source_id],
           name: :knowledge_entries_user_source_unique_index)
  end
end
