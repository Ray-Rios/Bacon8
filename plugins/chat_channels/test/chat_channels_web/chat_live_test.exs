defmodule ChatChannelsWeb.ChatLiveTest do
  # The Chat page at /chat. The page itself is large and is still being tidied (the plan's
  # phase 3); these pin what moving it must not change, plus the invitations list that came
  # over from the desktop's notification panel.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Ecto.Query

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, _} = Bacon8.Plugins.activate("chat_channels")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    settle_on_exit()
    :ok
  end

  defp verified(attrs \\ %{}), do: user(Map.merge(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)}, attrs))
  defp signed_in(user), do: build_conn() |> Plug.Test.init_test_session(%{"user_id" => user.id})

  test "a visitor is sent to log in" do
    assert {:error, {:redirect, %{to: to}}} = live(build_conn(), "/chat")
    assert to =~ "login"
  end

  test "a signed-in user lands in a channel, and the page calls itself Chat" do
    me = verified()
    general = channel_fixture(%{name: "general-#{System.unique_integer([:positive])}"})

    {:ok, view, html} = live(signed_in(me), "/chat")

    assert html =~ "Public Channels"
    assert html =~ general.name
    assert page_title(view) =~ "Chat - "
  end

  test "a channel's own address opens that channel" do
    me = verified()
    {:ok, _first} = ChatChannels.create_channel(%{name: "aaa-#{System.unique_integer([:positive])}"})
    target = channel_fixture(%{name: "zzz-#{System.unique_integer([:positive])}"})

    {:ok, _view, _html} = live(signed_in(me), "/chat/#{target.id}")

    # being in a channel is being on its presence list (the page tracks the open channel)
    assert Map.has_key?(Bacon8Web.Presence.list("presence:channel:#{target.id}"), to_string(me.id))
  end

  describe "sending a message" do
    defp messages_in(channel), do: Bacon8.Repo.all(from m in ChatChannels.Message, where: m.channel_id == ^channel.id, preload: [:attachments])

    test "with only an attachment and no text posts it, with a blank body" do
      me = verified()
      channel = channel_fixture(%{name: "files-#{System.unique_integer([:positive])}"})
      {:ok, view, _html} = live(signed_in(me), "/chat/#{channel.id}")

      file =
        file_input(view, "form[phx-submit=send_message]", :forum_attachment, [
          %{name: "notes.md", content: "# notes", type: "text/markdown"}
        ])

      render_upload(file, "notes.md")
      view |> form("form[phx-submit=send_message]", %{message: ""}) |> render_submit()

      assert [message] = messages_in(channel)
      assert message.content == ""
      assert [%{filename: "notes.md"}] = message.attachments
    end

    test "with no text and no attachment posts nothing" do
      me = verified()
      channel = channel_fixture(%{name: "empty-#{System.unique_integer([:positive])}"})
      {:ok, view, _html} = live(signed_in(me), "/chat/#{channel.id}")

      view |> form("form[phx-submit=send_message]", %{message: "   "}) |> render_submit()

      assert messages_in(channel) == []
    end

    test "text alone still posts" do
      me = verified()
      channel = channel_fixture(%{name: "text-#{System.unique_integer([:positive])}"})
      {:ok, view, _html} = live(signed_in(me), "/chat/#{channel.id}")

      view |> form("form[phx-submit=send_message]", %{message: "hello"}) |> render_submit()

      assert [%{content: "hello"}] = messages_in(channel)
    end
  end

  test "someone else's private channel is not listed" do
    me = verified()
    secret = channel_fixture(%{name: "secret-#{System.unique_integer([:positive])}", is_private: true})

    {:ok, _view, html} = live(signed_in(me), "/chat")
    refute html =~ secret.name
  end

  describe "invitations" do
    setup do
      owner = verified()
      {:ok, club} = ChatChannels.create_user_channel(owner, %{"name" => "club-#{System.unique_integer([:positive])}", "is_private" => "true"})
      invitee = verified()
      {:ok, invite} = ChatChannels.create_personal_invite(owner.id, invitee.email, club.id)
      %{owner: owner, club: club, invitee: invitee, invite: invite}
    end

    test "are listed above the channels, with who asked", %{owner: owner, club: club, invitee: invitee} do
      {:ok, _view, html} = live(signed_in(invitee), "/chat")

      assert html =~ "Invitations (1)"
      assert html =~ club.name
      assert html =~ (owner.name || owner.email)
    end

    test "nobody else sees them", %{owner: owner} do
      {:ok, _view, html} = live(signed_in(owner), "/chat")
      refute html =~ "Invitations ("
    end

    test "accepting joins the channel and shows it in the sidebar", %{club: club, invitee: invitee} do
      {:ok, view, _html} = live(signed_in(invitee), "/chat")

      html = view |> element("button[phx-click=accept_invite]") |> render_click()

      refute html =~ "Invitations ("
      assert html =~ club.name
      assert ChatChannels.is_channel_member?(club.id, invitee.id)
      assert ChatChannels.count_pending_invites(invitee.id) == 0
    end

    test "declining removes it and does not join", %{club: club, invitee: invitee} do
      {:ok, view, _html} = live(signed_in(invitee), "/chat")

      html = view |> element("button[phx-click=decline_invite]") |> render_click()

      refute html =~ "Invitations ("
      refute ChatChannels.is_channel_member?(club.id, invitee.id)
      assert ChatChannels.count_pending_invites(invitee.id) == 0
    end

    test "an invite that was withdrawn meanwhile can't be accepted", %{club: club, owner: owner, invitee: invitee, invite: invite} do
      {:ok, view, _html} = live(signed_in(invitee), "/chat")
      {:ok, _} = ChatChannels.revoke_channel_invite(owner, invite.id)

      html = view |> element("button[phx-click=accept_invite]") |> render_click()

      assert html =~ "accepted any more"
      refute ChatChannels.is_channel_member?(club.id, invitee.id)
    end
  end

  test "the invitations switch is the plugin's own setting" do
    me = verified()
    {:ok, view, html} = live(signed_in(me), "/chat")
    assert html =~ "Let people invite me to channels"
    assert ChatChannels.allow_invites?(me.id)

    view |> element("#allow-invites input") |> render_click()
    refute ChatChannels.allow_invites?(me.id)

    view |> element("#allow-invites input") |> render_click()
    assert ChatChannels.allow_invites?(me.id)
  end

  describe "the dialogs" do
    setup do
      owner = verified()
      {:ok, club} = ChatChannels.create_user_channel(owner, %{"name" => "club-#{System.unique_integer([:positive])}", "is_private" => "true"})
      friend = verified()
      member_fixture(club, friend)
      %{owner: owner, club: club, friend: friend}
    end

    test "the members dialog lists the members, for the owner", %{owner: owner, club: club, friend: friend} do
      {:ok, view, html} = live(signed_in(owner), "/chat/#{club.id}")
      refute html =~ friend.name

      html = render_hook(view, "open_members_modal", %{"channel_id" => club.id})
      assert html =~ friend.name
      assert html =~ owner.name

      html = render_hook(view, "hide_members_modal", %{})
      refute html =~ friend.name
    end

    test "the invite dialog offers a person and a code, and creating a code reports it", %{owner: owner, club: club} do
      {:ok, view, _} = live(signed_in(owner), "/chat/#{club.id}")

      html = render_hook(view, "show_invite_modal", %{})
      assert html =~ "Invite a specific user"
      assert html =~ "Create invite code"

      html = render_hook(view, "create_channel_invite", %{"max_uses" => "3", "expires_at" => ""})
      assert html =~ "Invite code: "
      assert %{max_uses: 3} = Bacon8.Repo.get_by!(ChatChannels.ChannelInvite, channel_id: club.id, max_uses: 3)

      html = render_hook(view, "hide_invite_modal", %{})
      refute html =~ "Create invite code"
    end

    test "the create-channel dialog opens and closes", %{owner: owner} do
      {:ok, view, _} = live(signed_in(owner), "/chat")

      assert render_hook(view, "show_create_user_channel", %{}) =~ "Create Private Channel"
      refute render_hook(view, "hide_create_channel", %{}) =~ "Create Private Channel"
    end
  end

  describe "streams" do
    setup do
      streamer = verified()
      channel = channel_fixture(%{name: "live-#{System.unique_integer([:positive])}", channel_type: "video"})
      %{streamer: streamer, channel: channel}
    end

    test "starting and ending a stream from the page", %{streamer: streamer, channel: channel} do
      {:ok, view, _} = live(signed_in(streamer), "/chat/#{channel.id}")

      render_hook(view, "start_stream", %{"type" => "video"})
      session = ChatChannels.get_active_stream(channel.id)
      assert session.streamer_id == streamer.id
      assert :sys.get_state(view.pid).socket.assigns.active_stream.id == session.id

      render_hook(view, "end_stream", %{"session_id" => session.id})
      assert ChatChannels.get_active_stream(channel.id) == nil
      assert :sys.get_state(view.pid).socket.assigns.active_stream == nil
    end

    test "a stream type the schema doesn't know is refused with a message", %{streamer: streamer, channel: channel} do
      {:ok, view, _} = live(signed_in(streamer), "/chat/#{channel.id}")
      assert render_hook(view, "start_stream", %{"type" => "smell"}) =~ "Failed to start stream"
      assert ChatChannels.get_active_stream(channel.id) == nil
    end
  end

  describe "the message box, replies and edits" do
    setup do
      me = verified()
      channel = channel_fixture(%{name: "talk-#{System.unique_integer([:positive])}"})
      member_fixture(channel, me)
      %{me: me, channel: channel}
    end

    test "the page shows the channel's header and message box", %{me: me, channel: channel} do
      {:ok, _view, html} = live(signed_in(me), "/chat/#{channel.id}")
      assert html =~ channel.name
      assert html =~ ~s(phx-submit="send_message")
      refute html =~ ~s(phx-submit="send_reply")
      refute html =~ ~s(phx-submit="apply_edit_message")
    end

    test "sending a message stores it and shows it", %{me: me, channel: channel} do
      {:ok, view, _} = live(signed_in(me), "/chat/#{channel.id}")

      render_hook(view, "send_message", %{"message" => "hello there"})
      assert Bacon8.Repo.get_by!(ChatChannels.Message, channel_id: channel.id, content: "hello there")
      assert render(view) =~ "hello there"
    end

    test "replying opens the reply box, and sending it stores a reply", %{me: me, channel: channel} do
      parent = message_fixture(channel, me, "the question")
      {:ok, view, _} = live(signed_in(me), "/chat/#{channel.id}")

      html = render_hook(view, "start_reply", %{"message_id" => parent.id})
      assert html =~ ~s(phx-submit="send_reply")

      render_hook(view, "send_reply", %{"content" => "the answer", "reply_to_id" => parent.id})
      assert %{reply_to_id: reply_to} = Bacon8.Repo.get_by!(ChatChannels.Message, channel_id: channel.id, content: "the answer")
      assert reply_to == parent.id

      html = render_hook(view, "cancel_reply", %{})
      refute html =~ ~s(phx-submit="send_reply")
    end

    test "editing opens the edit box, and applying it changes the message", %{me: me, channel: channel} do
      msg = message_fixture(channel, me, "typo")
      {:ok, view, _} = live(signed_in(me), "/chat/#{channel.id}")

      html = render_hook(view, "start_edit_message", %{"message_id" => msg.id})
      assert html =~ ~s(phx-submit="apply_edit_message")

      render_hook(view, "apply_edit_message", %{"message_id" => msg.id, "content" => "fixed"})
      assert ChatChannels.get_message(msg.id).content == "fixed"
      refute render(view) =~ ~s(phx-submit="apply_edit_message")
    end

    test "someone else's message can't be edited", %{me: me, channel: channel} do
      other = verified()
      member_fixture(channel, other)
      msg = message_fixture(channel, other, "mine, not yours")
      {:ok, view, _} = live(signed_in(me), "/chat/#{channel.id}")

      render_hook(view, "apply_edit_message", %{"message_id" => msg.id, "content" => "hacked"})
      assert ChatChannels.get_message(msg.id).content == "mine, not yours"
    end

    test "a full channel stays light: one reaction picker for the page, not one per message", %{me: me, channel: channel} do
      # (2026-10-28: each message and reply carried its own ~1,100-button picker; 25 messages made
      # an 8 MB first update and 31,000 elements, and froze phones for 15-20 s)
      for i <- 1..25 do
        m = message_fixture(channel, me, "message #{i}", 100 - i)
        message_fixture(channel, me, "reply to #{i}", 50 - i, %{reply_to_id: m.id})
      end

      {:ok, view, html} = live(signed_in(me), "/chat/#{channel.id}")
      assert html =~ "message 25"
      assert length(String.split(html, ~s(phx-hook="ReactionPicker"))) == 2
      # the whole page, 25 messages and their replies, in well under a megabyte
      assert byte_size(html) < 600_000

      # a reaction picked in the shared picker lands on the message named
      [m | _] = ChatChannels.list_messages(channel.id)
      render_hook(view, "toggle_reaction", %{"message_id" => m.id, "emoji" => "👍"})
      assert Enum.any?(ChatChannels.get_message(m.id) |> Bacon8.Repo.preload(:reactions) |> Map.get(:reactions), &(&1.emoji == "👍"))
    end

    test "pinned messages show above the list for everyone in the channel", %{me: me, channel: channel} do
      msg = message_fixture(channel, me, "read me first", 0, %{is_pinned: true})
      {:ok, _view, html} = live(signed_in(me), "/chat/#{channel.id}")
      assert html =~ "read me first"
      assert html =~ "Pinned"
      assert ChatChannels.get_message(msg.id).is_pinned
    end
  end
end
