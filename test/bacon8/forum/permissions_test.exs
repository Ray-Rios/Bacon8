defmodule Bacon8.Forum.PermissionsTest do
  # Who may post, moderate, manage and invite, and how membership changes reach
  # the rest of the system (PubSub, plugin hooks). These rules decide what a
  # chat_channels plugin has to keep, so they are pinned before it exists.
  use Bacon8.DataCase, async: false

  import Bacon8.ForumFixtures

  alias Bacon8.Forum

  setup do
    settle_on_exit()
    owner = user()
    channel = channel_fixture(%{owner_id: owner.id})
    private = channel_fixture(%{owner_id: owner.id, is_private: true})
    %{owner: owner, channel: channel, private: private}
  end

  describe "can_post_in_channel?/2" do
    test "anyone may post in a public channel, an anonymous visitor included", %{channel: channel} do
      assert Forum.can_post_in_channel?(user(), channel)
      assert Forum.can_post_in_channel?(nil, channel)
    end

    test "a private channel needs membership; an anonymous visitor never gets in", %{private: private} do
      member = user()
      member_fixture(private, member)

      assert Forum.can_post_in_channel?(member, private)
      refute Forum.can_post_in_channel?(user(), private)
      refute Forum.can_post_in_channel?(nil, private)
    end

    test "a site ban stops posting everywhere, even for a member", %{channel: channel, private: private} do
      banned = user(%{role: "banned"})
      member_fixture(private, banned)

      refute Forum.can_post_in_channel?(banned, channel)
      refute Forum.can_post_in_channel?(banned, private)
    end

    test "a ban from one channel stops posting there, public or private", %{channel: channel, private: private} do
      u = user()
      member_fixture(channel, u, "member", %{is_banned: true})
      member_fixture(private, u, "member", %{is_banned: true})

      refute Forum.can_post_in_channel?(u, channel)
      refute Forum.can_post_in_channel?(u, private)
      assert Forum.can_post_in_channel?(user(), channel)
    end

    test "staff may post in a private channel they aren't in", %{private: private} do
      for role <- ~w(admin gm editor), do: assert(Forum.can_post_in_channel?(user(%{role: role}), private))
      assert Forum.can_post_in_channel?(user(%{is_admin: true}), private)
    end
  end

  describe "can_moderate_channel?/2 and can_manage_channel?/2" do
    test "the owner, by channel row or by member role, does both", %{owner: owner, channel: channel} do
      assert Forum.can_moderate_channel?(owner, channel)
      assert Forum.can_manage_channel?(owner, channel)

      other = user()
      member_fixture(channel, other, "owner")
      assert Forum.can_moderate_channel?(other, channel)
      assert Forum.can_manage_channel?(other, channel)
    end

    test "a moderator moderates but doesn't manage", %{channel: channel} do
      mod = user()
      member_fixture(channel, mod, "moderator")
      assert Forum.can_moderate_channel?(mod, channel)
      refute Forum.can_manage_channel?(mod, channel)
    end

    test "a plain member does neither; neither does a visitor", %{channel: channel} do
      m = user()
      member_fixture(channel, m)
      refute Forum.can_moderate_channel?(m, channel)
      refute Forum.can_manage_channel?(m, channel)
      refute Forum.can_moderate_channel?(nil, channel)
      refute Forum.can_manage_channel?(nil, channel)
    end

    test "site staff do both everywhere", %{channel: channel} do
      for role <- ~w(admin gm editor) do
        s = user(%{role: role})
        assert Forum.can_moderate_channel?(s, channel)
        assert Forum.can_manage_channel?(s, channel)
      end
    end
  end

  describe "can_invite_to_channel?/2" do
    test "owners and moderators always may", %{channel: channel, private: private} do
      for ch <- [channel, private], role <- ~w(owner moderator) do
        u = user()
        member_fixture(ch, u, role)
        assert Forum.can_invite_to_channel?(u, ch)
      end
    end

    test "a member may invite to a public channel but not a non-public one", %{channel: channel} do
      m = user()
      member_fixture(channel, m)
      assert Forum.can_invite_to_channel?(m, channel)

      {:ok, closed} = Forum.create_channel(%{name: "closed-#{System.unique_integer([:positive])}", is_public: false})
      m2 = user()
      member_fixture(closed, m2)
      refute Forum.can_invite_to_channel?(m2, closed)
    end

    test "a banned member, a non-member and a visitor may not", %{channel: channel} do
      banned = user()
      member_fixture(channel, banned, "owner", %{is_banned: true})
      refute Forum.can_invite_to_channel?(banned, channel)
      refute Forum.can_invite_to_channel?(user(), channel)
      refute Forum.can_invite_to_channel?(nil, channel)
    end

    test "staff always may", %{channel: channel} do
      assert Forum.can_invite_to_channel?(admin(), channel)
    end
  end

  describe "membership" do
    test "one row per user per channel", %{channel: channel} do
      u = user()
      member_fixture(channel, u)
      assert {:error, cs} = Forum.create_channel_member(%{channel_id: channel.id, user_id: u.id})
      assert errors_on(cs) != %{}
      assert Forum.is_channel_member?(channel.id, u.id)
      refute Forum.is_channel_member?(channel.id, user().id)
    end

    test "only owner, moderator, member and banned are roles", %{channel: channel} do
      assert {:error, cs} = Forum.create_channel_member(%{channel_id: channel.id, user_id: user().id, role: "admin"})
      assert %{role: [_]} = errors_on(cs)
    end

    test "joining stamps joined_at", %{channel: channel} do
      assert %{joined_at: %DateTime{}} = member_fixture(channel, user())
    end

    test "user_role_in_channel/2 is nil for a stranger", %{channel: channel} do
      assert Forum.user_role_in_channel(channel.id, user().id) == nil
    end

    test "a ban announces itself and tells the plugins", %{channel: channel} do
      u = user()
      member = member_fixture(channel, u)
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")

      assert {:ok, %{is_banned: true}} = Forum.update_channel_member(member, %{is_banned: true})
      assert_receive {:user_banned, uid, cid} when uid == u.id and cid == channel.id
    end

    test "setting the role to banned counts as a ban too", %{channel: channel} do
      u = user()
      member = member_fixture(channel, u)
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")

      assert {:ok, _} = Forum.update_channel_member(member, %{role: "banned"})
      assert_receive {:user_banned, uid, _} when uid == u.id
    end

    test "removing a member announces the kick; removing twice says not found", %{channel: channel} do
      u = user()
      member_fixture(channel, u)
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")

      assert {:ok, _} = Forum.remove_channel_member(channel.id, u.id)
      assert_receive {:user_kicked, uid, cid} when uid == u.id and cid == channel.id
      assert {:error, :not_found} = Forum.remove_channel_member(channel.id, u.id)
      refute Forum.is_channel_member?(channel.id, u.id)
    end

    test "the member list has the owner even without a member row, in order", %{owner: owner, channel: channel} do
      m = user()
      member_fixture(channel, m)

      members = Forum.list_channel_members(channel.id)
      assert Enum.any?(members, &(&1.user_id == owner.id and &1.role == "owner"))
      assert Enum.any?(members, &(&1.user_id == m.id and &1.role == "member"))
    end

    test "the member list shows pending personal invites as invited", %{owner: owner, channel: channel} do
      invitee = user()
      {:ok, invite} = Forum.create_personal_invite(owner.id, invitee.email, channel.id)

      invited = Enum.find(Forum.list_channel_members(channel.id), &(&1.role == "invited"))
      assert invited.user_id == invitee.id
      assert invited._invite_id == invite.id
    end

    test "mark_channel_messages_read/3 needs a membership", %{channel: channel} do
      u = user()
      msg = message_fixture(channel, u)

      assert {:error, :not_member} = Forum.mark_channel_messages_read(u.id, channel.id, msg.id)

      member_fixture(channel, u)
      assert {:ok, member} = Forum.mark_channel_messages_read(u.id, channel.id, msg.id)
      assert member.last_read_message_id == msg.id
      assert member.last_seen_at
    end
  end
end
