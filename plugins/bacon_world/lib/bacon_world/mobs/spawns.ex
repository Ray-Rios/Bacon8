defmodule BaconWorld.Mobs.Spawns do
  @moduledoc """
  Where creatures live and what they are. Distances here are metres; the zone
  converts them to scene units (2.2 units per 1.8 m, like the characters).

  The village around the spawn point is safe: no creature goes within
  `safe_radius/0` of it, so a chase ends at the edge of town (EverQuest's guards,
  without the guards). The camps are well outside it.

  Each creature carries a weapon you can see in its hand, and that weapon is most
  of what it drops.

  Some kinds have more (all optional; the skeletons have none of them):

    * `radius` - metres from its middle to its hide (0.4 for a skeleton), for reach both ways
    * `leash` - how far a chase may drag it from home (default `leash/0`)
    * `moves` - `[{move, weight}]`: what its swings are ("bite", "claw", "tail"); the client
      plays the clip and the chat names it
    * `breath` - a cone of fire now and then: `every_ms`, `windup_ms` (the roar before it:
      step out of the cone), `range` (m), `half_arc_deg`, `dmg`
    * `drops` - `[{item_id, chance}]` on top of `loot`
    * `respawn_ms` - instead of `respawn_ms/0`
    * `boss`, `scale` - for the client (nameplate, model size)
    * `ranged` - it shoots (the goblin archers' bows): it holds off at its `reach` and the client
      draws an arrow for each attack
    * `aquatic` - lives in deep water and never leaves it (the Kraken); it reaches swimmers,
      and anyone on the shore within its reach, but not riders in the air
    * `roam` - wanders on its own, anywhere within this many metres of its spawn point (where it
      can go: for an aquatic kind, deep water), instead of milling about the spot
    * `specials` - big moves it winds up (the client shows the windup, `{:cast, id, move}`), one
      every `special_every_ms`, picked by weight among those whose `range` (m) reaches the target:
      `shape` `:target` (its chase target only), `:cone` (`half_arc_deg`) or `:ring` (all
      round), `windup_ms`, `busy_ms` (standing still), `dmg`, and what it does to whoever it
      hits: `root_ms` (held), `blind_ms` (ink), `pull_m` (dragged toward it), `squeeze`
      (`{ticks, dmg}`: more damage each second while it holds you)
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
    },
    # Rats (2026-10-28): quick, weak, in packs, a nuisance near town. Their own little rig
    # (rats-view.ts): no weapons; they bite.
    "giant_rat" => %{
      name: "a giant rat",
      levels: 1..2,
      hp: {9, 6},
      dmg: {1, 3},
      dly_ms: 1500,
      walk: 1.0,
      run: 4.4,
      aggro: 6.0,
      reach: 0.7,
      radius: 0.3,
      moves: [{"bite", 3}, {"claw", 1}],
      weapons: [{nil, 1}],
      offhand: [{nil, 1}],
      loot: [{"rat_tail", 0.7, 1..1}, {"rat_pelt", 0.35, 1..1}],
      coins: 0..4,
      weapon_drop: 0.0,
      respawn_ms: 45_000..80_000
    },
    "plague_rat" => %{
      name: "a plague rat",
      scale: 1.4,
      levels: 3..4,
      hp: {16, 8},
      dmg: {2, 5},
      dly_ms: 1600,
      walk: 1.1,
      run: 4.8,
      aggro: 8.0,
      reach: 0.85,
      radius: 0.4,
      moves: [{"bite", 3}, {"claw", 1}],
      weapons: [{nil, 1}],
      offhand: [{nil, 1}],
      loot: [{"rat_tail", 0.8, 1..1}, {"rat_pelt", 0.6, 1..2}],
      coins: 2..8,
      weapon_drop: 0.0
    },
    # Goblins (2026-10-28): small, green and spiteful, on the male's rig (B8_Goblin.glb plays his
    # packs). The archers keep their distance and shoot (`ranged`: they stop at their reach).
    "goblin" => %{
      name: "a goblin",
      levels: 2..4,
      hp: {15, 9},
      dmg: {2, 6},
      dly_ms: 1900,
      walk: 1.3,
      run: 4.1,
      aggro: 10.0,
      reach: 1.0,
      weapons: [{"rusty_dagger", 3}, {"bone_club", 2}, {"spiked_club", 2}, {"rusty_short_sword", 2}, {"rusty_hand_axe", 1}],
      offhand: [{nil, 5}, {"dented_buckler", 2}, {"rusty_dagger", 1}],
      loot: [{"goblin_ear", 0.6, 1..2}, {"tarnished_trinket", 0.08, 1..1}],
      coins: 6..26,
      weapon_drop: 0.7
    },
    "goblin_archer" => %{
      name: "a goblin archer",
      levels: 3..4,
      hp: {13, 8},
      dmg: {3, 7},
      dly_ms: 2400,
      walk: 1.3,
      run: 4.0,
      aggro: 16.0,
      reach: 16.0,
      ranged: true,
      weapons: [{"goblin_shortbow", 1}],
      offhand: [{nil, 1}],
      loot: [{"goblin_ear", 0.6, 1..2}, {"tarnished_trinket", 0.1, 1..1}],
      coins: 8..30,
      weapon_drop: 0.35
    },
    # Orcs (2026-10-28): big, grey-green, tusked, on the male's rig (B8_Orc.glb); harder than
    # anything outside the lairs. A warlord leads the warband at its hold.
    "orc" => %{
      name: "an orc",
      levels: 5..7,
      hp: {38, 15},
      dmg: {5, 12},
      dly_ms: 2500,
      walk: 1.2,
      run: 3.9,
      aggro: 12.0,
      reach: 1.4,
      radius: 0.5,
      weapons: [{"orcish_cleaver", 4}, {"spiked_club", 2}, {"orcish_greataxe", 2}, {"notched_battle_axe", 1}, {"cracked_maul", 1}],
      offhand: [{nil, 3}, {"cracked_kite_shield", 1}, {"dented_buckler", 1}],
      loot: [{"orc_tusk", 0.55, 1..2}, {"orcish_war_belt", 0.1, 1..1}, {"tarnished_trinket", 0.1, 1..1}],
      coins: 25..80,
      weapon_drop: 0.6
    },
    "orc_warlord" => %{
      name: "an orc warlord",
      scale: 1.08,
      levels: 9..10,
      hp: {210, 30},
      dmg: {9, 18},
      dly_ms: 2700,
      walk: 1.2,
      run: 4.0,
      aggro: 14.0,
      reach: 1.6,
      radius: 0.55,
      leash: 40.0,
      weapons: [{"orcish_greataxe", 1}],
      offhand: [{nil, 1}],
      loot: [{"orc_tusk", 1.0, 2..3}, {"orcish_war_belt", 0.5, 1..1}],
      drops: [{"ashwood_longbow", 0.2}],
      coins: 150..300,
      weapon_drop: 0.5,
      respawn_ms: 360_000..540_000
    },
    # The boss (2026-10-24): a red dragon in its lair (north-east of the village; on Crater Lake,
    # the plateau north-east of the crater). Big enough
    # that you hit its flank, not its middle; it bites and claws what is in front, lashes its
    # tail, and every 13-18 s rears back and breathes fire in a cone (a group spreads out;
    # anyone can step out of the cone during the roar).
    "baconator" => %{
      name: "Baconator",
      boss: true,
      scale: 0.8,
      levels: 12..12,
      hp: {1400, 50},
      dmg: {12, 22},
      dly_ms: 2900,
      walk: 2.4,
      run: 6.8,
      aggro: 24.0,
      reach: 5.0,
      radius: 3.4,
      leash: 55.0,
      moves: [{"bite", 5}, {"claw", 3}, {"tail", 2}],
      breath: %{every_ms: 13_000..18_000, windup_ms: 1_050, range: 17.0, half_arc_deg: 32.0, dmg: {18, 32}},
      weapons: [{nil, 1}],
      offhand: [{nil, 1}],
      loot: [{"dragon_scale", 1.0, 2..5}, {"baconator_fang", 0.45, 1..2}],
      drops: [{"emberforged_longsword", 0.35}, {"dragonbone_greataxe", 0.25}, {"scaleplate_shield", 0.25}],
      coins: 300..700,
      weapon_drop: 0.0,
      respawn_ms: 1_200_000..1_800_000
    },
    # The second boss (2026-10-27): the Kraken, in the deep middle of Crater Lake. It doesn't leave
    # the deep water; swim out to it, or fight it from a boat... or from the shore, if it follows you
    # there. At 2.1 times the model's size (2026-10-27: half as big again) its mantle towers 23 m over the
    # water; it roams the deep water on its own; its arms lash and slam whatever is in reach (16 m), and every 9-13 s it does something
    # worse: snatches its target with a hunting tentacle (held fast and squeezed), sprays ink (a
    # cone: blind), or churns the lake into a maelstrom (everyone round it is battered and dragged
    # in - the long windup is the time to swim clear).
    "kraken" => %{
      name: "the Kraken",
      boss: true,
      scale: 2.1,
      aquatic: true,
      levels: 16..16,
      hp: {2600, 80},
      dmg: {16, 28},
      dly_ms: 3100,
      walk: 4.0,
      run: 11.0,
      aggro: 80.0,
      reach: 16.0,
      radius: 9.5,
      leash: 320.0,
      # it roams the deep water on its own, anywhere within this of where it spawned (m)
      roam: 300.0,
      moves: [{"lash", 5}, {"slam", 3}],
      special_every_ms: 9_000..13_000,
      specials: [
        %{move: "grab", weight: 4, shape: :target, range: 33.0, windup_ms: 700, busy_ms: 1_200, dmg: {10, 16}, root_ms: 3_500, squeeze: {3, {8, 14}}},
        %{move: "ink", weight: 3, shape: :cone, range: 39.0, half_arc_deg: 38.0, windup_ms: 650, busy_ms: 900, dmg: {4, 8}, blind_ms: 5_000},
        %{move: "maelstrom", weight: 3, shape: :ring, range: 36.0, windup_ms: 1_900, busy_ms: 2_600, dmg: {20, 34}, pull_m: 9.0}
      ],
      weapons: [{nil, 1}],
      offhand: [{nil, 1}],
      loot: [{"kraken_ink_sac", 1.0, 1..3}, {"abyssal_hook", 0.9, 2..6}, {"kraken_beak", 0.4, 1..1}],
      drops: [{"abyssal_harpoon", 0.3}, {"krakenfang_cutlass", 0.3}, {"barnacled_buckler", 0.25}],
      coins: 600..1200,
      weapon_drop: 0.0,
      respawn_ms: 1_500_000..2_100_000
    }
  }

  # By the village: the three beginners' camps (both worlds).
  @near [
    %{id: "graveyard", name: "the Old Graveyard", x: 52.0, z: -48.0, radius: 9.0, theme: "graveyard", mobs: [{"decaying_skeleton", 6}]},
    %{id: "chapel", name: "the Ruined Chapel", x: -6.0, z: 64.0, radius: 10.0, theme: "ruins", mobs: [{"decaying_skeleton", 2}, {"skeleton", 4}]},
    %{id: "barrow", name: "the Barrow", x: -66.0, z: -14.0, radius: 10.0, theme: "barrow", mobs: [{"skeleton", 2}, {"skeleton_warrior", 3}]},
    # 2026-10-28: rats on the edge of town, between the graveyard and the chapel
    %{id: "warren", name: "the Rat Warren", x: 62.0, z: 30.0, radius: 7.0, theme: "warren", mobs: [{"giant_rat", 5}]}
  ]

  # On the round island (no terrain) the goblins camp on its western shore.
  @island_goblins [%{id: "goblin_camp", name: "the Goblin Camp", x: -96.0, z: 72.0, radius: 9.0, theme: "goblin", mobs: [{"goblin", 3}, {"goblin_archer", 1}]}]

  # The round island (no terrain): Baconator just north-east of the village.
  @island @near ++ @island_goblins ++ [%{id: "lair", name: "Baconator's Lair", x: 92.0, z: 42.0, radius: 16.0, theme: "lair", mobs: [{"baconator", 1}]}]

  # Crater Lake (BaconWorld.Terrain, 2026-10-26): camps out across the zone, harder the further from
  # town, each on a flat, dry spot picked from the heightfield (slope under ~16 degrees within 18 m,
  # 60 m from water, 150 m from the map's edge). Baconator's lair is on the high plateau north-east
  # of the crater, ~2 km from town (nothing near the crater itself is flat enough). For the time
  # being: the owner will place creatures in game (BACON_WORLD.md, "World building in game").
  @crater_lake @near ++
                 [
                   %{id: "north_graves", name: "the North Graves", x: -26.0, z: -220.0, radius: 9.0, theme: "graveyard", mobs: [{"decaying_skeleton", 5}]},
                   %{id: "shore_ruins", name: "the Shore Ruins", x: -222.0, z: 72.0, radius: 10.0, theme: "ruins", mobs: [{"decaying_skeleton", 2}, {"skeleton", 3}]},
                   %{id: "east_barrow", name: "the East Barrow", x: 516.0, z: 100.0, radius: 10.0, theme: "barrow", mobs: [{"skeleton", 3}, {"skeleton_warrior", 2}]},
                   %{id: "hollow_graves", name: "the Hollow Graves", x: 52.0, z: -522.0, radius: 10.0, theme: "graveyard", mobs: [{"skeleton", 5}]},
                   %{id: "plateau_ruins", name: "the Plateau Ruins", x: 672.0, z: -488.0, radius: 11.0, theme: "ruins", mobs: [{"skeleton", 2}, {"skeleton_warrior", 3}]},
                   %{id: "crater_road", name: "the Crater Road Barrow", x: 108.0, z: -818.0, radius: 10.0, theme: "barrow", mobs: [{"skeleton", 2}, {"skeleton_warrior", 3}]},
                   %{id: "high_ruins", name: "the High Ruins", x: 988.0, z: -82.0, radius: 11.0, theme: "ruins", mobs: [{"skeleton_warrior", 5}]},
                   %{id: "west_barrow", name: "the Western Barrow", x: -1266.0, z: -148.0, radius: 10.0, theme: "barrow", mobs: [{"skeleton_warrior", 5}]},
                   # 2026-10-28: rats, goblins and orcs (flat, dry spots from the heightfield, like the rest)
                   %{id: "rat_nest", name: "the Rat Nest", x: 128.0, z: 112.0, radius: 7.0, theme: "warren", mobs: [{"giant_rat", 6}]},
                   %{id: "drowned_cellars", name: "the Drowned Cellars", x: -160.0, z: -696.0, radius: 9.0, theme: "warren", mobs: [{"plague_rat", 5}, {"giant_rat", 2}]},
                   %{id: "goblin_thicket", name: "the Goblin Thicket", x: -152.0, z: -128.0, radius: 9.0, theme: "goblin", mobs: [{"goblin", 3}, {"goblin_archer", 1}]},
                   %{id: "goblin_camp", name: "the Goblin Camp", x: 104.0, z: -272.0, radius: 11.0, theme: "goblin", mobs: [{"goblin", 4}, {"goblin_archer", 2}]},
                   %{id: "orc_warcamp", name: "the Orc Warcamp", x: 608.0, z: -360.0, radius: 12.0, theme: "orc", mobs: [{"orc", 4}, {"goblin_archer", 2}]},
                   %{id: "warlords_hold", name: "the Warlord's Hold", x: 888.0, z: -200.0, radius: 12.0, theme: "orc", mobs: [{"orc", 3}, {"orc_warlord", 1}]},
                   %{id: "lair", name: "Baconator's Lair", x: 930.0, z: -1756.0, radius: 16.0, theme: "lair", mobs: [{"baconator", 1}]},
                   # the deep middle of the crater's lake (~317 m of water under it)
                   %{id: "kraken_deep", name: "the Kraken's Deep", x: -147.0, z: -1947.0, radius: 0.0, theme: "deep", mobs: [{"kraken", 1}]}
                 ]

  # Metres.
  @safe_radius 40.0
  @leash 30.0

  def kinds, do: @kinds
  def kind(id), do: Map.fetch!(@kinds, id)
  @doc "The zone's camps: Crater Lake's when its terrain is loaded, else the round island's."
  def camps, do: if(BaconWorld.Terrain.loaded(), do: @crater_lake, else: @island)
  def safe_radius, do: @safe_radius
  def leash, do: @leash

  @doc "Seconds a corpse lies before it decays; whoever killed it may loot it alone for the first minute."
  def corpse_ms, do: 240_000
  def loot_lock_ms, do: 60_000
  def respawn_ms, do: 70_000..110_000

  @doc "How long a kind lies dead before it comes back."
  def respawn_ms(kind_id), do: Map.get(kind(kind_id), :respawn_ms, respawn_ms())

  @doc "Metres from a creature's middle to its hide."
  def radius(kind_id), do: Map.get(kind(kind_id), :radius, 0.4)

  @doc "How far a chase may take it from home, metres."
  def leash(kind_id), do: Map.get(kind(kind_id), :leash, @leash)

  @doc "True for a creature of the deep water (it never leaves it)."
  def aquatic?(kind_id), do: Map.has_key?(@kinds, kind_id) and Map.get(kind(kind_id), :aquatic, false) == true

  @doc "True for a boss (roots last a third as long on one)."
  def boss?(kind_id), do: Map.has_key?(@kinds, kind_id) and Map.get(kind(kind_id), :boss, false) == true

  @doc """
  Every spawn point: `%{id, camp, kind, x, z}` in metres, spread over the camp on
  a sunflower pattern so they don't stand in a line. `except`: camps that are placements now
  (`BaconWorld.Building.ensure_seeded/1`), whose creatures the placements spawn instead.
  """
  def points(except \\ []) do
    golden = :math.pi() * (3 - :math.sqrt(5))

    camps()
    |> Enum.reject(&(&1.id in except))
    |> Enum.flat_map(fn camp ->
      kinds = Enum.flat_map(camp.mobs, fn {kind, count} -> List.duplicate(kind, count) end)
      total = length(kinds)

      kinds
      |> Enum.with_index()
      |> Enum.map(fn {kind, n} ->
        r = if total == 1, do: 0.0, else: camp.radius * 0.8 * :math.sqrt((n + 0.5) / total)
        a = n * golden
        %{id: "#{camp.id}:#{n}", camp: camp.id, kind: kind, x: camp.x + r * :math.cos(a), z: camp.z + r * :math.sin(a)}
      end)
    end)
  end

  @doc "What the client needs to dress the camps."
  def camps_payload(units_per_metre, placed \\ []) do
    # `placed`: camps whose pieces are placements now: the client draws only their ground
    Enum.map(camps(), fn c -> %{id: c.id, name: c.name, theme: c.theme, x: c.x * units_per_metre, z: c.z * units_per_metre, radius: c.radius * units_per_metre, placed: c.id in placed} end)
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
