defmodule ChatChannels.InvitesTest do
  # Invite codes and personal invites: who can use one, when it stops working,
  # and who may revoke it. Pinned before the forum becomes the chat_channels
  # plugin.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures

  alias ChatChannels.ChannelInvite

  setup do
    settle_on_exit()
    owner = user()
    {:ok, channel} = ChatChannels.create_user_channel(owner, %{"name" => "inv-#{System.unique_integer([:positive])}"})
    %{owner: owner, channel: channel}
  end

  defp code_invite(channel, owner, attrs \\ %{}) do
    {:ok, invite} = ChatChannels.create_channel_invite(Map.merge(%{channel_id: channel.id, inviter_id: owner.id}, attrs))
    invite
  end

  describe "ChannelInvite.is_valid?/1" do
    test "a fresh invite is valid" do
      assert ChannelInvite.is_valid?(%ChannelInvite{})
    end

    test "revoked, expired and used-up invites are not" do
      refute ChannelInvite.is_valid?(%ChannelInvite{is_revoked: true})
      refute ChannelInvite.is_valid?(%ChannelInvite{revoked_at: past(5)})
      refute ChannelInvite.is_valid?(%ChannelInvite{expires_at: past(5)})
      assert ChannelInvite.is_valid?(%ChannelInvite{expires_at: future(60)})
      refute ChannelInvite.is_valid?(%ChannelInvite{max_uses: 2, uses: 2})
      assert ChannelInvite.is_valid?(%ChannelInvite{max_uses: 2, uses: 1})
    end
  end

  describe "create_channel_invite/1" do
    test "makes a ten-character code and loads the channel and inviter", %{owner: owner, channel: channel} do
      invite = code_invite(channel, owner)
      assert byte_size(invite.code) == 10
      assert invite.channel.id == channel.id
      assert invite.inviter.id == owner.id
      assert invite.uses == 0
    end

    test "codes are unique, and one is needed along with the channel and inviter", %{owner: owner, channel: channel} do
      a = code_invite(channel, owner)
      assert {:error, cs} = ChatChannels.create_channel_invite(%{channel_id: channel.id, inviter_id: owner.id, code: a.code})
      assert errors_on(cs) != %{}

      assert {:error, cs} = ChatChannels.create_channel_invite(%{})
      assert %{channel_id: _, inviter_id: _} = errors_on(cs)
    end

    test "get_invite_link/1 points at /chat/invite" do
      assert ChatChannels.get_invite_link("abc") == "/chat/invite/abc"
    end
  end

  describe "use_channel_invite/2" do
    test "joins the user as a member and counts the use", %{owner: owner, channel: channel} do
      invite = code_invite(channel, owner)
      joiner = user()

      assert {:ok, member} = ChatChannels.use_channel_invite(invite.code, joiner.id)
      assert member.role == "member"
      assert ChatChannels.is_channel_member?(channel.id, joiner.id)
      assert ChatChannels.get_invite_by_code(invite.code).uses == 1
    end

    test "an unknown code is invalid", %{owner: _} do
      assert {:error, :invalid_invite} = ChatChannels.use_channel_invite("nope", user().id)
    end

    test "a user already in the channel can't use it again", %{owner: owner, channel: channel} do
      invite = code_invite(channel, owner)
      assert {:error, :already_member} = ChatChannels.use_channel_invite(invite.code, owner.id)
    end

    test "a revoked invite is refused", %{owner: owner, channel: channel} do
      invite = code_invite(channel, owner)
      {:ok, _} = ChatChannels.revoke_channel_invite(owner, invite.id)
      assert {:error, :invite_revoked} = ChatChannels.use_channel_invite(invite.code, user().id)
    end

    test "an expired one is refused", %{owner: owner, channel: channel} do
      invite = code_invite(channel, owner, %{expires_at: past(60)})
      assert {:error, :invite_expired} = ChatChannels.use_channel_invite(invite.code, user().id)
    end

    test "max_uses is enforced", %{owner: owner, channel: channel} do
      invite = code_invite(channel, owner, %{max_uses: 1})
      assert {:ok, _} = ChatChannels.use_channel_invite(invite.code, user().id)
      assert {:error, :invite_expired} = ChatChannels.use_channel_invite(invite.code, user().id)
    end

    test "a personal invite works only for the person it names", %{owner: owner, channel: channel} do
      invitee = user()
      {:ok, invite} = ChatChannels.create_personal_invite(owner.id, invitee.email, channel.id)

      assert {:error, :invite_not_for_user} = ChatChannels.use_channel_invite(invite.code, user().id)
      assert {:ok, _} = ChatChannels.use_channel_invite(invite.code, invitee.id)
      assert ChatChannels.get_invite_by_code(invite.code).accepted_at
    end
  end

  describe "create_personal_invite/4" do
    test "finds the person by email or by user name", %{owner: owner, channel: channel} do
      by_email = user()
      by_name = user()

      assert {:ok, %{invitee_id: id1}} = ChatChannels.create_personal_invite(owner.id, by_email.email, channel.id)
      assert id1 == by_email.id
      assert {:ok, %{invitee_id: id2}} = ChatChannels.create_personal_invite(owner.id, by_name.name, channel.id)
      assert id2 == by_name.id
    end

    test "or by their id", %{owner: owner, channel: channel} do
      invitee = user()
      assert {:ok, %{invitee_id: id}} = ChatChannels.create_personal_invite(owner.id, invitee.id, channel.id)
      assert id == invitee.id
    end

    test "says so when nobody matches", %{owner: owner, channel: channel} do
      assert {:error, :invitee_not_found} = ChatChannels.create_personal_invite(owner.id, "no-such-person", channel.id)
      assert {:error, :invitee_not_found} = ChatChannels.create_personal_invite(owner.id, nil, channel.id)
    end

    test "won't invite someone already in the channel, or invite them twice", %{owner: owner, channel: channel} do
      member = user()
      member_fixture(channel, member)
      assert {:error, :already_member} = ChatChannels.create_personal_invite(owner.id, member.email, channel.id)

      other = user()
      assert {:ok, _} = ChatChannels.create_personal_invite(owner.id, other.email, channel.id)
      assert {:error, :invite_already_pending} = ChatChannels.create_personal_invite(owner.id, other.email, channel.id)
    end

    test "a pending invite shows for the invitee, then goes once declined", %{owner: owner, channel: channel} do
      invitee = user()
      {:ok, invite} = ChatChannels.create_personal_invite(owner.id, invitee.email, channel.id)

      assert ChatChannels.count_pending_invites(invitee.id) == 1
      assert [%{id: id}] = ChatChannels.list_pending_invites_for_user(invitee.id)
      assert id == invite.id

      assert {:error, :forbidden} = ChatChannels.decline_invite(invite.id, user().id)
      assert {:ok, _} = ChatChannels.decline_invite(invite.id, invitee.id)
      assert ChatChannels.count_pending_invites(invitee.id) == 0
    end

    test "can_send_invite?/1 allows ten an hour", %{owner: owner, channel: channel} do
      assert ChatChannels.can_send_invite?(owner.id)
      for _ <- 1..10, do: code_invite(channel, owner)
      refute ChatChannels.can_send_invite?(owner.id)
    end
  end

  describe "accept_channel_invite/2" do
    test "joins the invitee and stamps the invite", %{owner: owner, channel: channel} do
      invitee = user()
      {:ok, invite} = ChatChannels.create_personal_invite(owner.id, invitee.email, channel.id)

      assert {:ok, %{role: "member"}} = ChatChannels.accept_channel_invite(invite.id, invitee.id)
      assert ChatChannels.is_channel_member?(channel.id, invitee.id)
      assert Repo.get(ChannelInvite, invite.id).accepted_at
      assert ChatChannels.count_pending_invites(invitee.id) == 0
    end

    test "not for someone else, not once revoked, not for an unknown id", %{owner: owner, channel: channel} do
      invitee = user()
      {:ok, invite} = ChatChannels.create_personal_invite(owner.id, invitee.email, channel.id)

      assert {:error, :forbidden} = ChatChannels.accept_channel_invite(invite.id, user().id)
      assert {:error, :not_found} = ChatChannels.accept_channel_invite(Ecto.UUID.generate(), invitee.id)

      {:ok, _} = ChatChannels.revoke_channel_invite(owner, invite.id)
      assert {:error, :forbidden} = ChatChannels.accept_channel_invite(invite.id, invitee.id)
    end
  end

  describe "revoke_channel_invite/2" do
    test "the inviter, the channel owner and staff may; others may not", %{owner: owner, channel: channel} do
      inviter = user()
      member_fixture(channel, inviter, "moderator")

      for revoker <- [inviter, owner, admin()] do
        invite = code_invite(channel, inviter)
        assert {:ok, %{is_revoked: true, revoked_at: %DateTime{}}} = ChatChannels.revoke_channel_invite(revoker, invite.id)
      end

      invite = code_invite(channel, inviter)
      assert {:error, :forbidden} = ChatChannels.revoke_channel_invite(user(), invite.id)
      assert {:error, :not_found} = ChatChannels.revoke_channel_invite(owner, Ecto.UUID.generate())
    end
  end
end
