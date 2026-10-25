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
  (a projectile, with `travel_ms`), "land"; `"spin"`), `"healed"` (someone healed
  you), and `"world_position_corrected"` for Recall.

  Spell damage lands after the projectile's flight (`{:spell_land, ...}`); a heal on
  another player is applied by that player's LiveView (`{:player_heal, ...}` on the
  zone topic), as creature hits are.
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias BaconWorld.{Abilities, Combat, Items, Mobs, Skills, World}
  alias BaconWorld.Mobs.Brain
  alias BaconWorldWeb.GameEvents
  alias Phoenix.PubSub

  # moving further than this (metres) while casting interrupts the cast
  @interrupt_m 0.6

  # ---------------------------------------------------------------------------
  # The tree and the hotbars
  # ---------------------------------------------------------------------------

  def handle_event("skills_fetch", _params, socket) do
    case character(socket) do
      {:ok, c} -> {:reply, Map.put(Skills.payload(c), :ok, true), socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("skill_learn", %{"node" => node}, socket) do
    with {:ok, c} <- character(socket),
         {:ok, payload} <- Skills.learn(c.id, node) do
      {:ok, c} = World.fetch_character(c.id)
      socket = refresh_pools(socket, c)
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

      if a.cast_ms > 0 do
        token = make_ref()
        Process.send_after(self(), {:cast_complete, token}, a.cast_ms)
        cast = %{ability: id, token: token, from: {me.position.x, me.position.z}, target: target, heading: heading}
        broadcast(socket, %{character_id: me.character_id, ability: id, phase: "begin", target: target, cast_ms: a.cast_ms})
        {:reply, %{ok: true, cast_ms: a.cast_ms}, assign(socket, casting: cast)}
      else
        socket = complete(socket, a, target, heading)
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
          true -> socket |> assign(casting: nil) |> complete(Abilities.get(cast.ability), cast.target, cast.heading)
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
  defp complete(socket, a, target, heading) do
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

      effect(socket, c, me, a, target, heading)
    else
      :no_mana -> push_event(socket, "cast_result", %{ability: a.id, ok: false, reason: "no_mana"})
      _ -> socket
    end
  end

  defp effect(socket, c, me, %{effect: %{type: "recall"}} = a, _target, _heading) do
    socket = BaconWorldWeb.MountEvents.dismount(socket)
    dest = bind_point(c)
    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", from: [me.position.x, me.position.y, me.position.z], to: [dest.x, dest.y, dest.z]})
    World.save_position(c.user_id, c.id, (me[:zone] && me.zone.slug) || "lobby", dest)

    socket
    |> assign(
      current_character_runtime: Map.put(me, :position, dest),
      last_world_update_ms: System.monotonic_time(:millisecond)
    )
    |> push_event("world_position_corrected", dest)
    |> result(a, %{})
  end

  defp effect(socket, c, me, %{effect: %{type: "heal"}} = a, target, _heading) do
    amount = round(Abilities.amount(a, World.stat(c, "level")) * (1 + Skills.bonus(c, "spell_pct") / 100))

    if target in [nil, me.character_id] do
      broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: me.character_id, amount: amount})
      socket |> heal(amount, nil) |> result(a, %{amount: amount, target: me.character_id})
    else
      if topic = socket.assigns[:current_zone_topic] do
        PubSub.broadcast(Bacon8.PubSub, topic, {:player_heal, %{target_id: target, amount: amount, from_id: me.character_id, from_name: me.name}})
      end

      broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: target, amount: amount})
      result(socket, a, %{amount: amount, target: target})
    end
  end

  defp effect(socket, c, me, %{effect: %{type: "damage"} = e} = a, target, _heading) do
    pct = Skills.bonus(c, "spell_pct")
    base = Abilities.amount(a, World.stat(c, "level")) * (1 + pct / 100)
    crit = :rand.uniform() < 0.06
    damage = max(1, round(base * (1 - e.spread + :rand.uniform() * 2 * e.spread) * if(crit, do: 1.5, else: 1.0)))
    travel_ms = travel_ms(socket, me, target, e.speed_m)
    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "launch", target: target, travel_ms: travel_ms})
    Process.send_after(self(), {:spell_land, %{ability: a.id, target: target, damage: damage, crit: crit}}, travel_ms)
    socket
  end

  defp effect(socket, _c, me, %{effect: %{type: "root"} = e} = a, target, _heading) do
    attack = %{id: me.character_id, target: target, ms: e.ms, x: me.position.x, z: me.position.z, range: a.range_m * 1.15 * Brain.u()}

    case Mobs.root(zone(socket), attack) do
      :ok ->
        broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "land", target: target})
        result(socket, a, %{target: target})

      {:error, reason} ->
        push_event(socket, "cast_result", %{ability: a.id, ok: false, reason: to_string(reason)})
    end
  end

  defp effect(socket, c, me, %{effect: %{type: "spin"} = e} = a, _target, heading) do
    eq = socket.assigns[:equipment] || %{}
    item = eq["main"] || Items.fist()

    attack = %{
      id: me.character_id,
      level: socket.assigns[:level] || 1,
      x: me.position.x,
      z: me.position.z,
      heading: heading,
      item: item,
      heavy: false,
      target: nil,
      sweep: {e.max, 360},
      mult: e.mult,
      extra_reach: e.reach_m,
      pct: Skills.bonus(c, "melee_pct")
    }

    broadcast(socket, %{character_id: me.character_id, ability: a.id, phase: "spin"})

    case Mobs.melee(zone(socket), attack) do
      {:ok, hits} ->
        {socket, progress} = GameEvents.award_kills(socket, hits)
        result(socket, a, %{hits: hits, progress: progress})

      _ ->
        result(socket, a, %{hits: []})
    end
  end

  defp effect(socket, _c, _me, a, _target, _heading), do: result(socket, a, %{})

  @doc "A fireball's flight is over: it hits (or the creature got away)."
  def spell_land(%{ability: id, target: target, damage: damage, crit: crit}, socket) do
    a = Abilities.get(id)
    me = runtime(socket)

    if me do
      # the creature may have moved during the flight: some slack on the range
      attack = %{id: me.character_id, target: target, damage: damage, crit: crit, x: me.position.x, z: me.position.z, range: a.range_m * 1.3 * Brain.u()}

      case Mobs.spell_hit(zone(socket), attack) do
        %{} = hit ->
          {socket, progress} = GameEvents.award_kills(socket, [hit])
          result(socket, a, %{hits: [hit], progress: progress})

        {:error, reason} ->
          push_event(socket, "cast_result", %{ability: id, ok: false, reason: to_string(reason)})
      end
    else
      socket
    end
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
  defp target_for(_socket, _me, %{target: t}, _id) when t in ["self", "none"], do: {:ok, nil}

  defp target_for(_socket, _me, %{target: "enemy"}, id) when is_binary(id) and id != "", do: {:ok, id}
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
      round(min(d / speed_m, 2.0) * 1000)
    else
      _ -> 400
    end
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
