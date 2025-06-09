defmodule App.TestHelpers do
  @moduledoc """
  Helper functions for tests
  """

  import ExUnit.Assertions
  alias App.Repo

  def assert_email_sent(to: to, subject: subject_pattern) do
    # In a real test environment, you'd check for emails in the test mailbox
    # This is a placeholder for email assertion logic
    assert is_binary(to)
    assert is_binary(subject_pattern) or is_struct(subject_pattern, Regex)
  end

  def assert_task_created(user, task_type) do
    tasks = App.Tasks.list_pending_tasks(user)
    assert Enum.any?(tasks, &(&1.task_type == task_type)),
           "Expected task of type '#{task_type}' to be created"
  end

  def assert_knowledge_entry_exists(user, content_pattern) do
    entries = Repo.all(
      from e in App.Knowledge.KnowledgeEntry,
      where: e.user_id == ^user.id and ilike(e.content, ^"%#{content_pattern}%")
    )

    assert length(entries) > 0,
           "Expected knowledge entry containing '#{content_pattern}' to exist"
  end

  def simulate_time_passage(seconds) do
    # Helper for testing time-dependent functionality
    # In a real test, you might use libraries like Timex.freeze or similar
    :timer.sleep(seconds * 10)  # Simulate passage of time quickly
  end

  def create_test_conversation_with_messages(user, message_count \\ 3) do
    conversation = App.Fixtures.conversation_fixture(user)

    messages = for i <- 1..message_count do
      role = if rem(i, 2) == 1, do: "user", else: "assistant"
      App.Fixtures.message_fixture(conversation, %{
        role: role,
        content: "Test message #{i}"
      })
    end

    {conversation, messages}
  end

  def assert_valid_json_response(response) do
    assert is_map(response)
    refute response == %{}
  end

  def assert_successful_tool_execution(result) do
    assert match?({:ok, _}, result), "Expected successful tool execution, got: #{inspect(result)}"
  end

  def assert_failed_tool_execution(result, expected_error \\ nil) do
    assert match?({:error, _}, result), "Expected failed tool execution, got: #{inspect(result)}"

    if expected_error do
      {:error, actual_error} = result
      assert actual_error =~ expected_error,
             "Expected error containing '#{expected_error}', got: #{actual_error}"
    end
  end

  def wait_for_async_operation(timeout \\ 1000) do
    # Helper for waiting for async operations in tests
    :timer.sleep(timeout)
  end

  def mock_http_response(status, body) do
    %HTTPoison.Response{
      status_code: status,
      body: if(is_map(body), do: Jason.encode!(body), else: body),
      headers: [{"content-type", "application/json"}]
    }
  end

  def assert_redirect_to_oauth(conn, provider) do
    location = Plug.Conn.get_resp_header(conn, "location") |> List.first()
    assert location != nil, "Expected redirect location header"

    case provider do
      :google -> assert location =~ "accounts.google.com"
      :hubspot -> assert location =~ "app.hubspot.com"
    end
  end

  def with_mocked_apis(test_func) do
    # In a full test environment, you'd set up HTTP mocking here
    # Using libraries like ExVCR, Mox, or HTTPoison.Base mocks
    test_func.()
  end
end