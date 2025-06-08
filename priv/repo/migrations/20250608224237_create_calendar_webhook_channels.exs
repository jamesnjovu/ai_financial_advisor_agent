defmodule App.Repo.Migrations.CreateCalendarWebhookChannels do
  use Ecto.Migration

  def change do
    create table(:calendar_webhook_channels) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :channel_id, :string, null: false
      add :resource_id, :string, null: false
      add :calendar_id, :string, null: false, default: "primary"
      add :expiration, :utc_datetime, null: false
      add :token, :string
      add :active, :boolean, default: true

      timestamps()
    end

    create unique_index(:calendar_webhook_channels, [:channel_id])
    create index(:calendar_webhook_channels, [:user_id])
    create index(:calendar_webhook_channels, [:active])
    create index(:calendar_webhook_channels, [:expiration])
  end
end
