defmodule Bacon8Web.GamesEntitlementsApiTest do
  # /api/games/:slug/entitlements (2026-10-29): a game client or server asks what the player owns
  # in that game (store items, mounts), the items and passes the front page promises.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Bacon8.LiveHelpers

  alias Bacon8.Entitlements

  @endpoint Bacon8Web.Endpoint

  setup do
    game = Bacon8.Games.get_game_by_slug("bacon_world") || elem(Bacon8.Games.create_game(%{slug: "bacon_world", name: "Bacon World", is_active: true}), 1)
    if not game.is_active, do: game |> Bacon8.Games.Game.changeset(%{is_active: true}) |> Bacon8.GamesRepo.update!()
    user = verified()
    {:ok, token, _} = Bacon8.Auth.Guardian.encode_and_sign(user)
    %{user: user, conn: build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)}
  end

  defp grant(user, kind, key, extra \\ %{}),
    do: {:ok, _} = Entitlements.grant(user, Map.merge(%{kind: kind, key: key, source_type: "test", source_id: Ecto.UUID.generate()}, extra))

  test "lists the player's items in this game only, and checks one", %{user: user, conn: conn} do
    grant(user, "bacon_world_mount", "ember_drake")
    grant(user, "rays_space_sim_ship", "corvette")
    grant(user, "store_download", Ecto.UUID.generate())
    grant(user, "bacon_world_mount", "frost_drake", %{ends_at: DateTime.add(DateTime.utc_now(), -60)})

    assert %{"success" => true, "entitlements" => items} = json_response(get(conn, "/api/games/bacon_world/entitlements"), 200)
    assert Enum.map(items, &{&1["kind"], &1["key"]}) == [{"bacon_world_mount", "ember_drake"}], "another game's, the store's and an ended one aren't listed"

    assert %{"active" => true} = json_response(get(conn, "/api/games/bacon_world/entitlements/check?kind=bacon_world_mount&key=ember_drake"), 200)
    assert %{"active" => false} = json_response(get(conn, "/api/games/bacon_world/entitlements/check?kind=bacon_world_mount&key=frost_drake"), 200)
    assert json_response(get(conn, "/api/games/bacon_world/entitlements/check"), 400)
  end

  test "needs a player token or the server key", %{} do
    assert json_response(get(build_conn(), "/api/games/bacon_world/entitlements"), 401)
  end
end
