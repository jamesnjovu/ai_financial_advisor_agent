defmodule App.Mocks do
  @moduledoc """
  Mock modules for external API calls during testing
  """

  def mock_openai_response(content \\ "Test AI response") do
    %{
      "choices" => [
        %{
          "message" => %{
            "content" => content,
            "role" => "assistant"
          }
        }
      ],
      "usage" => %{
        "total_tokens" => 50
      }
    }
  end

  def mock_openai_tool_response(tool_calls) do
    %{
      "choices" => [
        %{
          "message" => %{
            "content" => "I'll help you with that.",
            "role" => "assistant",
            "tool_calls" => tool_calls
          }
        }
      ]
    }
  end

  def mock_embedding_response() do
    %{
      "data" => [
        %{
          "embedding" => Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)
        }
      ]
    }
  end

  def mock_gmail_list_response(messages \\ []) do
    default_messages = [
      %{"id" => "msg_1", "threadId" => "thread_1"},
      %{"id" => "msg_2", "threadId" => "thread_2"}
    ]

    %{
      "messages" => if(Enum.empty?(messages), do: default_messages, else: messages),
      "resultSizeEstimate" => length(messages)
    }
  end

  def mock_hubspot_contacts_response(contacts \\ []) do
    default_contacts = [App.Fixtures.hubspot_contact_fixture()]

    %{
      "results" => if(Enum.empty?(contacts), do: default_contacts, else: contacts),
      "total" => length(contacts)
    }
  end

  def mock_calendar_events_response(events \\ []) do
    default_events = [App.Fixtures.calendar_event_fixture()]

    %{
      "items" => if(Enum.empty?(events), do: default_events, else: events),
      "nextPageToken" => nil
    }
  end

  def mock_google_oauth_token_response() do
    %{
      "access_token" => "mock_access_token_#{System.unique_integer()}",
      "refresh_token" => "mock_refresh_token_#{System.unique_integer()}",
      "expires_in" => 3600,
      "token_type" => "Bearer"
    }
  end

  def mock_google_userinfo_response() do
    %{
      "id" => "google_id_#{System.unique_integer()}",
      "email" => "test#{System.unique_integer()}@example.com",
      "name" => "Test User",
      "picture" => "https://example.com/avatar.jpg"
    }
  end

  def mock_hubspot_oauth_token_response() do
    %{
      "access_token" => "mock_hubspot_token_#{System.unique_integer()}",
      "refresh_token" => "mock_hubspot_refresh_#{System.unique_integer()}",
      "expires_in" => 3600
    }
  end

  def mock_hubspot_account_info() do
    %{
      "portalId" => System.unique_integer(),
      "accountName" => "Test Company",
      "domain" => "testcompany.com"
    }
  end
end