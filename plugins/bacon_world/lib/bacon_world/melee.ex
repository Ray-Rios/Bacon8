defmodule BaconWorld.Melee do
  @moduledoc """
  Melee numbers, pure functions (the zone and the LiveView call them).

  A swing hits what is in front of the attacker, Black Desert style: within the
  weapon's reach and an arc around where the attacker looks. One-handed weapons
  and fists hit one creature (the targeted one if it is in the arc, else the
  nearest); two-handers sweep up to three.

  Damage is EverQuest-shaped: a roll between 40% and 100% of the weapon's DMG,
  plus a level bonus; 6% of hits are critical (x1.75). A heavy swing (a
  two-hander's right button) does x1.5 and takes x1.4 as long.

  Headings are yaw angles: 0 faces +Z, and a character facing `h` looks along
  `(sin h, cos h)`.
  """

  @crit_chance 0.06
  @crit_mult 1.75
  @heavy_dmg 1.5
  @heavy_dly 1.4
  @ranged_arc 30
  @ranged_target_arc 60

  @doc "Milliseconds between swings with `item` (EverQuest DLY is tenths of a second)."
  def delay_ms(item, heavy \\ false), do: round(item.dly * 100 * if(heavy, do: @heavy_dly, else: 1.0))

  @doc "Chance to hit, from the attacker's and defender's levels."
  def hit_chance(attacker_level, defender_level),
    do: (0.88 + 0.03 * (attacker_level - defender_level)) |> max(0.4) |> min(0.97)

  @doc "`{damage, crit?}` for a hit with `item`. `rand` returns a float in [0, 1)."
  def roll_damage(item, attacker_level, heavy \\ false, rand \\ &:rand.uniform/0) do
    hi = max(1, item.dmg)
    lo = max(1, round(hi * 0.4))
    base = lo + min(hi - lo, trunc(rand.() * (hi - lo + 1)))
    dmg = base + div(max(attacker_level, 1), 3)
    dmg = if heavy, do: round(dmg * @heavy_dmg), else: dmg
    if rand.() < @crit_chance, do: {round(dmg * @crit_mult), true}, else: {dmg, false}
  end

  @doc """
  How far (metres, centre to centre) a swing reaches another player: the weapon's
  reach, both bodies, and slack for positions up to 100 ms old.
  """
  def pvp_reach(item), do: item.reach + 2 * 0.35 + 0.8

  @doc """
  How many creatures one swing can hit, and the arc (degrees) it covers. Narrow
  enough that you have to face what you hit (2026-10-23: two-handers swept 150
  degrees and hit players nearly beside them).
  """
  def sweep(%{ranged: true}), do: {1, @ranged_arc}
  def sweep(item) do
    if item.hands == 2, do: {3, 110}, else: {1, 90}
  end

  @doc """
  A bow (2026-10-28) shoots one arrow at one thing: whatever lies within a narrow cone (#{30}
  degrees) along where the archer looks, out to the bow's reach; the selected target counts
  within a wider one (`ranged_target_arc/0`), so a targeted creature is hit when the archer
  faces it roughly. Arrows never run out.
  """
  def ranged?(%{ranged: true}), do: true
  def ranged?(_), do: false

  @doc "The cone (degrees) inside which a bow's selected target is hit."
  def ranged_target_arc, do: @ranged_target_arc

  # Up close (inside this share of the reach) the arc widens to this half-angle, so
  # something pressed against your side still counts, but never anything behind you.
  @close_share 0.2
  @close_half_arc 80

  @doc """
  True when `{tx, tz}` is within `reach` of `{ax, az}` and inside an arc of
  `arc_deg` around `heading`. Right next to the attacker the arc widens to
  #{2 * @close_half_arc} degrees; nothing behind the attacker ever counts.
  """
  def in_arc?({ax, az}, heading, {tx, tz}, reach, arc_deg) do
    dx = tx - ax
    dz = tz - az
    dist = :math.sqrt(dx * dx + dz * dz)

    cond do
      dist > reach -> false
      dist < 1.0e-6 -> true
      true ->
        half = if dist < @close_share * reach, do: max(arc_deg / 2, @close_half_arc), else: arc_deg / 2
        angle_between({:math.sin(heading), :math.cos(heading)}, {dx / dist, dz / dist}) <= half
    end
  end

  # Degrees between two unit vectors.
  defp angle_between({ax, az}, {bx, bz}) do
    dot = (ax * bx + az * bz) |> max(-1.0) |> min(1.0)
    :math.acos(dot) * 180 / :math.pi()
  end

  @doc "The heading from `from` toward `to`."
  def heading_to({fx, fz}, {tx, tz}), do: :math.atan2(tx - fx, tz - fz)
end
