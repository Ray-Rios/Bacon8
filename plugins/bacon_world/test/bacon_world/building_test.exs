defmodule BaconWorld.BuildingTest do
  # Build mode (2026-10-28): the catalogue, who may place what, placing, moving and deleting,
  # creature spawns and NPCs placed in the world, and the LiveView's events.
  use Bacon8.DataCase, async: false

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
      assert Enum.count(cat, &(&1.kind == "model")) == 126
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
