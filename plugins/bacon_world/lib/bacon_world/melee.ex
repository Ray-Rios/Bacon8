defmodule BaconWorld.Melee do
  @moduledoc """
  Melee and combat numbers, pure functions (the zone and the LiveView call them).

  A swing hits what is in front of the attacker, Black Desert style: within the
  weapon's reach and an arc around where the attacker looks. One-handed weapons
  and fists hit one creature (the targeted one if it is in the arc, else the
  nearest); two-handers sweep up to three.

  Damage is EverQuest-shaped and tuned via `BaconWorld.Tuning`: a roll between 40%
  and 100% of the weapon's DMG, plus `floor(level / melee_level_div)` (default 3);
  `melee_crit_chance` (default 6%) of hits are critical (`×1.75`). A heavy swing
  (a two-hander's right button) does `×1.5` and takes `×1.4` as long.

  Armour Class (`total_ac/1`) mitigates incoming physical damage using a hyperbolic
  curve (`BaconWorld.Tuning.mitigate_ac/2`): `reduction = min(0.75, ac / (ac + 50))`.

  Headings are yaw angles: 0 faces +Z, and a character facing `h` looks along
  `(sin h, cos h)`.
  """

  alias BaconWorld.{Items, Tuning}

  @ranged_arc 30
  @ranged_target_arc 60

  @doc "Milliseconds between swings with `item` (EverQuest DLY is tenths of a second)."
  def delay_ms(item, heavy \\ false) do
    heavy_dly = Tuning.get("heavy_swing_delay")
    round(item.dly * 100 * if(heavy, do: heavy_dly, else: 1.0))
  end

  @doc "Chance to hit, from the attacker's and defender's levels."
  def hit_chance(attacker_level, defender_level),
    do: (0.88 + 0.03 * (attacker_level - defender_level)) |> max(0.4) |> min(0.97)

  @doc "`{damage, crit?}` for a hit with `item`. `rand` returns a float in [0, 1)."
  def roll_damage(item, attacker_level, heavy \\ false, rand \\ &:rand.uniform/0, opts_or_crit \\ 0.0) do
    {mult, crit_bonus} =
      cond do
        is_list(opts_or_crit) ->
          {Keyword.get(opts_or_crit, :mult, 1.0), Keyword.get(opts_or_crit, :crit_bonus, 0.0)}

        is_number(opts_or_crit) ->
          {1.0, opts_or_crit * 1.0}

        true ->
          {1.0, 0.0}
      end

    t = Tuning.current()
    lvl_div = max(1.0, Map.get(t, "melee_level_div", 3.0))
    heavy_dmg = Map.get(t, "heavy_swing_mult", 1.5)
    crit_chance = min(0.95, Map.get(t, "melee_crit_chance", 0.06) + crit_bonus)
    crit_mult = Map.get(t, "melee_crit_mult", 1.75)

    hi = max(1, item.dmg)
    lo = max(1, round(hi * 0.4))
    base = lo + min(hi - lo, trunc(rand.() * (hi - lo + 1)))
    dmg = base + trunc(max(attacker_level, 1) / lvl_div)
    dmg = if heavy, do: round(dmg * heavy_dmg), else: dmg
    dmg = if mult == 1.0, do: dmg, else: max(1, round(dmg * mult))
    if rand.() < crit_chance, do: {round(dmg * crit_mult), true}, else: {dmg, false}
  end

  @doc "Total Armour Class (AC) from an equipment map (`slot => item | nil`)."
  def total_ac(equipment) when is_map(equipment) do
    equipment
    |> Map.values()
    |> Enum.reduce(0, fn
      %{ac: ac}, sum when is_integer(ac) and ac > 0 -> sum + ac
      id, sum when is_binary(id) ->
        case Items.get(id) do
          %{ac: ac} when is_integer(ac) and ac > 0 -> sum + ac
          _ -> sum
        end
      _, sum -> sum
    end)
  end

  def total_ac(_), do: 0

  @doc """
  Computes the full Character Stats Readout map sent to the client (`stats_sheet`),
  combining equipment, level, skill-tree passive bonuses, and active combat buffs.
  Accepts either `(equipment, level, ...)` or `(level, equipment, ...)`.
  """
  def stats_sheet(arg1, arg2, tree_bonuses \\ %{}, combat_buffs \\ %{}) do
    {equipment, level} =
      if is_integer(arg1) do
        {arg2 || %{}, arg1}
      else
        {arg1 || %{}, arg2 || 1}
      end

    t = Tuning.current()
    lvl = max(1, level || 1)
    lvl_div = max(1.0, Map.get(t, "melee_level_div", 3.0))
    lvl_bonus = trunc(lvl / lvl_div)

    main = (equipment && equipment["main"]) || Items.fist()
    off = equipment && equipment["off"]
    two_hand? = Items.two_handed?(main)
    off_weapon =
      cond do
        two_hand? -> nil
        off && off[:kind] in ["weapon", "shield", "light"] -> off
        true -> Items.fist()
      end

    now = System.monotonic_time(:millisecond)
    temp_ac =
      cond do
        Map.has_key?(combat_buffs, :ac_until) -> if (combat_buffs[:ac_until] || 0) > now, do: combat_buffs[:ac] || combat_buffs[:ac_bonus] || 0, else: 0
        true -> combat_buffs[:ac] || combat_buffs[:ac_bonus] || 0
      end

    temp_dmg =
      cond do
        Map.has_key?(combat_buffs, :dmg_until) -> if (combat_buffs[:dmg_until] || 0) > now, do: combat_buffs[:dmg_pct] || 0, else: 0
        true -> combat_buffs[:dmg_pct] || 0
      end

    temp_crit =
      cond do
        Map.has_key?(combat_buffs, :crit_until) -> if (combat_buffs[:crit_until] || 0) > now, do: combat_buffs[:crit] || combat_buffs[:crit_bonus] || 0.0, else: 0.0
        true -> combat_buffs[:crit] || combat_buffs[:crit_bonus] || 0.0
      end

    shield_hp =
      cond do
        Map.has_key?(combat_buffs, :shield_until) -> if (combat_buffs[:shield_until] || 0) > now, do: max(0, combat_buffs[:shield] || 0), else: 0
        true -> max(0, combat_buffs[:shield] || 0)
      end

    gear_ac = total_ac(equipment || %{})
    ac = gear_ac + temp_ac
    mitigation_pct = Float.round(Tuning.ac_reduction(ac) * 100.0, 1)

    melee_pct = Map.get(tree_bonuses, "melee_pct", 0) + temp_dmg
    spell_pct = Map.get(tree_bonuses, "spell_pct", 0) + temp_dmg
    melee_mult = 1.0 + melee_pct / 100.0

    main_lo = max(1, round((max(1, r_dmg(main)) * 0.4 + lvl_bonus) * melee_mult))
    main_hi = max(1, round((max(1, r_dmg(main)) + lvl_bonus) * melee_mult))
    main_dly_s = Float.round(r_dly(main) / 10.0, 2)
    main_dps = if main_dly_s > 0, do: Float.round((main_lo + main_hi) / 2.0 / main_dly_s, 1), else: 0.0
    melee_crit_pct = Float.round((Map.get(t, "melee_crit_chance", 0.06) + temp_crit) * 100.0, 1)

    {off_name, off_lo, off_hi, off_dly_s} =
      if off_weapon do
        olo = max(1, round((max(1, r_dmg(off_weapon)) * 0.4 + lvl_bonus) * melee_mult))
        ohi = max(1, round((max(1, r_dmg(off_weapon)) + lvl_bonus) * melee_mult))
        {off_weapon.name, olo, ohi, Float.round(r_dly(off_weapon) / 10.0, 2)}
      else
        {nil, 0, 0, 0.0}
      end

    %{
      level: lvl,
      ac: ac,
      total_ac: ac,
      gear_ac: gear_ac,
      ac_bonus: temp_ac,
      temp_ac: temp_ac,
      mitigation_pct: mitigation_pct,
      ac_mitigation_pct: mitigation_pct,
      reduction_pct: mitigation_pct,
      shield: shield_hp,
      shield_hp: shield_hp,
      level_dmg_bonus: lvl_bonus,
      main_name: main.name,
      main_skill: main[:skill] || "Hand to Hand",
      main_dmg: r_dmg(main),
      main_dly: r_dly(main),
      main_min: main_lo,
      main_max: main_hi,
      min_dmg: main_lo,
      max_dmg: main_hi,
      main_dly_s: main_dly_s,
      main_dps: main_dps,
      dps: main_dps,
      two_handed: two_hand?,
      heavy_mult: Map.get(t, "heavy_swing_mult", 1.5),
      off_name: off_name,
      off_min: off_lo,
      off_max: off_hi,
      off_dly_s: off_dly_s,
      melee_pct: melee_pct,
      spell_pct: spell_pct,
      bonus_hp: Map.get(tree_bonuses, "hp", Map.get(tree_bonuses, "max_hp", 0)),
      bonus_mp: Map.get(tree_bonuses, "mp", Map.get(tree_bonuses, "max_mp", 0)),
      melee_crit_pct: melee_crit_pct,
      crit_pct: melee_crit_pct,
      melee_crit_mult: Map.get(t, "melee_crit_mult", 1.75),
      spell_crit_pct: Float.round((Map.get(t, "spell_crit_chance", 0.05) + temp_crit) * 100.0, 1),
      spell_crit_mult: Map.get(t, "spell_crit_mult", 1.5)
    }
  end

  defp r_dmg(%{dmg: d}) when is_number(d) and d > 0, do: d
  defp r_dmg(_), do: 3
  defp r_dly(%{dly: d}) when is_number(d) and d > 0, do: d
  defp r_dly(_), do: 9

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
