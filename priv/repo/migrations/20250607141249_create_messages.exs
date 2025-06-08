defmodule App.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all)
      add :role, :string, null: false # "user" | "assistant" | "system"
      add :content, :text, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:role])
  end
end
