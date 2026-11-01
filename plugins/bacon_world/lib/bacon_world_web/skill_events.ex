defmodule BaconWorldWeb.SkillEvents do
  @moduledoc """
  The skill tree and casting, the third part of `BaconWorldWeb.PlayLive`
  (`BaconWorld.SkillTree`, `BaconWorld.Skills`, `BaconWorld.Abilities`).

  Client events (all reply):

    * `"skills_fetch"` - the tree, the ability catalogue, what you have, the points
      left and your hotbars (`BaconWorld.Skills.payload/1`).
    * `"skill_learn"` `%{node}` - spend a point. Replies the new payload.
    * `"hotbar_set"` `%{hotbars}` - `%{"skills" => %{"Q" => id}, "spells" => [20]}`.
    * `"cast"` `%{ability, target_id, heading}` - a spell or skill. Checks you have it,
      it is off cooldown, you have the mana and a fitting target; a spell with a cast
      time starts casting (moving interrupts it). Replies `%{ok, cast_ms}`; the
      outcome comes as `"cast_result"`.
    * `"cast_cancel"` - stop casting.

  Pushed: `"cast_result"` `%{ability, ok, reason?, hits?, progress?, cooldown_ms}`,
  `"zone_cast"` (someone's cast, for its look: `phase` "begin", "cancel", "launch"
  (a projectile, with `travel_ms`), "land", "aoe", "cone", "chain", "shield",
  "buff", "dash", "spin", "strike", "taunt"), `"healed"` (someone healed you),
  `"stats_sheet"` (updated character combat readout), and
  `"world_position_corrected"` for Recall and dashes/leaps/blinks.

  Spell damage lands after the projectile's flight (`{:spell_land, ...}`); a heal on
  another player is applied by that player's LiveView (`{:player_heal, ...}` on the
  zone topic), as creature hits are.
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias BaconWorld.{Abilities, Combat, Items, Melee, Mobs, Skills, Terrain, Tuning, Water, World}
  alias BaconWorld.Mobs.Brain
  alias BaconWorldWeb.GameEvents
  alias Phoenix.PubSub

  # moving further than this (metres) while casting interrupts the cast
  @interrupt_m 0.6

  # ---------------------------------------------------------------------------
  # Active combat buffs & stats sheet helper
  # ---------------------------------------------------------------------------

  @doc "Returns active temporary combat buffs on the socket, expiring old ones."
  def active_buffs(socket) do
    now = System.monotonic_time(:millisecond)
    raw = socket.assigns[:combat_buffs] || %{}

    %{
      shield: if((raw[:shield_until] || 0) > now, do: max(0, raw[:shield] || 0), else: 0),
      ac: if((raw[:ac_until] || 0) > now, do: raw[:ac] || 0, else: 0),
      dmg_pct: if((raw[:dmg_until] || 0) > now, do: raw[:dmg_pct] || 0, else: 0),
      crit: if((raw[:crit_until] || 0) > now, do: raw[:crit] || 0.0, else: 0.0)
    }
  end

  @doc "Absorbs incoming damage with an active shield buff. Returns `{remaining_damage, socket}`."
  def absorb_shield(socket, damage) when is_integer(damage) and damage > 0 do
    now = System.monotonic_time(:millisecond)
    raw = socket.assigns[:combat_buffs] || %{}
    shield = if (raw[:shield_until] || 0) > now, do: max(0, raw[:shield] || 0), else: 0

    if shield <= 0 do
      {damage, socket}
    else
      used = min(shield, damage)
      left = shield - used
      new_raw = Map.put(raw, :shield, left)
      socket = assign(socket, combat_buffs: new_raw) |> push_stats_sheet()
      {damage - used, socket}
    end
  end

  def absorb_shield(socket, damage), do: {damage, socket}

  @doc "Computes and pushes the live character stats sheet to the client."
  def push_stats_sheet(socket) do
    case character(socket) do
      {:ok, c} ->
        eq = socket.assigns[:equipment] || %{}
        level = socket.assigns[:level] || World.stat(c, "level")
        buffs = active_buffs(socket)

        skill_bonuses = %{
          "hp" => Skills.bonus(c, "hp"),
          "mp" => Skills.bonus(c, "mp"),
          "melee_pct" => Skills.bonus(c, "melee_pct"),
          "spell_pct" => Skills.bonus(c, "spell_pct")
        }

        sheet = Melee.stats_sheet(eq, level, skill_bonuses, buffs)
        push_event(socket, "stats_sheet", sheet)

      _ ->
        socket
    end
  end

  # ---------------------------------------------------------------------------
  # The tree and the hotbars
  # ---------------------------------------------------------------------------

  def handle_event("skills_fetch", _params, socket) do
    case character(socket) do
      {:ok, c} -> {:reply, Map.put(Skills.payload(c), :ok, true), push_stats_sheet(socket)}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("skill_learn", %{"node" => node}, socket) do
    with {:ok, c} <- character(socket),
         {:ok, payload} <- Skills.learn(c.id, node) do
      {:ok, c} = World.fetch_character(c.id)
      socket = socket |> refresh_pools(c) |> push_stats_sheet()
      {:reply, Map.put(payload, :ok, true), socket}
    else
      {:error, msg} when is_binary(msg) -> {:reply, %{ok: false, error: msg}, socket}
      _ -> {:reply, %{ok: false, error: "You can't learn that right now."}, socket}
    end
  end

  def handle_event("hotbar_set", %{"hotbars" => bars}, socket) do
    with {:ok, c} <- character(socket),
         {:ok, clean} <- Skills.set_hotbars(c.id, bars) do
      {:reply, %{ok: true, hotbars: clean}, socket}
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Casting
  # ---------------------------------------------------------------------------

  def handle_event("cast", %{"ability" => id} = params, socket) do
    now = System.monotonic_time(:millisecond)

    with {:ok, c} <- character(socket),
         me when not is_nil(me) <- runtime(socket),
         %{} = a <- Abilities.get(id) || {:error, "You don't know that."},
         true <- Abilities.active?(a) || {:error, "That's always on."},
         true <- id in Skills.state(c).abilities || {:error, "You haven't learned #{a.name}."},
         false <- (socket.assigns[:is_dead?] || false) && {:error, "You can't do that while dead."},
         true <- (is_nil(socket.assigns[:mount]) or a.effect.type == "recall") || {:error, "You can't do that from the saddle."},
         true <- is_nil(socket.assigns[:casting]) || {:error, "You are already casting."},
         true <- ready?(socket, id, now) || {:error, "#{a.name} isn't ready yet."},
         true <- World.stat(c, "mp") >= a.mp || {:error, "You don't have enough mana."},
         {:ok, target} <- target_for(socket, me, a, params["target_id"]) do
      heading = if is_number(params["heading"]), do: params["heading"] * 1.0, else: me.position[:heading] || 0.0
      smash? = params["smash"] == true

      if a.cast_ms > 0 do
        token = make_ref()
        Process.send_after(self(), {:cast_complete, token}, a.cast_ms)
        cast = %{ability: id, token: token, from: {me.position.x, me.position.z}, target: target, heading: heading, smash: smash?}
        broadcast(socket, %{character_id: me.character_id, ability: id, phase: "begin", target: target, cast_ms: a.cast_ms, school: a.school})
        {:reply, %{ok: true, cast_ms: a.cast_ms}, assign(socket, casting: cast)}
      else
        socket = complete(socket, a, target, heading, smash?)
        {:reply, %{ok: true, cast_ms: 0}, socket}
      end
    else
      {:error, msg} when is_binary(msg) -> {:reply, %{ok: false, error: msg}, socket}
      _ -> {:reply, %{ok: false, error: "You can't do that right now."}, socket}
    end
  end

  def handle_event("cast_cancel", _params, socket), do: {:reply, %{ok: true}, cancel(socket, "cancelled")}

  def handle_event(_event, _params, socket), do: {:reply, %{ok: false, error: "bad request"}, socket}

  @doc "A cast time ran out: the spell goes off, unless the caster moved or died."
  def cast_complete(token, socket) do
    case socket.assigns[:casting] do
      %{token: ^token} = cast ->
        me = runtime(socket)
        {fx, fz} = cast.from
        moved = me && :math.sqrt(:math.pow(me.position.x - fx, 2) + :math.pow(me.position.z - fz, 2)) / Brain.u()

        cond do
          socket.assigns[:is_dead?] || is_nil(me) -> cancel(socket, "dead")
          moved > @interrupt_m -> cancel(socket, "interrupted")
          true -> socket |> assign(casting: nil) |> complete(Abilities.get(cast.ability), cast.target, cast.heading, cast[:smash] == true)
        end

      _ ->
        socket
    end
  end

  @doc "Interrupts a cast (moving, dying, being asked)."
  def cancel(socket, reason) do
    case socket.assigns[:casting] do
      nil ->
        socket

      cast ->
        if me = runtime(socket), do: broadcast(socket, %{character_id: me.character_id, ability: cast.ability, phase: "cancel"})

        socket
        |> assign(casting: nil)
        |> push_event("cast_result", %{ability: cast.ability, ok: false, reason: reason})
    end
  end

  # The spell or skill goes off: mana, cooldown, then what it does.
  defp complete(socket, a, target, heading, smash? \\ false) do
    with {:ok, c} <- character(socket),
         me when not is_nil(me) <- runtime(socket),
         {:ok, %{hp: hp, max_hp: max_hp, mp: mp, max_mp: max_mp}} <- Combat.get_character_stats(c.id),
         true <- mp >= a.mp || :no_mana do
      if a.mp > 0 do
        {:ok, _} = Combat.update_character_hp_mp(c.id, hp, mp - a.mp)
      end

      socket =
        socket
        |> push_event("character_stats_update", %{hp: hp, max_hp: max_hp, mp: mp - a.mp, max_mp: max_mp})
        |> assign(cooldowns: Map.put(socket.assigns[:cooldowns] || %{}, a.id, System.monotonic_time(:millisecond) + a.cooldown_ms))
        |> assign(current_smash: smash?)

      effect(socket, c, me, a, target, heading)
    else
      :no_mana -> push_event(socket, "cast_result", %{ability: a.id, ok: false, reason: "no_mana"})
      _ -> socket
    end
  end

  # 1. Recall
  defp effect(socket, c, me, %{effect: %{type: "recall"}} = a, _target, _heading) do
    socket = BaconWorldWeb.MountEvents.dismount(socket)
    dest = bind_point(c)
    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", from: [me.position.x, me.position.y, me.position.z], to: [dest.x, dest.y, dest.z], school: a.school})
    World.save_position(c.user_id, c.id, (me[:zone] && me.zone.slug) || "lobby", dest)

    socket
    |> assign(
      current_character_runtime: Map.put(me, :position, dest),
      last_world_update_ms: System.monotonic_time(:millisecond)
    )
    |> push_event("world_position_corrected", dest)
    |> result(a, %{})
  end

  # 2. Direct Heal & Heal-over-Time
  defp effect(socket, c, me, %{effect: %{type: "heal"} = e} = a, target, _heading) do
    buffs = active_buffs(socket)
    pct = Skills.bonus(c, "spell_pct") + buffs.dmg_pct
    amount = max(1, round(Abilities.amount(a, World.stat(c, "level")) * (1 + pct / 100)))
    hot_ticks = e[:hot_ticks] || 0
    socket = apply_self_buffs(socket, c, e)

    socket =
      if hot_ticks > 0 do
        ratio = if (e[:hot_ratio] || 0.0) > 0, do: e.hot_ratio, else: 0.3
        tick_amt = max(1, round(amount * ratio))
        Process.send_after(self(), {:hot_tick, target || me.character_id, tick_amt, hot_ticks}, 2_000)
        socket
      else
        socket
      end

    if target in [nil, me.character_id] do
      broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: me.character_id, amount: amount, school: a.school})
      socket |> heal(amount, nil) |> result(a, %{amount: amount, target: me.character_id})
    else
      if topic = socket.assigns[:current_zone_topic] do
        PubSub.broadcast(Bacon8.PubSub, topic, {:player_heal, %{target_id: target, amount: amount, from_id: me.character_id, from_name: me.name}})
      end

      broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: target, amount: amount, school: a.school})
      result(socket, a, %{amount: amount, target: target})
    end
  end

  # 3. Single-target Spell Damage (projectiles & beams) & Drain
  defp effect(socket, c, me, %{effect: %{type: type} = e} = a, target, _heading) when type in ["damage", "drain"] do
    socket = apply_self_buffs(socket, c, e)
    {damage, crit} = roll_spell_damage(socket, c, a, e)
    speed = e[:speed_m] || 22.0
    travel_ms = if speed > 0, do: travel_ms(socket, me, target, speed), else: 80
    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "launch", target: target, travel_ms: travel_ms, school: a.school})
    Process.send_after(self(), {:spell_land, %{ability: a.id, target: target, damage: damage, crit: crit, smash: socket.assigns[:current_smash] == true}}, travel_ms)
    socket
  end

  # 4. Area of Effect (self-centered nova or target-centered storm/meteor/eruption)
  defp effect(socket, c, me, %{effect: %{type: "aoe"} = e} = a, target, _heading) do
    socket = apply_self_buffs(socket, c, e)
    {cx, cz} = aoe_center(socket, me, target)
    {damage, crit} = roll_spell_damage(socket, c, a, e)
    radius_m = e[:radius_m] || 5.5

    broadcast(socket, %{
      character_id: me.character_id,
      ability: a.id,
      phase: "aoe",
      target: target,
      x: cx,
      z: cz,
      radius_m: radius_m,
      school: a.school
    })

    drain = drain_fraction(e)

    socket =
      if drain > 0 and damage > 0 do
        heal(socket, max(1, round(damage * drain)), nil)
      else
        socket
      end

    attack = %{
      id: me.character_id,
      shape: :circle,
      x: cx,
      z: cz,
      radius_m: radius_m,
      max_targets: e[:max] || 6,
      damage: damage,
      crit: crit,
      effect: e
    }

    pvp_hits = pvp_aoe(socket, me, cx, cz, radius_m * Brain.u(), damage, crit, a.id)
    if socket.assigns[:current_smash] == true do
      smash_aoe(socket, cx, cz, radius_m * Brain.u(), damage)
    end

    case Mobs.spell_aoe(zone(socket), attack) do
      {:ok, hits} ->
        {socket, progress} = GameEvents.award_kills(socket, hits)
        result(socket, a, %{hits: pvp_hits ++ hits, progress: progress})

      _ ->
        result(socket, a, %{hits: pvp_hits})
    end
  end

  # 5. Frontal Cone (Dragon's Breath, Cone of Cold, Gust, Crimson Tide, Tidal Wave, Chi Burst, etc.)
  defp effect(socket, c, me, %{effect: %{type: "cone"} = e} = a, _target, heading) do
    socket = apply_self_buffs(socket, c, e)
    {damage, crit} = roll_spell_damage(socket, c, a, e)
    arc = e[:arc] || 100
    range_m = max(a.range_m, 4.0)

    broadcast(socket, %{
      character_id: me.character_id,
      ability: a.id,
      phase: "cone",
      heading: heading,
      range_m: range_m,
      arc: arc,
      school: a.school
    })

    drain = drain_fraction(e)

    socket =
      if drain > 0 and damage > 0 do
        heal(socket, max(1, round(damage * drain)), nil)
      else
        socket
      end

    attack = %{
      id: me.character_id,
      shape: :cone,
      x: me.position.x,
      z: me.position.z,
      heading: heading,
      range_m: range_m,
      arc_deg: arc,
      max_targets: e[:max] || 5,
      damage: damage,
      crit: crit,
      effect: e
    }

    pvp_hits = pvp_cone(socket, me, heading, arc, range_m * Brain.u(), damage, crit, a.id)
    if socket.assigns[:current_smash] == true do
      smash_cone(socket, me, heading, arc, range_m * Brain.u(), damage)
    end

    case Mobs.spell_aoe(zone(socket), attack) do
      {:ok, hits} ->
        {socket, progress} = GameEvents.award_kills(socket, hits)
        result(socket, a, %{hits: pvp_hits ++ hits, progress: progress})

      _ ->
        result(socket, a, %{hits: pvp_hits})
    end
  end

  # 6. Chain (Chain Lightning, Chain Heal, Thorn Volley, Multi-Shot, Spiked Shield)
  defp effect(socket, c, me, %{effect: %{type: "chain"} = e} = a, target, _heading) do
    {damage, crit} = roll_spell_damage(socket, c, a, e)

    socket =
      if heal_pct = e[:heal_pct] do
        heal(socket, max(1, round(damage * heal_pct)), nil)
      else
        socket
      end

    attack = %{
      id: me.character_id,
      shape: :chain,
      target: target,
      x: me.position.x,
      z: me.position.z,
      range_m: max(a.range_m, 6.0),
      jumps: e[:jumps] || 3,
      jump_m: e[:jump_m] || 8.0,
      damage: damage,
      crit: crit,
      effect: e
    }

    case Mobs.spell_aoe(zone(socket), attack) do
      {:ok, hits} when hits != [] ->
        broadcast(socket, %{
          character_id: me.character_id,
          ability: a.id,
          phase: "chain",
          target: target,
          targets: Enum.map(hits, & &1.id),
          school: a.school
        })

        {socket, progress} = GameEvents.award_kills(socket, hits)
        result(socket, a, %{hits: hits, progress: progress})

      {:error, reason} ->
        push_event(socket, "cast_result", %{ability: a.id, ok: false, reason: to_string(reason)})

      _ ->
        push_event(socket, "cast_result", %{ability: a.id, ok: false, reason: "out_of_range"})
    end
  end

  # 7. Root (single-target Entangling Roots / Throw Net, or AoE Frost Nova / Quicksand / Traps)
  defp effect(socket, c, me, %{effect: %{type: "root"} = e} = a, target, _heading) do
    if a.target == "self" or is_nil(target) do
      {damage, crit} = roll_spell_damage(socket, c, a, e)
      radius_m = e[:radius_m] || 5.5

      broadcast(socket, %{
        character_id: me.character_id,
        ability: a.id,
        phase: "aoe",
        x: me.position.x,
        z: me.position.z,
        radius_m: radius_m,
        school: a.school
      })

      attack = %{
        id: me.character_id,
        shape: :circle,
        x: me.position.x,
        z: me.position.z,
        radius_m: radius_m,
        max_targets: e[:max] || 6,
        damage: damage,
        crit: crit,
        effect: Map.put(e, :root_ms, e[:ms] || 4_000)
      }

      case Mobs.spell_aoe(zone(socket), attack) do
        {:ok, hits} ->
          {socket, progress} = GameEvents.award_kills(socket, hits)
          result(socket, a, %{hits: hits, progress: progress})

        _ ->
          result(socket, a, %{hits: []})
      end
    else
      attack = %{id: me.character_id, target: target, ms: e.ms, x: me.position.x, z: me.position.z, range: a.range_m * 1.15 * Brain.u()}

      case Mobs.root(zone(socket), attack) do
        :ok ->
          broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: target, school: a.school})
          result(socket, a, %{target: target})

        {:error, reason} ->
          push_event(socket, "cast_result", %{ability: a.id, ok: false, reason: to_string(reason)})
      end
    end
  end

  # 8. Stun (single-target Deep Freeze / Hex of Slumber / Fear, or AoE Shadowfury / Intimidating Shout)
  defp effect(socket, c, me, %{effect: %{type: "stun"} = e} = a, target, _heading) do
    {damage, crit} = roll_spell_damage(socket, c, a, e)
    eff = Map.put(e, :stun_ms, e[:ms] || 3_000)

    if a.target == "self" or is_nil(target) do
      radius_m = e[:radius_m] || 6.0

      broadcast(socket, %{
        character_id: me.character_id,
        ability: a.id,
        phase: "aoe",
        x: me.position.x,
        z: me.position.z,
        radius_m: radius_m,
        school: a.school
      })

      attack = %{
        id: me.character_id,
        shape: :circle,
        x: me.position.x,
        z: me.position.z,
        radius_m: radius_m,
        max_targets: e[:max] || 5,
        damage: damage,
        crit: crit,
        effect: eff
      }

      case Mobs.spell_aoe(zone(socket), attack) do
        {:ok, hits} ->
          {socket, progress} = GameEvents.award_kills(socket, hits)
          result(socket, a, %{hits: hits, progress: progress})

        _ ->
          result(socket, a, %{hits: []})
      end
    else
      attack = %{
        id: me.character_id,
        target: target,
        damage: damage,
        crit: crit,
        x: me.position.x,
        z: me.position.z,
        range: a.range_m * 1.2 * Brain.u(),
        effect: eff
      }

      case Mobs.spell_hit(zone(socket), attack) do
        %{} = hit ->
          broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: target, school: a.school})
          {socket, progress} = GameEvents.award_kills(socket, [hit])
          result(socket, a, %{hits: [hit], progress: progress, target: target})

        {:error, reason} ->
          push_event(socket, "cast_result", %{ability: a.id, ok: false, reason: to_string(reason)})
      end
    end
  end

  # 9. Protective Shield / Ward (Ice Barrier, Mana Shield, Divine Shield, Barkskin, Stoneskin, Shield Wall, etc.)
  defp effect(socket, c, me, %{effect: %{type: "shield"} = e} = a, _target, _heading) do
    ms = non_zero(e[:duration_ms], e[:ms], 10_000)
    pct = Skills.bonus(c, "spell_pct")
    shield_amt = max(5, round(Abilities.amount(a, World.stat(c, "level")) * (1 + pct / 100)))
    e_with_shield = Map.put(e, :shield_hp, shield_amt) |> Map.put(:duration_ms, ms)

    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "shield", ms: ms, school: a.school})

    socket
    |> apply_self_buffs(c, e_with_shield)
    |> push_stats_sheet()
    |> result(a, %{shield: shield_amt, ms: ms})
  end

  # 10. Temporary Combat Buff / Stance / Shout / Meditation
  defp effect(socket, c, me, %{effect: %{type: "buff_temp"} = e} = a, _target, _heading) do
    ms = non_zero(e[:duration_ms], e[:ms], 10_000)
    socket = apply_self_buffs(socket, c, Map.put(e, :duration_ms, ms))

    heal_amt = Abilities.amount(a, World.stat(c, "level"))

    socket =
      cond do
        heal_amt > 0 ->
          heal(socket, heal_amt, nil)

        (e[:hp_pct] || 0) > 0 ->
          max_hp = World.stat(c, "max_hp")
          heal(socket, max(1, round(max_hp * e.hp_pct / 100)), nil)

        true ->
          socket
      end

    hot_ticks = e[:hot_ticks] || 0

    if hot_ticks > 0 do
      base_h = if heal_amt > 0, do: heal_amt, else: 20
      ratio = if (e[:hot_ratio] || 0.0) > 0, do: e.hot_ratio, else: 0.35
      Process.send_after(self(), {:hot_tick, me.character_id, max(1, round(base_h * ratio)), hot_ticks}, 2_000)
    end

    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "buff", ms: ms, school: a.school})

    socket
    |> push_stats_sheet()
    |> result(a, %{ms: ms})
  end

  # 11. Dash / Leap / Blink / Charge / Disengage / Dragoon Dive
  defp effect(socket, c, me, %{effect: %{type: "dash"} = e} = a, target, heading) do
    socket = apply_self_buffs(socket, c, e)
    u = Brain.u()
    dash_m = e[:dash_m] || 8.0
    dir = if dash_m >= 0, do: 1.0, else: -1.0
    dist_m = abs(dash_m)
    sin = :math.sin(heading) * dir
    cos = :math.cos(heading) * dir

    {tx, ty, tz} = dash_destination(me.position, sin, cos, dist_m, u)
    dest = %{x: tx, y: ty, z: tz, heading: heading}

    broadcast(socket, %{
      character_id: me.character_id,
      ability: a.id,
      phase: "dash",
      from: [me.position.x, me.position.y, me.position.z],
      to: [tx, ty, tz],
      school: a.school
    })

    socket =
      socket
      |> assign(
        current_character_runtime: Map.put(me, :position, dest),
        last_world_update_ms: System.monotonic_time(:millisecond)
      )
      |> push_event("world_position_corrected", dest)

    # If the dash also strikes on arrival (Lunge, Leap Slam, Dragoon Dive, Shield Charge, Flying Kick, Charge)
    if (e[:mult] && e.mult > 1.0) or (e[:base] && e.base > 0) or (e[:stun_ms] && e.stun_ms > 0) or (e[:slow_ms] && e.slow_ms > 0) do
      eq = socket.assigns[:equipment] || %{}
      item = eq["main"] || Items.fist()
      buffs = active_buffs(socket)

      attack = %{
        id: me.character_id,
        level: socket.assigns[:level] || 1,
        x: tx,
        z: tz,
        heading: heading,
        item: item,
        heavy: false,
        target: target,
        sweep: {e[:max] || 3, e[:arc] || 180},
        mult: e[:mult] || 1.25,
        extra_reach: e[:reach_m] || e[:radius_m] || 2.2,
        pct: Skills.bonus(c, "melee_pct") + buffs.dmg_pct,
        crit_bonus: buffs.crit,
        effect: e
      }

      dash_reach = max(3.8, Melee.pvp_reach(item) + (e[:reach_m] || e[:radius_m] || 2.2)) * u
      mult_val = (1 + (Skills.bonus(c, "melee_pct") + buffs.dmg_pct) / 100) * (e[:mult] || 1.25)
      {dash_dmg, dash_crit} = Melee.roll_damage(item, socket.assigns[:level] || 1, false, &:rand.uniform/0, mult: mult_val)
      pvp_hits = pvp_aoe(socket, me, tx, tz, dash_reach, dash_dmg, dash_crit, a.id)
      if socket.assigns[:current_smash] == true do
        smash_aoe(socket, tx, tz, dash_reach, dash_dmg)
      end

      case Mobs.melee(zone(socket), attack) do
        {:ok, hits} ->
          {socket, progress} = GameEvents.award_kills(socket, hits)
          result(socket, a, %{hits: pvp_hits ++ hits, progress: progress})

        _ ->
          result(socket, a, %{hits: pvp_hits})
      end
    else
      result(socket, a, %{})
    end
  end

  # 12. 360-degree or Wide Spin Attack
  defp effect(socket, c, me, %{effect: %{type: "spin"} = e} = a, _target, heading) do
    socket = apply_self_buffs(socket, c, e)
    eq = socket.assigns[:equipment] || %{}
    item = eq["main"] || Items.fist()
    buffs = active_buffs(socket)

    attack = %{
      id: me.character_id,
      level: socket.assigns[:level] || 1,
      x: me.position.x,
      z: me.position.z,
      heading: heading,
      item: item,
      heavy: false,
      target: nil,
      sweep: {e[:max] || 8, 360},
      mult: e[:mult] || 0.9,
      extra_reach: e[:reach_m] || 0.6,
      pct: Skills.bonus(c, "melee_pct") + buffs.dmg_pct,
      crit_bonus: buffs.crit,
      effect: e
    }

    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "spin", school: a.school})

    weapon_reach = Melee.pvp_reach(item)
    extra_reach = e[:reach_m] || 0.6
    spin_reach = max(4.2, weapon_reach + extra_reach) * Brain.u()
    mult_val = (1 + (Skills.bonus(c, "melee_pct") + buffs.dmg_pct) / 100) * (e[:mult] || 1.0)
    {spin_dmg, spin_crit} = Melee.roll_damage(item, socket.assigns[:level] || 1, false, &:rand.uniform/0, mult: mult_val)
    pvp_hits = pvp_aoe(socket, me, me.position.x, me.position.z, spin_reach, spin_dmg, spin_crit, a.id)
    if socket.assigns[:current_smash] == true do
      smash_aoe(socket, me.position.x, me.position.z, spin_reach, spin_dmg)
    end

    case Mobs.melee(zone(socket), attack) do
      {:ok, hits} ->
        {socket, progress} = GameEvents.award_kills(socket, hits)
        result(socket, a, %{hits: pvp_hits ++ hits, progress: progress})

      _ ->
        result(socket, a, %{hits: pvp_hits})
    end
  end

  # 13. Martial / Weapon Strike & Ranged Shot
  defp effect(socket, c, me, %{effect: %{type: "strike"} = e} = a, target, heading) do
    socket = apply_self_buffs(socket, c, e)
    eq = socket.assigns[:equipment] || %{}
    item = eq["main"] || Items.fist()
    buffs = active_buffs(socket)
    extra_reach = max(e[:reach_m] || 1.2, a.range_m - 2.0)
    strike_reach = (Melee.pvp_reach(item) + extra_reach) * Brain.u()
    arc = e[:arc] || 105
    max_targets = e[:max] || 1

    attack = %{
      id: me.character_id,
      level: socket.assigns[:level] || 1,
      x: me.position.x,
      z: me.position.z,
      heading: heading,
      item: item,
      heavy: false,
      target: target,
      sweep: {max_targets, arc},
      mult: e[:mult] || 1.35,
      extra_reach: extra_reach,
      execute_mult: e[:execute_mult],
      pct: Skills.bonus(c, "melee_pct") + buffs.dmg_pct,
      crit_bonus: buffs.crit,
      effect: e
    }

    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "strike", target: target, range_m: a.range_m, school: a.school})

    topic = socket.assigns[:current_zone_topic]
    my_pvp = (socket.assigns[:current_character_payload] && socket.assigns[:current_character_payload][:pvp_flagged] == true) ||
             (socket.assigns[:current_character_runtime] && socket.assigns[:current_character_runtime][:pvp_flagged] == true) ||
             Combat.pvp_flagged?(me.character_id)

    mult_val = (1 + (Skills.bonus(c, "melee_pct") + buffs.dmg_pct) / 100) * (e[:mult] || 1.35)
    crit_bonus = buffs.crit + (e[:crit_bonus] || 0.0)
    {strike_dmg, strike_crit} = Melee.roll_damage(item, socket.assigns[:level] || 1, false, &:rand.uniform/0, mult: mult_val, crit_bonus: crit_bonus)

    pvp_victims =
      if topic && my_pvp do
        (socket.assigns[:zone_online_characters] || [])
        |> Enum.filter(fn p ->
          p.character_id != me.character_id and not p.dead and
            (p[:pvp] == true || Combat.pvp_flagged?(p.character_id)) and
            (p.character_id == target or
             Melee.in_arc?({me.position.x, me.position.z}, heading, {(p.x || 0.0) * 1.0, (p.z || 0.0) * 1.0}, strike_reach, arc))
        end)
        |> Enum.sort_by(fn p -> {if(p.character_id == target, do: 0, else: 1), :math.pow((p.x || 0.0) - me.position.x, 2) + :math.pow((p.z || 0.0) - me.position.z, 2)} end)
        |> Enum.take(max_targets)
      else
        []
      end

    pvp_mult = Tuning.get("pvp_damage_mult") || 1.0
    final_damage = max(1, round(strike_dmg * pvp_mult))

    pvp_hits =
      Enum.map(pvp_victims, fn victim ->
        h = %{
          attacker_id: me.character_id,
          attacker_name: me.name,
          target_id: victim.character_id,
          target_name: victim.character_name,
          hit: true,
          damage: final_damage,
          crit: strike_crit,
          ability: a.id
        }
        PubSub.broadcast(Bacon8.PubSub, topic, {:pvp_hit, h})
        %{id: victim.character_id, name: victim.character_name, damage: final_damage, crit: strike_crit}
      end)

    drain = drain_fraction(e)
    socket = if drain > 0 and pvp_hits != [], do: heal(socket, max(1, round(final_damage * drain)), nil), else: socket

    if socket.assigns[:current_smash] == true do
      dmg = max(1, round(strike_dmg))
      u = Brain.u()

      placement_id =
        cond do
          is_binary(target) and BaconWorld.Building.placement?(zone(socket), target) ->
            target

          true ->
            placements = BaconWorld.Building.list(zone(socket))

            placements
            |> Enum.filter(fn p ->
              px = p.x * u
              pz = p.z * u
              Melee.in_arc?({me.position.x, me.position.z}, heading, {px, pz}, strike_reach, arc)
            end)
            |> Enum.min_by(fn p -> :math.pow(p.x * u - me.position.x, 2) + :math.pow(p.z * u - me.position.z, 2) end, fn -> nil end)
            |> case do
              %{id: pid} -> pid
              _ -> nil
            end
        end

      if placement_id do
        BaconWorld.Building.damage_placement(socket.assigns.current_user, zone(socket), placement_id, dmg)
      end
    end

    case Mobs.melee(zone(socket), attack) do
      {:ok, hits} ->
        drain = drain_fraction(e)

        socket =
          if drain > 0 and pvp_hits == [] do
            dealt = Enum.reduce(hits, 0, fn h, acc -> acc + (h[:damage] || 0) end)
            if dealt > 0, do: heal(socket, max(1, round(dealt * drain)), nil), else: socket
          else
            socket
          end

        {socket, progress} = GameEvents.award_kills(socket, hits)
        result(socket, a, %{hits: pvp_hits ++ hits, progress: progress})

      _ ->
        result(socket, a, %{hits: pvp_hits})
    end
  end

  # 14. Taunt / Challenge
  defp effect(socket, c, me, %{effect: %{type: "taunt"} = e} = a, target, _heading) do
    socket = apply_self_buffs(socket, c, e)

    attack = %{
      id: me.character_id,
      target: target,
      x: me.position.x,
      z: me.position.z,
      radius_m: e[:radius_m] || max(a.range_m, 8.0),
      max: e[:max] || 1,
      effect: e
    }

    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "taunt", target: target, school: a.school})

    case Mobs.taunt(zone(socket), attack) do
      {:ok, ids} ->
        result(socket, a, %{taunted: ids})

      _ ->
        result(socket, a, %{taunted: []})
    end
  end

  defp effect(socket, _c, _me, a, _target, _heading), do: result(socket, a, %{})

  @doc "A projectile's flight is over: it hits (or the creature got away)."
  def spell_land(%{ability: id, target: target, damage: damage, crit: crit} = payload, socket) do
    a = Abilities.get(id)
    me = runtime(socket)

    if me && a do
      # the creature may have moved during the flight: some slack on the range
      attack = %{
        id: me.character_id,
        target: target,
        damage: damage,
        crit: crit,
        x: me.position.x,
        z: me.position.z,
        range: max(a.range_m, 5.0) * 1.3 * Brain.u(),
        effect: a.effect
      }

      case Mobs.spell_hit(zone(socket), attack) do
        %{} = hit ->
          drain = drain_fraction(a.effect)

          socket =
            if drain > 0 and damage > 0 do
              heal(socket, max(1, round(damage * drain)), nil)
            else
              socket
            end

          socket =
            if (a.effect[:hot_ticks] || 0) > 0 and damage > 0 do
              Process.send_after(self(), {:hot_tick, me.character_id, max(1, round(damage * 0.25)), a.effect.hot_ticks}, 2_000)
              socket
            else
              socket
            end

          socket =
            if (a.effect[:mp_restore] || 0) > 0 do
              restore_mp(socket, me.character_id, a.effect.mp_restore)
            else
              socket
            end

          {socket, progress} = GameEvents.award_kills(socket, [hit])
          result(socket, a, %{hits: [hit], progress: progress})

        _ ->
          target_player = Enum.find(socket.assigns[:zone_online_characters] || [], &(&1.character_id == target))
          topic = socket.assigns[:current_zone_topic]

          cond do
            target_player && topic && Combat.pvp_flagged?(me.character_id) && Combat.pvp_flagged?(target_player.character_id) ->
              pvp_mult = Tuning.get("pvp_damage_mult") || 1.0
              final_damage = max(1, round(damage * pvp_mult))
              h = %{
                attacker_id: me.character_id,
                attacker_name: me.name,
                target_id: target_player.character_id,
                target_name: target_player.character_name,
                hit: true,
                damage: final_damage,
                crit: crit,
                ability: a.id
              }
              PubSub.broadcast(Bacon8.PubSub, topic, {:pvp_hit, h})
              broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: target, school: a.school})

              drain = drain_fraction(a.effect)
              socket = if drain > 0 and final_damage > 0, do: heal(socket, max(1, round(final_damage * drain)), nil), else: socket
              socket = if (a.effect[:mp_restore] || 0) > 0, do: restore_mp(socket, me.character_id, a.effect.mp_restore), else: socket

              result(socket, a, %{hits: [%{id: target_player.character_id, name: target_player.character_name, damage: final_damage, crit: crit}]})

            is_binary(target) and payload[:smash] == true and BaconWorld.Building.placement?(zone(socket), target) ->
              dmg = max(1, damage)
              BaconWorld.Building.damage_placement(socket.assigns.current_user, zone(socket), target, dmg)
              broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: target, school: a.school})
              result(socket, a, %{hits: [%{id: target, damage: dmg, crit: crit}]})

            true ->
              push_event(socket, "cast_result", %{ability: id, ok: false, reason: "miss"})
          end
      end
    else
      socket
    end
  end

  @doc "A periodic heal-over-time tick."
  def hot_tick(target_id, amount, left, socket) do
    me = runtime(socket)

    socket =
      if me && !socket.assigns[:is_dead?] do
        if target_id in [nil, me.character_id] do
          heal(socket, amount, nil)
        else
          if topic = socket.assigns[:current_zone_topic] do
            PubSub.broadcast(Bacon8.PubSub, topic, {:player_heal, %{target_id: target_id, amount: amount, from_id: me.character_id, from_name: me.name}})
          end

          socket
        end
      else
        socket
      end

    if left > 1 && me && !socket.assigns[:is_dead?] do
      Process.send_after(self(), {:hot_tick, target_id, amount, left - 1}, 2_000)
    end

    socket
  end

  @doc "Someone healed a player: the target's LiveView applies it."
  def player_heal(%{target_id: tid, amount: amount, from_name: from} = _h, socket) do
    me = runtime(socket)

    if me && me.character_id == tid && !socket.assigns[:is_dead?] do
      socket |> heal(amount, from)
    else
      socket
    end
  end

  @doc "A cast in the zone, ours included (the client draws them all the same way)."
  def zone_cast(payload, socket), do: push_event(socket, "zone_cast", payload)

  # ---------------------------------------------------------------------------

  defp non_zero(a, b, fallback) do
    cond do
      is_number(a) and a > 0 -> a
      is_number(b) and b > 0 -> b
      true -> fallback
    end
  end

  defp drain_fraction(e) do
    raw = e[:drain_pct] || e[:self_heal_pct] || e[:heal_pct] || 0

    cond do
      raw <= 0 -> 0.0
      raw > 1.0 -> raw / 100.0
      true -> raw * 1.0
    end
  end

  defp apply_self_buffs(socket, _c, e) do
    now = System.monotonic_time(:millisecond)
    ms = non_zero(e[:duration_ms], e[:ms], 10_000)
    raw = socket.assigns[:combat_buffs] || %{}

    shield_hp = non_zero(e[:shield_hp], 0, 0)
    ac_bonus = if (e[:temp_ac] || 0) != 0, do: e[:temp_ac], else: e[:ac] || e[:ac_bonus] || 0
    dmg_pct = if (e[:temp_dmg_pct] || 0) != 0, do: e[:temp_dmg_pct], else: e[:dmg_pct] || 0
    crit_bonus = if (e[:temp_crit] || 0.0) > 0, do: e[:temp_crit], else: e[:crit_bonus] || 0.0

    new_buffs =
      raw
      |> then(&if(shield_hp > 0, do: Map.merge(&1, %{shield: shield_hp, shield_until: now + ms}), else: &1))
      |> then(&if(ac_bonus != 0, do: Map.merge(&1, %{ac: ac_bonus, ac_until: now + ms}), else: &1))
      |> then(&if(dmg_pct != 0, do: Map.merge(&1, %{dmg_pct: dmg_pct, dmg_until: now + ms}), else: &1))
      |> then(&if(crit_bonus > 0, do: Map.merge(&1, %{crit: crit_bonus, crit_until: now + ms}), else: &1))

    socket = if new_buffs != raw, do: assign(socket, combat_buffs: new_buffs), else: socket

    if (e[:mp_restore] || 0) > 0 and runtime(socket) do
      restore_mp(socket, runtime(socket).character_id, e.mp_restore)
    else
      socket
    end
  end

  defp roll_spell_damage(socket, c, a, e) do
    buffs = active_buffs(socket)
    pct = Skills.bonus(c, "spell_pct") + buffs.dmg_pct
    base = Abilities.amount(a, World.stat(c, "level")) * (1 + pct / 100)

    if base <= 0 do
      {0, false}
    else
      spread = e[:spread] || 0.15
      crit_chance = Tuning.get("spell_crit_chance") + buffs.crit
      crit_mult = Tuning.get("spell_crit_mult")
      crit = :rand.uniform() < crit_chance
      damage = max(1, round(base * (1 - spread + :rand.uniform() * 2 * spread) * if(crit, do: crit_mult, else: 1.0)))
      {damage, crit}
    end
  end

  defp aoe_center(socket, me, target) do
    if is_binary(target) and target != "" do
      case Enum.find(Mobs.snapshot(zone(socket)) |> List.wrap(), &(&1[:id] == target)) do
        %{x: mx, z: mz} -> {mx * 1.0, mz * 1.0}
        _ -> {me.position.x, me.position.z}
      end
    else
      {me.position.x, me.position.z}
    end
  end

  defp dash_destination(pos, sin, cos, dist_m, u) do
    # Step along the ray in 1m increments so we stop before unwalkable water/cliffs
    steps = max(1, round(dist_m))
    step_m = dist_m / steps

    {fx, fz} =
      Enum.reduce_while(1..steps, {pos.x, pos.z}, fn i, {last_x, last_z} ->
        nx = pos.x + sin * (i * step_m) * u
        nz = pos.z + cos * (i * step_m) * u

        if Water.walkable?(nx / u, nz / u) do
          {:cont, {nx, nz}}
        else
          {:halt, {last_x, last_z}}
        end
      end)

    fy = Terrain.surface_units(fx, fz, u)
    {fx, fy, fz}
  end

  defp restore_mp(socket, character_id, amount) do
    case Combat.get_character_stats(character_id) do
      {:ok, %{hp: hp, max_hp: max_hp, mp: mp, max_mp: max_mp}} ->
        new_mp = min(max_mp, mp + amount)
        {:ok, _} = Combat.update_character_hp_mp(character_id, hp, new_mp)
        push_event(socket, "character_stats_update", %{hp: hp, max_hp: max_hp, mp: new_mp, max_mp: max_mp})

      _ ->
        socket
    end
  end

  defp heal(socket, amount, from) do
    me = runtime(socket)

    case Combat.get_character_stats(me.character_id) do
      {:ok, %{hp: hp, max_hp: max_hp, mp: mp, max_mp: max_mp}} ->
        new_hp = min(max_hp, hp + amount)
        {:ok, _} = Combat.update_character_hp_mp(me.character_id, new_hp, mp)

        socket
        |> assign(current_character_runtime: Map.put(me, :hp, new_hp))
        |> push_event("character_stats_update", %{hp: new_hp, max_hp: max_hp, mp: mp, max_mp: max_mp})
        |> GameEvents.broadcast_hp(me.character_id, new_hp, max_hp, "hurt")
        |> then(&if(from, do: push_event(&1, "healed", %{from: from, amount: new_hp - hp}), else: &1))

      _ ->
        socket
    end
  end

  # After a buff: the pools grew (or shrank), everyone's view of our bar too.
  defp refresh_pools(socket, c) do
    me = runtime(socket)
    hp = World.stat(c, "hp")
    max_hp = World.stat(c, "max_hp")

    socket =
      socket
      |> push_event("character_stats_update", %{hp: hp, max_hp: max_hp, mp: World.stat(c, "mp"), max_mp: World.stat(c, "max_mp")})

    if me,
      do: socket |> assign(current_character_runtime: Map.merge(me, %{hp: hp, max_hp: max_hp, max_mp: World.stat(c, "max_mp")})) |> GameEvents.broadcast_hp(me.character_id, hp, max_hp, "hurt"),
      else: socket
  end

  defp result(socket, a, extra) do
    push_event(socket, "cast_result", Map.merge(%{ability: a.id, ok: true, cooldown_ms: a.cooldown_ms}, extra))
  end

  # Who a spell is aimed at: a creature id for "enemy", a player (or you) for
  # "friendly" within range, nothing for the rest.
  defp target_for(_socket, _me, %{target: "self"}, _id), do: {:ok, nil}
  defp target_for(_socket, _me, %{target: t}, id) when t in ["none", "enemy"] and is_binary(id) and id != "", do: {:ok, id}
  defp target_for(_socket, _me, %{target: "none"}, _id), do: {:ok, nil}
  defp target_for(_socket, _me, %{target: "enemy"}, _id), do: {:error, "You need a target."}

  defp target_for(socket, me, %{target: "friendly", range_m: range}, id) do
    other = is_binary(id) && id != me.character_id && Enum.find(socket.assigns[:zone_online_characters] || [], &(&1.character_id == id))

    cond do
      !other ->
        {:ok, me.character_id}

      other.dead ->
        {:error, "#{other.character_name} is dead."}

      :math.sqrt(:math.pow((other.x || 0.0) - me.position.x, 2) + :math.pow((other.z || 0.0) - me.position.z, 2)) > range * Brain.u() ->
        {:error, "#{other.character_name} is too far away."}

      true ->
        {:ok, other.character_id}
    end
  end

  defp travel_ms(socket, me, target, speed_m) do
    # where the creature is now (the zone's last snapshot is enough for a flight time)
    with %{} = mob <- Enum.find(Mobs.snapshot(zone(socket)) |> List.wrap(), &(&1[:id] == target)) do
      d = :math.sqrt(:math.pow((mob[:x] || 0.0) - me.position.x, 2) + :math.pow((mob[:z] || 0.0) - me.position.z, 2)) / Brain.u()
      round(min(d / max(speed_m, 1.0), 2.0) * 1000)
    else
      _ ->
        case Enum.find(socket.assigns[:zone_online_characters] || [], &(&1.character_id == target)) do
          %{x: px, z: pz} ->
            d = :math.sqrt(:math.pow((px || 0.0) - me.position.x, 2) + :math.pow((pz || 0.0) - me.position.z, 2)) / Brain.u()
            round(min(d / max(speed_m, 1.0), 2.0) * 1000)

          _ ->
            case BaconWorld.Building.get(zone(socket), target) do
              %{x: px, z: pz} ->
                u = Brain.u()
                d = :math.sqrt(:math.pow(px * u - me.position.x, 2) + :math.pow(pz * u - me.position.z, 2)) / u
                round(min(d / max(speed_m, 1.0), 2.0) * 1000)

              _ ->
                400
            end
        end
    end
  end

  defp pvp_aoe(socket, me, cx, cz, radius_scene, damage, crit, ability_id) do
    topic = socket.assigns[:current_zone_topic]
    my_pvp = (socket.assigns[:current_character_payload] && socket.assigns[:current_character_payload][:pvp_flagged] == true) ||
             (socket.assigns[:current_character_runtime] && socket.assigns[:current_character_runtime][:pvp_flagged] == true) ||
             Combat.pvp_flagged?(me.character_id)

    if topic && my_pvp do
      pvp_mult = Tuning.get("pvp_damage_mult") || 1.0
      final_damage = max(1, round(damage * pvp_mult))

      (socket.assigns[:zone_online_characters] || [])
      |> Enum.filter(fn p ->
        p.character_id != me.character_id and not p.dead and
          (p[:pvp] == true || Combat.pvp_flagged?(p.character_id)) and
          :math.sqrt(:math.pow((p.x || 0.0) - cx, 2) + :math.pow((p.z || 0.0) - cz, 2)) <= radius_scene
      end)
      |> Enum.map(fn p ->
        h = %{
          attacker_id: me.character_id,
          attacker_name: me.name,
          target_id: p.character_id,
          target_name: p.character_name,
          hit: true,
          damage: final_damage,
          crit: crit,
          ability: ability_id
        }
        PubSub.broadcast(Bacon8.PubSub, topic, {:pvp_hit, h})
        %{id: p.character_id, name: p.character_name, damage: final_damage, crit: crit}
      end)
    else
      []
    end
  end

  defp pvp_cone(socket, me, heading, arc_deg, range_scene, damage, crit, ability_id) do
    topic = socket.assigns[:current_zone_topic]
    my_pvp = (socket.assigns[:current_character_payload] && socket.assigns[:current_character_payload][:pvp_flagged] == true) ||
             (socket.assigns[:current_character_runtime] && socket.assigns[:current_character_runtime][:pvp_flagged] == true) ||
             Combat.pvp_flagged?(me.character_id)

    if topic && my_pvp do
      pvp_mult = Tuning.get("pvp_damage_mult") || 1.0
      final_damage = max(1, round(damage * pvp_mult))

      (socket.assigns[:zone_online_characters] || [])
      |> Enum.filter(fn p ->
        p.character_id != me.character_id and not p.dead and
          (p[:pvp] == true || Combat.pvp_flagged?(p.character_id)) and
          Melee.in_arc?({me.position.x, me.position.z}, heading, {(p.x || 0.0) * 1.0, (p.z || 0.0) * 1.0}, range_scene, arc_deg)
      end)
      |> Enum.map(fn p ->
        h = %{
          attacker_id: me.character_id,
          attacker_name: me.name,
          target_id: p.character_id,
          target_name: p.character_name,
          hit: true,
          damage: final_damage,
          crit: crit,
          ability: ability_id
        }
        PubSub.broadcast(Bacon8.PubSub, topic, {:pvp_hit, h})
        %{id: p.character_id, name: p.character_name, damage: final_damage, crit: crit}
      end)
    else
      []
    end
  end

  defp smash_aoe(socket, cx, cz, radius_scene, damage) do
    zone = zone(socket)
    u = Brain.u()
    placements = BaconWorld.Building.list(zone)

    placements
    |> Enum.filter(fn p ->
      px = p.x * u
      pz = p.z * u
      :math.sqrt(:math.pow(px - cx, 2) + :math.pow(pz - cz, 2)) <= radius_scene
    end)
    |> Enum.each(fn p ->
      BaconWorld.Building.damage_placement(socket.assigns.current_user, zone, p.id, max(1, round(damage)))
    end)
  end

  defp smash_cone(socket, me, heading, arc_deg, range_scene, damage) do
    zone = zone(socket)
    u = Brain.u()
    placements = BaconWorld.Building.list(zone)

    placements
    |> Enum.filter(fn p ->
      px = p.x * u
      pz = p.z * u
      Melee.in_arc?({me.position.x, me.position.z}, heading, {px, pz}, range_scene, arc_deg)
    end)
    |> Enum.each(fn p ->
      BaconWorld.Building.damage_placement(socket.assigns.current_user, zone, p.id, max(1, round(damage)))
    end)
  end

  defp ready?(socket, id, now), do: now >= Map.get(socket.assigns[:cooldowns] || %{}, id, now)

  defp bind_point(c) do
    case (c.settings || %{})["bind"] do
      %{"x" => x, "z" => z} = b -> %{x: x * 1.0, y: (b["y"] || 0.0) * 1.0, z: z * 1.0, heading: (b["heading"] || 0.0) * 1.0}
      _ -> World.spawn_point(World.zone_for((c.settings || %{})["zone_slug"]))
    end
  end

  defp broadcast(socket, payload) do
    if topic = socket.assigns[:current_zone_topic], do: PubSub.broadcast(Bacon8.PubSub, topic, {:zone_cast, payload})
    :ok
  end

  defp zone(socket), do: socket.assigns[:mobs_zone] || "lobby"

  defp runtime(socket), do: socket.assigns[:current_character_runtime] || socket.assigns[:current_character_payload]

  defp character(socket) do
    case runtime(socket) do
      %{character_id: id} -> World.fetch_character(id)
      _ -> {:error, :not_in_world}
    end
  end
end
