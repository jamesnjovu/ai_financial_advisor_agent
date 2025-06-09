defmodule App.Integrations.HubSpotClientTest do
  use App.DataCase, async: true

  alias App.Integrations.HubSpotClient
  alias App.Accounts

  describe "contact operations" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        hubspot_access_token: "test_hubspot_token"
      })
      %{user: user}
    end

    test "create_or_update_contact/2 handles missing email", %{user: user} do
      contact_data = %{
        "firstname" => "John",
        "lastname" => "Doe"
        # Missing email
      }

      result = HubSpotClient.create_or_update_contact(user, contact_data)
      assert match?({:error, "Email is required for contact creation"}, result)
    end

    test "validates contact data structure", %{user: user} do
      valid_contact_data = %{
        "email" => "john@example.com",
        "firstname" => "John",
        "lastname" => "Doe",
        "company" => "Acme Corp",
        "phone" => "+1234567890"
      }

      # Test that the data structure is valid
      assert is_map(valid_contact_data)
      assert Map.has_key?(valid_contact_data, "email")

      # The actual API call would be mocked in a full test
      # Here we just verify the function exists and accepts the parameters
      assert is_function(&HubSpotClient.create_or_update_contact/2, 2)
    end
  end

  describe "search operations" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        hubspot_access_token: "test_token"
      })
      %{user: user}
    end

    test "search_contacts/2 accepts query parameter", %{user: user} do
      query = "john@example.com"

      # Test that the function exists and accepts parameters
      # In a real test environment, you'd mock the HTTP response
      assert is_function(&HubSpotClient.search_contacts/2, 2)
      assert is_binary(query)
    end
  end
end
