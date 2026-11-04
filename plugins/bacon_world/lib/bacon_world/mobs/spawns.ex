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

  # The creature types (name, levels, hp, damage, speeds, weapons, loot...) are rows of
  # bacon_world_defs, kind "monster" (BaconWorld.Defs, 2026-11-02: owner "move everything into the
  # DB"), edited on /admin/bacon_world/database; they were a map here until then
  # (priv/seed/monsters.json is that map, exported).

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

  def kinds, do: BaconWorld.Defs.map("monster")
  def kind(id), do: Map.fetch!(kinds(), id)

  @ranks ~w(normal elite rare boss)

  @doc "The ranks a monster type may have (the Bestiary page)."
  def ranks, do: @ranks

  @doc """
  A kind's rank (2026-11-03): its `rank` ("normal", "elite", "rare" or "boss"), else "boss"
  for a kind with `boss: true`, else "normal".
  """
  def rank(kind) when is_map(kind) do
    case kind[:rank] do
      r when r in @ranks -> r
      _ -> if kind[:boss] == true, do: "boss", else: "normal"
    end
  end

  def rank(_), do: "normal"

  @doc "Experience a rank is worth against the formula (World tuning `rank_<rank>_xp_mult`; normal: 1)."
  def rank_xp_mult("normal"), do: 1.0

  def rank_xp_mult(rank) when rank in @ranks do
    case BaconWorld.Tuning.get("rank_#{rank}_xp_mult") do
      n when is_number(n) -> n * 1.0
      _ -> 1.0
    end
  end

  def rank_xp_mult(_), do: 1.0
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
  def aquatic?(kind_id), do: Map.has_key?(kinds(), kind_id) and Map.get(kind(kind_id), :aquatic, false) == true

  @doc "True for a boss (roots last a third as long on one)."
  def boss?(kind_id), do: Map.has_key?(kinds(), kind_id) and Map.get(kind(kind_id), :boss, false) == true

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
