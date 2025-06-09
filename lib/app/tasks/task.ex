defmodule App.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :task_type, :string
    field :context, :map, default: %{}
    field :next_action_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user, App.Accounts.User
    belongs_to :conversation, App.Chat.Conversation

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:user_id, :conversation_id, :title, :description, :status, :task_type, :context, :next_action_at, :completed_at, :metadata])
    |> validate_required([:user_id, :title, :task_type])
    |> validate_inclusion(:status, ["pending", "in_progress", "waiting", "completed", "failed"])
  end
end
