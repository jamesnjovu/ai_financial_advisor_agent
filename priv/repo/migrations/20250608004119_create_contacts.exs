defmodule App.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :email, :string
      add :name, :string
      add :phone, :string
      add :company, :string
      add :hubspot_id, :string
      add :gmail_thread_ids, {:array, :string}, default: []
      add :last_contact_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:contacts, [:user_id])
    create index(:contacts, [:email])
    create index(:contacts, [:hubspot_id])
    create unique_index(:contacts, [:user_id, :email])
  end
end
