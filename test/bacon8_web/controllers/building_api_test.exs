defmodule Bacon8Web.BuildingApiTest do
  # /api/games/:slug/build (2026-11-14): RaysSpaceSim's and Tears of Babylon's build mode through
  # the hub, as the player or as a game server acting for one.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Bacon8.LiveHelpers

  @endpoint Bacon8Web.Endpoint

  setup do
    Bacon8.Building.reset()

    for slug <- ["tears_of_babylon", "bacon_world"] do
      game = Bacon8.Games.get_game_by_slug(slug) || elem(Bacon8.Games.create_game(%{slug: slug, name: slug, is_active: true}), 1)
      if not game.is_active, do: game |> Bacon8.Games.Game.changeset(%{is_active: true}) |> Bacon8.GamesRepo.update!()
    end

    user = verified()
    {:ok, token, _} = Bacon8.Auth.Guardian.encode_and_sign(user)
    %{user: user, conn: build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)}
  end

  test "a player lists the catalogue, places, moves, damages and removes", %{conn: conn} do
    assert %{"catalogue" => cat} = json_response(get(conn, "/api/games/tears_of_babylon/build/catalogue"), 200)
    assert Enum.find(cat, &(&1["id"] == "P_Barrel"))["allowed"]

    assert %{"placement" => %{"id" => id}, "revision" => rev} =
             json_response(post(conn, "/api/games/tears_of_babylon/build/zones/valley", %{"asset" => "P_Barrel", "x" => 3, "y" => 0, "z" => 4}), 200)

    assert %{"unchanged" => true} = json_response(get(conn, "/api/games/tears_of_babylon/build/zones/valley?rev=#{rev}"), 200)
    assert %{"placements" => [%{"id" => ^id}]} = json_response(get(conn, "/api/games/tears_of_babylon/build/zones/valley"), 200)
    assert %{"placement" => %{"x" => 5.0}} = json_response(put(conn, "/api/games/tears_of_babylon/build/zones/valley/#{id}", %{"x" => 5}), 200)
    assert %{"placement" => %{"result" => "damaged", "hp" => 7}} = json_response(post(conn, "/api/games/tears_of_babylon/build/zones/valley/#{id}/damage", %{"amount" => 3}), 200)
    assert json_response(delete(conn, "/api/games/tears_of_babylon/build/zones/valley/#{id}?smash=true"), 200)
    assert %{"placements" => []} = json_response(get(conn, "/api/games/tears_of_babylon/build/zones/valley"), 200)
  end

  test "refused: what the role doesn't allow, Bacon World's zones, rule changes by non-admins, no auth", %{conn: conn} do
    assert %{"success" => false} = json_response(post(conn, "/api/games/tears_of_babylon/build/zones/valley", %{"asset" => "P_Waystone", "x" => 0, "z" => 0}), 422)
    assert json_response(post(conn, "/api/games/bacon_world/build/zones/lobby", %{"asset" => "P_Barrel", "x" => 0, "z" => 0}), 403)
    assert json_response(put(conn, "/api/games/tears_of_babylon/build/rules/P_Barrel", %{"min_role" => "gm"}), 422)
    assert json_response(get(build_conn(), "/api/games/tears_of_babylon/build/zones/valley"), 401)
  end
end
