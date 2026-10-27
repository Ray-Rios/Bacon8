defmodule BaconWorld.Mobs.Brain do
  @moduledoc """
  What a creature does, as pure functions over a map, so the rules can be tested
  without processes (`BaconWorld.Mobs.Zone` runs them ten times a second).

  A creature idles and wanders near its spawn point; a player who comes within its
  aggro range (and doesn't con grey to it) is chased and hit until one of them
  dies, the player reaches the safe village, or the chase drags the creature too
  far from home. Then it runs home and heals. Hitting a creature always makes it
  come for you. A dead creature leaves a corpse holding its loot (mostly the
  weapon it held); the killer may loot alone for a minute, then anyone; the corpse
  decays after four minutes, or once emptied, and the creature respawns later.

  Positions are scene units (`u/0` per metre), times milliseconds.

  Events returned for the zone to broadcast:

    * `{:spawn, view}`
    * `{:aggro, id, character_id}`
    * `{:attack, id, character_id, hit?, damage}`, or with a sixth element, the move
      (`"bite"`, `"claw"`, `"tail"`, `"breath"`) for kinds that have `moves` or `breath`
    * `{:attack, id, character_id, hit?, damage, move, fx}` - a special (the Kraken's "grab",
      "ink", "maelstrom") and what it does to the one it hits: `%{root_ms}`, `%{blind_ms}`,
      `%{pull: [x, z], pull_m}` (the client applies them: you are held, blinded, dragged)
    * `{:cast, id, move}` - a creature starts something everyone should see coming (the
      dragon rearing back to breathe fire, the Kraken's specials)
    * `{:damaged, id, character_id, damage, crit?, hp, max_hp}` (from `melee/4`)
    * `{:died, id, killer_id}`
    * `{:corpse_gone, id}`
  """

  alias BaconWorld.{Items, Melee, Progression}
  alias BaconWorld.Mobs.Spawns

  @u 2.2 / 1.8
  # Players this high (metres, on a flying mount) are out of reach of the creatures.
  @airborne_m 6.0
  @player_radius 0.35
  @mob_radius 0.4
  # Extra reach for the player's swing: positions arrive ~100 ms late.
  @swing_slack 0.6
  @loot_distance 4.5
  @looter_timeout 90_000

  def u, do: @u

  # ---------------------------------------------------------------------------
  # Spawning
  # ---------------------------------------------------------------------------

  @doc "A new creature at a spawn point (`BaconWorld.Mobs.Spawns.points/0`)."
  def spawn(point, now) do
    kind = Spawns.kind(point.kind)
    level = Enum.random(kind.levels)
    {base, per} = kind.hp
    max_hp = base + per * level
    weapon = Spawns.weighted(kind.weapons)
    offhand = if Items.two_handed?(Items.get(weapon)), do: nil, else: Spawns.weighted(kind.offhand)
    x = point.x * @u
    z = point.z * @u

    %{
      id: point.id,
      camp: point.camp,
      kind: point.kind,
      name: kind.name,
      level: level,
      hp: max_hp,
      max_hp: max_hp,
      x: x,
      z: z,
      h: :rand.uniform() * 2 * :math.pi() - :math.pi(),
      home: {x, z},
      # where it spawned: a roaming kind (Spawns `roam`) wanders anywhere near it
      origin: {x, z},
      state: :idle,
      target: nil,
      goal: nil,
      next_think: now + Enum.random(1_000..6_000),
      # Times are the zone's clock, which can be negative (the BEAM's monotonic time
      # often is), so nothing here may use 0 to mean "long ago".
      next_attack: now,
      weapon: weapon,
      offhand: offhand,
      damage_by: %{},
      corpse: nil,
      respawn_at: nil,
      vx: 0.0,
      vz: 0.0,
      # breath: a pending cone of fire `%{at}` (nil when none); busy_until: no moving or
      # swinging before then (the breath's windup and blast)
      breath: nil,
      next_breath: now + 6_000,
      busy_until: now,
      # special: a pending special `%{move, at, target}` (Spawns `specials`); squeeze: a held
      # target taking damage each second `%{target, next, left, dmg}`
      special: nil,
      next_special: now + 8_000,
      squeeze: nil,
      # rooted (a player's Entangling Roots): no moving before then, swinging still
      rooted_until: now
    }
  end

  def alive?(%{state: s}), do: s not in [:dead, :gone]

  # ---------------------------------------------------------------------------
  # Thinking and moving
  # ---------------------------------------------------------------------------

  @doc """
  One step. `players` is `%{character_id => %{x, z, dead, level}}`, `dt` seconds,
  `point` the creature's spawn point (for respawning). Returns `{mob, events}`.
  """
  def tick(mob, players, now, dt, point)

  def tick(%{state: :gone} = m, _players, now, _dt, point) do
    if now >= m.respawn_at do
      fresh = spawn(point, now)
      {fresh, [{:spawn, view(fresh)}]}
    else
      {m, []}
    end
  end

  def tick(%{state: :dead} = m, _players, now, _dt, _point) do
    if now >= m.corpse.despawn_at do
      {%{m | state: :gone, corpse: nil, respawn_at: now + Enum.random(Spawns.respawn_ms(m.kind))}, [{:corpse_gone, m.id}]}
    else
      {m, []}
    end
  end

  def tick(m, players, now, dt, _point) do
    kind = Spawns.kind(m.kind)
    {m, e1} = check_target(m, players, kind)
    {m, e2} = maybe_aggro(m, players, kind)
    {m, e0} = breathe(m, players, kind, now)
    {m, e4} = unleash(m, players, kind, now)
    {m, e5} = squeeze(m, players, kind, now)
    e0 = e0 ++ e4 ++ e5
    {m2, e3} = if now < m.busy_until, do: {%{m | vx: 0.0, vz: 0.0}, []}, else: act(m, players, kind, now, dt)
    # rooted: it turns and swings, but stays where it is
    m2 = if now < Map.get(m, :rooted_until, now), do: %{m2 | x: m.x, z: m.z, vx: 0.0, vz: 0.0}, else: m2
    {m2, e1 ++ e2 ++ e0 ++ e3}
  end

  @doc "True for a player too high up for the creatures (a flying mount)."
  def airborne?(p), do: (Map.get(p, :y) || 0.0) > @airborne_m * @u

  @doc "Flying or swimming: no creature chases or attacks them (they don't fly or swim)."
  def out_of_reach?(p), do: airborne?(p) or Map.get(p, :swimming, false) == true

  @doc "As `out_of_reach?/1` for a kind: a creature of the deep (the Kraken) reaches swimmers."
  def out_of_reach?(p, kind) do
    if Map.get(kind, :aquatic, false), do: airborne?(p), else: out_of_reach?(p)
  end

  # A chase ends when the target is gone, dead, safe in the village, or too far from home.
  defp check_target(%{state: :chase, target: t} = m, players, kind) do
    p = players[t]
    {hx, hz} = m.home

    if is_nil(p) or p.dead or in_safe_zone?(p.x, p.z) or out_of_reach?(p, kind) or dist({m.x, m.z}, {hx, hz}) > Spawns.leash(m.kind) * @u do
      {%{m | state: :return, target: nil, goal: m.home}, []}
    else
      {m, []}
    end
  end

  defp check_target(m, _players, _kind), do: {m, []}

  defp maybe_aggro(%{state: s} = m, players, kind) when s in [:idle, :wander] do
    range = kind.aggro * @u

    players
    |> Enum.filter(fn {_id, p} ->
      not p.dead and not in_safe_zone?(p.x, p.z) and not out_of_reach?(p, kind) and dist({m.x, m.z}, {p.x, p.z}) <= range and
        aggressive_to?(m.level, p.level || 1)
    end)
    |> Enum.min_by(fn {_id, p} -> dist({m.x, m.z}, {p.x, p.z}) end, fn -> nil end)
    |> case do
      nil -> {m, []}
      {id, _p} -> {%{chase_from_here(m) | state: :chase, target: id, goal: nil}, [{:aggro, m.id, id}]}
    end
  end

  defp maybe_aggro(m, _players, _kind), do: {m, []}

  # A roamer's chase is measured (and ends) where it began, not at its spawn point.
  defp chase_from_here(m) do
    if Map.has_key?(Spawns.kinds(), m.kind) and Spawns.kind(m.kind)[:roam], do: %{m | home: {m.x, m.z}}, else: m
  end

  # EverQuest: creatures leave alone players they con grey to (far above them).
  defp aggressive_to?(mob_level, player_level), do: Progression.con(mob_level, player_level) != :grey

  defp act(%{state: :idle} = m, _players, %{roam: roam} = kind, now, _dt) when is_number(roam) do
    m = %{m | vx: 0.0, vz: 0.0}

    if now >= m.next_think do
      case roam_goal(m, kind, roam) do
        nil -> {%{m | next_think: now + Enum.random(1_000..3_000)}, []}
        goal -> {%{m | state: :wander, goal: goal, home: {m.x, m.z}}, []}
      end
    else
      {m, []}
    end
  end

  defp act(%{state: :idle} = m, _players, _kind, now, _dt) do
    m = %{m | vx: 0.0, vz: 0.0}

    if now >= m.next_think do
      {hx, hz} = m.home
      a = :rand.uniform() * 2 * :math.pi()
      r = :rand.uniform() * 4.0 * @u
      {%{m | state: :wander, goal: {hx + r * :math.cos(a), hz + r * :math.sin(a)}}, []}
    else
      {m, []}
    end
  end

  defp act(%{state: :wander, goal: goal} = m, _players, kind, now, dt) do
    m0 = m
    m = move(m, goal, kind.walk * @u, dt, 0.05)
    # a roamer that can't go on (the deep water ends that way) picks somewhere else
    stuck = is_number(kind[:roam]) and dt > 0 and m.x == m0.x and m.z == m0.z

    if stuck or dist({m.x, m.z}, goal) < 0.2 * @u,
      do: {%{m | state: :idle, goal: nil, vx: 0.0, vz: 0.0, next_think: now + Enum.random(4_000..11_000)}, []},
      else: {m, []}
  end

  defp act(%{state: :chase, target: t} = m, players, kind, now, dt) do
    p = Map.fetch!(players, t)
    reach = (kind.reach + @player_radius) * @u
    m = move(m, {p.x, p.z}, kind.run * @u, dt, reach * 0.8)
    m = %{m | h: Melee.heading_to({m.x, m.z}, {p.x, p.z})}
    d = dist({m.x, m.z}, {p.x, p.z})
    breath = kind[:breath]
    special = kind[:specials] && now >= Map.get(m, :next_special, now) && pick_special(kind.specials, d)

    cond do
      special ->
        # Wind up: everyone sees it coming (`:cast`); it lands after the windup (`unleash/4`).
        at = now + special.windup_ms

        {%{m | special: %{move: special.move, at: at, target: t}, busy_until: at + special.busy_ms,
              next_special: now + Enum.random(kind.special_every_ms), next_attack: max(m.next_attack, at + special.busy_ms + 300), vx: 0.0, vz: 0.0},
         [{:cast, m.id, special.move}]}

      breath && now >= m.next_breath && d <= breath.range * @u * 0.85 ->
        # Rear back: the fire comes after the windup, at whoever is in the cone then.
        at = now + breath.windup_ms
        {%{m | breath: %{at: at}, busy_until: at + 1_300, next_breath: now + Enum.random(breath.every_ms), next_attack: max(m.next_attack, at + 1_600), vx: 0.0, vz: 0.0},
         [{:cast, m.id, "breath"}]}

      d <= reach and now >= m.next_attack ->
        swing(m, t, p, kind, now)

      true ->
        # Coming into range: a beat before the first swing.
        m = if m.next_attack < now - kind.dly_ms, do: %{m | next_attack: now + 450}, else: m
        {m, []}
    end
  end

  defp act(%{state: :return} = m, _players, kind, now, dt) do
    m = move(m, m.home, kind.run * @u, dt, 0.0)

    if dist({m.x, m.z}, m.home) < 0.3 * @u,
      do: {%{m | state: :idle, goal: nil, hp: m.max_hp, damage_by: %{}, vx: 0.0, vz: 0.0, next_think: now + Enum.random(2_000..6_000)}, []},
      else: {m, []}
  end

  defp swing(m, t, p, kind, now) do
    hit = :rand.uniform() < Melee.hit_chance(m.level, p.level || 1)
    {lo, hi} = kind.dmg
    damage = if hit, do: Enum.random((lo + m.level - 1)..(hi + 2 * (m.level - 1))), else: 0
    m = %{m | next_attack: now + kind.dly_ms + Enum.random(0..300)}

    case kind[:moves] do
      nil ->
        {m, [{:attack, m.id, t, hit, damage}]}

      moves ->
        move = Spawns.weighted(moves)
        damage = if move == "tail", do: round(damage * 0.8), else: damage
        {m, [{:attack, m.id, t, hit, damage, move}]}
    end
  end

  # A breath whose windup is over: everyone in the cone burns (each rolls to hit).
  defp breathe(%{breath: %{at: at}} = m, players, kind, now) when now >= at do
    b = kind.breath
    range = b.range * @u
    {lo, hi} = b.dmg

    events =
      for {id, p} <- players,
          not p.dead,
          not in_safe_zone?(p.x, p.z),
          not out_of_reach?(p, kind),
          Melee.in_arc?({m.x, m.z}, m.h, {p.x, p.z}, range, b.half_arc_deg * 2) do
        hit = :rand.uniform() < Melee.hit_chance(m.level, p.level || 1)
        damage = if hit, do: Enum.random((lo + m.level - 1)..(hi + 2 * (m.level - 1))), else: 0
        {:attack, m.id, id, hit, damage, "breath"}
      end

    {%{m | breath: nil}, events}
  end

  defp breathe(m, _players, _kind, _now), do: {m, []}

  # A special whose range reaches `d` (scene units), by weight; nil when none does.
  defp pick_special(specials, d) do
    case Enum.filter(specials, &(d <= &1.range * @u * 0.9)) do
      [] -> nil
      ok -> Spawns.weighted(Enum.map(ok, &{&1, &1.weight}))
    end
  end

  # A special whose windup is over lands on whoever it reaches then (each rolls to hit).
  defp unleash(%{special: %{at: at} = sp} = m, players, kind, now) when now >= at do
    s = Enum.find(kind.specials, &(&1.move == sp.move))
    range = s.range * @u
    {lo, hi} = s.dmg

    events =
      for {id, p} <- players,
          not p.dead,
          not in_safe_zone?(p.x, p.z),
          not out_of_reach?(p, kind),
          special_reaches?(m, s, sp, id, p, range) do
        hit = :rand.uniform() < Melee.hit_chance(m.level, p.level || 1)
        damage = if hit, do: Enum.random((lo + m.level - 1)..(hi + 2 * (m.level - 1))), else: 0
        {:attack, m.id, id, hit, damage, s.move, special_fx(s, m, hit)}
      end

    # a tentacle that caught its target holds on and squeezes
    squeeze =
      case {s[:squeeze], Enum.find(events, fn {:attack, _, id, hit, _, _, _} -> hit and id == sp.target end)} do
        {{ticks, dmg}, {:attack, _, id, _, _, _, _}} -> %{target: id, next: now + 1_000, left: ticks, dmg: dmg, range: range}
        _ -> Map.get(m, :squeeze)
      end

    {%{m | special: nil, squeeze: squeeze}, events}
  end

  defp unleash(m, _players, _kind, _now), do: {m, []}

  defp special_reaches?(m, %{shape: :target}, sp, id, p, range), do: id == sp.target and dist({m.x, m.z}, {p.x, p.z}) <= range + @player_radius * @u
  defp special_reaches?(m, %{shape: :ring}, _sp, _id, p, range), do: dist({m.x, m.z}, {p.x, p.z}) <= range
  defp special_reaches?(m, %{shape: :cone} = s, _sp, _id, p, range), do: Melee.in_arc?({m.x, m.z}, m.h, {p.x, p.z}, range, s.half_arc_deg * 2)

  # What a special does to whoever it hits, for the client to apply (it moves the character).
  defp special_fx(%{pull_m: pull}, m, _hit), do: %{pull: [r2(m.x), r2(m.z)], pull_m: pull}
  defp special_fx(%{root_ms: ms}, _m, true), do: %{root_ms: ms}
  defp special_fx(%{blind_ms: ms}, _m, true), do: %{blind_ms: ms}
  defp special_fx(_s, _m, _hit), do: %{}

  # Held: a squeeze each second while it lasts, the victim is alive and still in reach.
  defp squeeze(%{squeeze: %{next: nx} = q} = m, players, _kind, now) when now >= nx do
    p = players[q.target]

    if q.left <= 0 or is_nil(p) or p.dead or dist({m.x, m.z}, {p.x, p.z}) > q.range + @player_radius * @u do
      {%{m | squeeze: nil}, []}
    else
      {lo, hi} = q.dmg
      damage = Enum.random((lo + m.level - 1)..(hi + 2 * (m.level - 1)))
      {%{m | squeeze: %{q | next: now + 1_000, left: q.left - 1}}, [{:attack, m.id, q.target, true, damage, "squeeze"}]}
    end
  end

  defp squeeze(m, _players, _kind, _now), do: {m, []}

  # Walks toward `goal` at `speed` (units/s), stopping `stop` short. Never into the village.
  defp move(m, {gx, gz}, speed, dt, stop) do
    dx = gx - m.x
    dz = gz - m.z
    d = :math.sqrt(dx * dx + dz * dz)

    if d <= stop or d < 1.0e-6 do
      %{m | vx: 0.0, vz: 0.0}
    else
      step = min(speed * dt, d - stop)
      {nx, nz} = keep_out_of_town(m.x + dx / d * step, m.z + dz / d * step)
      # creatures don't swim: they stop at the water's edge (BaconWorld.Terrain; never on flat
      # ground); a creature of the deep (the Kraken) stops where the deep water ends
      deep = BaconWorld.Terrain.deep?(nx / @u, nz / @u)
      {nx, nz} = if deep != Spawns.aquatic?(m.kind), do: {m.x, m.z}, else: {nx, nz}
      moved = dist({nx, nz}, {m.x, m.z})
      v = if dt > 0, do: moved / dt, else: 0.0
      %{m | x: nx, z: nz, h: :math.atan2(dx, dz), vx: dx / d * v, vz: dz / d * v}
    end
  end

  # Somewhere to roam to: a few tries at a random point within `roam` metres of its spawn point,
  # 40 m or more away, where it may go (deep water for an aquatic kind); nil when none was found.
  defp roam_goal(m, kind, roam) do
    {ox, oz} = Map.get(m, :origin, m.home)

    Enum.find_value(1..12, fn _ ->
      a = :rand.uniform() * 2 * :math.pi()
      r = :math.sqrt(:rand.uniform()) * roam * @u
      {gx, gz} = {ox + r * :math.cos(a), oz + r * :math.sin(a)}
      deep = BaconWorld.Terrain.deep?(gx / @u, gz / @u)
      ok = if kind[:aquatic], do: deep, else: not deep

      if ok and dist({gx, gz}, {m.x, m.z}) > 40.0 * @u and not in_safe_zone?(gx, gz), do: {gx, gz}
    end)
  end

  defp keep_out_of_town(x, z) do
    r = Spawns.safe_radius() * @u
    d = :math.sqrt(x * x + z * z)
    if d >= r or d < 1.0e-6, do: {x, z}, else: {x / d * r, z / d * r}
  end

  @doc "True inside the safe village (scene units)."
  def in_safe_zone?(x, z), do: :math.sqrt(x * x + z * z) < Spawns.safe_radius() * @u

  # ---------------------------------------------------------------------------
  # Getting hit
  # ---------------------------------------------------------------------------

  @doc """
  A player's swing. `attack` is `%{id, level, x, z, heading, item, heavy, target}`
  (`item` a catalogue map, `target` the creature the player has selected, if any).
  Returns `{mobs, hits, events}`; `hits` are `%{id, hit, damage, crit, killed,
  level, hp, max_hp}`.
  """
  def melee(mobs, attack, now, rand \\ &:rand.uniform/0) do
    # a skill may sweep wider (the spin attack: everything around), reach further and
    # hit harder or softer (`sweep`, `extra_reach` metres, `mult`); buffs add `pct`
    {max_targets, arc} = attack[:sweep] || Melee.sweep(attack.item)
    mult = (attack[:mult] || 1.0) * (1 + (attack[:pct] || 0) / 100)
    extra = attack[:extra_reach] || 0.0
    # A big creature (the dragon) is hit at its hide, not its middle.
    reach = fn mob -> (attack.item.reach + extra + mob_radius(mob) + @player_radius + @swing_slack) * @u end

    victims =
      mobs
      |> Map.values()
      |> Enum.filter(&(alive?(&1) and Melee.in_arc?({attack.x, attack.z}, attack.heading, {&1.x, &1.z}, reach.(&1), arc)))
      |> Enum.sort_by(fn mob -> {if(mob.id == attack[:target], do: 0, else: 1), dist({attack.x, attack.z}, {mob.x, mob.z})} end)
      |> Enum.take(max_targets)

    Enum.reduce(victims, {mobs, [], []}, fn mob, {acc, hits, events} ->
      if rand.() < Melee.hit_chance(attack.level, mob.level) do
        {damage, crit} = Melee.roll_damage(attack.item, attack.level, attack.heavy, rand)
        damage = if mult == 1.0, do: damage, else: max(1, round(damage * mult))
        {mob2, evs} = take_damage(mob, attack.id, damage, crit, now)
        hit = %{id: mob.id, hit: true, damage: damage, crit: crit, killed: not alive?(mob2), level: mob.level, hp: max(mob2.hp, 0), max_hp: mob.max_hp}
        {Map.put(acc, mob.id, mob2), hits ++ [hit], events ++ evs}
      else
        # A miss still makes it angry.
        {mob2, evs} = provoke(mob, attack.id)
        miss = %{id: mob.id, hit: false, damage: 0, crit: false, killed: false, level: mob.level, hp: mob.hp, max_hp: mob.max_hp}
        {Map.put(acc, mob.id, mob2), hits ++ [miss], events ++ evs ++ [{:damaged, mob.id, attack.id, 0, false, mob.hp, mob.max_hp}]}
      end
    end)
  end

  @doc """
  A spell landing on one creature (`BaconWorldWeb.SkillEvents`): `attack` is
  `%{id (the caster), target, damage, crit, x, z, range}` (range in scene units, to the
  creature's hide). Returns `{mobs, result, events}`; `result` is a hit map like
  `melee/4`'s or `{:error, reason}`.
  """
  def spell_hit(mobs, attack, now) do
    with %{} = mob <- mobs[attack.target] || {:error, :no_target},
         true <- alive?(mob) || {:error, :no_target},
         true <- in_spell_range?(mob, attack) || {:error, :out_of_range} do
      {mob2, evs} = take_damage(mob, attack.id, attack.damage, attack[:crit] || false, now)
      hit = %{id: mob.id, hit: true, damage: attack.damage, crit: attack[:crit] || false, killed: not alive?(mob2), level: mob.level, hp: max(mob2.hp, 0), max_hp: mob.max_hp}
      {Map.put(mobs, mob.id, mob2), hit, evs}
    else
      err -> {mobs, err, []}
    end
  end

  @doc """
  Roots a creature for `attack.ms` (a boss for a third of it) and makes it angry.
  Returns `{mobs, :ok | {:error, reason}, events}`.
  """
  def root(mobs, attack, now) do
    with %{} = mob <- mobs[attack.target] || {:error, :no_target},
         true <- alive?(mob) || {:error, :no_target},
         true <- in_spell_range?(mob, attack) || {:error, :out_of_range} do
      ms = if Spawns.boss?(mob.kind), do: div(attack.ms, 3), else: attack.ms
      {mob2, evs} = provoke(%{mob | rooted_until: now + ms}, attack.id)
      {Map.put(mobs, mob.id, mob2), :ok, [{:rooted, mob.id, ms} | evs]}
    else
      err -> {mobs, err, []}
    end
  end

  defp in_spell_range?(mob, attack), do: dist({attack.x, attack.z}, {mob.x, mob.z}) <= attack.range + (mob_radius(mob) + @player_radius) * @u

  defp mob_radius(%{kind: kind}), do: if(Map.has_key?(Spawns.kinds(), kind), do: Spawns.radius(kind), else: @mob_radius)

  @doc "Applies damage from a character. Returns `{mob, events}`."
  def take_damage(mob, character_id, damage, crit, now) do
    if alive?(mob) do
      hp = mob.hp - damage
      mob = %{mob | hp: hp, damage_by: Map.update(mob.damage_by, character_id, damage, &(&1 + damage))}
      dmg_event = {:damaged, mob.id, character_id, damage, crit, max(hp, 0), mob.max_hp}

      if hp <= 0 do
        {dead, evs} = die(mob, now)
        {dead, [dmg_event | evs]}
      else
        {mob, evs} = provoke(mob, character_id)
        {mob, [dmg_event | evs]}
      end
    else
      {mob, []}
    end
  end

  defp provoke(%{state: :chase, target: t} = mob, _character_id) when not is_nil(t), do: {mob, []}

  defp provoke(mob, character_id) do
    if alive?(mob), do: {%{chase_from_here(mob) | state: :chase, target: character_id, goal: nil}, [{:aggro, mob.id, character_id}]}, else: {mob, []}
  end

  defp die(mob, now) do
    kind = Spawns.kind(mob.kind)
    killer = mob.damage_by |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end) |> elem(0)

    corpse = %{
      items: roll_loot(mob, kind),
      coins: Enum.random(kind.coins) * mob.level,
      owner: killer,
      free_at: now + Spawns.loot_lock_ms(),
      despawn_at: now + Spawns.corpse_ms(),
      looter: nil,
      looter_since: now
    }

    mob = mob |> Map.put(:special, nil) |> Map.put(:squeeze, nil)
    {%{mob | state: :dead, hp: 0, target: nil, goal: nil, vx: 0.0, vz: 0.0, corpse: corpse}, [{:died, mob.id, killer}]}
  end

  @doc false
  def roll_loot(mob, kind) do
    weapon = if mob.weapon && :rand.uniform() < kind.weapon_drop, do: [%{item_id: mob.weapon, quantity: 1}], else: []
    off = if mob.offhand && :rand.uniform() < 0.6, do: [%{item_id: mob.offhand, quantity: 1}], else: []

    junk =
      for {item_id, chance, qty} <- kind.loot, :rand.uniform() < chance do
        %{item_id: item_id, quantity: Enum.random(qty)}
      end

    drops = for {item_id, chance} <- Map.get(kind, :drops, []), :rand.uniform() < chance, do: %{item_id: item_id, quantity: 1}

    weapon ++ off ++ junk ++ drops
  end

  # ---------------------------------------------------------------------------
  # Looting (EverQuest: one looter at a time, the killer first)
  # ---------------------------------------------------------------------------

  @doc """
  Opens a corpse for `character_id` standing at `{x, z}`. Coins go to the looter at
  once. `{:ok, mob, coins, items}` or `{:error, reason}`: `:not_a_corpse`,
  `:too_far`, `:not_yours_yet`, `:someone_else_looting`.
  """
  def loot_open(%{state: :dead, corpse: c} = mob, character_id, {x, z}, now) do
    cond do
      dist({x, z}, {mob.x, mob.z}) > @loot_distance * @u ->
        {:error, :too_far}

      c.owner && c.owner != character_id && now < c.free_at ->
        {:error, :not_yours_yet}

      c.looter && c.looter != character_id && now - c.looter_since < @looter_timeout ->
        {:error, :someone_else_looting}

      true ->
        corpse = %{c | looter: character_id, looter_since: now, coins: 0}
        {:ok, %{mob | corpse: corpse}, c.coins, c.items}
    end
  end

  def loot_open(_mob, _character_id, _pos, _now), do: {:error, :not_a_corpse}

  @doc "Takes item `index` from an open corpse. `{:ok, mob, item}` or `{:error, reason}`."
  def loot_take(%{state: :dead, corpse: %{looter: looter} = c} = mob, character_id, index) when looter == character_id do
    case Enum.at(c.items, index) do
      nil -> {:error, :no_such_item}
      item -> {:ok, %{mob | corpse: %{c | items: List.delete_at(c.items, index)}}, item}
    end
  end

  def loot_take(_mob, _character_id, _index), do: {:error, :not_looting}

  @doc "Puts an item back (it didn't fit in the bags)."
  def loot_return(%{state: :dead, corpse: c} = mob, item), do: %{mob | corpse: %{c | items: c.items ++ [item]}}
  def loot_return(mob, _item), do: mob

  @doc "Closes the loot window. An emptied corpse decays a few seconds later."
  def loot_close(%{state: :dead, corpse: %{looter: looter} = c} = mob, character_id, now) when looter == character_id do
    c = %{c | looter: nil}
    c = if c.items == [] and c.coins == 0, do: %{c | despawn_at: min(c.despawn_at, now + 3_000)}, else: c
    %{mob | corpse: c}
  end

  def loot_close(mob, _character_id, _now), do: mob

  # ---------------------------------------------------------------------------
  # What clients see
  # ---------------------------------------------------------------------------

  @doc "A creature as the client draws it."
  def view(m) do
    %{
      id: m.id,
      kind: m.kind,
      name: m.name,
      level: m.level,
      hp: max(m.hp, 0),
      max_hp: m.max_hp,
      x: r2(m.x),
      z: r2(m.z),
      h: Float.round(m.h * 1.0, 3),
      state: Atom.to_string(m.state),
      weapon: m.weapon,
      offhand: m.offhand,
      target: m.target,
      corpse: m.corpse && %{owner: m.corpse.owner, empty: m.corpse.items == [] and m.corpse.coins == 0},
      boss: Map.get(Spawns.kind(m.kind), :boss, false),
      scale: Map.get(Spawns.kind(m.kind), :scale, 1.0)
    }
  end

  @doc "Position and velocity, compact, for the frequent updates: `[id, x, z, h, vx, vz]`."
  def motion(m), do: [m.id, r2(m.x), r2(m.z), Float.round(m.h * 1.0, 3), r2(m.vx), r2(m.vz)]

  defp r2(v), do: Float.round(v * 1.0, 2)

  defp dist({ax, az}, {bx, bz}), do: :math.sqrt((ax - bx) * (ax - bx) + (az - bz) * (az - bz))
end
