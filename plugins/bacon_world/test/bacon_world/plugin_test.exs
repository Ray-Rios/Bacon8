defmodule BaconWorld.PluginTest do
  # Not async: activation changes the node-wide active-plugin cache.
  use Bacon8.DataCase, async: false
  import Phoenix.ConnTest

  @endpoint Bacon8Web.Endpoint

  setup do
    Bacon8.Plugins.refresh_cache()
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  test "is discovered from plugins/bacon_world" do
    assert BaconWorld.Plugin in Bacon8.Plugins.installed()
    assert %{slug: "bacon_world", path: "/games/bacon_world"} = Bacon8.Plugins.game_info(BaconWorld.Plugin)
  end

  describe "old Web Lobby links (renamed 2026-10-21)" do
    test "the plugin names its previous slug" do
      assert BaconWorld.Plugin.previous_slugs() == ["web_lobby"]
    end

    test "/games/web_lobby redirects permanently, keeping the rest of the path and the query" do
      conn = build_conn() |> get("/games/web_lobby")
      assert conn.status == 301
      assert redirected_to(conn, 301) == "/games/bacon_world"

      conn = build_conn() |> get("/games/web_lobby/somewhere/deeper?ch=abc&x=1")
      assert redirected_to(conn, 301) == "/games/bacon_world/somewhere/deeper?ch=abc&x=1"
    end

    test "/admin/web_lobby redirects permanently too" do
      assert build_conn() |> get("/admin/web_lobby") |> redirected_to(301) == "/admin/bacon_world"
      assert build_conn() |> get("/admin/web_lobby/settings") |> redirected_to(301) == "/admin/bacon_world/settings"
    end

    test "only the old slug itself redirects, not a slug that merely starts with it" do
      assert build_conn() |> get("/games/web_lobby_extra") |> response(404)
    end

    test "redirects work while the plugin is inactive; the new page does the gating" do
      refute Bacon8.Plugins.active?("bacon_world")
      assert build_conn() |> get("/games/web_lobby") |> redirected_to(301) == "/games/bacon_world"
    end
  end

  test "its page answers 404 until activated, then asks visitors to sign in" do
    refute Bacon8.Plugins.active?("bacon_world")
    assert build_conn() |> get("/games/bacon_world") |> response(404)

    {:ok, _} = Bacon8.Plugins.activate("bacon_world")
    assert %{is_active: true} = Bacon8.Games.get_game_by_slug("bacon_world")

    conn = build_conn() |> get("/games/bacon_world")
    assert conn.status == 302
    assert [%{slug: "bacon_world"}] = Bacon8.Plugins.active_games()
  end
end
