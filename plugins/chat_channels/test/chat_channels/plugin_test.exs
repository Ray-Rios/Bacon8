defmodule ChatChannels.PluginTest do
  # Chat Channels as a plugin: where it mounts, what the hub asks of it, and the seams the
  # forum's move out of the core cut (account removal, nav badge, the old /forum address).
  # Not async: activation changes the node-wide active-plugin cache.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures
  import Phoenix.ConnTest

  alias ChatChannels.{Message, Reaction}

  @endpoint Bacon8Web.Endpoint

  setup do
    Bacon8.Plugins.refresh_cache()
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    settle_on_exit()
    :ok
  end

  describe "the plugin" do
    test "is installed, mounts at /chat and needs nothing else" do
      assert ChatChannels.Plugin in Bacon8.Plugins.installed()
      assert Bacon8.Plugins.get("chat_channels") == ChatChannels.Plugin
      assert ChatChannels.Plugin.mount() == "chat"
      assert ChatChannels.Plugin.requires() == []
    end

    # Chat used to be part of the core, so it was always on. A site whose plugin list doesn't
    # name it would lose chat (and RaysSpaceSim, which requires it) on the next deploy.
    test "is on by default, in the default list and in production's" do
      assert File.read!("config/config.exs") =~ ~r/default_active_plugins, \[[^\]]*"chat_channels"/
      assert File.read!("k3s/overlays/prod/configmap.yaml") =~ ~r/BACON8_ACTIVE_PLUGINS: "[^"]*chat_channels/
    end

    test "the page and the old forum address answer only while it is active" do
      assert build_conn() |> get("/chat") |> response(404)
      assert build_conn() |> get("/forum") |> response(404)

      {:ok, _} = Bacon8.Plugins.activate("chat_channels")

      # a visitor who isn't signed in is sent to log in
      assert build_conn() |> get("/chat") |> redirected_to() =~ "login"
    end
  end

  describe "/forum, where this page used to live" do
    setup do
      {:ok, _} = Bacon8.Plugins.activate("chat_channels")
      :ok
    end

    test "answers 301 to /chat" do
      conn = build_conn() |> get("/forum")
      assert conn.status == 301
      assert redirected_to(conn, 301) == "/chat"
    end

    test "keeps the channel and the query string" do
      id = Ecto.UUID.generate()
      assert build_conn() |> get("/forum/#{id}") |> redirected_to(301) == "/chat/#{id}"
      assert build_conn() |> get("/forum/#{id}?message=abc&x=1") |> redirected_to(301) == "/chat/#{id}?message=abc&x=1"
      assert build_conn() |> get("/forum?channel=#{id}") |> redirected_to(301) == "/chat?channel=#{id}"
    end
  end

  describe "the navigation link" do
    test "is just \"Chat\", with no badge for a visitor or when nothing is pending" do
      assert [%{label: "Chat", path: "/chat"} = item] = ChatChannels.Plugin.nav_links(nil)
      refute Map.has_key?(item, :badge)

      assert [item] = ChatChannels.Plugin.nav_links(user())
      refute Map.has_key?(item, :badge)
    end

    test "counts the invitations waiting for the user" do
      owner = user()
      invitee = user()
      {:ok, one} = ChatChannels.create_user_channel(owner, %{"name" => "one-#{System.unique_integer([:positive])}"})
      {:ok, two} = ChatChannels.create_user_channel(owner, %{"name" => "two-#{System.unique_integer([:positive])}"})

      {:ok, invite} = ChatChannels.create_personal_invite(owner.id, invitee.email, one.id)
      assert [%{badge: 1}] = ChatChannels.Plugin.nav_links(invitee)

      {:ok, _} = ChatChannels.create_personal_invite(owner.id, invitee.email, two.id)
      assert [%{badge: 2}] = ChatChannels.Plugin.nav_links(invitee)

      {:ok, _} = ChatChannels.decline_invite(invite.id, invitee.id)
      assert [%{badge: 1}] = ChatChannels.Plugin.nav_links(invitee)
    end

    test "the hub shows it while chat is active, and not otherwise" do
      refute Enum.any?(Bacon8.Plugins.nav_links(user()), &(&1.label == "Chat"))
      {:ok, _} = Bacon8.Plugins.activate("chat_channels")
      assert Enum.any?(Bacon8.Plugins.nav_links(user()), &(&1.label == "Chat"))
    end

    test "the admin sidebar gets the custom emoji page" do
      assert [%{path: "/admin/chat_channels/custom-emojis"}] = ChatChannels.Plugin.admin_nav()
    end
  end

  describe "when a user is banned or deleted, what they wrote goes" do
    setup do
      %{gone: user(), stays: user(), channel: channel_fixture()}
    end

    defp write_something(channel, user) do
      msg = message_fixture(channel, user, "words")
      {:ok, _} = ChatChannels.add_reaction(msg, user, "👍")
      msg
    end

    test "the hub event removes that user's messages and reactions, and no one else's", %{gone: gone, stays: stays, channel: channel} do
      mine = write_something(channel, gone)
      theirs = write_something(channel, stays)
      {:ok, _} = ChatChannels.add_reaction(theirs, gone, "🎉")

      assert :ok = ChatChannels.Plugin.hub_event({:user_content_removed, gone.id})

      assert Repo.get(Message, mine.id) == nil
      assert Repo.get(Message, theirs.id)
      assert Repo.aggregate(from(r in Reaction, where: r.user_id == ^gone.id), :count) == 0
      assert Repo.aggregate(from(r in Reaction, where: r.user_id == ^stays.id), :count) == 1
    end

    test "events it doesn't know are ignored" do
      assert :ok = ChatChannels.Plugin.hub_event({:something_new, 1})
      assert :ok = ChatChannels.Plugin.hub_event({:channel_deleted, Ecto.UUID.generate()})
    end

    test "banning an account (the core's cleanup) reaches the plugin", %{gone: gone, stays: stays, channel: channel} do
      mine = write_something(channel, gone)
      theirs = write_something(channel, stays)

      assert :ok = Bacon8.Accounts.cleanup_banned_user(gone)

      assert Repo.get(Message, mine.id) == nil
      assert Repo.get(Message, theirs.id)
    end

    test "deleting an account does too", %{gone: gone, stays: stays, channel: channel} do
      mine = write_something(channel, gone)
      theirs = write_something(channel, stays)

      assert {:ok, _} = Bacon8.Accounts.delete_user(gone)

      assert Repo.get(Message, mine.id) == nil
      assert Repo.get(Message, theirs.id)
      assert Repo.get(Bacon8.Accounts.User, gone.id) == nil
    end
  end
end
