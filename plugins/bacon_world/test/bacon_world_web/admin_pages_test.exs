defmodule BaconWorldWeb.AdminPagesTest do
  # Every Bacon World admin page opens for an admin (2026-11-02: World crashed on load, an upload
  # accept list LiveView refused, and Database answered 400, a query given {:ok, id}; neither had a
  # test that opened the page).
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, _} = Bacon8.Plugins.activate("bacon_world")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    %{conn: signed_in(person("admin"))}
  end

  for path <- ~w(/admin/bacon_world /admin/bacon_world/skills /admin/bacon_world/tuning /admin/bacon_world/world /admin/bacon_world/database) do
    test "#{path} opens", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, unquote(path))
    end
  end

  test "every database tab opens", %{conn: conn} do
    for tab <- ~w(players objects npcs monsters items monster_types merchants) do
      assert {:ok, _view, _html} = live(conn, "/admin/bacon_world/database?tab=#{tab}")
    end
  end

  test "the tuning page shows its settings", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/bacon_world/tuning")
    assert html =~ "tuning[melee_crit_chance]"
    assert html =~ "tuning[xp_mult]"
  end

  test "the sidebar lists Bacon World once", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/bacon_world")
    refute html =~ "Bacon World database"
    refute html =~ "Bacon World tuning"
  end

  test "a zone can be renamed on the World page", %{conn: conn} do
    [_ | _] = BaconWorld.WorldGen.layout(1)
    BaconWorld.WorldGen.plan!(1)
    zone = BaconWorld.WorldEditor.get(1)
    {:ok, view, _html} = live(conn, "/admin/bacon_world/world?zone=1")
    view |> form("#zone-name-1", %{name: "Hollowmere", description: "Fens east of the lake"}) |> render_submit()
    assert BaconWorld.WorldEditor.get(1).name == "Hollowmere"
    assert BaconWorld.WorldEditor.get(1).description == "Fens east of the lake"
    assert zone.name != "Hollowmere"
  end
end
