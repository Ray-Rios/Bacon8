defmodule BaconWorld.MobsTest do
  # The creature rules (BaconWorld.Mobs.Brain), melee numbers and levels: pure, no database.
  use ExUnit.Case, async: true

  alias BaconWorld.{Items, Melee, Progression}
  alias BaconWorld.Mobs.{Brain, Spawns}

  @u 2.2 / 1.8

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  defp point(kind \\ "decaying_skeleton"), do: %{id: "test:0", camp: "test", kind: kind, x: 60.0, z: 0.0}

  defp mob(attrs \\ %{}) do
    point() |> Brain.spawn(0) |> Map.merge(%{level: 1, hp: 30, max_hp: 30, h: 0.0}) |> Map.merge(attrs)
  end

  # A player `m` metres from the creature's spawn (along -x, toward the village).
  defp player_at(m, attrs \\ %{}), do: Map.merge(%{x: (60.0 - m) * @u, z: 0.0, dead: false, level: 1}, attrs)

  defp run(mob, players, from, ms, step \\ 100) do
    Enum.reduce(0..div(ms, step), {mob, []}, fn i, {m, evs} ->
      {m2, e} = Brain.tick(m, players, from + i * step, step / 1000, point())
      {m2, evs ++ e}
    end)
  end

  describe "spawns" do
    test "every camp is outside the safe village and spawns its creatures" do
      points = Spawns.points()
      # 18 skeletons and the dragon, the warren's 5 rats, the goblin camp's 4 (2026-10-28)
      assert length(points) == 27
      assert Enum.all?(points, fn p -> :math.sqrt(p.x * p.x + p.z * p.z) > Spawns.safe_radius() end)
      assert points |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 27
    end

    test "creatures hold a weapon from their list; a two-hander leaves the off hand empty" do
      for _ <- 1..40 do
        m = Brain.spawn(point("skeleton_warrior"), 0)
        assert m.level in 3..5
        assert m.hp == m.max_hp
        weapon = Items.get(m.weapon)
        assert weapon
        if Items.two_handed?(weapon), do: assert(is_nil(m.offhand))
      end
    end
  end

  describe "thinking" do
    test "a player close by outside the village is chased and hit" do
      players = %{"p1" => player_at(5)}
      {m, evs} = run(mob(), players, 0, 6_000)
      assert {:aggro, "test:0", "p1"} in evs
      assert m.state == :chase
      # It closed the distance and swung at least once.
      assert Enum.any?(evs, &match?({:attack, "test:0", "p1", _, _}, &1))
      assert :math.sqrt(:math.pow(m.x - players["p1"].x, 2) + :math.pow(m.z - players["p1"].z, 2)) < 2.0 * @u
    end

    test "creatures swing on the BEAM's clock, which is often negative" do
      # System.monotonic_time/1 usually starts far below zero; nothing may treat 0 as "long ago".
      t0 = -576_460_752_303
      m = point() |> Brain.spawn(t0) |> Map.merge(%{level: 1, hp: 30, max_hp: 30, h: 0.0})
      {_m, evs} = run(m, %{"p1" => player_at(2)}, t0, 6_000)
      assert Enum.any?(evs, &match?({:attack, "test:0", "p1", _, _}, &1))
    end

    test "nobody is chased into the village, and the dead are left alone" do
      {m, evs} = run(mob(), %{"p1" => player_at(30.0)}, 0, 2_000)
      refute Enum.any?(evs, &match?({:aggro, _, _}, &1))
      assert m.state in [:idle, :wander]

      {_m, evs} = run(mob(), %{"p1" => player_at(4, %{dead: true})}, 0, 2_000)
      refute Enum.any?(evs, &match?({:aggro, _, _}, &1))
    end

    test "players who con grey to a creature aren't attacked" do
      {_m, evs} = run(mob(), %{"p1" => player_at(4, %{level: 20})}, 0, 2_000)
      refute Enum.any?(evs, &match?({:aggro, _, _}, &1))
    end

    test "a chase ends at the village edge: the creature runs home and heals" do
      {m, _} = run(mob(), %{"p1" => player_at(5)}, 0, 1_000)
      assert m.state == :chase
      m = %{m | hp: 3}
      # The player steps into the village.
      safe = %{"p1" => %{x: 10.0, z: 0.0, dead: false, level: 1}}
      {m, _} = Brain.tick(m, safe, 2_000, 0.1, point())
      assert m.state == :return
      {m, _} = run(m, safe, 2_100, 20_000)
      assert m.state in [:idle, :wander]
      assert m.hp == m.max_hp
      assert Brain.in_safe_zone?(10.0, 0.0)
    end
  end

  describe "melee" do
    defp attack(attrs \\ %{}) do
      Map.merge(%{id: "p1", level: 1, x: 59.0 * @u, z: 0.0, heading: :math.pi() / 2, item: Items.get("worn_short_sword"), heavy: false, target: nil}, attrs)
    end

    test "a swing hits what is in front, within reach" do
      mobs = %{"test:0" => mob()}
      always = fn -> 0.0 end
      {mobs2, [hit], evs} = Brain.melee(mobs, attack(), 1_000, always)
      assert hit.hit and hit.damage > 0 and not hit.killed
      assert mobs2["test:0"].hp == 30 - hit.damage
      assert mobs2["test:0"].state == :chase and mobs2["test:0"].target == "p1"
      assert Enum.any?(evs, &match?({:damaged, "test:0", "p1", _, _, _, 30}, &1))

      # Facing away: nothing.
      assert {_, [], []} = Brain.melee(mobs, attack(%{heading: -:math.pi() / 2}), 1_000, always)
      # Out of reach: nothing.
      assert {_, [], []} = Brain.melee(mobs, attack(%{x: 50.0 * @u}), 1_000, always)
    end

    test "a kill leaves a corpse with loot; the killer loots first" do
      mobs = %{"test:0" => mob(%{hp: 1})}
      {mobs, [hit], evs} = Brain.melee(mobs, attack(), 1_000, fn -> 0.0 end)
      assert hit.killed
      assert {:died, "test:0", "p1"} in evs
      corpse = mobs["test:0"]
      assert corpse.state == :dead and corpse.corpse.owner == "p1"

      pos = {59.0 * @u, 0.0}
      assert {:error, :not_yours_yet} = Brain.loot_open(corpse, "p2", pos, 2_000)
      assert {:error, :too_far} = Brain.loot_open(corpse, "p1", {0.0, 0.0}, 2_000)
      assert {:ok, opened, coins, items} = Brain.loot_open(corpse, "p1", pos, 2_000)
      assert coins > 0
      assert {:error, :someone_else_looting} = Brain.loot_open(opened, "p2", pos, 2_000 + Spawns.loot_lock_ms())
      # Coins only once.
      assert {:ok, _, 0, ^items} = Brain.loot_open(opened, "p1", pos, 2_500)

      looted =
        Enum.reduce(items, opened, fn _, m ->
          {:ok, m, _item} = Brain.loot_take(m, "p1", 0)
          m
        end)

      assert looted.corpse.items == []
      closed = Brain.loot_close(looted, "p1", 3_000)
      # An empty corpse decays within seconds, then the creature respawns later.
      {gone, [{:corpse_gone, "test:0"}]} = Brain.tick(closed, %{}, 6_100, 0.1, point())
      assert gone.state == :gone
      {back, [{:spawn, view}]} = Brain.tick(gone, %{}, gone.respawn_at, 0.1, point())
      assert back.state == :idle and view.id == "test:0"
    end

    test "two-handers sweep up to three; one-handers hit one" do
      mobs = for i <- 0..3, into: %{}, do: {"m#{i}", mob(%{id: "m#{i}", x: 60.0 * @u, z: (i - 1.5) * 0.3 * @u})}
      always = fn -> 0.0 end
      {_, hits, _} = Brain.melee(mobs, attack(%{item: Items.get("rusty_two_handed_sword")}), 1_000, always)
      assert length(hits) == 3
      {_, hits, _} = Brain.melee(mobs, attack(%{target: "m3"}), 1_000, always)
      assert [%{id: "m3"}] = hits
    end
  end

  describe "numbers" do
    test "damage rolls stay within the weapon's range plus the level bonus" do
      sword = Items.get("worn_short_sword")

      for _ <- 1..200 do
        {d, crit} = Melee.roll_damage(sword, 1)
        if crit, do: assert(d <= round(6 * 1.75)), else: assert(d in 2..6)
      end

      assert Melee.delay_ms(sword) == 1_200
      assert Melee.delay_ms(sword, true) == 1_680
      assert Melee.hit_chance(1, 30) == 0.4
    end

    test "arcs" do
      assert Melee.in_arc?({0.0, 0.0}, 0.0, {0.0, 1.0}, 2.0, 90)
      refute Melee.in_arc?({0.0, 0.0}, 0.0, {0.0, -1.0}, 2.0, 90)
      refute Melee.in_arc?({0.0, 0.0}, 0.0, {0.0, 3.0}, 2.0, 90)
      refute Melee.in_arc?({0.0, 0.0}, :math.pi(), {0.0, 0.1}, 2.0, 90), "nothing behind you, however close"
      assert Melee.in_arc?({0.0, 0.0}, 0.0, {0.3, 0.1}, 2.0, 90), "pressed against your side counts"
      refute Melee.in_arc?({0.0, 0.0}, 0.0, {1.5, 0.3}, 2.0, 110), "off to the side at reach doesn't"
    end

    test "levels, con and experience" do
      assert Progression.xp_to_next(1) == 100
      assert {2, 0} = Progression.apply_xp(1, 100)
      assert {3, 5} = Progression.apply_xp(1, 100 + Progression.xp_to_next(2) + 5)
      assert Progression.con(1, 1) == :white
      assert Progression.con(4, 1) == :red
      assert Progression.con(2, 1) == :yellow
      assert Progression.con(1, 10) == :grey
      assert Progression.kill_xp(1, 10) == 0
      assert Progression.kill_xp(2, 1) > Progression.kill_xp(1, 1)
      assert Progression.max_hp(1) == 40
    end

    test "the item catalogue is consistent" do
      for item <- Items.all() do
        assert item.name != ""
        if item.kind in ["weapon", "shield", "light"], do: assert(item.dmg > 0 and item.dly > 0 and item.set)
        if item.hands == 2, do: assert(item.slots == ["main"])
      end

      for {id, _} <- Items.starter_kit(), do: assert(Items.get(id))

      for {_, kind} <- Spawns.kinds(), {id, _} <- kind.weapons ++ kind.offhand ++ Enum.map(kind.loot, &{elem(&1, 0), 0}) ++ Map.get(kind, :drops, []), id do
        assert Items.get(id), "#{id} is in the catalogue"
      end
    end
  end

  describe "Baconator, the boss" do
    defp dragon_point, do: %{id: "lair:0", camp: "lair", kind: "baconator", x: 92.0, z: 0.0}

    defp dragon(attrs \\ %{}), do: dragon_point() |> Brain.spawn(0) |> Map.merge(%{h: -:math.pi() / 2}) |> Map.merge(attrs)

    # metres from the dragon toward the village (-x), `side` metres off its line
    defp near_dragon(m, side \\ 0.0, attrs \\ %{}), do: Map.merge(%{x: (92.0 - m) * @u, y: 0.0, z: side * @u, dead: false, level: 8}, attrs)

    defp run_dragon(mob, players, from, ms) do
      Enum.reduce(0..div(ms, 100), {mob, []}, fn i, {m, evs} ->
        {m2, e} = Brain.tick(m, players, from + i * 100, 0.1, dragon_point())
        {m2, evs ++ e}
      end)
    end

    test "its lair is a camp of one, far outside the village" do
      [p] = Enum.filter(Spawns.points(), &(&1.kind == "baconator"))
      assert {p.x, p.z} == {92.0, 42.0}
      assert Brain.view(Brain.spawn(p, 0)).boss
    end

    test "it bites, claws and lashes its tail at whoever it chases" do
      {_m, evs} = run_dragon(dragon(%{next_breath: 1_000_000}), %{"a" => near_dragon(6.0)}, 0, 12_000)
      moves = for {:attack, _, "a", _, _, move} <- evs, do: move
      assert moves != []
      assert Enum.all?(moves, &(&1 in ["bite", "claw", "tail"]))
    end

    test "fire: a roar first, then everyone in the cone burns and those outside it don't" do
      players = %{"front" => near_dragon(8.0), "beside" => near_dragon(8.0, 3.0), "behind" => near_dragon(-9.0)}
      m = dragon(%{state: :chase, target: "front", next_breath: 0, next_attack: 1_000_000})
      {m, evs} = Brain.tick(m, players, 100, 0.1, dragon_point())
      assert {:cast, "lair:0", "breath"} in evs
      # nothing burns during the windup
      {m, evs} = run_dragon(m, players, 200, 700)
      refute Enum.any?(evs, &match?({:attack, _, _, _, _, "breath"}, &1))
      {_m, evs} = run_dragon(m, players, 1_000, 600)
      burned = for {:attack, _, id, _, _, "breath"} <- evs, do: id
      assert "front" in burned and "beside" in burned
      refute "behind" in burned
    end

    test "a player high on a flying mount is out of its reach" do
      high = near_dragon(8.0, 0.0, %{y: 9.0 * @u})
      {m, evs} = run_dragon(dragon(), %{"a" => high}, 0, 3_000)
      assert m.state != :chase
      refute Enum.any?(evs, &match?({:aggro, _, _}, &1))
    end

    test "its hide is hit from further away than a skeleton's middle" do
      m = dragon(%{x: 0.0, z: 0.0})
      item = Items.get("worn_short_sword")
      # 3.5 m away: a skeleton would be out of reach
      attack = %{id: "a", level: 30, x: 0.0, z: -3.5 * @u, heading: 0.0, item: item, heavy: false, target: m.id}
      {_mobs, hits, _} = Brain.melee(%{m.id => m}, attack, 0, fn -> 0.0 end)
      assert [%{hit: true}] = hits
    end
  end

  describe "rats, goblins and orcs (2026-10-28)" do
    test "each new kind spawns with its weapons and drops what it should" do
      for kind <- ~w(giant_rat plague_rat goblin goblin_archer orc orc_warlord) do
        m = Brain.spawn(point(kind), 0)
        assert m.hp > 0 and m.kind == kind
        k = Spawns.kind(kind)
        assert m.level in k.levels
        for {item_id, _chance, _qty} <- k.loot, do: assert(Items.get(item_id), "#{kind} loot #{item_id}")
        for {w, _} <- k.weapons, w != nil, do: assert(Items.get(w), "#{kind} weapon #{w}")
      end

      # rats bite, bare-pawed
      rat = Brain.spawn(point("giant_rat"), 0)
      assert rat.weapon == nil and rat.offhand == nil
      # an archer holds a bow, two-handed, so nothing in the other hand
      archer = Brain.spawn(point("goblin_archer"), 0)
      assert archer.weapon == "goblin_shortbow" and archer.offhand == nil
    end

    test "a goblin archer shoots from its reach instead of closing in" do
      a = point("goblin_archer") |> Brain.spawn(0) |> Map.merge(%{level: 3, h: 0.0, state: :chase, target: "p1", next_attack: 0})
      players = %{"p1" => player_at(14.0, %{level: 3})}
      {_m, events} = run(a, players, 0, 300)
      assert Enum.any?(events, &match?({:attack, _, "p1", _, _}, &1))
    end
  end

  describe "bows (2026-10-28)" do
    defp shot(mobs, attrs) do
      bow = Items.get("hunting_bow")
      attack = Map.merge(%{id: "archer", level: 10, x: 0.0, z: 0.0, heading: 0.0, item: bow, heavy: false, target: nil}, attrs)
      {_mobs, hits, _} = Brain.melee(mobs, attack, 0, fn -> 0.0 end)
      hits
    end

    defp at_m(id, x, z), do: %{id => point() |> Brain.spawn(0) |> Map.merge(%{id: id, x: x * @u, z: z * @u, level: 1, hp: 30, max_hp: 30})}

    test "an arrow reaches far, along where the archer looks, one thing at a time" do
      bow = Items.get("hunting_bow")
      assert Melee.ranged?(bow) and bow.hands == 2 and bow.reach >= 30
      assert [%{id: "far"}] = shot(at_m("far", 0.0, 28.0), %{})
      # 25 degrees off: outside the cone
      assert [] = shot(at_m("off", 28.0 * :math.sin(0.44), 28.0 * :math.cos(0.44)), %{})
      # ...unless it is the target, which counts within a wider cone
      assert [%{id: "off"}] = shot(at_m("off", 28.0 * :math.sin(0.44), 28.0 * :math.cos(0.44)), %{target: "off"})
      # out of reach
      assert [] = shot(at_m("gone", 0.0, 45.0), %{})
      # two in a line: only one arrow
      mobs = Map.merge(at_m("a", 0.0, 10.0), at_m("b", 0.0, 20.0))
      assert [%{id: "a"}] = shot(mobs, %{})
      assert Melee.sweep(bow) == {1, 30}
    end
  end
end
