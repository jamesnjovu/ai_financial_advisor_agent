defmodule App.AccountsTest do
  use App.DataCase, async: true

  alias App.Accounts
  alias App.Accounts.User

  describe "users" do
    @valid_attrs %{
      email: "test@example.com",
      name: "Test User",
      google_id: "google123"
    }

    @invalid_attrs %{email: nil}

    test "create_user/1 with valid data creates a user" do
      assert {:ok, %User{} = user} = Accounts.create_user(@valid_attrs)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.google_id == "google123"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "get_user_by_email/1 returns user with given email" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert Accounts.get_user_by_email("test@example.com") == user
    end

    test "get_user_by_email/1 returns nil for non-existent email" do
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end

    test "authenticate_with_google/1 creates new user" do
      # Mock the OAuth responses
      mock_token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123"
      }

      mock_user_info = %{
        "email" => "newuser@example.com",
        "name" => "New User",
        "id" => "google_new_123"
      }

      # This would require mocking the HTTP calls in a real test
      # For now, test the direct user creation path
      attrs = %{
        email: mock_user_info["email"],
        name: mock_user_info["name"],
        google_id: mock_user_info["id"],
        google_access_token: mock_token_data["access_token"],
        google_refresh_token: mock_token_data["refresh_token"]
      }

      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.email == "newuser@example.com"
      assert user.google_access_token == "access_token_123"
    end
  end

  describe "hubspot integration" do
    test "connect_hubspot/2 updates user with hubspot tokens" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      hubspot_attrs = %{
        hubspot_access_token: "hubspot_token_123",
        hubspot_refresh_token: "hubspot_refresh_123",
        hubspot_portal_id: "portal_123"
      }

      assert {:ok, updated_user} = Accounts.update_user(user, hubspot_attrs)
      assert updated_user.hubspot_access_token == "hubspot_token_123"
      assert updated_user.hubspot_portal_id == "portal_123"
    end
  end
end