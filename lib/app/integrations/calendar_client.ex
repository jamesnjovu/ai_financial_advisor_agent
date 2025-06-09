defmodule App.Integrations.CalendarClient do
  @moduledoc """
  Google Calendar API client for managing calendar events
  """

  @options [
    timeout: 2_000_000,
    recv_timeout: 2_000_000
  ]

  alias App.Auth.GoogleOAuth

  @base_url "https://www.googleapis.com/calendar/v3"

  def list_events(user, opts \\ []) do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]
        calendar_id = opts[:calendar_id] || "primary"

        query_params = %{
                         timeMin: opts[:time_min] || DateTime.utc_now()
                                                     |> DateTime.to_iso8601(),
                         timeMax: opts[:time_max],
                         maxResults: opts[:max_results] || 100,
                         singleEvents: true,
                         orderBy: "startTime"
                       }
                       |> Enum.reject(fn {_k, v} -> is_nil(v) end)
                       |> Map.new()

        url = "#{@base_url}/calendars/#{calendar_id}/events?#{URI.encode_query(query_params)}"

        case HTTPoison.get(url, headers, @options) do
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

  def create_event(user, event_data, calendar_id \\ "primary") do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        url = "#{@base_url}/calendars/#{calendar_id}/events"

        case HTTPoison.post(url, Jason.encode!(event_data), headers, @options) do
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

  def update_event(user, event_id, event_data, calendar_id \\ "primary") do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        url = "#{@base_url}/calendars/#{calendar_id}/events/#{event_id}"

        case HTTPoison.put(url, Jason.encode!(event_data), headers, @options) do
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

  def delete_event(user, event_id, calendar_id \\ "primary") do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]
        url = "#{@base_url}/calendars/#{calendar_id}/events/#{event_id}"

        case HTTPoison.delete(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 204}} ->
            {:ok, :deleted}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def get_free_busy(user, emails, time_min, time_max) do
    case GoogleOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          timeMin: time_min,
          timeMax: time_max,
          items: Enum.map(emails, fn email -> %{id: email} end)
        }

        url = "#{@base_url}/freeBusy"

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

  def find_available_slots(user, duration_minutes, participants \\ [], opts \\ []) do
    start_time = opts[:start_time] || DateTime.utc_now()
    end_time = opts[:end_time] || DateTime.add(start_time, 7, :day)

    with {:ok, free_busy} <- get_free_busy(
      user,
      [user.email | participants],
      DateTime.to_iso8601(start_time),
      DateTime.to_iso8601(end_time)
    ) do

      busy_periods = extract_busy_periods(free_busy)
      available_slots = calculate_available_slots(start_time, end_time, busy_periods, duration_minutes)

      {:ok, available_slots}
    end
  end

  def build_event(summary, start_time, end_time, opts \\ []) do
    %{
      summary: summary,
      description: opts[:description],
      start: %{
        dateTime: DateTime.to_iso8601(start_time),
        timeZone: opts[:timezone] || "UTC"
      },
      end: %{
        dateTime: DateTime.to_iso8601(end_time),
        timeZone: opts[:timezone] || "UTC"
      },
      attendees: Enum.map(
        opts[:attendees] || [],
        fn email ->
           %{email: email}
        end
      ),
      location: opts[:location],
      reminders: %{
        useDefault: true
      }
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_busy_periods(%{"calendars" => calendars}) do
    calendars
    |> Enum.flat_map(
         fn {_email, %{"busy" => busy_periods}} ->
           Enum.map(
             busy_periods,
             fn %{"start" => start_str, "end" => end_str} ->
               {DateTime.from_iso8601(start_str), DateTime.from_iso8601(end_str)}
             end
           )
         end
       )
    |> Enum.filter(
         fn
           {{:ok, _start, _}, {:ok, _end, _}} -> true;
           _ -> false end
       )
    |> Enum.map(fn {{:ok, start, _}, {:ok, end_time, _}} -> {start, end_time} end)
    |> Enum.sort()
  end

  defp calculate_available_slots(start_time, end_time, busy_periods, duration_minutes) do
    # This is a simplified implementation
    # In practice, you'd want more sophisticated scheduling logic
    duration_seconds = duration_minutes * 60

    Stream.iterate(start_time, &DateTime.add(&1, 30, :minute))
    |> Stream.take_while(&(DateTime.compare(&1, end_time) == :lt))
    |> Stream.filter(
         fn slot_start ->
           slot_end = DateTime.add(slot_start, duration_seconds, :second)

           not Enum.any?(
             busy_periods,
             fn {busy_start, busy_end} ->
               DateTime.compare(slot_start, busy_end) == :lt and
               DateTime.compare(slot_end, busy_start) == :gt
             end
           )
         end
       )
    |> Enum.take(10) # Return first 10 available slots
  end
end