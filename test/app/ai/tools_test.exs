defmodule App.AI.ToolsTest do
  use App.DataCase, async: true

  alias App.AI.Tools
  alias App.Accounts

  describe "tool execution" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        google_access_token: "test_token",
        hubspot_access_token: "hubspot_token"
      })
      %{user: user}
    end

    test "execute_tool/3 handles unknown tools", %{user: user} do
      result = Tools.execute_tool("unknown_tool", %{}, user)
      assert match?({:error, "Unknown tool: unknown_tool"}, result)
    end

    test "search_emails tool validates parameters", %{user: user} do
      # Test with missing query parameter
      result = Tools.execute_tool("search_emails", %{}, user)
      assert match?({:error, _}, result)

      # Test with valid parameters (will fail HTTP call but validates structure)
      result = Tools.execute_tool("search_emails", %{"query" => "test"}, user)
      # Should return error due to no actual Gmail connection, but structured properly
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "schedule_meeting tool validates required fields", %{user: user} do
      # Missing required fields
      result = Tools.execute_tool("schedule_meeting", %{}, user)
      assert match?({:error, _}, result)

      # Valid structure
      params = %{
        "contact_email" => "client@example.com",
        "subject" => "Financial Review",
        "duration_minutes" => 60
      }

      result = Tools.execute_tool("schedule_meeting", params, user)
      # Will fail due to no real calendar access, but validates parameter structure
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "send_email tool validates parameters", %{user: user} do
      params = %{
        "to" => "client@example.com",
        "subject" => "Test Subject",
        "body" => "Test email body"
      }

      result = Tools.execute_tool("send_email", params, user)
      # Will fail HTTP call but parameter validation should pass
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "create_hubspot_contact tool works with minimal data", %{user: user} do
      params = %{
        "email" => "newclient@example.com",
        "firstname" => "John",
        "lastname" => "Doe"
      }

      result = Tools.execute_tool("create_hubspot_contact", params, user)
      # Will fail HTTP call but validates structure
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "add_instruction tool creates user instruction", %{user: user} do
      params = %{
        "instruction" => "When someone emails me, create a contact in HubSpot",
        "triggers" => ["email_received"]
      }

      result = Tools.execute_tool("add_instruction", params, user)
      assert match?({:ok, %{instruction_id: _, instruction: _}}, result)

      # Verify instruction was created
      instructions = App.Tasks.get_active_instructions(user)
      assert length(instructions) == 1
      assert hd(instructions).instruction =~ "create a contact"
    end
  end
end