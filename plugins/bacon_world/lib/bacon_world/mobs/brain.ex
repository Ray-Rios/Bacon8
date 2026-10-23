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
    * `{:attack, id, character_id, hit?, damage}`
    * `{:damaged, id, character_id, damage, crit?, hp, max_hp}` (from `melee/4`)
    * `{:died, id, killer_id}`
    * `{:corpse_gone, id}`
  """

  alias BaconWorld.{Items, Melee, Progression}
  alias BaconWorld.Mobs.Spawns

  @u 2.2 / 1.8
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
      vz: 0.0
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
      {%{m | state: :gone, corpse: nil, respawn_at: now + Enum.random(Spawns.respawn_ms())}, [{:corpse_gone, m.id}]}
    else
      {m, []}
    end
  end

  def tick(m, players, now, dt, _point) do
    kind = Spawns.kind(m.kind)
    {m, e1} = check_target(m, players)
    {m, e2} = maybe_aggro(m, players, kind)
    {m, e3} = act(m, players, kind, now, dt)
    {m, e1 ++ e2 ++ e3}
  end

  # A chase ends when the target is gone, dead, safe in the village, or too far from home.
  defp check_target(%{state: :chase, target: t} = m, players) do
    p = players[t]
    {hx, hz} = m.home

    if is_nil(p) or p.dead or in_safe_zone?(p.x, p.z) or dist({m.x, m.z}, {hx, hz}) > Spawns.leash() * @u do
      {%{m | state: :return, target: nil, goal: m.home}, []}
    else
      {m, []}
    end
  end

  defp check_target(m, _players), do: {m, []}

  defp maybe_aggro(%{state: s} = m, players, kind) when s in [:idle, :wander] do
    range = kind.aggro * @u

    players
    |> Enum.filter(fn {_id, p} ->
      not p.dead and not in_safe_zone?(p.x, p.z) and dist({m.x, m.z}, {p.x, p.z}) <= range and
        aggressive_to?(m.level, p.level || 1)
    end)
    |> Enum.min_by(fn {_id, p} -> dist({m.x, m.z}, {p.x, p.z}) end, fn -> nil end)
    |> case do
      nil -> {m, []}
      {id, _p} -> {%{m | state: :chase, target: id, goal: nil}, [{:aggro, m.id, id}]}
    end
  end

  defp maybe_aggro(m, _players, _kind), do: {m, []}

  # EverQuest: creatures leave alone players they con grey to (far above them).
  defp aggressive_to?(mob_level, player_level), do: Progression.con(mob_level, player_level) != :grey

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
    m = move(m, goal, kind.walk * @u, dt, 0.05)

    if dist({m.x, m.z}, goal) < 0.2 * @u,
      do: {%{m | state: :idle, goal: nil, vx: 0.0, vz: 0.0, next_think: now + Enum.random(4_000..11_000)}, []},
      else: {m, []}
  end

  defp act(%{state: :chase, target: t} = m, players, kind, now, dt) do
    p = Map.fetch!(players, t)
    reach = (kind.reach + @player_radius) * @u
    m = move(m, {p.x, p.z}, kind.run * @u, dt, reach * 0.8)
    m = %{m | h: Melee.heading_to({m.x, m.z}, {p.x, p.z})}

    if dist({m.x, m.z}, {p.x, p.z}) <= reach and now >= m.next_attack do
      hit = :rand.uniform() < Melee.hit_chance(m.level, p.level || 1)
      {lo, hi} = kind.dmg
      damage = if hit, do: Enum.random((lo + m.level - 1)..(hi + 2 * (m.level - 1))), else: 0
      {%{m | next_attack: now + kind.dly_ms + Enum.random(0..300)}, [{:attack, m.id, t, hit, damage}]}
    else
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
      moved = dist({nx, nz}, {m.x, m.z})
      v = if dt > 0, do: moved / dt, else: 0.0
      %{m | x: nx, z: nz, h: :math.atan2(dx, dz), vx: dx / d * v, vz: dz / d * v}
    end
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
    {max_targets, arc} = Melee.sweep(attack.item)
    reach = (attack.item.reach + @mob_radius + @player_radius + @swing_slack) * @u

    victims =
      mobs
      |> Map.values()
      |> Enum.filter(&(alive?(&1) and Melee.in_arc?({attack.x, attack.z}, attack.heading, {&1.x, &1.z}, reach, arc)))
      |> Enum.sort_by(fn mob -> {if(mob.id == attack[:target], do: 0, else: 1), dist({attack.x, attack.z}, {mob.x, mob.z})} end)
      |> Enum.take(max_targets)

    Enum.reduce(victims, {mobs, [], []}, fn mob, {acc, hits, events} ->
      if rand.() < Melee.hit_chance(attack.level, mob.level) do
        {damage, crit} = Melee.roll_damage(attack.item, attack.level, attack.heavy, rand)
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
    if alive?(mob), do: {%{mob | state: :chase, target: character_id, goal: nil}, [{:aggro, mob.id, character_id}]}, else: {mob, []}
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

    weapon ++ off ++ junk
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
      corpse: m.corpse && %{owner: m.corpse.owner, empty: m.corpse.items == [] and m.corpse.coins == 0}
    }
  end

  @doc "Position and velocity, compact, for the frequent updates: `[id, x, z, h, vx, vz]`."
  def motion(m), do: [m.id, r2(m.x), r2(m.z), Float.round(m.h * 1.0, 3), r2(m.vx), r2(m.vz)]

  defp r2(v), do: Float.round(v * 1.0, 2)

  defp dist({ax, az}, {bx, bz}), do: :math.sqrt((ax - bx) * (ax - bx) + (az - bz) * (az - bz))
end
