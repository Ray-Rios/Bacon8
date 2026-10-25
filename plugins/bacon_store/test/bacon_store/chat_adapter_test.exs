defmodule BaconStore.ChatAdapterTest do
  # The store sells channel passes and channel slots, which need Chat Channels, but the
  # store must keep working (and compile) on a site without chat. BaconStore.Chat is the
  # only place it touches chat, resolved when called.
  use Bacon8.DataCase, async: false

  alias BaconStore.Chat

  defp channel!(attrs) do
    {:ok, c} = ChatChannels.create_channel(Map.merge(%{name: "ch-#{System.unique_integer([:positive])}"}, attrs))
    c
  end

  test "chat is available when the plugin is installed" do
    assert Chat.available?()
  end

  test "lists private channels only, as id and name, by name" do
    pub = channel!(%{name: "pub-#{System.unique_integer([:positive])}"})
    b = channel!(%{name: "b-private-#{System.unique_integer([:positive])}", is_private: true})
    a = channel!(%{name: "a-private-#{System.unique_integer([:positive])}", is_private: true})

    list = Chat.private_channels()
    ids = Enum.map(list, & &1.id)

    assert a.id in ids and b.id in ids
    refute pub.id in ids
    assert Enum.find(list, &(&1.id == a.id)).name == a.name
    # the ids come back as the strings channel pages and products use, not raw bytes
    assert Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1)))
    assert Enum.find_index(ids, &(&1 == a.id)) < Enum.find_index(ids, &(&1 == b.id))
  end

  test "names a channel, and gives nil for one that isn't there or isn't an id" do
    c = channel!(%{})
    assert Chat.channel_name(c.id) == c.name
    assert Chat.channel_name(Ecto.UUID.generate()) == nil
    assert Chat.channel_name("not-an-id") == nil
    assert Chat.channel_name(nil) == nil
  end

  test "adds, finds and removes a member through chat" do
    c = channel!(%{is_private: true})
    u = user_fixture()

    refute Chat.member?(c.id, u.id)
    assert Chat.get_member(c.id, u.id) == nil

    assert {:ok, %{role: "member"}} = Chat.add_member(%{channel_id: c.id, user_id: u.id, role: "member"})
    assert Chat.member?(c.id, u.id)
    assert %{role: "member"} = Chat.get_member(c.id, u.id)

    assert {:ok, _} = Chat.remove_member(c.id, u.id)
    refute Chat.member?(c.id, u.id)
  end
end
