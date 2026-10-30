defmodule Bacon8.GameStatusTest do
  # The front page's status corner (2026-10-29): what Bacon8.GameStatus reports for each active
  # game, from a plugin's own game_stats/0 (Bacon World) or the hub's server heartbeats
  # (RaysSpaceSim), and the page that shows it.
  use Bacon8.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Bacon8.{GameStatus, Games}

  @endpoint Bacon8Web.Endpoint

  setup do
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  defp server!(game, attrs) do
    {:ok, s} =
      Games.register_server(
        Map.merge(%{"game_id" => game.id, "host" => "10.0.0.1", "port" => 7777, "name" => "Sol", "status" => "online", "current_players" => 0}, attrs)
      )

    s
  end

  test "a game that runs in the hub reports its zones and who is in them" do
    {:ok, _} = Bacon8.Plugins.activate("bacon_world")
    assert [%{slug: "bacon_world"} = bw] = GameStatus.snapshot(fresh: true)
    assert bw.name == "Bacon World"
    assert bw.href == "/games/bacon_world"
    assert is_list(bw.zones) and Enum.all?(bw.zones, &(is_binary(&1.name) and is_integer(&1.players)))
    assert bw.current_players == Enum.sum(Enum.map(bw.zones, & &1.players))
    assert is_integer(bw.total_players)
    assert bw.image == nil or String.starts_with?(bw.image, "/")
  end

  test "a downloaded game is online while a world server's heartbeat is fresh; dev shards don't count" do
    {:ok, _} = Bacon8.Plugins.activate("chat_channels")
    {:ok, _} = Bacon8.Plugins.activate("rays_space_sim")
    {:ok, game} = Bacon8.Plugins.ensure_game("rays_space_sim")

    rss = fn -> Enum.find(GameStatus.snapshot(fresh: true), &(&1.slug == "rays_space_sim")) end
    assert %{online: false, current_players: 0, zones: [%{name: "World server", online: false}]} = rss.()

    server!(game, %{"current_players" => 3})
    server!(game, %{"port" => 7778, "name" => "Ray's editor", "current_players" => 1, "metadata" => %{"dev" => true}})

    status = rss.()
    assert status.online
    assert status.current_players == 3, "the world server, not the dev shard"
    assert [%{name: "Sol", online: true, players: 3}] = status.zones
    assert status.href == "/pages/rays-space-sim"

    # total players: accounts with a character
    for user <- [user_fixture(), user_fixture()] do
      {:ok, _} = Games.create_character(%{game_id: game.id, user_id: user.id, name: "Pilot #{System.unique_integer([:positive])}"})
    end

    assert rss.().total_players == 2
  end

  test "the snapshot is cached between refreshes" do
    {:ok, _} = Bacon8.Plugins.activate("bacon_world")
    assert [_] = GameStatus.snapshot(fresh: true)
    {:ok, _} = Bacon8.Plugins.activate("chat_channels")
    {:ok, _} = Bacon8.Plugins.activate("rays_space_sim")
    assert [_] = GameStatus.snapshot(), "still the cached one"
    assert [_, _] = GameStatus.snapshot(fresh: true)
  end

  test "the front page shows the corner to visitors" do
    {:ok, _} = Bacon8.Plugins.activate("bacon_world")
    GameStatus.snapshot(fresh: true)
    {:ok, _view, html} = live(build_conn(), "/")
    assert html =~ ~s(id="game-ticker") and html =~ "Bacon World" and html =~ "playing now"
  end
end
