defmodule App.Webhooks.CalendarManager do
  @moduledoc """
  Manages Google Calendar webhook subscriptions and channel mappings
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Webhooks.CalendarChannel
  alias App.Integrations.CalendarClient
  alias App.Auth.GoogleOAuth
  alias App.Accounts.User

  @webhook_base_url Application.compile_env(:app, :webhook_base_url, "http://localhost:4500")

  def setup_calendar_webhook(%User{} = user, calendar_id \\ "primary") do
    # Generate unique channel ID
    channel_id = generate_channel_id(user.id, calendar_id)

    # Set expiration to 1 week from now (Google's max is 1 week for calendar events)
    expiration = DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)

    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          id: channel_id,
          type: "web_hook",
          address: "#{@webhook_base_url}/webhooks/calendar",
          expiration: DateTime.to_unix(expiration, :millisecond)
        }

        url = "https://www.googleapis.com/calendar/v3/calendars/#{calendar_id}/events/watch"

        case HTTPoison.post(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            response = Jason.decode!(body)

            # Store channel mapping in database
            attrs = %{
              user_id: user.id,
              channel_id: channel_id,
              resource_id: response["resourceId"],
              calendar_id: calendar_id,
              expiration: expiration,
              token: response["token"]
            }

            case create_or_update_channel(attrs) do
              {:ok, channel} ->
                {:ok, channel}

              {:error, changeset} ->
                # If we failed to store locally, try to stop the webhook
                stop_calendar_webhook(channel_id, token)
                {:error, changeset}
            end

          {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
            {:error, "Google Calendar API error #{status}: #{body}"}

          {:error, reason} ->
            {:error, "HTTP request failed: #{inspect(reason)}"}
        end

      error ->
        error
    end
  end

  def stop_calendar_webhook(channel_id, token) do
    payload = %{
      id: channel_id,
      resourceId: token
    }

    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(
           "https://www.googleapis.com/calendar/v3/channels/stop",
           Jason.encode!(payload),
           headers
         ) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        # Mark channel as inactive in database
        case get_channel_by_id(channel_id) do
          %CalendarChannel{} = channel ->
            update_channel(channel, %{active: false})

          nil ->
            {:ok, :not_found}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Google Calendar API error #{status}: #{body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  def find_user_by_channel(channel_id) do
    case get_channel_by_id(channel_id) do
      %CalendarChannel{user: user} = channel when not is_nil(user) ->
        {:ok, user, channel}

      %CalendarChannel{} = channel ->
        # Preload user if not already loaded
        channel = Repo.preload(channel, :user)
        {:ok, channel.user, channel}

      nil ->
        {:error, :channel_not_found}
    end
  end

  def process_calendar_change(channel_id, resource_id) do
    with {:ok, user, channel} <- find_user_by_channel(channel_id),
         {:ok, token} <- GoogleOAuth.get_valid_token(user) do

      # Get recent calendar events to see what changed
      headers = [{"Authorization", "Bearer #{token}"}]

      # Get events from the last hour to catch recent changes
      time_min = DateTime.add(DateTime.utc_now(), -1 * 60 * 60, :second)

      query_params = %{
        timeMin: DateTime.to_iso8601(time_min),
        maxResults: 50,
        singleEvents: true,
        orderBy: "updated"
      }

      url = "https://www.googleapis.com/calendar/v3/calendars/#{channel.calendar_id}/events?#{URI.encode_query(query_params)}"

      case HTTPoison.get(url, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          %{"items" => events} = Jason.decode!(body)

          # Process calendar events and trigger any relevant instructions
          App.Tasks.check_instructions_for_trigger(user, "calendar_event_created", %{
            calendar_id: channel.calendar_id,
            events: events,
            channel_id: channel_id
          })

          {:ok, %{processed: length(events)}}

        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          {:error, "Failed to fetch calendar events: #{status} - #{body}"}

        {:error, reason} ->
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end

  def cleanup_expired_channels do
    expired_channels =
      CalendarChannel
      |> where([c], c.expiration < ^DateTime.utc_now() and c.active == true)
      |> Repo.all()

    Enum.each(expired_channels, fn channel ->
      stop_calendar_webhook(channel.channel_id, channel.token)
    end)

    length(expired_channels)
  end

  def refresh_channel_subscriptions do
    # Get channels expiring in the next 24 hours
    soon_expiring = DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second)

    expiring_channels =
      CalendarChannel
      |> where([c], c.expiration < ^soon_expiring and c.active == true)
      |> preload(:user)
      |> Repo.all()

    Enum.each(expiring_channels, fn channel ->
      # Stop old webhook
      stop_calendar_webhook(channel.channel_id, channel.token)

      # Create new webhook
      setup_calendar_webhook(channel.user, channel.calendar_id)
    end)

    length(expiring_channels)
  end

  defp generate_channel_id(user_id, calendar_id) do
    "calendar_#{user_id}_#{calendar_id}_#{System.unique_integer([:positive])}"
  end

  defp create_or_update_channel(attrs) do
    case get_channel_by_id(attrs.channel_id) do
      nil ->
        %CalendarChannel{}
        |> CalendarChannel.changeset(attrs)
        |> Repo.insert()

      existing_channel ->
        existing_channel
        |> CalendarChannel.changeset(attrs)
        |> Repo.update()
    end
  end

  defp get_channel_by_id(channel_id) do
    CalendarChannel
    |> where([c], c.channel_id == ^channel_id)
    |> preload(:user)
    |> Repo.one()
  end

  defp update_channel(%CalendarChannel{} = channel, attrs) do
    channel
    |> CalendarChannel.changeset(attrs)
    |> Repo.update()
  end
end