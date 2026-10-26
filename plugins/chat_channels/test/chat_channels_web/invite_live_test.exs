defmodule ChatChannelsWeb.InviteLiveTest do
  # The page an invite link opens: /chat/invite/:code.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, _} = Bacon8.Plugins.activate("chat_channels")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    settle_on_exit()

    owner = user()
    {:ok, club} = ChatChannels.create_user_channel(owner, %{"name" => "club-#{System.unique_integer([:positive])}", "is_private" => "true"})
    {:ok, invite} = ChatChannels.create_channel_invite(%{channel_id: club.id, inviter_id: owner.id})
    %{owner: owner, club: club, invite: invite}
  end

  defp verified, do: user(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  defp signed_in(user), do: build_conn() |> Plug.Test.init_test_session(%{"user_id" => user.id})

  test "shows the channel and joins only when the button is pressed", %{club: club, invite: invite} do
    me = verified()
    {:ok, view, html} = live(signed_in(me), "/chat/invite/#{invite.code}")

    assert html =~ club.name
    refute ChatChannels.is_channel_member?(club.id, me.id)

    view |> element("#join-invite") |> render_click()
    assert_redirect(view, "/chat/#{club.id}")
    assert ChatChannels.is_channel_member?(club.id, me.id)
  end

  test "a member who opens it again is simply taken to the channel", %{club: club, invite: invite} do
    me = verified()
    member_fixture(club, me)
    {:ok, view, _} = live(signed_in(me), "/chat/invite/#{invite.code}")
    view |> element("#join-invite") |> render_click()
    assert_redirect(view, "/chat/#{club.id}")
  end

  test "a visitor is asked to sign in, and nothing is joined", %{club: club, invite: invite} do
    {:ok, _view, html} = live(build_conn(), "/chat/invite/#{invite.code}")
    assert html =~ club.name
    assert html =~ "Sign in"
    refute html =~ "join-invite"
  end

  test "a wrong, revoked or used-up code gives the same plain answer, and never names the channel", %{club: club, owner: owner, invite: invite} do
    me = verified()
    {:ok, _, wrong} = live(signed_in(me), "/chat/invite/nope")
    assert wrong =~ "can't be used"

    {:ok, _} = ChatChannels.revoke_channel_invite(owner, invite.id)
    {:ok, _, revoked} = live(signed_in(me), "/chat/invite/#{invite.code}")
    assert revoked =~ "can't be used"
    refute revoked =~ club.name

    {:ok, spent} = ChatChannels.create_channel_invite(%{channel_id: club.id, inviter_id: owner.id, max_uses: 1})
    spent |> Ecto.Changeset.change(uses: 1) |> Bacon8.Repo.update!()
    {:ok, _, used_up} = live(signed_in(me), "/chat/invite/#{spent.code}")
    assert used_up =~ "can't be used"
  end

  test "a personal invite is for that person only", %{club: club, owner: owner} do
    invitee = verified()
    {:ok, personal} = ChatChannels.create_personal_invite(owner.id, invitee.id, club.id)

    {:ok, _, other} = live(signed_in(verified()), "/chat/invite/#{personal.code}")
    assert other =~ "can't be used"

    {:ok, _, mine} = live(signed_in(invitee), "/chat/invite/#{personal.code}")
    assert mine =~ club.name
  end
end
