defmodule App.Tasks.UserInstruction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_instructions" do
    field :instruction, :string
    field :triggers, {:array, :string}, default: []
    field :active, :boolean, default: true
    field :priority, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :user, App.Accounts.User

    timestamps()
  end

  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:user_id, :instruction, :triggers, :active, :priority, :metadata])
    |> validate_required([:user_id, :instruction, :triggers])
    |> validate_length(:instruction, min: 10)
  end
end