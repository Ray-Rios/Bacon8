defmodule WebLobby.PluginTest do
  # Not async: activation changes the node-wide active-plugin cache.
  use Bacon8.DataCase, async: false
  import Phoenix.ConnTest

  @endpoint Bacon8Web.Endpoint

  setup do
    Bacon8.Plugins.refresh_cache()
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  test "is discovered from plugins/web_lobby" do
    assert WebLobby.Plugin in Bacon8.Plugins.installed()
    assert %{slug: "web_lobby", path: "/games/web_lobby"} = Bacon8.Plugins.game_info(WebLobby.Plugin)
  end

  test "its page answers 404 until activated, then asks visitors to sign in" do
    refute Bacon8.Plugins.active?("web_lobby")
    assert build_conn() |> get("/games/web_lobby") |> response(404)

    {:ok, _} = Bacon8.Plugins.activate("web_lobby")
    assert %{is_active: true} = Bacon8.Games.get_game_by_slug("web_lobby")

    conn = build_conn() |> get("/games/web_lobby")
    assert conn.status == 302
    assert [%{slug: "web_lobby"}] = Bacon8.Plugins.active_games()
  end
end
