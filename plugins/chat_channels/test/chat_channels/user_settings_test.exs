defmodule ChatChannels.UserSettingsTest do
  # The plugin's own per-user settings (they used to be columns on the hub's users table).
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures

  alias ChatChannels.UserSettings

  describe "the channel allowance" do
    test "add_channel_allowance/2 starts from the default and accumulates" do
      u = user()
      assert {:ok, 8} = ChatChannels.add_channel_allowance(u.id, 3)
      assert {:ok, 10} = ChatChannels.add_channel_allowance(u.id, 2)
      assert ChatChannels.channel_allowance(u.id) == 10
    end

    test "it never goes below zero, and a slot pass ending removes only what it gave" do
      u = user_with_allowance(2)
      assert {:ok, 0} = ChatChannels.add_channel_allowance(u.id, -5)
      assert {:ok, 3} = ChatChannels.add_channel_allowance(u.id, 3)
    end

    test "set_channel_allowance/2 sets it outright, inside 0..1000" do
      u = user()
      assert {:ok, 0} = ChatChannels.set_channel_allowance(u.id, 0)
      assert ChatChannels.channel_allowance(u.id) == 0
      assert {:error, :out_of_range} = ChatChannels.set_channel_allowance(u.id, -1)
      assert {:error, :out_of_range} = ChatChannels.set_channel_allowance(u.id, 1001)
      assert ChatChannels.channel_allowance(u.id) == 0
    end

    test "setting one thing leaves the others alone" do
      u = user()
      a = channel_fixture()
      {:ok, _} = ChatChannels.reorder_channels(u, [a.id])
      {:ok, false} = ChatChannels.set_allow_invites(u.id, false)
      {:ok, 9} = ChatChannels.set_channel_allowance(u.id, 9)

      assert ChatChannels.channel_order(u.id) == [a.id]
      refute ChatChannels.allow_invites?(u.id)
      assert ChatChannels.channel_allowance(u.id) == 9
    end
  end

  describe "invitations" do
    test "are on by default, and can be switched off and on" do
      u = user()
      assert ChatChannels.allow_invites?(u.id)
      {:ok, false} = ChatChannels.set_allow_invites(u.id, false)
      refute ChatChannels.allow_invites?(u.id)
      {:ok, true} = ChatChannels.set_allow_invites(u.id, true)
      assert ChatChannels.allow_invites?(u.id)
    end

    test "can_receive_invite?/2 follows the switch, and the block list" do
      invitee = user()
      inviter = user()
      assert ChatChannels.can_receive_invite?(invitee, inviter.id)

      {:ok, _} = ChatChannels.set_allow_invites(invitee.id, false)
      refute ChatChannels.can_receive_invite?(invitee, inviter.id)

      {:ok, _} = ChatChannels.set_allow_invites(invitee.id, true)
      refute ChatChannels.can_receive_invite?(%{invitee | blocked_user_ids: [inviter.id]}, inviter.id)
    end
  end

  test "settings go with the user" do
    u = user()
    {:ok, _} = ChatChannels.set_channel_allowance(u.id, 7)
    assert Repo.get(UserSettings, u.id)

    Repo.delete!(u)
    refute Repo.get(UserSettings, u.id)
  end
end
