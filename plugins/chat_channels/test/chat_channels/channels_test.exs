defmodule ChatChannels.ChannelsTest do
  # The channels half of the forum: creating, editing, ordering, deleting, the
  # per-user allowance, and who may do what to a channel. Written as
  # characterisation tests before the forum moves out of the core into the
  # chat_channels plugin (docs/chat-channels-plugin.md): whatever the
  # plugin does, these must still hold.
  #
  # Not async: the forum fires audit and notification tasks that need the shared
  # sandbox connection.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures


  setup do
    settle_on_exit()
    :ok
  end

  describe "create_channel/1" do
    test "needs a name, and a name is unique" do
      assert {:error, cs} = ChatChannels.create_channel(%{description: "no name"})
      assert %{name: ["can't be blank"]} = errors_on(cs)

      channel = channel_fixture()
      assert {:error, cs} = ChatChannels.create_channel(%{name: channel.name})
      assert %{name: ["has already been taken"]} = errors_on(cs)
    end

    test "only text, voice, video and stream channels exist" do
      assert {:error, cs} = ChatChannels.create_channel(%{name: "odd", channel_type: "carrier-pigeon"})
      assert %{channel_type: [_]} = errors_on(cs)

      for type <- ~w(text voice video stream) do
        assert {:ok, %{channel_type: ^type}} = ChatChannels.create_channel(%{name: "t-#{type}-#{System.unique_integer([:positive])}", channel_type: type})
      end
    end

    test "each new channel goes last" do
      a = channel_fixture()
      b = channel_fixture()
      assert b.position > a.position
    end

    test "announces the new channel" do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "chat:channels")
      channel = channel_fixture()
      assert_receive {:channel_created, %{id: id}} when id == channel.id
    end

    test "accepts atom or string keys" do
      assert {:ok, %{name: "atoms"}} = ChatChannels.create_channel(%{name: "atoms"})
      assert {:ok, %{name: "strings"}} = ChatChannels.create_channel(%{"name" => "strings"})
    end
  end

  describe "the per-user channel allowance" do
    test "defaults to five, also for a user that can't be read" do
      assert ChatChannels.default_channel_allowance() == 5
      assert ChatChannels.channel_allowance(user().id) == 5
      assert ChatChannels.channel_allowance(Ecto.UUID.generate()) == 5
      assert ChatChannels.channel_allowance(nil) == 5
    end

    test "lives on the user row" do
      assert ChatChannels.channel_allowance(user(%{channel_allowance: 12}).id) == 12
    end

    test "stops a user creating channels past it, naming the numbers" do
      u = user(%{channel_allowance: 2})
      for n <- 1..2, do: assert({:ok, _} = ChatChannels.create_user_channel(u, %{"name" => "mine-#{n}-#{u.id}"}))

      assert {:error, cs} = ChatChannels.create_user_channel(u, %{"name" => "mine-3-#{u.id}"})
      assert %{owner_id: [msg]} = errors_on(cs)
      assert msg =~ "2 of 2"
    end

    test "never stops an owner at the limit from editing what they have" do
      u = user(%{channel_allowance: 1})
      {:ok, channel} = ChatChannels.create_user_channel(u, %{"name" => "only-#{u.id}"})
      new_name = "renamed-#{u.id}"
      assert {:ok, %{name: ^new_name}} = ChatChannels.update_channel(channel, %{name: new_name})
    end
  end

  describe "create_user_channel/2" do
    test "makes the user the owner, and a member with the owner role" do
      u = user()
      {:ok, channel} = ChatChannels.create_user_channel(u, %{"name" => "owned-#{u.id}"})

      assert channel.owner_id == u.id
      assert channel.created_by_id == u.id
      assert channel.is_user_created
      assert channel.is_public
      refute channel.is_private
      assert ChatChannels.user_role_in_channel(channel.id, u.id) == "owner"
    end

    test "a private channel gets an invite code and stops being public" do
      u = user()

      for flag <- ["true", "on", true] do
        {:ok, channel} = ChatChannels.create_user_channel(u, %{"name" => "p-#{inspect(flag)}-#{u.id}", "is_private" => flag})
        assert channel.is_private
        refute channel.is_public
        assert is_binary(channel.invite_code) and byte_size(channel.invite_code) == 10
      end
    end

    test "a public channel has no invite code" do
      {:ok, channel} = ChatChannels.create_user_channel(user(), %{"name" => "pub-#{System.unique_integer([:positive])}"})
      assert channel.invite_code == nil
    end

    test "list_owned_channels/1 returns exactly this user's" do
      u = user()
      other = user()
      {:ok, mine} = ChatChannels.create_user_channel(u, %{"name" => "mine-#{u.id}"})
      {:ok, _} = ChatChannels.create_user_channel(other, %{"name" => "theirs-#{other.id}"})

      assert [%{id: id}] = ChatChannels.list_owned_channels(u.id)
      assert id == mine.id
    end
  end

  describe "listing" do
    test "text and voice listings split by type, voice including video" do
      text = channel_fixture(%{channel_type: "text"})
      voice = channel_fixture(%{channel_type: "voice"})
      video = channel_fixture(%{channel_type: "video"})
      stream = channel_fixture(%{channel_type: "stream"})

      text_ids = Enum.map(ChatChannels.list_text_channels(), & &1.id)
      voice_ids = Enum.map(ChatChannels.list_voice_channels(), & &1.id)

      assert text.id in text_ids
      refute voice.id in text_ids
      assert voice.id in voice_ids and video.id in voice_ids
      refute stream.id in voice_ids and stream.id in text_ids
    end

    test "list_public_channels/0 leaves private ones out" do
      pub = channel_fixture()
      priv = channel_fixture(%{is_private: true})
      ids = Enum.map(ChatChannels.list_public_channels(), & &1.id)
      assert pub.id in ids
      refute priv.id in ids
    end

    test "reorder_channels/1 sets the positions, skipping ids that aren't UUIDs" do
      [a, b, c] = for _ <- 1..3, do: channel_fixture()
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "chat:channels")

      ChatChannels.reorder_channels([c.id, "not-a-uuid", a.id, b.id])

      mine = for ch <- ChatChannels.list_channels(), ch.id in [a.id, b.id, c.id], do: ch.id
      assert mine == [c.id, a.id, b.id]
      assert_receive {:channels_reordered, _}
    end

    test "a user's own order keeps valid ids only" do
      u = user()
      a = channel_fixture()
      assert {:ok, updated} = ChatChannels.reorder_channels(u, [a.id, "junk", Ecto.UUID.generate()])
      assert a.id in updated.channel_order
      refute "junk" in updated.channel_order
    end

    test "get_or_create_default_channel/0 makes general once" do
      first = ChatChannels.get_or_create_default_channel()
      assert first.name == "general"
      assert ChatChannels.get_or_create_default_channel().id == first.id
    end
  end

  describe "update_channel/2" do
    test "renames, and announces it" do
      channel = channel_fixture()
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "chat:channels")
      new_name = "renamed-#{System.unique_integer([:positive])}"

      assert {:ok, %{name: ^new_name}} = ChatChannels.update_channel(channel, %{name: new_name})
      assert_receive {:channel_updated, %{id: id, name: ^new_name}} when id == channel.id
    end

    test "can't take another channel's name" do
      a = channel_fixture()
      b = channel_fixture()
      assert {:error, cs} = ChatChannels.update_channel(b, %{name: a.name})
      assert %{name: ["has already been taken"]} = errors_on(cs)
    end

    test "works from a stale struct (it re-reads the row)" do
      channel = channel_fixture()
      {:ok, _} = ChatChannels.update_channel(channel, %{description: "first"})
      assert {:ok, %{description: "second"}} = ChatChannels.update_channel(channel, %{description: "second"})
    end
  end

  describe "delete_channel/1" do
    test "never deletes general, whatever its case" do
      for name <- ["general", "General", "GENERAL"] do
        {:ok, general} = ChatChannels.create_channel(%{name: name})
        assert {:error, :protected_channel} = ChatChannels.delete_channel(general)
        assert ChatChannels.get_channel(general.id)
      end
    end

    test "takes the messages and reactions with it, and announces it" do
      channel = channel_fixture()
      author = user()
      msg = message_fixture(channel, author, "bye")
      {:ok, _} = ChatChannels.add_reaction(msg, author, "👍")
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "chat:channels")

      assert {:ok, _} = ChatChannels.delete_channel(channel)

      assert ChatChannels.get_channel(channel.id) == nil
      assert ChatChannels.get_message(msg.id) == nil
      assert ChatChannels.count_messages_in_channel(channel.id) == 0
      assert Repo.aggregate(ChatChannels.Reaction, :count) == 0
      assert_receive {:channel_deleted, id} when id == channel.id
    end

    test "leaves other channels alone" do
      a = channel_fixture()
      b = channel_fixture()
      message_fixture(b, user(), "stays")
      assert {:ok, _} = ChatChannels.delete_channel(a)
      assert ChatChannels.count_messages_in_channel(b.id) == 1
    end
  end

  describe "delete_channel_by_user/2" do
    setup do
      owner = user()
      {:ok, public} = ChatChannels.create_channel(%{name: "pub-#{System.unique_integer([:positive])}", owner_id: owner.id})
      {:ok, private} = ChatChannels.create_channel(%{name: "priv-#{System.unique_integer([:positive])}", owner_id: owner.id, is_private: true})
      %{owner: owner, public: public, private: private}
    end

    test "a public channel can be deleted only by staff, even by its owner", %{owner: owner, public: public} do
      assert {:error, :forbidden} = ChatChannels.delete_channel_by_user(owner, public)
      assert {:ok, _} = ChatChannels.delete_channel_by_user(admin(), public)
    end

    test "every staff role may", %{public: public} do
      for role <- ~w(admin gm editor) do
        {:ok, ch} = ChatChannels.create_channel(%{name: "staff-#{role}-#{System.unique_integer([:positive])}"})
        assert {:ok, _} = ChatChannels.delete_channel_by_user(user(%{role: role}), ch)
      end

      assert ChatChannels.get_channel(public.id)
    end

    test "the owner may delete their private channel; a stranger may not", %{owner: owner, private: private} do
      assert {:error, :forbidden} = ChatChannels.delete_channel_by_user(user(), private)
      assert {:ok, _} = ChatChannels.delete_channel_by_user(owner, private)
    end

    test "the creator may too, once the channel is private" do
      creator = user()
      {:ok, ch} = ChatChannels.create_channel(%{name: "c-#{System.unique_integer([:positive])}", created_by_id: creator.id, is_private: true})
      assert {:ok, _} = ChatChannels.delete_channel_by_user(creator, ch)
    end

    test "general is protected from everyone" do
      {:ok, general} = ChatChannels.create_channel(%{name: "General"})
      assert {:error, :protected_channel} = ChatChannels.delete_channel_by_user(admin(), general)
    end
  end

  describe "transfer_channel_ownership/3" do
    setup do
      old = user()
      {:ok, channel} = ChatChannels.create_user_channel(old, %{"name" => "xfer-#{System.unique_integer([:positive])}"})
      %{old: old, channel: channel, new: user()}
    end

    test "hands the channel over and swaps the member roles", %{old: old, channel: channel, new: new} do
      assert {:ok, updated} = ChatChannels.transfer_channel_ownership(old, channel, new.id)

      assert updated.owner_id == new.id
      assert ChatChannels.user_role_in_channel(channel.id, new.id) == "owner"
      assert ChatChannels.user_role_in_channel(channel.id, old.id) == "member"
    end

    test "promotes an existing member rather than adding a second row", %{old: old, channel: channel, new: new} do
      member_fixture(channel, new)
      assert {:ok, _} = ChatChannels.transfer_channel_ownership(old, channel, new.id)

      assert ChatChannels.user_role_in_channel(channel.id, new.id) == "owner"
      assert Enum.count(ChatChannels.list_channel_members(channel.id), &(&1.user_id == new.id)) == 1
    end

    test "a stranger can't; an admin can", %{channel: channel, new: new} do
      assert {:error, :forbidden} = ChatChannels.transfer_channel_ownership(user(), channel, new.id)
      assert {:ok, %{owner_id: id}} = ChatChannels.transfer_channel_ownership(admin(), channel, new.id)
      assert id == new.id
    end

    test "the old owner can no longer manage it", %{old: old, channel: channel, new: new} do
      assert ChatChannels.can_manage_channel?(old, channel)
      {:ok, updated} = ChatChannels.transfer_channel_ownership(old, channel, new.id)
      refute ChatChannels.can_manage_channel?(old, updated)
      assert ChatChannels.can_manage_channel?(new, updated)
    end
  end
end
