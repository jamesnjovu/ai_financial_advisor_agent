defmodule App.Repo.Migrations.CreateGmailWebhookChannels do
  use Ecto.Migration

  def change do
    create table(:gmail_webhook_channels) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :history_id, :string, null: false
      add :expiration, :utc_datetime, null: false
      add :active, :boolean, default: true

      timestamps()
    end

    create unique_index(:gmail_webhook_channels, [:user_id])
    create index(:gmail_webhook_channels, [:active])
    create index(:gmail_webhook_channels, [:expiration])
  end
end
