defmodule App.Auth.HubSpotOAuth do
  @moduledoc """
  HubSpot OAuth2 client
  """

  @hubspot_auth_url "https://app.hubspot.com/oauth/authorize"
  @hubspot_token_url "https://api.hubapi.com/oauth/v1/token"

  def authorize_url(state) do
    config = Application.get_env(:app, :hubspot_oauth)

    params = %{
      client_id: config[:client_id],
      redirect_uri: config[:redirect_uri],
      scope:
        [
          "timeline",
          "crm.objects.deals.read",
          "crm.objects.deals.write",
          "crm.objects.contacts.read",
          "crm.objects.contacts.write",
          "crm.schemas.contacts.read",
          "crm.schemas.deals.read",
          "oauth"
        ]
        |> Enum.join(" "),
      state: state
    }

    "#{@hubspot_auth_url}?#{URI.encode_query(params)}"
  end

  def get_token(code) do
    config = Application.get_env(:app, :hubspot_oauth)

    body = %{
      grant_type: "authorization_code",
      client_id: config[:client_id],
      client_secret: config[:client_secret],
      redirect_uri: config[:redirect_uri],
      code: code
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case HTTPoison.post(@hubspot_token_url, URI.encode_query(body), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{body: error_body}} ->
        {:error, Jason.decode!(error_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def refresh_token(refresh_token) do
    config = Application.get_env(:app, :hubspot_oauth)

    body = %{
      grant_type: "refresh_token",
      client_id: config[:client_id],
      client_secret: config[:client_secret],
      refresh_token: refresh_token
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case HTTPoison.post(@hubspot_token_url, URI.encode_query(body), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{body: error_body}} ->
        {:error, Jason.decode!(error_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_account_info(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case HTTPoison.get("https://api.hubapi.com/account-info/v3/details", headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      error ->
        {:error, error}
    end
  end

  # get valid token with refresh capability
  def get_valid_token(%{hubspot_access_token: token, hubspot_refresh_token: refresh_token} = user) do
    # Try current token first
    case test_token(token) do
      {:ok, _} ->
        {:ok, token}

      {:error, _} ->
        # Refresh token
        case refresh_token(refresh_token) do
          {:ok, %{"access_token" => new_token}} ->
            # Update user with new token
            App.Accounts.update_user(user, %{hubspot_access_token: new_token})
            {:ok, new_token}

          error ->
            error
        end
    end
  end

  def get_valid_token(_user) do
    {:error, :no_hubspot_token}
  end

  defp test_token(token) do
    headers = [{"Authorization", "Bearer #{token}"}]

    case HTTPoison.get("https://api.hubapi.com/account-info/v3/details", headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> {:ok, :valid}
      _ -> {:error, :invalid}
    end
  end
end