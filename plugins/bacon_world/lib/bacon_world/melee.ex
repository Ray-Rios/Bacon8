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

  @doc "How many creatures one swing can hit, and the arc (degrees) it covers."
  def sweep(item) do
    if item.hands == 2, do: {3, 150}, else: {1, 110}
  end

  @doc """
  True when `{tx, tz}` is within `reach` of `{ax, az}` and inside an arc of
  `arc_deg` around `heading`. Something right on top of the attacker always counts.
  """
  def in_arc?({ax, az}, heading, {tx, tz}, reach, arc_deg) do
    dx = tx - ax
    dz = tz - az
    dist = :math.sqrt(dx * dx + dz * dz)

    cond do
      dist > reach -> false
      dist < 0.35 * reach -> true
      true -> angle_between({:math.sin(heading), :math.cos(heading)}, {dx / dist, dz / dist}) <= arc_deg / 2
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
