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

  for path <- ~w(/admin/bacon_world /admin/bacon_world/skills /admin/bacon_world/tuning /admin/bacon_world/world /admin/bacon_world/database /admin/bacon_world/bestiary) do
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
    # the Bestiary's numbers have their own section, so saving the page keeps them (2026-11-03)
    assert html =~ "tuning[loot_chance_mult]"
    assert html =~ "tuning[rank_boss_xp_mult]"
  end

  describe "the Bestiary (2026-11-03)" do
    setup do
      old = Application.get_env(:bacon8, BaconWorld.Defs)
      Application.put_env(:bacon8, BaconWorld.Defs, source: :db)
      for k <- ~w(monster loot_table camp event), do: BaconWorld.Defs.reload(k)

      on_exit(fn ->
        Application.put_env(:bacon8, BaconWorld.Defs, old)
        for k <- ~w(monster loot_table camp event), do: BaconWorld.Defs.reload(k)
        BaconWorld.Building.forget_catalogue()
      end)
    end

    test "every tab and new form opens", %{conn: conn} do
      for q <- ~w(tab=monsters tab=camps tab=loot tab=xp tab=events tab=monsters&id=new tab=camps&id=new tab=loot&id=new tab=monsters&id=goblin tab=monsters&id=kraken tab=loot&id=camp_chest_major) do
        assert {:ok, _view, _html} = live(conn, "/admin/bacon_world/bestiary?#{q}")
      end
    end

    test "a loot table, a monster type and a camp made on the page", %{conn: conn} do
      {:ok, view, _} = live(conn, "/admin/bacon_world/bestiary?tab=loot&id=new")
      view |> form("form[phx-submit=loot_save]", %{t: %{name: "Test pockets", rolls: "1", empty: "10", pool: "goblin_ear 5 1-2"}}) |> render_submit()
      assert %{name: "Test pockets", empty: 10} = BaconWorld.Loot.get("test_pockets")

      {:ok, view, _} = live(conn, "/admin/bacon_world/bestiary?tab=monsters&id=new")

      view
      |> form("form[phx-submit=mon_save]", %{m: %{id: "test_imp", name: "a test imp", model: "goblin", levels: "2-3", loot_tables: "test_pockets", weapons: "rusty_dagger 1"}})
      |> render_submit()

      imp = BaconWorld.Mobs.Spawns.kind("test_imp")
      assert imp.model == "goblin" and imp.levels == 2..3 and imp.loot_tables == ["test_pockets"]
      assert BaconWorld.Building.asset("mob:test_imp")

      {:ok, view, _} = live(conn, "/admin/bacon_world/bestiary?tab=camps&id=new&zone=lobby")

      view
      |> form("form[phx-submit=camp_save]", %{c: %{name: "Imp Hollow", x: "120", z: "-40", assist_radius: "10", slots: %{"0" => %{count: "3", table: "test_imp 2, goblin 1"}}}})
      |> render_submit()

      assert [{"imp_hollow", camp}] = BaconWorld.Mobs.Camps.list()
      assert camp.zone == "lobby" and BaconWorld.Mobs.Camps.population(camp) == 3 and camp.assist_radius == 10.0
      assert [%{table: [{"test_imp", 2}, {"goblin", 1}]}] = camp.slots
      assert {:ok, _view, html} = live(conn, "/admin/bacon_world/bestiary?tab=camps&id=imp_hollow")
      assert html =~ "Imp Hollow"
    end

    test "the experience tab saves only its numbers", %{conn: conn} do
      melee = BaconWorld.Tuning.get("melee_crit_chance")
      {:ok, view, _} = live(conn, "/admin/bacon_world/bestiary?tab=xp")
      view |> form("form[phx-submit=xp_save]", %{x: %{rank_boss_xp_mult: "3"}}) |> render_submit()
      assert BaconWorld.Tuning.get("rank_boss_xp_mult") == 3.0
      assert BaconWorld.Tuning.get("melee_crit_chance") == melee
      BaconWorld.Tuning.bust()
    end
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
