defmodule App.Repo.Migrations.CreateInstructions do
  use Ecto.Migration

  def change do
    create table(:user_instructions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :instruction, :text, null: false
      add :triggers, {:array, :string}, default: [] # ["email_received", "calendar_event_created", etc.]
      add :active, :boolean, default: true
      add :priority, :integer, default: 0
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:user_instructions, [:user_id])
    create index(:user_instructions, [:active])
  end
end
