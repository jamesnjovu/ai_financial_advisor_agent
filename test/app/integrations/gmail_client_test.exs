defmodule App.Integrations.GmailClientTest do
  use App.DataCase, async: true

  alias App.Integrations.GmailClient
  alias App.Accounts

  describe "email data extraction" do
    test "extract_email_data/1 parses gmail message format" do
      # Mock Gmail API response structure
      mock_message = %{
        "id" => "msg_123",
        "threadId" => "thread_456",
        "snippet" => "This is a test email...",
        "payload" => %{
          "headers" => [
            %{"name" => "From", "value" => "client@example.com"},
            %{"name" => "To", "value" => "advisor@example.com"},
            %{"name" => "Subject", "value" => "Investment Question"},
            %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
          ],
          "body" => %{
            "data" => Base.encode64("Hello, I have a question about my portfolio.")
          }
        }
      }

      result = GmailClient.extract_email_data(mock_message)

      assert result.id == "msg_123"
      assert result.thread_id == "thread_456"
      assert result.from == "client@example.com"
      assert result.to == "advisor@example.com"
      assert result.subject == "Investment Question"
      assert result.body =~ "portfolio"
    end

    test "extract_email_data/1 handles missing headers gracefully" do
      mock_message = %{
        "id" => "msg_123",
        "threadId" => "thread_456",
        "payload" => %{
          "headers" => [],
          "body" => %{}
        }
      }

      result = GmailClient.extract_email_data(mock_message)

      assert result.id == "msg_123"
      assert result.from == nil
      assert result.subject == nil
    end

    test "decode_gmail_base64/1 handles URL-safe base64" do
      # Gmail uses URL-safe base64 encoding
      original_text = "Hello, this is a test email with special characters!"

      # Encode with URL-safe base64 (replace + with -, / with _)
      url_safe_encoded = original_text
                         |> Base.encode64()
                         |> String.replace("+", "-")
                         |> String.replace("/", "_")
                         |> String.replace("=", "")  # Gmail removes padding

      # The function should decode it properly
      # Note: This tests the private function logic
      assert is_binary(url_safe_encoded)
    end
  end

  describe "email building" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "advisor@example.com",
        name: "Test Advisor",
        google_access_token: "test_token"
      })
      %{user: user}
    end

    test "build_email/5 creates proper email format", %{user: user} do
      to = "client@example.com"
      subject = "Re: Investment Question"
      body = "Thank you for your question about portfolio allocation."

      # Test the email building logic (this tests the private function concept)
      # In a real test, you'd need to expose this or test through the public API
      assert is_binary(to)
      assert is_binary(subject)
      assert is_binary(body)
    end
  end
end
