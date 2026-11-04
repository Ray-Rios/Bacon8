defmodule BaconWorld.BestiaryTest do
  # The monster creation system (2026-11-03): loot tables, spawn rotation, managed camps and the
  # monster editor's form. Pure: definitions come from the seed files (config/test.exs).
  use ExUnit.Case, async: true

  alias BaconWorld.{Bestiary, Loot, Progression}
  alias BaconWorld.Mobs.{Brain, CampLayout, Camps, Rotation, Spawns}

  @u 2.2 / 1.8

  setup do
    :rand.seed(:exsss, {7, 8, 9})
    :ok
  end

  defp camp(attrs \\ %{}) do
    Map.merge(
      %{
        name: "Test Camp",
        zone: "lobby",
        x: 300.0,
        z: 300.0,
        rot: 0.0,
        size: "medium",
        radius: 10.0,
        theme: "goblin",
        features: ["campfire", "tents", "palisade"],
        levels: nil,
        elite_chance: 0.0,
        assist_radius: 12.0,
        respawn_ms: nil,
        dynamic_respawn: false,
        enabled: true,
        slots: [
          %{count: 3, table: [{"goblin", 70}, {"goblin_archer", 30}], mode: "random"},
          %{count: 1, table: [{"goblin", 1}], mode: "placeholder", rare: %{kind: "orc_warlord", chance: 0.1, cooldown_ms: 0}}
        ],
        clear: %{loot_table: "camp_chest_minor", xp_mult: 1.5, escalate_after: 2, boss: "orc_warlord"}
      },
      attrs
    )
  end

  describe "loot tables" do
    test "a pool picks by weight, with nothing one of the outcomes" do
      t = %{rolls: 1, empty: 50, pool: [%{item: "bone_chips", weight: 50, qty: 1..1}]}
      sim = Loot.simulate(fn -> Loot.roll(t, 1, chance_mult: 1.0, coin_mult: 1.0) end, 4000)
      assert_in_delta sim.nothing_pct, 50.0, 4.0
      assert [%{item_id: "bone_chips"}] = sim.rows
    end

    test "the chance multiplier thins out the empties and raises chances, up to 100%" do
      t = %{rolls: 1, empty: 50, pool: [%{item: "bone_chips", weight: 50, qty: 1..1}], always: [%{item: "skull_fragment", chance: 0.6, qty: 1..1}]}
      sim = Loot.simulate(fn -> Loot.roll(t, 1, chance_mult: 2.0, coin_mult: 1.0) end, 4000)
      assert Enum.find(sim.rows, &(&1.item_id == "skull_fragment")).pct == 100.0
      assert_in_delta Enum.find(sim.rows, &(&1.item_id == "bone_chips")).pct, 66.7, 4.0
    end

    test "levels limit pool lines; quantities, coins and nested tables" do
      t = %{
        rolls: 3,
        empty: 0,
        pool: [%{item: "rusty_dagger", weight: 1, qty: 1..1, min_level: 10, max_level: 20}, %{item: "bone_chips", weight: 1, qty: 2..3}],
        coins: 5..5,
        tables: [%{table: "camp_chest_major", chance: 1.0}]
      }

      r = Loot.roll(t, 2, chance_mult: 1.0, coin_mult: 1.0)
      refute Enum.any?(r.items, &(&1.item_id == "rusty_dagger"))
      bones = Enum.filter(r.items, &(&1.item_id == "bone_chips"))
      assert length(bones) == 3 and Enum.all?(bones, &(&1.quantity in 2..3))
      # its own 5 x level 2, and the nested chest's (12-30 x 2, and maybe the minor chest's)
      assert r.coins >= 10 + 24
      assert length(r.items) >= 3 + 3
    end

    test "an unknown item or table is skipped when rolling and refused when saving" do
      assert Loot.roll(%{rolls: 1, empty: 0, pool: [%{item: "no_such_thing", weight: 1}]}, 1).items == []
      assert {:error, errs} = Loot.from_form(%{"name" => "x", "pool" => "no_such_thing 5", "tables" => "nope 0.5"})
      assert Enum.any?(errs, &(&1 =~ "no_such_thing"))
      assert Enum.any?(errs, &(&1 =~ "nope"))
    end

    test "the form round-trips" do
      {:ok, t} =
        Loot.from_form(%{
          "name" => "Pockets",
          "rolls" => "1-2",
          "empty" => "30",
          "coins" => "2-4",
          "pool" => "goblin_ear 30 1-2\nrusty_dagger 4 1 2-8",
          "always" => "tarnished_trinket 15%",
          "tables" => "rat_nest 0.05"
        })

      assert t.rolls == 1..2 and t.empty == 30 and t.coins == 2..4
      assert [%{item: "goblin_ear", weight: 30.0, qty: 1..2}, %{item: "rusty_dagger", min_level: 2, max_level: 8}] = t.pool
      assert [%{item: "tarnished_trinket", chance: 0.15}] = t.always
      assert {:ok, ^t} = Loot.from_form(Loot.to_form(t))
    end

    test "the shipped tables name real items and tables" do
      for {id, t} <- Loot.list(), do: assert(Loot.check_items(t) == [], id)
    end
  end

  describe "spawn rotation" do
    test "random picks by weight; cycle goes in turn" do
      p = %{id: "c:t:0:0", camp: "c:t", kind: "goblin", table: [{"goblin", 3}, {"goblin_archer", 1}], mode: "random"}
      picks = for _ <- 1..2000, do: elem(Rotation.pick(p, nil, 0), 0)
      assert_in_delta Enum.count(picks, &(&1 == "goblin_archer")) / 2000, 0.25, 0.04

      c = %{p | mode: "cycle", table: [{"goblin", 1}, {"goblin_archer", 1}, {"orc", 1}]}
      {kinds, _} = Enum.map_reduce(1..6, nil, fn _, rot -> Rotation.pick(c, rot, 0) end)
      assert kinds == ~w(goblin goblin_archer orc goblin goblin_archer orc)
    end

    test "a rare takes its placeholder's point at its chance, then waits out its cooldown" do
      p = %{id: "c:t:0:0", camp: "c:t", kind: "goblin", table: [{"goblin", 1}], mode: "placeholder", rare: %{kind: "orc_warlord", chance: 1.0, cooldown_ms: 60_000}}
      {"orc_warlord", rot} = Rotation.pick(p, nil, 1_000)
      {"goblin", rot} = Rotation.pick(p, rot, 30_000)
      assert {"orc_warlord", _} = Rotation.pick(p, rot, 61_000)
    end

    test "a monster type deleted since is skipped" do
      p = %{id: "x", camp: "c:t", kind: "goblin", table: [{"gone_kind", 5}, {"goblin", 1}]}
      for _ <- 1..20, do: assert(elem(Rotation.pick(p, nil, 0), 0) == "goblin")
    end

    test "a plain point always spawns its kind" do
      assert {"skeleton", nil} = Rotation.pick(%{id: "x", kind: "skeleton"}, nil, 0)
    end

    test "day and night follow the client's sky: an hour a day on the wall clock" do
      hour = 3_600_000
      assert Rotation.night?(0)
      assert Rotation.night?(round(0.9 * hour))
      refute Rotation.night?(round(0.5 * hour))
      assert Rotation.open?(%{window: "night"}, 5 * hour + round(0.1 * hour))
      refute Rotation.open?(%{window: "night"}, 5 * hour + round(0.5 * hour))
      assert Rotation.open?(%{window: "day"}, round(0.5 * hour))
      assert Rotation.open?(%{}, 123)
    end
  end

  describe "managed camps" do
    test "its points: one a creature, ids by slot, inside the camp, with their rotation" do
      pts = Camps.points("t", camp())
      assert Enum.map(pts, & &1.id) == ~w(c:t:0:0 c:t:0:1 c:t:0:2 c:t:1:0)
      assert Enum.all?(pts, &(&1.camp == "c:t"))
      assert Enum.all?(pts, fn p -> :math.sqrt(:math.pow(p.x - 300, 2) + :math.pow(p.z - 300, 2)) <= 10.0 end)
      assert Enum.at(pts, 3).rare.kind == "orc_warlord"
      assert Camps.population(camp()) == 4
    end

    test "a creature of a camp: its kind from the table, the camp's level band, elites" do
      one = camp(%{levels: 7..7, slots: [%{count: 1, table: [{"goblin", 1}]}]})
      [p] = Camps.points("t", %{one | elite_chance: 1.0})
      m = Brain.spawn(p, 0)
      assert m.kind == "goblin"
      assert m.level == 8
      assert m.elite and m.name == "an elite goblin"
      plain = Brain.spawn(%{p | elite_chance: 0.0}, 0)
      assert plain.level == 7 and not plain.elite
      assert m.max_hp > plain.max_hp
      assert Brain.view(m).scale > Brain.view(plain).scale
      assert Brain.xp_mult(m) == 2.0
      assert Brain.xp_mult(plain) == 1.0
    end

    test "its rare's rank prices its experience; a kill's hit says so" do
      assert Spawns.rank(%{boss: true}) == "boss"
      assert Spawns.rank(%{rank: "rare"}) == "rare"
      assert Spawns.rank(%{}) == "normal"
      assert Spawns.rank_xp_mult("rare") == 2.0
      # bosses are worth what their level is until the owner says otherwise
      assert Spawns.rank_xp_mult("boss") == 1.0

      m = Brain.spawn(%{id: "t:0", camp: "t", kind: "decaying_skeleton", x: 60.0, z: 0.0}, 0) |> Map.merge(%{hp: 1, h: 0.0})
      attack = %{id: "p1", x: 59.0 * @u, z: 0.0, heading: :math.pi() / 2, item: BaconWorld.Items.get("worn_short_sword"), level: 1, heavy: false, target: nil}
      {_mobs, [hit], _evs} = Brain.melee(%{"t:0" => m}, attack, 1_000, fn -> 0.0 end)
      assert hit.killed and hit.xp_mult == 1.0
    end

    test "campmates assist within the radius; far ones and other camps don't" do
      at = fn id, camp, x -> Brain.spawn(%{id: id, camp: camp, kind: "goblin", x: x, z: 0.0}, 0) |> Map.put(:state, :idle) end
      mobs = Map.new([at.("c:t:0:0", "c:t", 0.0), at.("c:t:0:1", "c:t", 5.0), at.("c:t:0:2", "c:t", 40.0), at.("c:u:0:0", "c:u", 2.0)], &{&1.id, &1})
      camps = %{"c:t" => %{assist_radius: 12.0}, "c:u" => %{assist_radius: 12.0}}
      {mobs, evs} = Camps.assist(mobs, [{:aggro, "c:t:0:0", "p1"}], camps, 0)
      assert evs == [{:aggro, "c:t:0:1", "p1"}]
      assert mobs["c:t:0:1"].state == :chase and mobs["c:t:0:1"].target == "p1"
      assert mobs["c:t:0:2"].state == :idle
      assert mobs["c:u:0:0"].state == :idle
    end

    test "cleared when none is alive (its boss aside); the boss comes every N clears" do
      mobs = %{"c:t:0:0" => %{camp: "c:t", state: :dead}, "c:t:0:1" => %{camp: "c:t", state: :gone}, "c:t:boss" => %{camp: "c:t", state: :idle}}
      assert Camps.cleared?(mobs, "c:t")
      refute Camps.cleared?(Map.put(mobs, "c:t:0:2", %{camp: "c:t", state: :idle}), "c:t")
      refute Camps.escalates?(camp(), 1)
      assert Camps.escalates?(camp(), 2)
      refute Camps.escalates?(camp(%{clear: %{escalate_after: 0, boss: "orc_warlord"}}), 9)
      assert %{id: "c:t:boss", kind: "orc_warlord", once: true} = Camps.boss_point("t", camp())
      reward = Camps.clear_reward(camp(%{clear: %{loot_table: "camp_chest_major", xp_mult: 1.5}}), 5)
      assert reward.xp_mult == 1.5 and length(reward.items) >= 3 and reward.coins >= 12 * 5
    end

    test "a point whose time of day isn't now stays empty and looks again later; one out of its time fades" do
      closed = if Rotation.night?(Rotation.wall_ms()), do: "day", else: "night"
      p = %{id: "c:t:0:0", camp: "c:t", kind: "skeleton", x: 300.0, z: 0.0, window: closed}
      m = Brain.dormant(p, 0)
      assert m.state == :gone
      {m2, []} = Brain.tick(m, %{}, m.respawn_at, 0.1, p)
      assert m2.state == :gone and m2.respawn_at > m.respawn_at
      {m3, [{:spawn, _}]} = Brain.tick(m2, %{}, m2.respawn_at, 0.1, Map.delete(p, :window))
      assert m3.state == :idle
      assert {%{state: :gone}, [{:corpse_gone, "c:t:0:0"}]} = Brain.depop(m3, 0)
      # a creature in a fight stays
      assert {%{state: :chase}, []} = Brain.depop(%{m3 | state: :chase, target: "p1"}, 0)
    end

    test "a camp's respawn time; faster with players near when dynamic; at once when the admin says" do
      p = %{id: "c:t:0:0", camp: "c:t", kind: "skeleton", x: 300.0, z: 0.0, respawn_ms: 100_000..100_000}
      dead = p |> Brain.spawn(0) |> Map.merge(%{state: :dead, corpse: %{despawn_at: 0, items: [], coins: 0}})
      {gone, _} = Brain.tick(dead, %{}, 0, 0.1, p)
      assert gone.respawn_at == 100_000
      near = for i <- 1..4, into: %{}, do: {"p#{i}", %{x: 300.0 * @u, z: 0.0, dead: false, level: 1}}
      {gone2, _} = Brain.tick(dead, near, 0, 0.1, Map.put(p, :dynamic_respawn, true))
      assert gone2.respawn_at == 70_000
      {gone3, _} = Brain.tick(Map.put(dead, :respawn_now, true), %{}, 0, 0.1, p)
      assert gone3.respawn_at == 0
    end

    test "loot tables on a kind add to its corpse; an elite rolls them twice" do
      kind = Spawns.kind("goblin") |> Map.put(:loot_tables, ["camp_chest_major"])
      mob = %{weapon: nil, offhand: nil, level: 5, loot_tables: [], elite: false}
      {items, coins} = Brain.roll_loot_and_coins(mob, kind)
      assert length(items) >= 3 and coins >= 12 * 5
      {elite_items, _} = Brain.roll_loot_and_coins(%{mob | elite: true}, kind)
      assert length(elite_items) >= 6
    end

    test "the form: what's wrong, and a round trip" do
      assert {:error, errs} = Camps.from_form(%{"name" => "", "zone" => "lobby", "slots" => %{"0" => %{"count" => "2", "table" => "goblin 1, nonesuch 2"}}})
      assert Enum.any?(errs, &(&1 =~ "name"))
      assert Enum.any?(errs, &(&1 =~ "nonesuch"))

      assert {:error, [_ | _]} = Camps.from_form(%{"name" => "Big", "zone" => "lobby", "slots" => %{"0" => %{"count" => "25", "table" => "goblin"}}})

      c = camp()
      {:ok, c2} = Camps.from_form(Camps.to_form(c))
      assert c2.slots == Enum.map(c.slots, &Map.merge(%{rare: nil, window: nil, loot_tables: [], respawn_ms: nil}, &1))
      assert c2.clear == c.clear
      assert c2.features == c.features
      assert {c2.x, c2.z, c2.radius, c2.assist_radius, c2.levels} == {300.0, 300.0, 10.0, 12.0, nil}
    end

    test "decor: the same layout every time, catalogue pieces, around the camp" do
      a = CampLayout.pieces("t", camp())
      assert a == CampLayout.pieces("t", camp())
      assert Enum.any?(a, &(&1["asset"] == "P_Campfire"))
      assert Enum.count(a, &(&1["asset"] == "P_Tent")) == 2
      assert Enum.any?(a, &(&1["asset"] == "K_Wall_Palisade_Vertical"))
      assert Enum.all?(a, fn p -> :math.sqrt(:math.pow(p["x"] - 300, 2) + :math.pow(p["z"] - 300, 2)) < 20 end)
      assert CampLayout.origin("t") == "camp:c:t"
    end

    test "an old camp becomes a managed one, keeping its creatures and remembering them" do
      code = Enum.find(Spawns.camps(), &(&1.id == "goblin_camp"))

      placements = [
        %BaconWorld.Placement{asset: "mob:goblin", x: 104.0, y: 1.0, z: -272.0, rot: 0.0, scale: 1.0, data: %{"count" => 4, "radius" => 6.0, "origin" => "camp:goblin_camp"}},
        %BaconWorld.Placement{asset: "P_Tent", x: 100.0, y: 1.0, z: -270.0, rot: 0.0, scale: 1.0, data: %{"origin" => "camp:goblin_camp"}}
      ]

      c = Camps.from_legacy(code, "lobby", placements)
      assert c.name == "Goblin Camp"
      assert [%{count: 4, table: [{"goblin", 1}]}] = c.slots
      assert [%{"asset" => "mob:goblin"}] = c.legacy.placements
      assert Camps.validate(c) == []
    end
  end

  describe "the monster editor" do
    test "a monster type round-trips through the form" do
      for id <- ~w(goblin kraken baconator) do
        k = Spawns.kind(id)
        {:ok, ^id, k2} = Bestiary.from_form(Bestiary.to_form(id, k), %{id: id})

        for key <- Map.keys(k), do: assert(k2[key] == k[key], "#{id} #{key}: #{inspect(k[key])} vs #{inspect(k2[key])}")
      end
    end

    test "unknown items are refused; a new type's id comes from its name" do
      p = Bestiary.to_form(nil, Bestiary.blank()) |> Map.merge(%{"name" => "Grub the Small", "weapons" => "no_such_club 1"})
      assert {:error, errs} = Bestiary.from_form(p)
      assert Enum.any?(errs, &(&1 =~ "no_such_club"))
      assert {:ok, "grub_the_small", k} = Bestiary.from_form(Map.put(p, "weapons", "worn_club 1"))
      assert k.offhand == [{nil, 1}] and k.model == "skeleton"
    end

    test "a preview at a level, and the curve" do
      pv = Bestiary.preview(Spawns.kind("goblin"), 3, 3)
      assert pv.hp == 15 + 9 * 3
      assert pv.con == :white
      assert pv.xp == Progression.kill_xp(3, 3)
      rows = Bestiary.xp_table()
      assert length(rows) == Progression.max_level() - 1
      assert hd(rows).to_next == Progression.xp_to_next(1)
      assert Progression.kill_xp(3, 3, 2.0) == 2 * Progression.kill_xp(3, 3)
    end

    test "the examples are valid monster types" do
      for %{"id" => id, "data" => d} <- Bestiary.examples()["monsters"] do
        assert Bestiary.validate(id, BaconWorld.Defs.decode(d)) == [], id
        assert BaconWorld.Defs.decode(d).model in Bestiary.models()
      end
    end

    test "a loot simulation of a kind" do
      sim = Bestiary.simulate_loot(Spawns.kind("goblin"), 3, 500)
      assert sim.n == 500
      assert Enum.any?(sim.rows, &(&1.item_id == "goblin_ear"))
    end
  end
end
