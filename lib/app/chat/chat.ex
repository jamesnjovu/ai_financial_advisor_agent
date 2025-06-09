defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """
  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Chat.{
    Conversation,
    Message
  }
  alias App.Accounts.User

  def get_message(id) do
    Message
    |> where([m], m.id == ^id)
    |> Repo.one()
  end

  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  def list_conversations(%User{} = user) do
    Conversation
    |> where([c], c.user_id == ^user.id)
    |> order_by([c], desc: c.updated_at)
    |> preload(:messages)
    |> Repo.all()
  end

  def create_conversation(%User{} = user, attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  def get_conversation_messages(%Conversation{} = conversation) do
    Message
    |> where([m], m.conversation_id == ^conversation.id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def get_conversation(id, %User{} = user) do
    Conversation
    |> where([c], c.id == ^id and c.user_id == ^user.id)
    |> preload(:messages)
    |> Repo.one()
  end

  def create_message(%Conversation{} = conversation, attrs) do
    %Message{}
    |> Message.changeset(Map.put(attrs, :conversation_id, conversation.id))
    |> Repo.insert()
  end
end
