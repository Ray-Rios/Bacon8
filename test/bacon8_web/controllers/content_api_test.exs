defmodule Bacon8Web.ContentApiTest do
  # /api/games/:slug/content (2026-11-15): a game's definitions through the hub. Anyone signed in
  # reads; admins and GMs change; loot is rolled for a game's server or for staff, never for a
  # player's own client.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Bacon8.LiveHelpers

  alias Bacon8.GameContent

  @endpoint Bacon8Web.Endpoint
  @base "/api/games/tears_of_babylon/content"

  setup do
    GameContent.reset()
    on_exit(&GameContent.reset/0)

    for slug <- ["tears_of_babylon", "bacon_world"] do
      game = Bacon8.Games.get_game_by_slug(slug) || elem(Bacon8.Games.create_game(%{slug: slug, name: slug, is_active: true}), 1)
      if not game.is_active, do: game |> Bacon8.Games.Game.changeset(%{is_active: true}) |> Bacon8.GamesRepo.update!()
    end

    %{player: as(verified()), gm: as(person("gm")), editor: as(person("editor"))}
  end

  defp as(user) do
    {:ok, token, _} = Bacon8.Auth.Guardian.encode_and_sign(user)
    build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
  end

  test "a GM saves a camp; every player reads it, by kind, by zone and by revision", %{player: player, gm: gm} do
    assert %{"definition" => %{"id" => "outskirts_01:Camp1"}, "revision" => rev} =
             json_response(put(gm, @base <> "/camp/outskirts_01:Camp1", %{"data" => %{"zone" => "outskirts_01", "slots" => 4}}), 200)

    json_response(put(gm, @base <> "/camp/outskirts_02:Camp1", %{"data" => %{"zone" => "outskirts_02", "slots" => 2}}), 200)

    assert %{"kinds" => [%{"kind" => "camp", "count" => 2}], "read_only" => false} = json_response(get(player, @base), 200)
    assert %{"definitions" => [_, _], "revision" => rev2} = json_response(get(player, @base <> "/camp"), 200)
    assert rev2 != rev
    assert %{"definitions" => [%{"id" => "outskirts_01:Camp1", "data" => %{"slots" => 4}}]} = json_response(get(player, @base <> "/camp?zone=outskirts_01"), 200)
    assert %{"unchanged" => true} = json_response(get(player, @base <> "/camp?rev=#{rev2}"), 200)
    assert %{"definition" => %{"data" => %{"slots" => 2}}} = json_response(get(player, @base <> "/camp/outskirts_02:Camp1"), 200)
    assert json_response(get(player, @base <> "/camp/nobody"), 404)
    assert %{"definitions" => [], "revision" => 0} = json_response(get(player, @base <> "/monster"), 200)
  end

  test "players and editors change nothing; nobody signed out gets in", %{player: player, editor: editor, gm: gm} do
    for conn <- [player, editor] do
      assert json_response(put(conn, @base <> "/camp/a", %{"data" => %{}}), 403)
      assert json_response(delete(conn, @base <> "/camp/a"), 403)
      assert json_response(get(conn, @base <> "/history"), 403)
      assert json_response(post(conn, @base <> "/loot_table/x/roll", %{}), 403)
    end

    assert get(build_conn(), @base <> "/camp").status == 401
    assert json_response(put(gm, @base <> "/camp/a", %{"data" => "not an object"}), 422)
    assert json_response(get(player, "/api/games/no_such_game/content"), 404)
    assert GameContent.list("tears_of_babylon", "camp") == []
  end

  test "Bacon World's definitions are read here and not written", %{gm: gm} do
    assert %{"read_only" => true} = json_response(get(gm, "/api/games/bacon_world/content"), 200)
    assert json_response(put(gm, "/api/games/bacon_world/content/monster/goblin", %{"data" => %{}}), 422)["message"] =~ "Studio"
  end

  test "history lists the changes and undo puts one back", %{gm: gm} do
    json_response(put(gm, @base <> "/zone/outskirts_01", %{"data" => %{"name" => "The RoT"}}), 200)
    json_response(put(gm, @base <> "/zone/outskirts_01", %{"data" => %{"name" => "Wrong"}}), 200)
    assert %{"history" => [%{"id" => change, "action" => "update", "before" => %{"name" => "The RoT"}}, %{"action" => "create"}]} =
             json_response(get(gm, @base <> "/history?kind=zone"), 200)

    assert json_response(post(gm, @base <> "/history/#{change}/undo"), 200)
    assert GameContent.get("tears_of_babylon", "zone", "outskirts_01") == %{"name" => "The RoT"}
    assert json_response(post(gm, @base <> "/history/999999999/undo"), 422)
    assert json_response(delete(gm, @base <> "/zone/outskirts_01"), 200)
    assert GameContent.get("tears_of_babylon", "zone", "outskirts_01") == nil
  end

  test "a GM tries a loot table; a game server rolls it for real", %{gm: gm} do
    json_response(put(gm, @base <> "/loot_table/pelts", %{"data" => %{"always" => [%{"item" => "pelt", "qty" => 2}], "coins" => 1}}), 200)
    assert %{"rolls" => [%{"items" => [%{"item_id" => "pelt", "quantity" => 2}], "coins" => 7}]} =
             json_response(post(gm, @base <> "/loot_table/pelts/roll", %{"level" => 7}), 200)

    assert %{"rolls" => rolls} = json_response(post(gm, @base <> "/loot_table/pelts/roll", %{"level" => 1, "times" => 500}), 200)
    assert length(rolls) == 100
    assert json_response(post(gm, @base <> "/loot_table/nothing/roll", %{}), 404)

    key = "content-test-key"
    old = Application.get_env(:bacon8, :games_server_api_key)
    Application.put_env(:bacon8, :games_server_api_key, key)
    on_exit(fn -> Application.put_env(:bacon8, :games_server_api_key, old) end)
    server = build_conn() |> Plug.Conn.put_req_header("x-api-key", key)
    assert %{"rolls" => [%{"coins" => 3}]} = json_response(post(server, @base <> "/loot_table/pelts/roll", %{"level" => 3}), 200)
    # a server reads; to change anything it must say which staff member it acts for
    assert %{"definitions" => [_]} = json_response(get(server, @base <> "/loot_table"), 200)
    assert json_response(put(server, @base <> "/camp/a", %{"data" => %{}}), 400)
  end
end
