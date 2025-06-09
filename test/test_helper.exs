# Configure test environment
ExUnit.configure(exclude: [:integration, :performance], timeout: 10_000)

# Start test environment
ExUnit.start()

# Setup test database
Ecto.Adapters.SQL.Sandbox.mode(App.Repo, :manual)

# Ensure vector extension is available for tests
case Ecto.Adapters.SQL.query(App.Repo, "CREATE EXTENSION IF NOT EXISTS vector", []) do
  {:ok, _} -> :ok
  {:error, _} -> IO.warn("Vector extension not available in test database")
end

# Setup test data cleanup
defmodule App.TestSetup do
  def setup_test_data do
    # Clean up any test data
    Ecto.Adapters.SQL.query!(App.Repo, "TRUNCATE users, conversations, messages, knowledge_entries, tasks, user_instructions, contacts, calendar_webhook_channels RESTART IDENTITY CASCADE", [])
  end
end
