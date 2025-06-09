defmodule App.Fixtures do
  @moduledoc """
  Test fixtures for creating test data
  """

  alias App.{Accounts, Chat, Knowledge.KnowledgeEntry, Tasks}

  def user_fixture(attrs \\ %{}) do
    default_attrs = %{
      email: "user#{System.unique_integer()}@example.com",
      name: "Test User",
      google_access_token: "test_google_token",
      hubspot_access_token: "test_hubspot_token",
      hubspot_portal_id: "test_portal_#{System.unique_integer()}"
    }

    attrs = Map.merge(default_attrs, attrs)
    {:ok, user} = Accounts.create_user(attrs)
    user
  end

  def conversation_fixture(user, attrs \\ %{}) do
    default_attrs = %{
      title: "Test Conversation #{System.unique_integer()}"
    }

    attrs = Map.merge(default_attrs, attrs)
    {:ok, conversation} = Chat.create_conversation(user, attrs)
    conversation
  end

  def message_fixture(conversation, attrs \\ %{}) do
    default_attrs = %{
      role: "user",
      content: "Test message #{System.unique_integer()}"
    }

    attrs = Map.merge(default_attrs, attrs)
    {:ok, message} = Chat.create_message(conversation, attrs)
    message
  end

  def knowledge_entry_fixture(user, attrs \\ %{}) do
    unique_id = System.unique_integer()

    default_attrs = %{
      user_id: user.id,
      source_type: "email",
      source_id: "test_email_#{unique_id}",
      title: "Test Email #{unique_id}",
      content: "This is test content about financial planning and client communication #{unique_id}",
      metadata: %{
        from: "client#{unique_id}@example.com",
        to: user.email,
        date: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      last_synced_at: DateTime.utc_now()
    }

    attrs = Map.merge(default_attrs, attrs)

    changeset = KnowledgeEntry.changeset(%KnowledgeEntry{}, attrs)
    {:ok, entry} = App.Repo.insert(changeset)
    entry
  end

  def task_fixture(user, attrs \\ %{}) do
    default_attrs = %{
      title: "Test Task #{System.unique_integer()}",
      task_type: "test_task",
      context: %{test_data: "test_value"},
      status: "pending"
    }

    attrs = Map.merge(default_attrs, attrs)
    {:ok, task} = Tasks.create_task(user, attrs)
    task
  end

  def user_instruction_fixture(user, attrs \\ %{}) do
    default_attrs = %{
      instruction: "Test instruction: do something when trigger happens",
      triggers: ["test_trigger"],
      active: true
    }

    instruction = Map.get(attrs, :instruction, default_attrs.instruction)
    triggers = Map.get(attrs, :triggers, default_attrs.triggers)

    {:ok, user_instruction} = Tasks.create_user_instruction(user, instruction, triggers)
    user_instruction
  end

  def gmail_message_fixture() do
    %{
      "id" => "msg_#{System.unique_integer()}",
      "threadId" => "thread_#{System.unique_integer()}",
      "snippet" => "This is a test email snippet...",
      "payload" => %{
        "headers" => [
          %{"name" => "From", "value" => "client@example.com"},
          %{"name" => "To", "value" => "advisor@example.com"},
          %{"name" => "Subject", "value" => "Investment Question"},
          %{"name" => "Date", "value" => DateTime.utc_now() |> DateTime.to_string()}
        ],
        "body" => %{
          "data" => Base.encode64("Hello, I have a question about my portfolio allocation.")
        }
      }
    }
  end

  def hubspot_contact_fixture() do
    %{
      "id" => "contact_#{System.unique_integer()}",
      "properties" => %{
        "email" => "client#{System.unique_integer()}@example.com",
        "firstname" => "John",
        "lastname" => "Doe",
        "company" => "Test Company",
        "phone" => "+1234567890",
        "createdate" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "lastmodifieddate" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  def calendar_event_fixture() do
    start_time = DateTime.utc_now() |> DateTime.add(1, :day)
    end_time = DateTime.add(start_time, 1, :hour)

    %{
      "id" => "event_#{System.unique_integer()}",
      "summary" => "Test Meeting",
      "description" => "Test meeting description",
      "start" => %{
        "dateTime" => DateTime.to_iso8601(start_time),
        "timeZone" => "UTC"
      },
      "end" => %{
        "dateTime" => DateTime.to_iso8601(end_time),
        "timeZone" => "UTC"
      },
      "attendees" => [
        %{"email" => "client@example.com", "responseStatus" => "needsAction"}
      ]
    }
  end
end

