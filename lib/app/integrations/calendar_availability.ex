defmodule App.Integrations.CalendarAvailability do
  @moduledoc """
  Functions for analyzing Google Calendar free/busy data and determining availability
  """

  @doc """
  Check if a specific time slot is free based on Google Calendar free/busy response
  """
  def is_time_slot_free?(free_busy_data, start_time, end_time) do
    case parse_free_busy_response(free_busy_data) do
      {:ok, busy_periods} ->
        not has_conflict?(busy_periods, start_time, end_time)

      {:error, _reason} ->
        # If we can't parse the response, assume conflicted for safety
        false
    end
  end

  @doc """
  Parse Google Calendar free/busy response and extract busy periods
  """
  def parse_free_busy_response(free_busy_data) do
    try do
      case free_busy_data do
        %{"calendars" => calendars} when is_map(calendars) ->
          busy_periods = extract_all_busy_periods(calendars)
          {:ok, busy_periods}

        %{"error" => error} ->
          {:error, "Free/busy API error: #{inspect(error)}"}

        _ ->
          {:error, "Invalid free/busy response format"}
      end
    rescue
      e -> {:error, "Failed to parse free/busy data: #{Exception.message(e)}"}
    end
  end

  @doc """
  Extract conflicts from free/busy data for a specific time range
  """
  def extract_conflicts(free_busy_data, start_time, end_time) do
    case parse_free_busy_response(free_busy_data) do
      {:ok, busy_periods} ->
        find_conflicting_periods(busy_periods, start_time, end_time)

      {:error, _} ->
        []
    end
  end

  @doc """
  Find the next available slot after conflicts
  """
  def find_next_available_slot(free_busy_data, requested_start, duration_minutes) do
    case parse_free_busy_response(free_busy_data) do
      {:ok, busy_periods} ->
        duration_seconds = duration_minutes * 60
        find_gap_after_conflicts(busy_periods, requested_start, duration_seconds)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp extract_all_busy_periods(calendars) do
    calendars
    |> Enum.flat_map(fn {_calendar_id, calendar_data} ->
      extract_busy_periods_for_calendar(calendar_data)
    end)
    |> Enum.sort_by(fn {start_time, _end_time} -> start_time end)
    |> merge_overlapping_periods()
  end

  defp extract_busy_periods_for_calendar(calendar_data) do
    case calendar_data do
      %{"busy" => busy_list} when is_list(busy_list) ->
        busy_list
        |> Enum.map(&parse_busy_period/1)
        |> Enum.reject(&is_nil/1)

      %{"errors" => errors} ->
        # Calendar has errors (e.g., permission issues)
        # Log the errors but don't treat as busy time
        []

      _ ->
        # No busy periods or unexpected format
        []
    end
  end

  defp parse_busy_period(%{"start" => start_str, "end" => end_str}) do
    with {:ok, start_time} <- parse_datetime_string(start_str),
         {:ok, end_time} <- parse_datetime_string(end_str) do
      {start_time, end_time}
    else
      _ -> nil
    end
  end

  defp parse_busy_period(_), do: nil

  defp parse_datetime_string(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime_string(_), do: {:error, :invalid_format}

  defp merge_overlapping_periods([]), do: []
  defp merge_overlapping_periods([single_period]), do: [single_period]
  defp merge_overlapping_periods(periods) do
    periods
    |> Enum.reduce([], fn {start_time, end_time}, acc ->
      case acc do
        [] ->
          [{start_time, end_time}]

        [{last_start, last_end} | rest] ->
          if DateTime.compare(start_time, last_end) != :gt do
            # Overlapping or adjacent periods - merge them
            merged_end = if DateTime.compare(end_time, last_end) == :gt, do: end_time, else: last_end
            [{last_start, merged_end} | rest]
          else
            # Non-overlapping period
            [{start_time, end_time} | acc]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp has_conflict?(busy_periods, start_time, end_time) do
    Enum.any?(busy_periods, fn {busy_start, busy_end} ->
      periods_overlap?(start_time, end_time, busy_start, busy_end)
    end)
  end

  defp periods_overlap?(start1, end1, start2, end2) do
    # Two periods overlap if:
    # start1 < end2 AND start2 < end1
    DateTime.compare(start1, end2) == :lt and DateTime.compare(start2, end1) == :lt
  end

  defp find_conflicting_periods(busy_periods, start_time, end_time) do
    busy_periods
    |> Enum.filter(fn {busy_start, busy_end} ->
      periods_overlap?(start_time, end_time, busy_start, busy_end)
    end)
    |> Enum.map(fn {busy_start, busy_end} ->
      %{
        start: DateTime.to_iso8601(busy_start),
        end: DateTime.to_iso8601(busy_end),
        conflict_type: determine_conflict_type(start_time, end_time, busy_start, busy_end)
      }
    end)
  end

  defp determine_conflict_type(requested_start, requested_end, busy_start, busy_end) do
    cond do
      # Completely encompasses the requested time
      DateTime.compare(busy_start, requested_start) != :gt and
      DateTime.compare(busy_end, requested_end) != :lt ->
        :completely_blocked

      # Partial overlap at the beginning
      DateTime.compare(busy_start, requested_start) == :lt and
      DateTime.compare(busy_end, requested_end) == :lt ->
        :partial_beginning

      # Partial overlap at the end
      DateTime.compare(busy_start, requested_start) == :gt and
      DateTime.compare(busy_end, requested_end) == :gt ->
        :partial_end

      # Requested time encompasses the busy period
      DateTime.compare(requested_start, busy_start) != :gt and
      DateTime.compare(requested_end, busy_end) != :lt ->
        :internal_conflict

      true ->
        :overlap
    end
  end

  defp find_gap_after_conflicts(busy_periods, requested_start, duration_seconds) do
    # Find the earliest time after requested_start where we can fit duration_seconds
    case find_blocking_period(busy_periods, requested_start) do
      nil ->
        # No immediate conflicts, check if we have enough time before next busy period
        case find_next_busy_period(busy_periods, requested_start) do
          nil ->
            # No upcoming conflicts
            {:ok, requested_start}

          {next_busy_start, _next_busy_end} ->
            available_duration = DateTime.diff(next_busy_start, requested_start, :second)
            if available_duration >= duration_seconds do
              {:ok, requested_start}
            else
              # Not enough time, need to find gap after this busy period
              find_gap_after_busy_periods(busy_periods, requested_start, duration_seconds)
            end
        end

      {_conflict_start, conflict_end} ->
        # There's an immediate conflict, start searching after it ends
        find_gap_after_busy_periods(busy_periods, conflict_end, duration_seconds)
    end
  end

  defp find_blocking_period(busy_periods, start_time) do
    Enum.find(busy_periods, fn {busy_start, busy_end} ->
      DateTime.compare(busy_start, start_time) != :gt and
      DateTime.compare(busy_end, start_time) == :gt
    end)
  end

  defp find_next_busy_period(busy_periods, after_time) do
    busy_periods
    |> Enum.filter(fn {busy_start, _busy_end} ->
      DateTime.compare(busy_start, after_time) == :gt
    end)
    |> Enum.min_by(fn {busy_start, _busy_end} -> busy_start end, fn -> nil end)
  end

  defp find_gap_after_busy_periods(busy_periods, earliest_start, duration_seconds) do
    # Sort busy periods and find gaps between them
    sorted_periods = Enum.sort_by(busy_periods, fn {start_time, _} -> start_time end)

    case find_suitable_gap(sorted_periods, earliest_start, duration_seconds) do
      {:ok, gap_start} ->
        {:ok, gap_start}

      :no_gap_found ->
        # No suitable gap found in busy periods, suggest time after all conflicts
        case List.last(sorted_periods) do
          nil -> {:ok, earliest_start}
          {_last_start, last_end} -> {:ok, last_end}
        end
    end
  end

  defp find_suitable_gap([], earliest_start, _duration_seconds) do
    {:ok, earliest_start}
  end

  defp find_suitable_gap([{first_start, first_end} | rest], earliest_start, duration_seconds) do
    # Check gap before first period
    gap_start = max_datetime(earliest_start, earliest_start)
    gap_end = first_start
    gap_duration = DateTime.diff(gap_end, gap_start, :second)

    if gap_duration >= duration_seconds do
      {:ok, gap_start}
    else
      # Check gaps between periods
      find_gap_between_periods([{first_start, first_end} | rest], first_end, duration_seconds)
    end
  end

  defp find_gap_between_periods([], last_end, _duration_seconds) do
    {:ok, last_end}
  end

  defp find_gap_between_periods([{_current_start, current_end} | rest], _previous_end, duration_seconds) do
    case rest do
      [] ->
        # No more periods, time after current is available
        {:ok, current_end}

      [{next_start, _next_end} | _] ->
        gap_duration = DateTime.diff(next_start, current_end, :second)
        if gap_duration >= duration_seconds do
          {:ok, current_end}
        else
          find_gap_between_periods(rest, current_end, duration_seconds)
        end
    end
  end

  defp max_datetime(dt1, dt2) do
    if DateTime.compare(dt1, dt2) == :gt, do: dt1, else: dt2
  end

  @doc """
  Format conflict information for user-friendly display
  """
  def format_conflicts(conflicts) when is_list(conflicts) do
    conflicts
    |> Enum.map(&format_single_conflict/1)
    |> Enum.join(", ")
  end

  defp format_single_conflict(%{start: start_str, end: end_str, conflict_type: type}) do
    with {:ok, start_dt, _} <- DateTime.from_iso8601(start_str),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_str) do
      start_time = Calendar.strftime(start_dt, "%I:%M %p")
      end_time = Calendar.strftime(end_dt, "%I:%M %p")

      case type do
        :completely_blocked -> "Completely blocked #{start_time}-#{end_time}"
        :partial_beginning -> "Conflict until #{end_time}"
        :partial_end -> "Conflict starting #{start_time}"
        :internal_conflict -> "Meeting during #{start_time}-#{end_time}"
        :overlap -> "Overlap #{start_time}-#{end_time}"
      end
    else
      _ -> "Scheduling conflict"
    end
  end

  @doc """
  Validate free/busy response structure
  """
  def validate_free_busy_response(response) do
    case response do
      %{"calendars" => calendars} when is_map(calendars) ->
        validation_results = Enum.map(calendars, fn {calendar_id, calendar_data} ->
          validate_calendar_data(calendar_id, calendar_data)
        end)

        errors = Enum.reject(validation_results, &match?(:ok, &1))

        if Enum.empty?(errors) do
          :ok
        else
          {:error, errors}
        end

      %{"error" => error} ->
        {:error, "API error: #{inspect(error)}"}

      _ ->
        {:error, "Invalid response format"}
    end
  end

  defp validate_calendar_data(calendar_id, calendar_data) do
    case calendar_data do
      %{"busy" => busy_periods} when is_list(busy_periods) ->
        invalid_periods = Enum.reject(busy_periods, &valid_busy_period?/1)
        if Enum.empty?(invalid_periods) do
          :ok
        else
          {:error, "Invalid busy periods in calendar #{calendar_id}: #{inspect(invalid_periods)}"}
        end

      %{"errors" => errors} ->
        {:error, "Calendar #{calendar_id} has errors: #{inspect(errors)}"}

      _ ->
        # No busy periods or unexpected format - this is okay
        :ok
    end
  end

  defp valid_busy_period?(%{"start" => start_str, "end" => end_str})
       when is_binary(start_str) and is_binary(end_str) do
    case {DateTime.from_iso8601(start_str), DateTime.from_iso8601(end_str)} do
      {{:ok, start_dt, _}, {:ok, end_dt, _}} ->
        DateTime.compare(start_dt, end_dt) == :lt
      _ ->
        false
    end
  end

  defp valid_busy_period?(_), do: false
end

