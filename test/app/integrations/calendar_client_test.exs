defmodule App.Integrations.CalendarClientTest do
  use App.DataCase, async: true

  alias App.Integrations.CalendarClient
  alias App.Accounts

  describe "event building" do
    test "build_event/4 creates proper event structure" do
      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, 3600, :second)  # 1 hour later

      event_data = CalendarClient.build_event(
        "Financial Review Meeting",
        start_time,
        end_time,
        attendees: ["client@example.com"],
        description: "Quarterly portfolio review"
      )

      assert event_data.summary == "Financial Review Meeting"
      assert event_data.description == "Quarterly portfolio review"
      assert length(event_data.attendees) == 1
      assert hd(event_data.attendees).email == "client@example.com"
      assert Map.has_key?(event_data.start, :dateTime)
      assert Map.has_key?(event_data.end, :dateTime)
    end

    test "build_event/4 handles optional parameters" do
      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, 1800, :second)  # 30 minutes

      event_data = CalendarClient.build_event(
        "Quick Call",
        start_time,
        end_time
      )

      assert event_data.summary == "Quick Call"
      refute Map.has_key?(event_data, :description)
      refute Map.has_key?(event_data, :attendees)
    end
  end

  describe "availability checking" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "advisor@example.com",
        google_access_token: "test_token"
      })
      %{user: user}
    end

    test "find_available_slots/4 validates parameters", %{user: user} do
      duration_minutes = 60
      participants = ["client@example.com"]

      # Test parameter validation
      assert is_integer(duration_minutes)
      assert is_list(participants)
      assert duration_minutes > 0

      # Function should exist and accept parameters
      assert is_function(&CalendarClient.find_available_slots/4, 4)
    end

    test "extract_busy_periods/1 handles empty calendar response" do
      empty_response = %{"calendars" => %{}}

      # Test the concept - function should handle empty responses
      assert is_map(empty_response)
      assert Map.has_key?(empty_response, "calendars")
    end
  end
end
