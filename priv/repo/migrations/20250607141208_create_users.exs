defmodule App.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string, size: 100
      add :google_id, :string
      add :google_access_token, :text
      add :google_refresh_token, :text
      add :hubspot_access_token, :text
      add :hubspot_refresh_token, :text
      add :hubspot_portal_id, :string

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:google_id])
  end
end
