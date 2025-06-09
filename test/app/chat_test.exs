defmodule App.ChatTest do
  use App.DataCase, async: true

  alias App.Chat
  alias App.Chat.{Conversation, Message}
  alias App.Accounts

  describe "conversations" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })
      %{user: user}
    end

    test "create_conversation/2 creates a conversation for user", %{user: user} do
      attrs = %{title: "Test Conversation"}
      assert {:ok, %Conversation{} = conversation} = Chat.create_conversation(user, attrs)
      assert conversation.title == "Test Conversation"
      assert conversation.user_id == user.id
      assert conversation.status == "active"
    end

    test "list_conversations/1 returns conversations for user", %{user: user} do
      {:ok, conv1} = Chat.create_conversation(user, %{title: "Conv 1"})
      {:ok, conv2} = Chat.create_conversation(user, %{title: "Conv 2"})

      conversations = Chat.list_conversations(user)
      assert length(conversations) == 2
      assert Enum.any?(conversations, &(&1.id == conv1.id))
      assert Enum.any?(conversations, &(&1.id == conv2.id))
    end

    test "get_conversation/2 returns conversation for user", %{user: user} do
      {:ok, conversation} = Chat.create_conversation(user, %{title: "Test"})

      found_conversation = Chat.get_conversation(conversation.id, user)
      assert found_conversation.id == conversation.id
      assert found_conversation.user_id == user.id
    end
  end

  describe "messages" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })
      {:ok, conversation} = Chat.create_conversation(user, %{title: "Test"})
      %{user: user, conversation: conversation}
    end

    test "create_message/2 creates a message", %{conversation: conversation} do
      attrs = %{
        role: "user",
        content: "Hello, AI!"
      }

      assert {:ok, %Message{} = message} = Chat.create_message(conversation, attrs)
      assert message.role == "user"
      assert message.content == "Hello, AI!"
      assert message.conversation_id == conversation.id
    end

    test "get_conversation_messages/1 returns messages in order", %{conversation: conversation} do
      {:ok, msg1} = Chat.create_message(conversation, %{role: "user", content: "First"})
      {:ok, msg2} = Chat.create_message(conversation, %{role: "assistant", content: "Second"})

      messages = Chat.get_conversation_messages(conversation)
      assert length(messages) == 2
      assert Enum.at(messages, 0).id == msg1.id
      assert Enum.at(messages, 1).id == msg2.id
    end

    test "update_message/2 updates message attributes", %{conversation: conversation} do
      {:ok, message} = Chat.create_message(conversation, %{role: "user", content: "Original"})

      assert {:ok, updated_message} = Chat.update_message(message, %{content: "Updated"})
      assert updated_message.content == "Updated"
    end
  end
end
