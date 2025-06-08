defmodule App.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :title, :string
      add :status, :string, default: "active"

      timestamps()
    end

    create index(:conversations, [:user_id])
  end
end
