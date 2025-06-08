defmodule App.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all)
      add :title, :string, null: false
      add :description, :text
      add :status, :string, default: "pending" # pending, in_progress, waiting, completed, failed
      add :task_type, :string, null: false # "schedule_meeting", "send_email", "create_contact", etc.
      add :context, :map, default: %{} # Store task-specific data
      add :next_action_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:status])
    create index(:tasks, [:next_action_at])
    create index(:tasks, [:task_type])
  end
end
