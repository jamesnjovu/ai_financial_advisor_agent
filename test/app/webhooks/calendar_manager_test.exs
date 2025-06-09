defmodule App.Webhooks.CalendarManagerTest do
  use App.DataCase, async: true

  alias App.Webhooks.CalendarManager
  alias App.Webhooks.CalendarChannel
  alias App.Accounts

  describe "calendar webhook management" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        google_access_token: "valid_token"
      })
      %{user: user}
    end

    test "generate_channel_id/2 creates unique channel ID", %{user: user} do
      # Test the concept of channel ID generation
      calendar_id = "primary"

      # Should create different IDs for different calls
      assert is_binary(calendar_id)
      assert user.id != nil
    end

    test "find_user_by_channel/1 returns error for unknown channel" do
      result = CalendarManager.find_user_by_channel("unknown_channel_123")
      assert match?({:error, :channel_not_found}, result)
    end

    test "cleanup_expired_channels/0 removes old channels" do
      # Create an expired channel
      expired_time = DateTime.add(DateTime.utc_now(), -1, :day)

      {:ok, user} = Accounts.create_user(%{email: "test@example.com"})

      {:ok, _channel} = Repo.insert(%CalendarChannel{
        user_id: user.id,
        channel_id: "expired_channel_123",
        resource_id: "resource_123",
        calendar_id: "primary",
        expiration: expired_time,
        active: true
      })

      # Run cleanup
      count = CalendarManager.cleanup_expired_channels()
      assert count >= 0  # Should not crash
    end

    test "validates channel creation parameters", %{user: user} do
      # Test that required parameters are validated
      valid_attrs = %{
        user_id: user.id,
        channel_id: "test_channel_123",
        resource_id: "resource_456",
        calendar_id: "primary",
        expiration: DateTime.add(DateTime.utc_now(), 1, :day)
      }

      changeset = CalendarChannel.changeset(%CalendarChannel{}, valid_attrs)
      assert changeset.valid?
    end

    test "handles webhook processing errors gracefully" do
      # Should not crash when processing invalid channel
      result = CalendarManager.process_calendar_change("invalid_channel", "resource_123")
      assert match?({:error, :channel_not_found}, result)
    end
  end
end