defmodule BaconWorld.Mobs.Spawns do
  @moduledoc """
  Where creatures live and what they are. Distances here are metres; the zone
  converts them to scene units (2.2 units per 1.8 m, like the characters).

  The village around the spawn point is safe: no creature goes within
  `safe_radius/0` of it, so a chase ends at the edge of town (EverQuest's guards,
  without the guards). The camps are well outside it.

  Each creature carries a weapon you can see in its hand, and that weapon is most
  of what it drops.
  """

  @kinds %{
    "decaying_skeleton" => %{
      name: "a decaying skeleton",
      levels: 1..2,
      hp: {14, 9},
      dmg: {1, 4},
      dly_ms: 2300,
      walk: 1.1,
      run: 3.3,
      aggro: 8.0,
      reach: 1.25,
      weapons: [{"bone_club", 3}, {"rusty_dagger", 2}, {"rusty_short_sword", 2}, {nil, 1}],
      offhand: [{nil, 7}, {"dented_buckler", 1}],
      loot: [{"bone_chips", 0.6, 1..3}, {"skull_fragment", 0.12, 1..1}],
      coins: 2..14,
      weapon_drop: 0.9
    },
    "skeleton" => %{
      name: "a skeleton",
      levels: 2..3,
      hp: {18, 11},
      dmg: {2, 6},
      dly_ms: 2200,
      walk: 1.2,
      run: 3.6,
      aggro: 9.0,
      reach: 1.3,
      weapons: [
        {"rusty_scimitar", 3},
        {"rusty_cutlass", 2},
        {"rusty_hand_axe", 3},
        {"dented_mace", 2},
        {"rusty_short_sword", 2},
        {"splintered_spear", 2}
      ],
      offhand: [{nil, 5}, {"dented_buckler", 2}, {"rusty_dagger", 1}],
      loot: [{"bone_chips", 0.7, 1..4}, {"skull_fragment", 0.2, 1..2}],
      coins: 8..30,
      weapon_drop: 0.85
    },
    "skeleton_warrior" => %{
      name: "a skeleton warrior",
      levels: 3..5,
      hp: {24, 13},
      dmg: {3, 9},
      dly_ms: 2500,
      walk: 1.2,
      run: 3.8,
      aggro: 10.0,
      reach: 1.5,
      weapons: [
        {"rusty_two_handed_sword", 3},
        {"notched_battle_axe", 3},
        {"cracked_maul", 2},
        {"rusty_halberd", 2},
        {"pitted_longsword", 2},
        {"cracked_morning_star", 2},
        {"pitted_war_hammer", 2}
      ],
      offhand: [{nil, 3}, {"cracked_kite_shield", 2}, {"dented_buckler", 1}],
      loot: [{"bone_chips", 0.8, 2..5}, {"skull_fragment", 0.35, 1..2}],
      coins: 25..80,
      weapon_drop: 0.8
    }
  }

  @camps [
    %{id: "graveyard", name: "the Old Graveyard", x: 52.0, z: -48.0, radius: 9.0, theme: "graveyard", mobs: [{"decaying_skeleton", 6}]},
    %{id: "chapel", name: "the Ruined Chapel", x: -6.0, z: 64.0, radius: 10.0, theme: "ruins", mobs: [{"decaying_skeleton", 2}, {"skeleton", 4}]},
    %{id: "barrow", name: "the Barrow", x: -66.0, z: -14.0, radius: 10.0, theme: "barrow", mobs: [{"skeleton", 2}, {"skeleton_warrior", 3}]}
  ]

  # Metres.
  @safe_radius 40.0
  @leash 30.0

  def kinds, do: @kinds
  def kind(id), do: Map.fetch!(@kinds, id)
  def camps, do: @camps
  def safe_radius, do: @safe_radius
  def leash, do: @leash

  @doc "Seconds a corpse lies before it decays; whoever killed it may loot it alone for the first minute."
  def corpse_ms, do: 240_000
  def loot_lock_ms, do: 60_000
  def respawn_ms, do: 70_000..110_000

  @doc """
  Every spawn point: `%{id, camp, kind, x, z}` in metres, spread over the camp on
  a sunflower pattern so they don't stand in a line.
  """
  def points do
    golden = :math.pi() * (3 - :math.sqrt(5))

    Enum.flat_map(@camps, fn camp ->
      kinds = Enum.flat_map(camp.mobs, fn {kind, count} -> List.duplicate(kind, count) end)
      total = length(kinds)

      kinds
      |> Enum.with_index()
      |> Enum.map(fn {kind, n} ->
        r = camp.radius * 0.8 * :math.sqrt((n + 0.5) / total)
        a = n * golden
        %{id: "#{camp.id}:#{n}", camp: camp.id, kind: kind, x: camp.x + r * :math.cos(a), z: camp.z + r * :math.sin(a)}
      end)
    end)
  end

  @doc "What the client needs to dress the camps."
  def camps_payload(units_per_metre) do
    Enum.map(@camps, fn c -> %{id: c.id, name: c.name, theme: c.theme, x: c.x * units_per_metre, z: c.z * units_per_metre, radius: c.radius * units_per_metre} end)
  end

  @doc "Picks from `[{value, weight}]`."
  def weighted(list) do
    total = Enum.sum(Enum.map(list, &elem(&1, 1)))
    pick = :rand.uniform() * total

    Enum.reduce_while(list, 0.0, fn {value, w}, acc ->
      if pick < acc + w, do: {:halt, {:ok, value}}, else: {:cont, acc + w}
    end)
    |> case do
      {:ok, value} -> value
      _ -> list |> List.last() |> elem(0)
    end
  end
end
