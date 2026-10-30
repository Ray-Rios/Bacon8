defmodule BaconWorld.BuildingTest do
  # Build mode (2026-10-28): the catalogue, who may place what, placing, moving and deleting,
  # creature spawns and NPCs placed in the world, and the LiveView's events.
  use Bacon8.DataCase, async: false

  import Ecto.Query

  alias Bacon8.GamesRepo
  alias BaconWorld.{Building, Merchants, Placement}
  alias BaconWorld.Mobs.{Brain, Spawns}
  alias BaconWorldWeb.BuildEvents

  @zone "build_test"

  defp user(role, extra \\ %{}), do: Map.merge(%{id: Ecto.UUID.generate(), role: role, is_admin: false}, extra)

  defp at(asset, x, z, extra \\ %{}), do: Map.merge(%{"asset" => asset, "x" => x, "y" => 0.0, "z" => z, "rot" => 0.0}, extra)

  describe "the catalogue" do
    test "props, building pieces, every creature kind and the NPC templates" do
      cat = Building.catalogue()
      ids = MapSet.new(cat, & &1.id)
      assert MapSet.member?(ids, "P_Barrel")
      assert MapSet.member?(ids, "K_Wall_Stone")
      for kind <- Map.keys(Spawns.kinds()), do: assert(MapSet.member?(ids, "mob:" <> kind))
      for t <- Merchants.templates(), do: assert(MapSet.member?(ids, "npc:" <> t.id))
      # 90 props, 36 building pieces, the plinth and (2026-10-29) the Robin Hood hat
      assert Enum.count(cat, &(&1.kind == "model")) == 128
      assert Building.asset("X_RobinHat").category == "Props"
      assert Building.asset("X_Plinth").category == "Building"
      assert Building.asset("P_TreeOak").category == "Trees & plants"
      assert Building.asset("P_Boulder").category == "Rocks"
      assert Building.asset("mob:goblin").name == "Goblin"
    end

    test "defaults: members build, GMs place creatures and NPCs, admins the bosses and the waystone" do
      assert Building.min_role("P_Barrel") == "member"
      assert Building.min_role("K_Roof_Tile") == "member"
      assert Building.min_role("mob:goblin") == "gm"
      assert Building.min_role("npc:villager") == "gm"
      assert Building.min_role("mob:baconator") == "admin"
      assert Building.min_role("mob:kraken") == "admin"
      assert Building.min_role("P_Waystone") == "admin"
      assert Building.min_role("P_Nope") == nil
    end
  end

  describe "who may place what" do
    test "by rank; guests and the banned never; is_admin counts as admin" do
      assert Building.can_place?(user("member"), "P_Barrel")
      refute Building.can_place?(user("member"), "mob:rat")
      refute Building.can_place?(user("member"), "mob:giant_rat")
      assert Building.can_place?(user("gm"), "mob:giant_rat")
      refute Building.can_place?(user("gm"), "mob:baconator")
      assert Building.can_place?(user("admin"), "mob:baconator")
      assert Building.can_place?(user("member", %{is_admin: true}), "mob:baconator")
      refute Building.can_place?(user("guest"), "P_Barrel")
      refute Building.can_place?(user("banned"), "P_Barrel")
      refute Building.can_place?(user("admin"), "P_Nope")
    end

    test "admins change the rule in game; nobody else can" do
      assert {:error, _} = Building.set_rule(user("gm"), "P_Barrel", "gm")
      assert {:error, _} = Building.set_rule(user("admin"), "P_Barrel", "guest")
      assert {:error, _} = Building.set_rule(user("admin"), "P_Nope", "gm")
      assert {:ok, "gm"} = Building.set_rule(user("admin"), "P_Barrel", "gm")
      refute Building.can_place?(user("member"), "P_Barrel")
      assert Building.can_place?(user("gm"), "P_Barrel")
      # and back down: members may place creatures now
      assert {:ok, "member"} = Building.set_rule(user("admin"), "mob:giant_rat", "member")
      assert Building.can_place?(user("member"), "mob:giant_rat")
      # a rule naming guests can't be made, so guests stay out
      refute Building.can_place?(user("guest"), "mob:giant_rat")
      entry = Enum.find(Building.catalogue_for(user("member")), &(&1.id == "P_Barrel"))
      assert entry.min_role == "gm" and entry.allowed == false
    end
  end

  describe "placing, moving, deleting" do
    test "a member puts a barrel down, turns it, and anyone allowed may remove it" do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, Building.topic(@zone))
      m = user("member")
      assert {:ok, v} = Building.place(m, nil, @zone, at("P_Barrel", 10.0, -4.0, %{"rot" => -1.0, "scale" => 9.0}))
      assert v.asset == "P_Barrel" and v.x == 10.0 and v.z == -4.0
      # the turn wraps into 0..2pi; the size is clamped
      assert_in_delta v.rot, 2 * :math.pi() - 1.0, 1.0e-3
      assert v.scale == 2.0
      assert_receive {:build_placed, %{id: id}}
      assert [%{id: ^id}] = Building.list(@zone)

      assert {:ok, v2} = Building.move(m, @zone, id, %{"x" => 12.5, "rot" => 0.5})
      assert v2.x == 12.5 and v2.z == -4.0
      assert_in_delta v2.rot, 0.5, 1.0e-3
      # another member may move and delete it: placing a kind means you may remove any of it
      other = user("member")
      assert {:ok, _} = Building.delete(other, @zone, id)
      assert_receive {:build_removed, ^id, "P_Barrel"}
      assert Building.list(@zone) == []
      assert {:error, _} = Building.delete(other, @zone, id)
    end

    test "a smash is a delete that every client shatters" do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, Building.topic(@zone))
      m = user("member")
      {:ok, %{id: id}} = Building.place(m, nil, @zone, at("P_Barrel", 3.0, 3.0))
      assert {:ok, %{asset: "P_Barrel"}} = Building.delete(m, @zone, id, smash: true)
      assert_receive {:build_removed, ^id, "P_Barrel", :smashed}
      refute_received {:build_removed, ^id, "P_Barrel"}
      assert Building.list(@zone) == []
    end

    test "refuses what it should" do
      m = user("member")
      assert {:error, _} = Building.place(m, nil, @zone, at("mob:goblin", 1.0, 1.0))
      assert {:error, _} = Building.place(user("guest"), nil, @zone, at("P_Barrel", 1.0, 1.0))
      assert {:error, _} = Building.place(m, nil, @zone, at("P_Nope", 1.0, 1.0))
      assert {:error, _} = Building.place(m, nil, @zone, at("P_Barrel", "a", 1.0))
      assert {:error, _} = Building.place(m, nil, @zone, at("P_Barrel", 1.0e7, 1.0))
      assert {:error, _} = Building.move(m, @zone, "not-an-id", %{"x" => 1.0})
      {:ok, v} = Building.place(user("gm"), nil, @zone, at("mob:goblin", 1.0, 1.0))
      # a member can't move or delete what only GMs may place
      assert {:error, _} = Building.move(m, @zone, v.id, %{"x" => 2.0})
      assert {:error, _} = Building.delete(m, @zone, v.id)
      # another zone doesn't see it
      assert {:error, _} = Building.delete(user("admin"), "elsewhere", v.id)
    end
  end

  describe "creature spawns" do
    test "count and radius make the zone's spawn points, clamped" do
      {:ok, v} = Building.place(user("gm"), nil, @zone, at("mob:goblin", 100.0, 50.0, %{"data" => %{"count" => 40, "radius" => 6.0}}))
      assert v.data["count"] == 12
      p = GamesRepo.get!(Placement, v.id)
      points = Building.points_for(p)
      assert length(points) == 12
      assert Enum.all?(points, &(&1.kind == "goblin" and String.starts_with?(&1.id, "p:#{v.id}:")))
      assert Enum.all?(points, &(:math.sqrt((&1.x - 100.0) ** 2 + (&1.z - 50.0) ** 2) <= 6.0 + 1.0e-6))
      assert length(Building.mob_points(@zone)) == 12
      # each point spawns a creature
      mob = Brain.spawn(hd(points), 0)
      assert mob.kind == "goblin" and mob.hp > 0
    end
  end

  describe "NPCs" do
    test "a placed clothier trades like Tilda: found by id, in the zone, with her stock" do
      {:ok, v} = Building.place(user("gm"), nil, @zone, at("npc:clothier", 20.0, 30.0, %{"rot" => :math.pi() / 2, "data" => %{"name" => "  Greta  "}}))
      assert v.npc.name == "Greta"
      m = Merchants.get("p:" <> v.id)
      assert m.kind == "trader" and m.zone == @zone and m.sells == Merchants.get("tilda").sells
      assert Merchants.near?(m, {20.0 * Brain.u(), 31.0 * Brain.u()})
      assert Enum.any?(Merchants.in_zone(@zone), &(&1.id == "p:" <> v.id))
      # facing where it was turned to (+x)
      {fx, _fz} = m.face
      assert fx > 20.0
      assert Merchants.get("p:" <> Ecto.UUID.generate()) == nil
      assert Merchants.get("p:junk") == nil
    end
  end

  describe "the village and camps as placements, and binding stones" do
    # (each test seeds a zone of its own: seeding is cached per zone for the node's life)
    defp fresh_zone, do: "seed_test_" <> String.slice(Ecto.UUID.generate(), 0, 8)

    test "seeding happens once: the village and the camps become placements, with where they came from" do
      zone = fresh_zone()
      village = Building.seed_rows("village.json")
      assert length(village) > 300
      assert Enum.any?(village, &(&1["asset"] == "P_Waystone"))

      seeded = Building.ensure_seeded(zone)
      assert seeded.village
      assert seeded.camps != []
      placed = GamesRepo.all(from(p in Placement, where: p.zone == ^zone))
      n = length(placed)
      assert Enum.count(placed, &(&1.data["origin"] == "village")) == length(village)
      assert Enum.any?(placed, &String.starts_with?(&1.data["origin"] || "", "camp:"))
      # stretched pieces keep their stretch
      assert Enum.any?(placed, &match?([_, _, _], &1.data["s"]))
      # camp creatures are spawn placements now, so the code's camps stop spawning
      assert Enum.any?(placed, &String.starts_with?(&1.asset, "mob:"))
      assert Spawns.points(seeded.camps) |> Enum.all?(&(&1.camp not in seeded.camps))

      # a second call (even after the cache is lost: another node) inserts nothing
      :persistent_term.erase({Building, :seeded, zone, "village"})
      assert Building.ensure_seeded(zone).village
      assert GamesRepo.aggregate(from(p in Placement, where: p.zone == ^zone), :count) == n

      # what builders delete stays deleted
      [barrel | _] = Enum.reject(placed, &(&1.asset == "P_Waystone" or String.starts_with?(&1.asset, "mob:")))
      assert {:ok, _} = Building.delete(user("admin"), zone, barrel.id)
      :persistent_term.erase({Building, :seeded, zone, "village"})
      Building.ensure_seeded(zone)
      assert GamesRepo.get(Placement, barrel.id) == nil
    end

    test "within 100 m of a binding stone only GMs and admins build" do
      zone = fresh_zone()
      {:ok, stone} = Building.place(user("admin"), nil, zone, at("P_Waystone", 0.0, 0.0))
      assert Building.binding_radius() == 100.0
      assert Building.protected?(zone, 99.0, 0.0)
      refute Building.protected?(zone, 101.0, 0.0)

      m = user("member")
      assert {:error, msg} = Building.place(m, nil, zone, at("P_Barrel", 60.0, 60.0))
      assert msg =~ "binding stone"
      assert {:ok, out} = Building.place(m, nil, zone, at("P_Barrel", 120.0, 0.0))
      # nor carried in, nor anything in town moved out or removed
      assert {:error, _} = Building.move(m, zone, out.id, %{"x" => 50.0})
      {:ok, inside} = Building.place(user("gm"), nil, zone, at("P_Barrel", 10.0, 0.0))
      assert {:error, _} = Building.move(m, zone, inside.id, %{"x" => 130.0})
      assert {:error, _} = Building.delete(m, zone, inside.id)
      # GMs may
      assert {:ok, _} = Building.move(user("gm"), zone, inside.id, %{"x" => 20.0})
      assert {:ok, _} = Building.delete(user("gm"), zone, inside.id)
      # moving the stone itself is judged by where it goes, not by its own circle
      assert {:ok, _} = Building.move(user("admin"), zone, stone.id, %{"x" => 300.0})
      refute Building.protected?(zone, 0.0, 0.0)
      assert {:ok, _} = Building.place(m, nil, zone, at("P_Barrel", 0.0, 0.0))
    end

    test "a move keeps a piece's stretch and where it came from" do
      zone = fresh_zone()
      {:ok, v} = Building.place(user("admin"), nil, zone, at("P_Barrel", 500.0, 500.0))
      GamesRepo.update_all(from(p in Placement, where: p.id == ^v.id), set: [data: %{"origin" => "village", "s" => [2.0, 1.0, 3.0]}])
      {:ok, _} = Building.move(user("admin"), zone, v.id, %{"x" => 505.0, "data" => %{"origin" => "forged"}})
      p = GamesRepo.get(Placement, v.id)
      assert p.data["origin"] == "village" and p.data["s"] == [2.0, 1.0, 3.0]
    end

    test "binding at a stone: only beside one; Recall and respawn go there" do
      zone = fresh_zone()
      u = Brain.u()
      {:ok, _} = Building.place(user("admin"), nil, zone, at("P_Waystone", 40.0, 40.0))
      me = user("member")
      assert {:error, _} = Building.bind(me, Ecto.UUID.generate(), zone, %{x: 0.0, y: 0.0, z: 0.0})
      # beside the stone, but no such character of yours: nothing saved
      assert {:error, _} = Building.bind(me, Ecto.UUID.generate(), zone, %{x: 42.0 * u, y: 0.0, z: 40.0 * u})

      c = %{settings: %{"zone_slug" => zone, "bind" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0, "zone" => zone}}}
      assert BaconWorld.Combat.respawn_point(c, nil) == %{x: 1.0, y: 2.0, z: 3.0, heading: 0.0}
    end
  end

  describe "the LiveView's events" do
    defp socket(u, extra \\ %{}) do
      assigns = Map.merge(%{__changed__: %{}, current_user: u, mobs_zone: @zone, current_character_runtime: %{character_id: Ecto.UUID.generate()}}, extra)
      %Phoenix.LiveView.Socket{assigns: assigns}
    end

    test "open, place, move, delete, and the rule" do
      a = user("admin")
      {:reply, open, _} = BuildEvents.handle_event("build_open", %{}, socket(a))
      assert open.ok and open.admin and open.role == "admin"
      assert Enum.any?(open.catalogue, &(&1.id == "mob:orc" and &1.allowed))

      {:reply, %{ok: true, placement: p}, s} = BuildEvents.handle_event("build_place", at("K_Wall_Stone", 3.0, 3.0), socket(a))
      {:reply, %{ok: true, placement: p2}, s} = BuildEvents.handle_event("build_move", %{"id" => p.id, "x" => 6.0}, s)
      assert p2.x == 6.0
      {:reply, %{ok: true}, _s} = BuildEvents.handle_event("build_delete", %{"id" => p.id}, s)
      {:reply, %{ok: true, role: "gm"}, _} = BuildEvents.handle_event("build_rule", %{"asset" => "K_Wall_Stone", "role" => "gm"}, socket(a))
      {:reply, %{ok: false}, _} = BuildEvents.handle_event("build_place", at("K_Wall_Stone", 3.0, 3.0), socket(user("member")))
      # nobody dead builds, nor anyone out of the world
      {:reply, %{ok: false}, _} = BuildEvents.handle_event("build_place", at("P_Barrel", 3.0, 3.0), socket(a, %{is_dead?: true}))
      {:reply, %{ok: false}, _} = BuildEvents.handle_event("build_place", at("P_Barrel", 3.0, 3.0), socket(a, %{current_character_runtime: nil}))
    end

    test "a burst limit" do
      s = socket(user("member"))

      s =
        Enum.reduce(1..40, s, fn i, s ->
          {:reply, %{ok: true}, s} = BuildEvents.handle_event("build_place", at("P_Crate", i * 1.0, 0.0), s)
          s
        end)

      assert {:reply, %{ok: false, error: "Slow down a little."}, _} = BuildEvents.handle_event("build_place", at("P_Crate", 0.0, 9.0), s)
    end
  end

end
