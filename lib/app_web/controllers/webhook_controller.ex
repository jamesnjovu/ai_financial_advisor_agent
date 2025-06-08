defmodule AppWeb.WebhookController do
  use AppWeb, :controller
  require Logger

  alias App.BackgroundWorker
  alias App.Accounts

  @doc """
  Handles Gmail/Google Pub/Sub webhook notifications

  Google sends push notifications when emails are received.
  The payload is base64 encoded and contains email metadata.
  """
  def gmail_webhook(conn, params) do
    with {:ok, webhook_data} <- decode_gmail_webhook(params),
         {:ok, user} <- find_user_by_email(webhook_data["emailAddress"]) do

      BackgroundWorker.process_email_webhook(user.id, webhook_data)
      Logger.info("Processed Gmail webhook for user #{user.id}")

      send_resp(conn, 200, "OK")
    else
      {:error, :invalid_format} ->
        Logger.warning("Invalid Gmail webhook format: #{inspect(params)}")
        send_resp(conn, 400, "Invalid webhook format")

      {:error, :decode_failed} ->
        Logger.warning("Failed to decode Gmail webhook data")
        send_resp(conn, 400, "Invalid webhook data")

      {:error, :user_not_found} ->
        Logger.info("Gmail webhook for unknown user - ignoring")
        send_resp(conn, 200, "OK")
    end
  end

  @doc """
  Handles HubSpot webhook notifications

  HubSpot sends webhooks when contacts, deals, or other objects change.
  """
  def hubspot_webhook(conn, params) do
    with {:ok, portal_id} <- extract_portal_id(params),
         {:ok, user} <- find_user_by_portal(portal_id) do

      BackgroundWorker.process_hubspot_webhook(portal_id, params)
      Logger.info("Processed HubSpot webhook for portal #{portal_id}")

      send_resp(conn, 200, "OK")
    else
      {:error, :invalid_portal_id} ->
        Logger.warning("Invalid HubSpot webhook - missing portalId: #{inspect(params)}")
        send_resp(conn, 400, "Invalid HubSpot webhook")

      {:error, :user_not_found} ->
        Logger.info("HubSpot webhook for unknown portal - ignoring")
        send_resp(conn, 200, "OK")
    end
  end

  @doc """
  Handles Google Calendar webhook notifications

  Google Calendar sends notifications when events change.
  Uses channel_id to map back to the specific user and calendar.
  """
  def calendar_webhook(conn, _params) do
    resource_state = get_req_header(conn, "x-goog-resource-state") |> List.first()
    channel_id = get_req_header(conn, "x-goog-channel-id") |> List.first()
    resource_id = get_req_header(conn, "x-goog-resource-id") |> List.first()

    case resource_state do
      "sync" ->
        Logger.info("Calendar sync notification received for channel: #{channel_id}")
        send_resp(conn, 200, "OK")

      "exists" ->
        Logger.info("Calendar event changed - channel: #{channel_id}, resource: #{resource_id}")

        case App.Webhooks.CalendarManager.process_calendar_change(channel_id, resource_id) do
          {:ok, result} ->
            Logger.info("Processed calendar webhook: #{inspect(result)}")
            send_resp(conn, 200, "OK")

          {:error, :channel_not_found} ->
            Logger.warning("Calendar webhook for unknown channel: #{channel_id}")
            send_resp(conn, 200, "OK")

          {:error, reason} ->
            Logger.error("Failed to process calendar webhook: #{inspect(reason)}")
            send_resp(conn, 200, "OK")
        end

      _ ->
        Logger.info("Unknown calendar webhook state: #{resource_state}")
        send_resp(conn, 200, "OK")
    end
  end

  @doc """
  Health check endpoint for monitoring webhook availability
  """
  def health(conn, _params) do
    json(conn, %{
      status: "ok",
      service: "AI Financial Advisor Webhooks",
      timestamp: DateTime.utc_now()
    })
  end

  # Private helper functions

  defp decode_gmail_webhook(%{"message" => %{"data" => encoded_data}}) do
    try do
      decoded = Base.decode64!(encoded_data)
      webhook_data = Jason.decode!(decoded)
      {:ok, webhook_data}
    rescue
      _ -> {:error, :decode_failed}
    end
  end

  defp decode_gmail_webhook(_), do: {:error, :invalid_format}

  defp find_user_by_email(nil), do: {:error, :user_not_found}

  defp find_user_by_email(email) do
    case Accounts.get_user_by_email(email) do
      %App.Accounts.User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  defp extract_portal_id(%{"portalId" => portal_id}) when is_integer(portal_id) do
    {:ok, to_string(portal_id)}
  end

  defp extract_portal_id(%{"portalId" => portal_id}) when is_binary(portal_id) do
    {:ok, portal_id}
  end

  defp extract_portal_id(_), do: {:error, :invalid_portal_id}

  defp find_user_by_portal(portal_id) do
    case Accounts.get_user_by_hubspot_portal(portal_id) do
      %App.Accounts.User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end
end