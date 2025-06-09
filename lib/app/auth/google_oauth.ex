defmodule App.Auth.GoogleOAuth do
  @moduledoc """
  Google OAuth2 client for Gmail and Calendar access with enhanced permissions
  """

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_userinfo_url "https://www.googleapis.com/oauth2/v2/userinfo"

  def authorize_url(state) do
    config = Application.get_env(:app, :google_oauth)

    IO.inspect config, label: :config
    
    params = %{
      client_id: config[:client_id],
      redirect_uri: config[:redirect_uri],
      response_type: "code",
      scope:
        [
          "openid",
          "email",
          "profile",
          "https://www.googleapis.com/auth/gmail.readonly",
          "https://www.googleapis.com/auth/gmail.send",
          "https://www.googleapis.com/auth/gmail.modify",
          "https://www.googleapis.com/auth/gmail.compose",
          "https://www.googleapis.com/auth/calendar.readonly",
          "https://www.googleapis.com/auth/calendar.events",
          "https://www.googleapis.com/auth/calendar"
        ]
        |> Enum.join(" "),
      access_type: "offline",
      prompt: "consent",
      state: state,
      include_granted_scopes: "true"
    }

    "#{@google_auth_url}?#{URI.encode_query(params)}"
  end

  def get_token(code) do
    config = Application.get_env(:app, :google_oauth)

    body = %{
      client_id: config[:client_id],
      client_secret: config[:client_secret],
      code: code,
      grant_type: "authorization_code",
      redirect_uri: config[:redirect_uri]
    }

    case HTTPoison.post(@google_token_url, Jason.encode!(body), [
      {"Content-Type", "application/json"}
    ]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{body: error_body}} ->
        {:error, Jason.decode!(error_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def refresh_token(refresh_token) do
    config = Application.get_env(:app, :google_oauth)

    body = %{
      client_id: config[:client_id],
      client_secret: config[:client_secret],
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    }

    case HTTPoison.post(@google_token_url, Jason.encode!(body), [
      {"Content-Type", "application/json"}
    ]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{body: error_body}} ->
        {:error, Jason.decode!(error_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_user_info(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case HTTPoison.get(@google_userinfo_url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      error ->
        {:error, error}
    end
  end

  def get_valid_token(%{google_access_token: token, google_refresh_token: refresh_token} = user) do
    # Try current token first
    case test_token(token) do
      {:ok, _} ->
        {:ok, token}

      {:error, _} ->
        # Refresh token
        case refresh_token(refresh_token) do
          {:ok, %{"access_token" => new_token}} ->
            # Update user with new token
            App.Accounts.update_user(user, %{google_access_token: new_token})
            {:ok, new_token}

          error ->
            error
        end
    end
  end

  defp test_token(token) do
    headers = [{"Authorization", "Bearer #{token}"}]

    case HTTPoison.get(@google_userinfo_url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> {:ok, :valid}
      _ -> {:error, :invalid}
    end
  end
end
