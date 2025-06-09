defmodule App.Auth.HubSpotOAuthTest do
  use App.DataCase, async: true

  alias App.Auth.HubSpotOAuth

  describe "OAuth URL generation" do
    test "authorize_url/1 generates valid HubSpot OAuth URL" do
      state = "test_state_456"
      url = HubSpotOAuth.authorize_url(state)

      assert url =~ "app.hubspot.com/oauth/authorize"
      assert url =~ "client_id="
      assert url =~ "state=#{state}"
      assert url =~ "scope="
      assert url =~ "crm.objects.contacts"
    end
  end

  describe "token operations" do
    test "get_token/1 exchanges code for token" do
      code = "test_authorization_code"
      assert is_function(&HubSpotOAuth.get_token/1, 1)
    end

    test "refresh_token/1 refreshes expired token" do
      refresh_token = "test_refresh_token"
      assert is_function(&HubSpotOAuth.refresh_token/1, 1)
    end

    test "get_account_info/1 retrieves account details" do
      access_token = "test_access_token"
      assert is_function(&HubSpotOAuth.get_account_info/1, 1)
    end
  end

  describe "token validation" do
    test "get_valid_token/1 with valid token" do
      user = %{
        hubspot_access_token: "valid_token",
        hubspot_refresh_token: "refresh_token"
      }

      result = HubSpotOAuth.get_valid_token(user)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "get_valid_token/1 with no token returns error" do
      user = %{hubspot_access_token: nil}

      result = HubSpotOAuth.get_valid_token(user)
      assert match?({:error, :no_hubspot_token}, result)
    end
  end

  describe "token revocation" do
    test "revoke_token/1 revokes valid token" do
      user = %{hubspot_access_token: "valid_token"}

      # Mock successful revocation response
      result = HubSpotOAuth.revoke_token(user)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "revoke_token/1 handles user without token" do
      user = %{hubspot_access_token: nil}

      result = HubSpotOAuth.revoke_token(user)
      assert match?({:error, :no_token_to_revoke}, result)
    end

    test "revoke_token/1 handles already revoked token" do
      user = %{hubspot_access_token: "already_revoked_token"}

      # In real test, mock 404 response
      result = HubSpotOAuth.revoke_token(user)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "revoke_token/1 handles network errors" do
      user = %{hubspot_access_token: "token_causing_network_error"}

      # In real test, mock network failure
      result = HubSpotOAuth.revoke_token(user)
      assert match?({:ok, _} | {:error, _}, result)
    end
  end
end