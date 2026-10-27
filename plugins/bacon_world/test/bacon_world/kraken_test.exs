defmodule BaconWorld.KrakenTest do
  # The Kraken (2026-10-27): a boss of the deep water with specials, and the mounts' attacks.
  # Pure (BaconWorld.Mobs.Brain, BaconWorld.Mounts): no database, no terrain (so it never moves).
  use ExUnit.Case, async: true

  alias BaconWorld.{Items, Mounts}
  alias BaconWorld.Mobs.{Brain, Spawns}

  @u 2.2 / 1.8

  setup do
    :rand.seed(:exsss, {7, 7, 7})
    :ok
  end

  # well away from the safe village round the origin
  @kx 200.0
  defp kpoint, do: %{id: "kraken_deep:0", camp: "kraken_deep", kind: "kraken", x: @kx, z: 0.0}

  # facing +z (heading 0)
  defp kraken(attrs \\ %{}), do: kpoint() |> Brain.spawn(0) |> Map.merge(%{h: 0.0, x: @kx * @u, z: 0.0, home: {@kx * @u, 0.0}}) |> Map.merge(attrs)

  # `m` metres in front of it (+z), `side` metres to the side
  defp at(m, side \\ 0.0, attrs \\ %{}), do: Map.merge(%{x: (@kx + side) * @u, y: 0.0, z: m * @u, dead: false, level: 14, swimming: true}, attrs)

  defp run(mob, players, from, ms) do
    Enum.reduce(0..div(ms, 100), {mob, []}, fn i, {m, evs} ->
      {m2, e} = Brain.tick(m, players, from + i * 100, 0.1, kpoint())
      {m2, evs ++ e}
    end)
  end

  test "it is a boss of the deep water, in its own camp on Crater Lake only" do
    k = Spawns.kind("kraken")
    assert k.boss and k.aquatic
    assert Spawns.aquatic?("kraken")
    refute Spawns.aquatic?("baconator")
    refute Enum.any?(Spawns.points(), &(&1.kind == "kraken"))
    assert Brain.view(kraken()).boss
  end

  test "it goes for swimmers (other creatures leave them alone), but not riders in the air" do
    {m, evs} = run(kraken(), %{"swimmer" => at(20.0)}, 0, 500)
    assert m.state == :chase
    assert {:aggro, "kraken_deep:0", "swimmer"} in evs

    {m, evs} = run(kraken(), %{"flyer" => at(20.0, 0.0, %{swimming: false, y: 12.0 * @u})}, 0, 1_000)
    assert m.state != :chase
    refute Enum.any?(evs, &match?({:aggro, _, _}, &1))
  end

  test "its arms lash and slam whoever is within reach" do
    {_m, evs} = run(kraken(%{state: :chase, target: "a", next_special: 1_000_000}), %{"a" => at(8.0)}, 0, 12_000)
    moves = for {:attack, _, "a", _, _, move} <- evs, do: move
    assert moves != []
    assert Enum.all?(moves, &(&1 in ["lash", "slam"]))
  end

  test "a special is wound up first (everyone sees it), then lands with what it does" do
    players = %{"a" => at(10.0)}
    m = kraken(%{state: :chase, target: "a", next_special: 0, next_attack: 1_000_000})
    {m, evs} = Brain.tick(m, players, 100, 0.1, kpoint())
    assert [{:cast, "kraken_deep:0", move}] = Enum.filter(evs, &match?({:cast, _, _}, &1))
    assert move in ["grab", "ink", "maelstrom"]
    assert m.special.move == move
    {_m, evs} = run(m, players, 200, 2_500)
    landed = for {:attack, _, "a", _, _, ^move, fx} <- evs, do: fx
    assert [fx] = landed
    assert is_map(fx)
  end

  test "maelstrom: everyone round it is dragged toward it, behind it too; ink is a cone in front" do
    spec = fn move -> Enum.find(Spawns.kind("kraken").specials, &(&1.move == move)) end
    players = %{"front" => at(12.0), "behind" => at(-12.0), "far" => at(40.0)}

    m = kraken(%{state: :chase, target: "front", special: %{move: "maelstrom", at: 0, target: "front"}, next_special: 1_000_000, next_attack: 1_000_000})
    {_m, evs} = Brain.tick(m, players, 100, 0.1, kpoint())
    hit = for {:attack, _, id, _, _, "maelstrom", fx} <- evs, do: {id, fx}
    assert Enum.sort(for {id, _} <- hit, do: id) == ["behind", "front"]
    assert Enum.all?(hit, fn {_id, fx} -> fx.pull == [Float.round(@kx * @u, 2), 0.0] and fx.pull_m == spec.("maelstrom").pull_m end)

    m = kraken(%{state: :chase, target: "front", special: %{move: "ink", at: 0, target: "front"}, next_special: 1_000_000, next_attack: 1_000_000})
    {_m, evs} = Brain.tick(m, players, 100, 0.1, kpoint())
    inked = for {:attack, _, id, _, _, "ink", _fx} <- evs, do: id
    assert inked == ["front"]
  end

  test "grab: only its target, held fast, then squeezed each second while in reach" do
    :rand.seed(:exsss, {1, 1, 1})
    players = %{"a" => at(15.0, 0.0, %{level: 1}), "b" => at(15.0, 1.0)}
    m = kraken(%{state: :chase, target: "a", special: %{move: "grab", at: 0, target: "a"}, next_special: 1_000_000, next_attack: 1_000_000, level: 40})
    {m, evs} = Brain.tick(m, players, 100, 0.1, kpoint())
    assert [{:attack, _, "a", true, dmg, "grab", %{root_ms: 3_500}}] = Enum.filter(evs, &match?({:attack, _, _, _, _, "grab", _}, &1))
    assert dmg > 0
    assert m.squeeze.target == "a"
    {m, evs} = run(m, players, 200, 4_500)
    squeezes = for {:attack, _, "a", true, d, "squeeze"} <- evs, do: d
    assert length(squeezes) == 3
    assert m.squeeze == nil
  end

  test "it leaves loot from its own table" do
    k = Spawns.kind("kraken")
    for {id, _, _} <- k.loot, do: assert(Items.get(id), id)
    for {id, _} <- k.drops, do: assert(Items.get(id), id)
  end

  describe "mounts" do
    test "every mount has two moves; the Kraken swims and doesn't fly" do
      for m <- Mounts.all() do
        assert %{move: _} = Mounts.attack(m, "left")
        assert %{move: _} = Mounts.attack(m, "right")
      end

      k = Mounts.get("abyssal_kraken")
      assert k.model == "kraken" and k.swims and not k.flies
      assert k.swim_speed > k.ground_speed
      assert Mounts.attack(Mounts.get("ember_drake"), "right").move == "fire"
      spec = Mounts.catalog_payload()["abyssal_kraken"]
      assert spec.attacks["right"].move == "maelstrom"
      refute Map.has_key?(spec.attacks["right"], :dmg)
    end

    test "a dragon's fire breath burns several creatures in its cone, not behind it" do
      move = Mounts.attack(Mounts.get("ember_drake"), "right")
      item = Mounts.attack_item(move)
      mk = fn id, x, z -> %{(Brain.spawn(%{id: id, camp: "t", kind: "skeleton", x: 0.0, z: 0.0}, 0)) | x: x * @u, z: z * @u, hp: 500, max_hp: 500, level: 1} end
      mobs = Map.new([mk.("a", 0.0, 4.0), mk.("b", 1.5, 7.0), mk.("c", 0.0, -5.0)], &{&1.id, &1})
      attack = %{id: "rider", level: 10, x: 0.0, z: 0.0, heading: 0.0, item: item, heavy: false, target: nil, sweep: {move.targets, move.arc}}
      {_mobs, hits, _} = Brain.melee(mobs, attack, 0, fn -> 0.0 end)
      assert Enum.sort(Enum.map(hits, & &1.id)) == ["a", "b"]
    end
  end
end
