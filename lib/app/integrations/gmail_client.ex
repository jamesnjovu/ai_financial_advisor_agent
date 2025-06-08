defmodule App.Integrations.GmailClient do
  @moduledoc """
  Gmail API client for reading and sending emails
  """

  alias App.Auth.GoogleOAuth

  @base_url "https://gmail.googleapis.com/gmail/v1"

  def list_messages(user, opts \\ []) do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]

        query_params = %{
          maxResults: opts[:max_results] || 100,
          q: opts[:query] || ""
        }

        url = "#{@base_url}/users/me/messages?#{URI.encode_query(query_params)}"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error

        end
      error ->
        error
    end
  end

  def get_message(user, message_id) do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]
        url = "#{@base_url}/users/me/messages/#{message_id}?format=full"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def send_email(user, to, subject, body, opts \\ []) do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        # Build the email with proper headers
        email_content = build_email(user, to, subject, body, opts)
        encoded_email = Base.encode64(email_content, padding: false)

        payload = %{
          raw: encoded_email
        }

        url = "#{@base_url}/users/me/messages/send"

        case HTTPoison.post(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def watch_inbox(user, webhook_url) do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          labelIds: ["INBOX"],
          topicName: "projects/your-project/topics/gmail-push"
        }

        url = "#{@base_url}/users/me/watch"

        case HTTPoison.post(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def search_emails(user, query) do
    list_messages(user, query: query)
  end

  # Fixed email building function - the key issue was here
  defp build_email(user, to, subject, body, opts) do
    from = opts[:from] || user.email || "me"
    cc = opts[:cc]
    bcc = opts[:bcc]

    # Build headers properly with proper line endings
    headers = [
      "To: #{to}",
      "From: #{from}",
      "Subject: #{subject}",
      "MIME-Version: 1.0",
      "Content-Type: text/plain; charset=utf-8"
    ]

    # Add optional headers if present
    headers = if cc, do: headers ++ ["Cc: #{cc}"], else: headers
    headers = if bcc, do: headers ++ ["Bcc: #{bcc}"], else: headers

    # Join headers with proper CRLF and add body with double CRLF separator
    email_content = Enum.join(headers, "\r\n") <> "\r\n\r\n" <> body
    email_content
  end

  def extract_email_data(message) do
    headers = get_headers(message)

    %{
      id: message["id"],
      thread_id: message["threadId"],
      from: get_header_value(headers, "From"),
      to: get_header_value(headers, "To"),
      subject: get_header_value(headers, "Subject"),
      date: get_header_value(headers, "Date"),
      body: extract_body(message),
      snippet: message["snippet"]
    }
  end

  defp get_headers(%{"payload" => %{"headers" => headers}}), do: headers
  defp get_headers(_), do: []

  defp get_header_value(headers, name) do
    Enum.find_value(headers, fn %{"name" => n, "value" => v} ->
      if String.downcase(n) == String.downcase(name), do: v
    end)
  end

  defp extract_body(%{"payload" => payload}) do
    extract_body_from_payload(payload)
  end

  defp extract_body_from_payload(%{"body" => %{"data" => data}}) when is_binary(data) do
    # Gmail uses URL-safe base64 encoding, need to convert it to standard base64
    case decode_gmail_base64(data) do
      {:ok, decoded} -> decoded
      {:error, _} -> ""
    end
  end

  defp extract_body_from_payload(%{"parts" => parts}) when is_list(parts) do
    Enum.find_value(parts, "", fn part ->
      case extract_body_from_payload(part) do
        "" -> nil
        body -> body
      end
    end)
  end

  defp extract_body_from_payload(_), do: ""

  defp decode_gmail_base64(data) when is_binary(data) do
    # Gmail uses URL-safe base64 (RFC 4648) which replaces + with - and / with _
    # Convert back to standard base64
    standard_base64 =
      data
      |> String.replace("-", "+")
      |> String.replace("_", "/")
      |> pad_base64()

    case Base.decode64(standard_base64) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  rescue
    _ -> {:error, :decode_failed}
  end

  defp pad_base64(data) do
    # Add padding if needed
    case rem(String.length(data), 4) do
      0 -> data
      n -> data <> String.duplicate("=", 4 - n)
    end
  end
end
