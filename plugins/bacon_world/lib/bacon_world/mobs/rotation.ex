defmodule BaconWorld.Mobs.Rotation do
  @moduledoc """
  Which creature a spawn point puts up next (2026-11-03, the camp system: `BaconWorld.Mobs.Camps`).

  A plain point (`%{kind: "skeleton"}`: the code's camps, a placed `mob:` spawn) always spawns its
  kind, as before. A managed camp's point carries a `table` of `{kind, weight}` and a `mode`:

    * `"random"` (the default) - a weighted pick each time it respawns
    * `"cycle"` - each kind of the table in turn (weights ignored)
    * `"placeholder"` - EverQuest's placeholders: the table's kinds stand in until the point's
      `rare` comes up

  `rare` (`%{kind, chance, cooldown_ms}`) works with every mode: on any respawn, once `cooldown_ms`
  have passed since it last rose here, the rare kind takes the point with `chance`.

  `window` (`"day"`, `"night"` or nil) keeps a point empty outside its part of the day. An in-game
  day is one real hour on the wall clock, the same one the client's sky uses (`sky-system.ts`:
  `Date.now() % 1 h`; night is the dark stretch either side of midnight).

  `rot` is a point's memory between spawns (`%{i, rare_at}`), kept on the creature
  (`BaconWorld.Mobs.Brain.spawn/3`). Times in `pick/3` are the zone's clock (monotonic ms).
  """

  alias BaconWorld.Mobs.Spawns

  @day_ms 3_600_000
  # sky-system.ts: dark from 0.80 to 0.20, with the colours changing either side
  @night_from 0.78
  @night_to 0.24

  def modes, do: ~w(random cycle placeholder)
  def windows, do: [nil, "day", "night"]

  @doc "A fresh memory."
  def fresh, do: %{i: 0, rare_at: nil}

  @doc "The kind to spawn at `point` and the memory after it: `{kind_id, rot}`."
  def pick(point, rot, now)

  def pick(%{table: [_ | _] = table} = point, rot, now) do
    rot = rot || fresh()
    # a monster type deleted since the camp was made is skipped
    known = Spawns.kinds()

    case {rare(point, rot, now), Enum.filter(table, fn {k, _w} -> Map.has_key?(known, k) end)} do
      {{:ok, kind}, _} -> {kind, %{rot | rare_at: now}}
      {:no, []} -> {point.kind, rot}
      {:no, ok} -> base(point[:mode] || "random", ok, rot)
    end
  end

  def pick(%{kind: kind}, rot, _now), do: {kind, rot}

  defp rare(%{rare: %{kind: k, chance: c} = r}, rot, now) when is_binary(k) and is_number(c) and c > 0 do
    cooled = is_nil(rot.rare_at) or now - rot.rare_at >= (r[:cooldown_ms] || 0)
    if cooled and Map.has_key?(Spawns.kinds(), k) and :rand.uniform() < c, do: {:ok, k}, else: :no
  end

  defp rare(_point, _rot, _now), do: :no

  defp base("cycle", table, rot) do
    {kind, _w} = Enum.at(table, rem(rot.i, length(table)))
    {kind, %{rot | i: rot.i + 1}}
  end

  defp base(_mode, table, rot), do: {Spawns.weighted(table), rot}

  @doc "Where in the in-game day wall-clock `ms` falls: 0.0 midnight, 0.25 dawn, 0.5 noon, 0.75 dusk."
  def phase(wall_ms) when is_integer(wall_ms), do: Integer.mod(wall_ms, @day_ms) / @day_ms

  @doc "True at night."
  def night?(wall_ms) do
    p = phase(wall_ms)
    p >= @night_from or p < @night_to
  end

  @doc "True when `point` may hold a creature at wall-clock `wall_ms`."
  def open?(%{window: "night"}, wall_ms), do: night?(wall_ms)
  def open?(%{window: "day"}, wall_ms), do: not night?(wall_ms)
  def open?(_point, _wall_ms), do: true

  @doc "The wall clock in milliseconds (what `open?/2` takes)."
  def wall_ms, do: System.os_time(:millisecond)
end
