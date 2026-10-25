defmodule ChatChannels.NoticesTest do
  # What chat tells the hub's notifications. @mentions never worked while this lived in
  # the core: it read `actor.username`, a field users don't have, inside a fire-and-forget
  # task, so every mention crashed quietly in the log.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures

  alias Bacon8.Notifications.UserNotification
  alias ChatChannels.Notices

  setup do
    settle_on_exit()
    %{channel: channel_fixture(), author: user()}
  end

  describe "extract_mentions/1" do
    test "finds each name once, with letters, digits, underscores and dashes" do
      assert Notices.extract_mentions("hi @ann, @bob_2 and @c-d, again @ann") == ["ann", "bob_2", "c-d"]
    end

    test "an @ inside a word is not a mention (email addresses)" do
      assert Notices.extract_mentions("write to bob@example.com or (@ann)") == ["ann"]
    end

    test "nothing to find in nothing" do
      assert Notices.extract_mentions("no names here") == []
      assert Notices.extract_mentions(nil) == []
    end
  end

  describe "mentions/2" do
    test "notifies the mentioned user, and says where to go", %{channel: channel, author: author} do
      bob = user()
      msg = message_fixture(channel, author, "hey @#{bob.name}, look at this")
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "user:#{bob.id}:notifications")

      assert {:ok, [n]} = Notices.mentions(msg, author)
      assert n.type == "mention"
      assert n.user_id == bob.id
      assert n.actor_id == author.id
      assert n.title == "#{author.name} mentioned you"
      assert n.source_kind == "chat_channel"
      assert n.source_id == channel.id
      assert n.resource_type == "message" and n.resource_id == msg.id

      stored = Repo.get!(UserNotification, n.id)
      assert stored.metadata["path"] == "/chat/#{channel.id}"
      assert stored.metadata["source_name"] == channel.name
      assert stored.content == "hey @#{bob.name}, look at this"

      assert_receive {:new_notification, %{id: id}} when id == n.id
    end

    test "names are matched without regard to case, and a user is told once", %{channel: channel, author: author} do
      bob = user()
      msg = message_fixture(channel, author, "@#{String.upcase(bob.name)} and again @#{bob.name}")
      assert {:ok, [_one]} = Notices.mentions(msg, author)
    end

    test "never the author, and nobody who doesn't exist", %{channel: channel, author: author} do
      msg = message_fixture(channel, author, "talking to myself @#{author.name} and @nobody-by-this-name")
      assert {:ok, []} = Notices.mentions(msg, author)
      assert Repo.aggregate(UserNotification, :count) == 0
    end

    test "a message without mentions costs nothing", %{channel: channel, author: author} do
      msg = message_fixture(channel, author, "just chatting")
      assert {:ok, []} = Notices.mentions(msg, author)
    end

    test "posting a message does it, in the background", %{channel: channel, author: author} do
      bob = user()
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "user:#{bob.id}:notifications")

      {:ok, _} = ChatChannels.create_message(author, channel.id, %{content: "psst @#{bob.name}"})

      assert_receive {:new_notification, %{type: "mention", user_id: uid}} when uid == bob.id, 2_000
    end
  end

  describe "invite/1" do
    setup do
      owner = user()
      {:ok, channel} = ChatChannels.create_user_channel(owner, %{"name" => "club-#{System.unique_integer([:positive])}", "description" => "Members only"})
      %{owner: owner, club: channel}
    end

    test "notifies the invitee, and says where to answer", %{owner: owner, club: club} do
      invitee = user()
      {:ok, invite} = ChatChannels.create_personal_invite(owner.id, invitee.email, club.id)
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "user:#{invitee.id}:notifications")

      assert {:ok, n} = Notices.invite(invite)
      assert n.type == "invite"
      assert n.user_id == invitee.id
      assert n.actor_id == owner.id
      assert n.title == "#{owner.name} invited you to ##{club.name}"
      assert n.content == "Members only"
      assert n.source_kind == "chat_channel" and n.source_id == club.id
      assert n.resource_type == "channel_invite" and n.resource_id == invite.id
      assert Repo.get!(UserNotification, n.id).metadata["path"] == "/chat"

      assert_receive {:new_notification, %{id: id}} when id == n.id
    end

    test "a code invite names nobody, so there is nobody to tell", %{owner: owner, club: club} do
      {:ok, invite} = ChatChannels.create_channel_invite(%{channel_id: club.id, inviter_id: owner.id})
      assert {:ok, nil} = Notices.invite(invite)
    end
  end
end
