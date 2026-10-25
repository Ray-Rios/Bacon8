defmodule ChatChannels.MessagesTest do
  # Messages, replies, reactions, pins and search: what is stored, who may edit
  # or delete it, what is shown to readers, and what is announced on
  # "channel:<id>". Pinned before the forum becomes the chat_channels plugin.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures


  setup do
    settle_on_exit()
    author = user()
    channel = channel_fixture()
    %{author: author, channel: channel}
  end

  describe "create_message/3" do
    test "stores the message with its author, and announces it", %{author: author, channel: channel} do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")

      assert {:ok, msg} = ChatChannels.create_message(author, channel.id, %{content: "hi there"})
      assert msg.content == "hi there"
      assert msg.user.id == author.id
      assert msg.channel_id == channel.id
      assert msg.replies == []
      assert_receive {:new_message, %{id: id}} when id == msg.id
    end

    test "refuses an empty message and one over 2000 characters", %{author: author, channel: channel} do
      assert {:error, cs} = ChatChannels.create_message(author, channel.id, %{content: ""})
      assert %{content: ["can't be blank"]} = errors_on(cs)

      assert {:error, cs} = ChatChannels.create_message(author, channel.id, %{content: String.duplicate("a", 2001)})
      assert %{content: [msg]} = errors_on(cs)
      assert msg =~ "at most 2000"

      assert {:ok, _} = ChatChannels.create_message(author, channel.id, %{content: String.duplicate("a", 2000)})
    end

    test "a site-banned user can't post", %{channel: channel} do
      assert {:error, :banned} = ChatChannels.create_message(user(%{role: "banned"}), channel.id, %{content: "x"})
    end

    test "a private channel is closed to non-members, open to members", %{author: author} do
      private = channel_fixture(%{is_private: true})
      assert {:error, :forbidden} = ChatChannels.create_message(author, private.id, %{content: "x"})

      member_fixture(private, author)
      assert {:ok, _} = ChatChannels.create_message(author, private.id, %{content: "x"})
    end

    test "a user banned from a channel can't post in it", %{author: author, channel: channel} do
      member_fixture(channel, author, "member", %{is_banned: true})
      assert {:error, :forbidden} = ChatChannels.create_message(author, channel.id, %{content: "x"})
    end

    test "a channel that doesn't exist is an error, not a crash", %{author: author} do
      assert {:error, :not_found} = ChatChannels.create_message(author, Ecto.UUID.generate(), %{content: "x"})
    end

    test "a reply carries the id of what it answers", %{author: author, channel: channel} do
      {:ok, parent} = ChatChannels.create_message(author, channel.id, %{content: "question"})
      {:ok, reply} = ChatChannels.create_message(author, channel.id, %{content: "answer", parent_id: parent.id})
      assert reply.reply_to_id == parent.id
    end

    test "members are limited to 30 messages a minute; staff are not", %{channel: channel} do
      member = user()
      for n <- 1..30, do: assert({:ok, _} = ChatChannels.create_message(member, channel.id, %{content: "m#{n}"}))
      assert {:error, :rate_limited} = ChatChannels.create_message(member, channel.id, %{content: "one too many"})

      staff = admin()
      for n <- 1..31, do: assert({:ok, _} = ChatChannels.create_message(staff, channel.id, %{content: "s#{n}"}))
    end
  end

  describe "reading" do
    test "list_messages/2 is oldest first", %{author: author, channel: channel} do
      a = message_fixture(channel, author, "first", 30)
      b = message_fixture(channel, author, "second", 20)
      c = message_fixture(channel, author, "third", 10)

      assert Enum.map(ChatChannels.list_messages(channel.id), & &1.id) == [a.id, b.id, c.id]
    end

    test "the limit keeps the newest messages, still oldest first", %{author: author, channel: channel} do
      for n <- 1..5, do: message_fixture(channel, author, "m#{n}", 60 - n * 10)

      assert Enum.map(ChatChannels.list_messages(channel.id, 2), & &1.content) == ["m4", "m5"]
    end

    test "replies hang under their parent and not at the top", %{author: author, channel: channel} do
      parent = message_fixture(channel, author, "parent", 20)
      reply = message_fixture(channel, author, "reply", 10, %{reply_to_id: parent.id})

      assert [top] = ChatChannels.list_messages(channel.id)
      assert top.id == parent.id
      assert Enum.map(top.replies, & &1.id) == [reply.id]
    end

    test "a site-banned author's messages are hidden", %{author: author, channel: channel} do
      banned = user(%{role: "banned"})
      keep = message_fixture(channel, author, "kept", 20)
      message_fixture(channel, banned, "hidden", 10)

      assert Enum.map(ChatChannels.list_messages(channel.id), & &1.id) == [keep.id]
    end

    test "other channels' messages stay out", %{author: author, channel: channel} do
      message_fixture(channel_fixture(), author, "elsewhere")
      assert ChatChannels.list_messages(channel.id) == []
    end

    test "the cursor pages back from a message", %{author: author, channel: channel} do
      ms = for n <- 1..5, do: message_fixture(channel, author, "m#{n}", 60 - n * 10)
      [_, m2, m3, m4, _] = ms

      assert Enum.map(ChatChannels.list_messages_cursor(channel.id, %{before: m4.id, limit: 2}), & &1.id) == [m2.id, m3.id]
      assert Enum.map(ChatChannels.list_messages_cursor(channel.id, %{limit: 2}), & &1.content) == ["m1", "m2"]
    end

    test "search is case-insensitive, in one channel, and counts agree", %{author: author, channel: channel} do
      message_fixture(channel, author, "Dragons are coming", 20)
      message_fixture(channel, author, "nothing to see", 10)
      message_fixture(channel_fixture(), author, "dragons elsewhere")

      assert [%{content: "Dragons are coming"}] = ChatChannels.search_messages(channel.id, "DRAGON")
      assert ChatChannels.count_messages_in_channel(channel.id) == 2
    end
  end

  describe "editing and deleting" do
    test "the author edits, and the edit is stamped and announced", %{author: author, channel: channel} do
      msg = message_fixture(channel, author, "before")
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")

      assert {:ok, updated} = ChatChannels.update_message_by_user(author, msg, %{content: "after"})
      assert updated.content == "after"
      assert updated.edited_at
      assert_receive {:message_updated, %{id: id}} when id == msg.id
    end

    test "another member can't edit; a moderator and staff can", %{author: author, channel: channel} do
      msg = message_fixture(channel, author, "mine")

      assert {:error, :forbidden} = ChatChannels.update_message_by_user(user(), msg, %{content: "x"})

      mod = user()
      member_fixture(channel, mod, "moderator")
      assert {:ok, _} = ChatChannels.update_message_by_user(mod, msg, %{content: "by mod"})
      assert {:ok, _} = ChatChannels.update_message_by_user(admin(), msg, %{content: "by admin"})
    end

    test "an author banned from the channel can't edit their old message", %{author: author, channel: channel} do
      msg = message_fixture(channel, author, "old")
      member_fixture(channel, author, "member", %{is_banned: true})
      assert {:error, :forbidden} = ChatChannels.update_message_by_user(author, msg, %{content: "new"})
    end

    test "the author deletes, and it is announced", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")

      assert {:ok, _} = ChatChannels.delete_message_by_user(author, msg)
      assert ChatChannels.get_message(msg.id) == nil
      assert_receive {:message_deleted, %{id: id}} when id == msg.id
    end

    test "a stranger can't delete; a moderator and staff can", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      assert {:error, :forbidden} = ChatChannels.delete_message_by_user(user(), msg)
      assert ChatChannels.get_message(msg.id)

      mod = user()
      member_fixture(channel, mod, "moderator")
      assert {:ok, _} = ChatChannels.delete_message_by_user(mod, msg)

      msg2 = message_fixture(channel, author)
      assert {:ok, _} = ChatChannels.delete_message_by_user(admin(), msg2)
    end

    test "deleting a message takes its reactions along", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      {:ok, _} = ChatChannels.add_reaction(msg, author, "🔥")
      assert {:ok, _} = ChatChannels.delete_message(msg)
      assert Repo.aggregate(ChatChannels.Reaction, :count) == 0
    end
  end

  describe "pins" do
    test "only a moderator pins, and pinning toggles", %{author: author, channel: channel} do
      msg = message_fixture(channel, author, "important")
      assert {:error, :forbidden} = ChatChannels.toggle_message_pin(author, msg)

      mod = user()
      member_fixture(channel, mod, "moderator")
      assert {:ok, %{is_pinned: true}} = ChatChannels.toggle_message_pin(mod, msg)
      assert [%{id: id}] = ChatChannels.list_pinned_messages(channel.id)
      assert id == msg.id

      assert {:ok, %{is_pinned: false}} = ChatChannels.toggle_message_pin(mod, ChatChannels.get_message!(msg.id))
      assert ChatChannels.list_pinned_messages(channel.id) == []
    end
  end

  describe "reactions" do
    test "toggling adds, then removes, and says which", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")

      assert {:ok, :added, _} = ChatChannels.toggle_reaction(msg, author, "👍")
      assert_receive {:reaction_added, _}
      assert ChatChannels.count_user_reactions(msg.id, author.id) == 1

      assert {:ok, :removed, _} = ChatChannels.toggle_reaction(msg, author, "👍")
      assert_receive {:reaction_removed, _}
      assert ChatChannels.count_user_reactions(msg.id, author.id) == 0
    end

    test "a user has at most five reactions on one message", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      assert ChatChannels.max_reactions_per_user() == 5

      for e <- ~w(a b c d e), do: assert({:ok, :added, _} = ChatChannels.toggle_reaction(msg, author, e))
      assert {:error, :limit_reached} = ChatChannels.toggle_reaction(msg, author, "f")
      assert {:error, :limit_reached} = ChatChannels.add_reaction(msg, author, "f")

      # one of the five can still be taken back
      assert {:ok, :removed, _} = ChatChannels.toggle_reaction(msg, author, "a")
    end

    test "different users can use the same emoji", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      assert {:ok, :added, _} = ChatChannels.toggle_reaction(msg, author, "👍")
      assert {:ok, :added, _} = ChatChannels.toggle_reaction(msg, user(), "👍")
    end

    test "add_reaction/3 twice keeps one", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      assert {:ok, first} = ChatChannels.add_reaction(msg, author, "🎉")
      assert {:ok, again} = ChatChannels.add_reaction(msg, author, "🎉")
      assert first.id == again.id
      assert ChatChannels.count_user_reactions(msg.id, author.id) == 1
    end

    test "remove_reaction/3 of one that isn't there says not found", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      assert {:error, :not_found} = ChatChannels.remove_reaction(msg, author, "👍")

      {:ok, _} = ChatChannels.add_reaction(msg, author, "👍")
      assert {:ok, _} = ChatChannels.remove_reaction(msg, author, "👍")
    end

    test "remove_all_user_reactions/2 clears only that user's", %{author: author, channel: channel} do
      msg = message_fixture(channel, author)
      other = user()
      for e <- ~w(a b), do: ChatChannels.add_reaction(msg, author, e)
      ChatChannels.add_reaction(msg, other, "a")

      assert :ok = ChatChannels.remove_all_user_reactions(msg, author)
      assert ChatChannels.count_user_reactions(msg.id, author.id) == 0
      assert ChatChannels.count_user_reactions(msg.id, other.id) == 1
    end
  end
end
