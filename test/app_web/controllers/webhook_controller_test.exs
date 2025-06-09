defmodule AppWeb.WebhookControllerTest do
  use AppWeb.ConnCase

  alias App.Accounts

  describe "gmail webhook" do
    test "POST /webhooks/gmail with valid data processes webhook", %{conn: conn} do
      # Create user for webhook
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        google_access_token: "test_token"
      })

      # Mock Gmail webhook payload
      webhook_data = %{
        emailAddress: user.email,
        message_id: "msg_123"
      }

      encoded_data = Base.encode64(Jason.encode!(webhook_data))

      payload = %{
        message: %{
          data: encoded_data
        }
      }

      conn = post(conn, ~p"/webhooks/gmail", payload)
      assert response(conn, 200) == "OK"
    end

    test "POST /webhooks/gmail with invalid data returns 400", %{conn: conn} do
      invalid_payload = %{invalid: "data"}

      conn = post(conn, ~p"/webhooks/gmail", invalid_payload)
      assert response(conn, 400) =~ "Invalid webhook"
    end

    test "POST /webhooks/gmail for unknown user returns 200", %{conn: conn} do
      # Webhook for non-existent user should not error
      webhook_data = %{
        emailAddress: "unknown@example.com",
        message_id: "msg_123"
      }

      encoded_data = Base.encode64(Jason.encode!(webhook_data))

      payload = %{
        message: %{
          data: encoded_data
        }
      }

      conn = post(conn, ~p"/webhooks/gmail", payload)
      assert response(conn, 200) == "OK"
    end
  end

  describe "hubspot webhook" do
    test "POST /webhooks/hubspot with valid portal processes webhook", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        hubspot_portal_id: "123456"
      })

      payload = %{
        portalId: 123456,
        contact_id: "contact_123",
        event_type: "contact.created"
      }

      conn = post(conn, ~p"/webhooks/hubspot", payload)
      assert response(conn, 200) == "OK"
    end

    test "POST /webhooks/hubspot without portalId returns 400", %{conn: conn} do
      payload = %{contact_id: "contact_123"}

      conn = post(conn, ~p"/webhooks/hubspot", payload)
      assert response(conn, 400) =~ "Invalid HubSpot webhook"
    end
  end

  describe "calendar webhook" do
    test "POST /webhooks/calendar handles sync notification", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-goog-resource-state", "sync")
        |> put_req_header("x-goog-channel-id", "test_channel_123")
        |> post(~p"/webhooks/calendar", %{})

      assert response(conn, 200) == "OK"
    end

    test "POST /webhooks/calendar handles event change", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-goog-resource-state", "exists")
        |> put_req_header("x-goog-channel-id", "test_channel_123")
        |> put_req_header("x-goog-resource-id", "resource_456")
        |> post(~p"/webhooks/calendar", %{})

      assert response(conn, 200) == "OK"
    end
  end

  describe "health check" do
    test "GET /webhooks/health returns status", %{conn: conn} do
      conn = get(conn, ~p"/webhooks/health")

      assert json_response(conn, 200)["status"] == "ok"
      assert json_response(conn, 200)["service"] == "AI Financial Advisor Webhooks"
    end
  end
end
