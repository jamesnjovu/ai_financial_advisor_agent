defmodule App.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Accounts.User
  alias App.Auth.{
    GoogleOAuth,
    HubSpotOAuth
  }

  def authenticate_with_google(code) do
    with {:ok, token_data} <- GoogleOAuth.get_token(code),
         {:ok, user_info} <- GoogleOAuth.get_user_info(token_data["access_token"]) do

      user_attrs = %{
        email: user_info["email"],
        name: user_info["name"],
        google_id: user_info["id"],
        google_access_token: token_data["access_token"],
        google_refresh_token: token_data["refresh_token"]
      }

      case get_user_by_google_id(user_info["id"]) do
        nil ->
          case get_user_by_email(user_info["email"]) do
            nil -> create_user(user_attrs)
            existing_user -> update_user(existing_user, user_attrs)
          end
        existing_user ->
          update_user(existing_user, user_attrs)
      end
    end
  end

  def get_user_by_google_id(google_id) when is_binary(google_id) do
    User
    |> where([a], a.google_id == ^google_id)
    |> limit(1)
    |> Repo.one()
  end

  def get_user_by_email(email) when is_binary(email) do
    User
    |> where([a], a.email == ^email)
    |> limit(1)
    |> Repo.one()
  end

  def get_user(id) do
    User
    |> where([a], a.id == ^id)
    |> limit(1)
    |> Repo.one()
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def connect_hubspot(%User{} = user, code) do
    with {:ok, token_data} <- HubSpotOAuth.get_token(code),
         {:ok, account_info} <- HubSpotOAuth.get_account_info(token_data["access_token"]) do

      hubspot_attrs = %{
        hubspot_access_token: token_data["access_token"],
        hubspot_refresh_token: token_data["refresh_token"],
        hubspot_portal_id: to_string(account_info["portalId"])
      }

      update_user(user, hubspot_attrs)
    end
  end

  def list_users_with_integrations do
    User
    |> where([u], not is_nil(u.google_access_token) or not is_nil(u.hubspot_access_token))
    |> Repo.all()
  end

  def get_user_by_hubspot_portal(portal_id) do
    User
    |> where([u], u.hubspot_portal_id == ^portal_id)
    |> Repo.one()
  end
end
