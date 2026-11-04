defmodule BaconWorld.Mobs.Zone do
  @moduledoc """
  The creatures of one zone: one process for the whole cluster (registered with
  `:global`; `BaconWorld.Mobs.Keeper` on every node makes sure it runs somewhere).

  Ten times a second it runs `BaconWorld.Mobs.Brain` for every creature against
  the players in the zone, read from Presence (each player's LiveView keeps its
  position, level and whether it is dead in its presence meta). It broadcasts on
  `BaconWorld.Mobs.topic/1`:

    * `{:mob_events, [event]}` - spawns, aggro, attacks, damage, deaths, corpses
      (maps with a `"t"` type; see `event/1`)
    * `{:mob_motion, [[id, x, z, h, vx, vz]]}` - five times a second, for the
      creatures that are moving

  Swings and looting come in as calls from the players' LiveViews
  (`BaconWorld.Mobs`), so a creature's HP and its corpse are only ever changed here.

  Managed camps (2026-11-03, `BaconWorld.Mobs.Camps`): their points come with the zone's others;
  after every change the camp rules run (`camp_rules/4`): campmates assist, a camp whose last
  creature falls is cleared (its reward goes on that corpse and into that kill's experience,
  announced in zone chat) and every few clears its boss rises (a point that spawns once). Points
  with a time of day (`BaconWorld.Mobs.Rotation`) empty out when it ends (`depop_out_of_window/1`).
  """
  use GenServer
  require Logger

  alias BaconWorld.Mobs
  alias BaconWorld.Mobs.{Brain, Camps, Rotation, Spawns}
  alias BaconWorld.World
  alias Bacon8Web.Presence

  @tick_ms 100
  @motion_every 2
  @players_every 2
  # ticks between looks at the time of day (camp slots that hold creatures by day or by night)
  @window_every 50

  def name(slug), do: {:global, {__MODULE__, slug}}

  def start_link(slug), do: GenServer.start_link(__MODULE__, slug, name: name(slug))

  @impl true
  def init(slug) do
    send(self(), :setup)

    {:ok,
     %{slug: slug, topic: Mobs.topic(slug), zone_topic: nil, mobs: %{}, points: %{}, players: %{}, n: 0, last: now(), moving: MapSet.new(),
       # managed camps: camp key ("c:<id>") => the camp; its clears since its boss last rose
       camps: %{}, camp_state: %{}}}
  end

  @impl true
  def handle_info(:setup, state) do
    # this process's ground is its zone's (BaconWorld.Terrain.use_zone/1)
    BaconWorld.Terrain.use_zone(state.slug)

    case zone_id(state.slug) do
      nil ->
        # No database yet, or the zone isn't seeded: try again shortly.
        Process.send_after(self(), :setup, 10_000)
        {:noreply, state}

      id ->
        t = now()
        # the camps in code, and the spawns placed in build mode (BaconWorld.Building)
        # (the code's village and camps become placements the first time: BaconWorld.Building)
        seeded = BaconWorld.Building.ensure_seeded(state.slug)
        camps = Map.new(Camps.for_zone(state.slug), fn {cid, c} -> {Camps.key(cid), c} end)
        points = Map.new(Spawns.points(seeded.camps) ++ BaconWorld.Building.mob_points(state.slug) ++ Camps.points_for_zone(state.slug), &{&1.id, &1})
        mobs = Map.new(points, fn {id, p} -> {id, rise(p, t)} end)
        Logger.info("bacon_world:mobs zone=#{state.slug} node=#{node()} creatures=#{map_size(mobs)} camps=#{map_size(camps)}")
        Process.send_after(self(), :tick, @tick_ms)
        {:noreply, %{state | zone_topic: "bacon_world:zone:#{id}", points: points, mobs: mobs, last: t, camps: camps}}
    end
  end

  def handle_info(:tick, state) do
    t = now()
    dt = min((t - state.last) / 1000, 0.5)
    state = if rem(state.n, @players_every) == 0, do: %{state | players: players(state.zone_topic)}, else: state

    {mobs, events} =
      Enum.reduce(state.mobs, {state.mobs, []}, fn {id, mob}, {acc, evs} ->
        {mob2, e} = Brain.tick(mob, state.players, t, dt, state.points[id])
        {Map.put(acc, id, mob2), evs ++ e}
      end)

    # a camp boss (a point that spawns once) is gone for good once its corpse is
    once = for {id, m} <- mobs, m.state == :gone, get_in(state.points, [id, :once]) == true, do: id
    state = %{state | mobs: Map.drop(mobs, once), points: Map.drop(state.points, once)}
    {state, _hits, events} = camp_rules(state, [], events, t)
    {state, w_events} = if rem(state.n, @window_every) == 0, do: depop_out_of_window(state, t), else: {state, []}
    events = events ++ w_events

    broadcast_events(state.topic, events)
    state = %{state | last: t, n: state.n + 1}
    state = if rem(state.n, @motion_every) == 0, do: broadcast_motion(state), else: state
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:snapshot, _from, state) do
    views = state.mobs |> Map.values() |> Enum.filter(&(&1.state != :gone)) |> Enum.map(&Brain.view/1)
    {:reply, views, state}
  end

  def handle_call({:melee, attack}, _from, state) do
    t = now()
    {mobs, hits, events} = Brain.melee(state.mobs, attack, t)
    {state, hits, events} = camp_rules(%{state | mobs: mobs}, hits, events, t)
    broadcast_events(state.topic, events)
    {:reply, {:ok, hits}, state}
  end

  def handle_call({:spell_hit, attack}, _from, state) do
    t = now()

    case Brain.spell_hit(state.mobs, attack, t) do
      {mobs, %{} = hit, events} ->
        {state, [hit], events} = camp_rules(%{state | mobs: mobs}, [hit], events, t)
        broadcast_events(state.topic, events)
        {:reply, hit, state}

      {mobs, result, events} ->
        broadcast_events(state.topic, events)
        {:reply, result, %{state | mobs: mobs}}
    end
  end

  def handle_call({:spell_aoe, attack}, _from, state) do
    t = now()

    case Brain.spell_aoe(state.mobs, attack, t) do
      {_mobs, {:error, _} = err, _events} ->
        {:reply, err, state}

      {mobs, hits, events} ->
        {state, hits, events} = camp_rules(%{state | mobs: mobs}, hits, events, t)
        broadcast_events(state.topic, events)
        {:reply, {:ok, hits}, state}
    end
  end

  def handle_call({:taunt, attack}, _from, state) do
    t = now()
    {mobs, count, events} = Brain.taunt(state.mobs, attack, t)
    {state, _hits, events} = camp_rules(%{state | mobs: mobs}, [], events, t)
    broadcast_events(state.topic, events)
    {:reply, {:ok, count}, state}
  end

  def handle_call({:root, attack}, _from, state) do
    t = now()
    {mobs, result, events} = Brain.root(state.mobs, attack, t)
    {state, _hits, events} = camp_rules(%{state | mobs: mobs}, [], events, t)
    broadcast_events(state.topic, events)
    {:reply, result, state}
  end

  # The admin's view of a managed camp (/admin/bacon_world/bestiary): its creatures and clears.
  def handle_call({:camp_status, camp_id}, _from, state) do
    ck = Camps.key(camp_id)
    prefix = ck <> ":"
    t = now()

    mobs =
      for {id, m} <- state.mobs, String.starts_with?(id, prefix) do
        %{
          id: id,
          kind: m.kind,
          name: m.name,
          level: m.level,
          state: m.state,
          hp: max(m.hp, 0),
          max_hp: m.max_hp,
          elite: Map.get(m, :elite, false),
          boss: Camps.boss_id?(id),
          target: m.target,
          respawn_in_s: if(m.state == :gone and is_integer(m.respawn_at), do: max(0, div(m.respawn_at - t, 1000))),
          decays_in_s: if(m.state == :dead and m.corpse, do: max(0, div(m.corpse.despawn_at - t, 1000)))
        }
      end
      |> Enum.sort_by(& &1.id)

    cs = Map.get(state.camp_state, ck, %{clears: 0, boss_up: false})
    {:reply, {:ok, Map.merge(cs, %{mobs: mobs, running: Map.has_key?(state.camps, ck)})}, state}
  end

  def handle_call({:loot_open, id, character_id, pos}, _from, state) do
    with %{} = mob <- state.mobs[id] || {:error, :not_a_corpse},
         {:ok, mob2, coins, items} <- Brain.loot_open(mob, character_id, pos, now()) do
      broadcast_events(state.topic, [{:corpse, mob2}])
      {:reply, {:ok, coins, items}, put_in(state.mobs[id], mob2)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:loot_take, id, character_id, index}, _from, state) do
    with %{} = mob <- state.mobs[id] || {:error, :not_looting},
         {:ok, mob2, item} <- Brain.loot_take(mob, character_id, index) do
      {:reply, {:ok, item, mob2.corpse.items}, put_in(state.mobs[id], mob2)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:put_points, placement_id, new_points}, state) do
    {:noreply, replace_points(state, "p:#{placement_id}:", new_points)}
  end

  # A managed camp saved, moved here or deleted (nil): its creatures start over.
  def handle_cast({:put_camp, camp_id, camp}, state) do
    ck = Camps.key(camp_id)
    live? = camp != nil and Map.get(camp, :enabled, true) != false and camp[:zone] == state.slug
    points = if live?, do: Camps.points(camp_id, camp), else: []
    state = replace_points(state, ck <> ":", points)
    camps = if live?, do: Map.put(state.camps, ck, camp), else: Map.delete(state.camps, ck)
    {:noreply, %{state | camps: camps, camp_state: if(live?, do: state.camp_state, else: Map.delete(state.camp_state, ck))}}
  end

  # The admin's "Respawn now": what is dead or gone in a managed camp comes back at once.
  def handle_cast({:camp_respawn, camp_id}, state) do
    prefix = Camps.key(camp_id) <> ":"
    t = now()

    mobs =
      Map.new(state.mobs, fn {id, m} ->
        cond do
          not String.starts_with?(id, prefix) or Camps.boss_id?(id) -> {id, m}
          m.state == :gone -> {id, %{m | respawn_at: t}}
          m.state == :dead and m.corpse != nil -> {id, m |> Map.put(:respawn_now, true) |> Map.put(:corpse, %{m.corpse | despawn_at: t})}
          true -> {id, m}
        end
      end)

    {:noreply, %{state | mobs: mobs}}
  end

  # The admin's "Clear out": a managed camp's creatures vanish and come back on their timers.
  def handle_cast({:camp_despawn, camp_id}, state) do
    prefix = Camps.key(camp_id) <> ":"
    t = now()

    {mobs, events} =
      Enum.reduce(state.mobs, {state.mobs, []}, fn {id, m}, {acc, evs} ->
        if String.starts_with?(id, prefix) and Brain.alive?(m) do
          delay = Enum.random(get_in(state.points, [id, :respawn_ms]) || Spawns.respawn_ms(m.kind))
          {Map.put(acc, id, %{m | state: :gone, target: nil, goal: nil, vx: 0.0, vz: 0.0, corpse: nil, respawn_at: t + delay}), evs ++ [{:corpse_gone, id}]}
        else
          {acc, evs}
        end
      end)

    broadcast_events(state.topic, events)
    {:noreply, %{state | mobs: mobs}}
  end

  def handle_cast({:loot_return, id, item}, state) do
    case state.mobs[id] do
      nil -> {:noreply, state}
      mob -> {:noreply, put_in(state.mobs[id], Brain.loot_return(mob, item))}
    end
  end

  def handle_cast({:loot_close, id, character_id}, state) do
    case state.mobs[id] do
      nil ->
        {:noreply, state}

      mob ->
        mob2 = Brain.loot_close(mob, character_id, now())
        broadcast_events(state.topic, [{:corpse, mob2}])
        {:noreply, put_in(state.mobs[id], mob2)}
    end
  end

  # ---------------------------------------------------------------------------

  defp now, do: System.monotonic_time(:millisecond)

  # A point's creature as the zone starts (or the point changes): risen, or waiting for its time
  # of day (a camp slot's `window`).
  defp rise(point, t) do
    if Rotation.open?(point, Rotation.wall_ms()), do: Brain.spawn(point, t), else: Brain.dormant(point, t)
  end

  # Every point whose id starts with `prefix` (a placed spawn's, a managed camp's) is replaced by
  # `new_points`: the old creatures vanish and the new ones rise at once.
  defp replace_points(state, prefix, new_points) do
    t = now()
    gone = for {id, _} <- state.points, String.starts_with?(id, prefix), do: id
    fresh = Map.new(new_points, &{&1.id, &1})
    mobs = Map.drop(state.mobs, gone)
    spawned = Map.new(fresh, fn {id, p} -> {id, rise(p, t)} end)
    risen = for {_id, m} <- spawned, Brain.alive?(m), do: {:spawn, Brain.view(m)}
    broadcast_events(state.topic, Enum.map(gone, &{:corpse_gone, &1}) ++ risen)
    %{state | points: state.points |> Map.drop(gone) |> Map.merge(fresh), mobs: Map.merge(mobs, spawned), moving: MapSet.difference(state.moving, MapSet.new(gone))}
  end

  # ---------------------------------------------------------------- managed camps

  # After creatures changed (a tick, a swing, a spell): campmates assist, cleared camps pay out
  # and escalate. `hits` are the swing's or spell's (a clear multiplies the last kill's
  # `xp_mult`). Returns `{state, hits, events}` with the extra events appended.
  defp camp_rules(%{camps: camps} = state, hits, events, _t) when camps == %{}, do: {state, hits, events}

  defp camp_rules(state, hits, events, t) do
    {mobs, assist_evs} =
      if Enum.any?(events, &match?({:aggro, _, _}, &1)),
        do: Camps.assist(state.mobs, events, state.camps, t),
        else: {state.mobs, []}

    died = for {:died, id, _killer} <- events, do: id
    {state, hits, clear_evs} = Enum.reduce(died, {%{state | mobs: mobs}, hits, []}, &on_death(&2, &1, t))
    {state, hits, events ++ assist_evs ++ clear_evs}
  end

  defp on_death({state, hits, evs}, id, t) do
    with %{camp: ("c:" <> camp_id) = ck} = mob <- state.mobs[id],
         %{} = camp <- state.camps[ck] do
      cs = Map.get(state.camp_state, ck, %{clears: 0, boss_up: false})

      cond do
        Camps.boss_id?(id) ->
          {%{state | camp_state: Map.put(state.camp_state, ck, %{cs | boss_up: false})}, hits, evs}

        Camps.cleared?(state.mobs, ck) ->
          cleared(state, hits, evs, {id, mob}, {camp_id, ck, camp, cs}, t)

        true ->
          {state, hits, evs}
      end
    else
      _ -> {state, hits, evs}
    end
  end

  defp cleared(state, hits, evs, {id, mob}, {camp_id, ck, camp, cs}, t) do
    reward = Camps.clear_reward(camp, mob.level)

    mobs =
      Map.update!(state.mobs, id, fn m ->
        if m.corpse, do: %{m | corpse: %{m.corpse | items: m.corpse.items ++ reward.items, coins: m.corpse.coins + reward.coins}}, else: m
      end)

    hits = Enum.map(hits, fn h -> if h[:id] == id and h[:killed], do: Map.put(h, :xp_mult, Map.get(h, :xp_mult, 1.0) * reward.xp_mult), else: h end)
    announce(state, camp[:name], "#{camp[:name] || "The camp"} has been cleared!")
    clears = cs.clears + 1

    if Camps.escalates?(camp, clears) and not cs.boss_up do
      point = Camps.boss_point(camp_id, camp)
      boss = Brain.spawn(point, t)
      announce(state, camp[:name], "#{cap(boss.name)} comes to avenge #{camp[:name] || "the camp"}!")

      state = %{state | mobs: Map.put(mobs, point.id, boss), points: Map.put(state.points, point.id, point), camp_state: Map.put(state.camp_state, ck, %{clears: 0, boss_up: true})}
      {state, hits, evs ++ [{:spawn, Brain.view(boss)}]}
    else
      {%{state | mobs: mobs, camp_state: Map.put(state.camp_state, ck, %{cs | clears: clears})}, hits, evs}
    end
  end

  # Points with a time of day whose time is over: their creatures fade unless they're fighting.
  defp depop_out_of_window(state, t) do
    wall = Rotation.wall_ms()

    Enum.reduce(state.points, {state, []}, fn {id, p}, {st, evs} ->
      with w when w in ["day", "night"] <- p[:window],
           false <- Rotation.open?(p, wall),
           %{} = m <- st.mobs[id],
           {m2, [_ | _] = e} <- Brain.depop(m, t) do
        {%{st | mobs: Map.put(st.mobs, id, m2)}, evs ++ e}
      else
        _ -> {st, evs}
      end
    end)
  end

  # A line in the zone's chat, from the camp (every player in the zone sees it).
  defp announce(%{zone_topic: nil}, _from, _text), do: :ok

  defp announce(state, from, text) do
    Phoenix.PubSub.broadcast(Bacon8.PubSub, state.zone_topic, {:zone_chat_message, %{
      character_id: nil,
      character_name: from || "World",
      message: text,
      zone_wide: true,
      sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }})
  end

  defp cap(<<c::utf8, rest::binary>>), do: String.upcase(<<c::utf8>>) <> rest
  defp cap(s), do: s

  defp zone_id(slug) do
    case World.zone_for(slug) do
      %{id: id} -> id
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # %{character_id => %{x, y, z, dead, level}} from the zone's presence.
  defp players(nil), do: %{}

  defp players(topic) do
    topic
    |> Presence.list()
    |> Enum.flat_map(fn {_key, %{metas: metas}} -> metas end)
    |> Enum.reduce(%{}, fn meta, acc ->
      case meta[:character_id] do
        nil ->
          acc

        id ->
          {x, z} = {num(meta[:x]), num(meta[:z])}
          # y is the height above the ground (Brain.airborne?/1): on a hillside nobody is flying.
          # Swimmers are out of reach (Brain.out_of_reach?/1).
          Map.put(acc, id, %{
            x: x,
            y: num(meta[:y]) - ground(x, z),
            z: z,
            swimming: swimming?(meta),
            dead: meta[:dead] == true,
            level: meta[:level] || 1
          })
      end
    end)
  rescue
    _ -> %{}
  end

  # The ground under a point, scene units (BaconWorld.Terrain; 0 without terrain).
  defp ground(x, z), do: BaconWorld.Terrain.surface_units(x, z, BaconWorld.Mobs.Brain.u())

  # The client's motion flags (8: swimming), or deep water under them.
  defp swimming?(meta) do
    m = meta[:m] || meta[:motion] || 0
    u = BaconWorld.Mobs.Brain.u()
    (is_integer(m) and Bitwise.band(m, 8) != 0) or BaconWorld.Terrain.deep?(num(meta[:x]) / u, num(meta[:z]) / u)
  end

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 0.0

  defp broadcast_events(_topic, []), do: :ok

  defp broadcast_events(topic, events) do
    Phoenix.PubSub.broadcast(Bacon8.PubSub, topic, {:mob_events, Enum.map(events, &event/1)})
  end

  # Only creatures that move, plus each one's first still frame (so clients stop it).
  defp broadcast_motion(state) do
    moving = for {id, m} <- state.mobs, Brain.alive?(m), m.vx != 0.0 or m.vz != 0.0, into: MapSet.new(), do: id
    send_ids = MapSet.union(moving, state.moving)

    if MapSet.size(send_ids) > 0 do
      list = for id <- send_ids, m <- [state.mobs[id]], m != nil, Brain.alive?(m), do: Brain.motion(m)
      if list != [], do: Phoenix.PubSub.broadcast(Bacon8.PubSub, state.topic, {:mob_motion, list})
    end

    %{state | moving: moving}
  end

  @doc false
  def event({:spawn, view}), do: %{t: "spawn", mob: view}
  def event({:aggro, id, cid}), do: %{t: "aggro", id: id, target: cid}
  def event({:attack, id, cid, hit, damage}), do: %{t: "attack", id: id, target: cid, hit: hit, damage: damage}
  def event({:attack, id, cid, hit, damage, move}), do: %{t: "attack", id: id, target: cid, hit: hit, damage: damage, move: move}
  def event({:attack, id, cid, hit, damage, move, fx}), do: %{t: "attack", id: id, target: cid, hit: hit, damage: damage, move: move, fx: fx}
  def event({:cast, id, move}), do: %{t: "cast", id: id, move: move}
  def event({:damaged, id, cid, damage, crit, hp, max_hp}), do: %{t: "damaged", id: id, by: cid, damage: damage, crit: crit, hp: hp, max_hp: max_hp}
  def event({:rooted, id, ms}), do: %{t: "rooted", id: id, ms: ms}
  def event({:died, id, killer}), do: %{t: "died", id: id, killer: killer}
  def event({:corpse_gone, id}), do: %{t: "gone", id: id}
  def event({:corpse, mob}), do: %{t: "corpse", id: mob.id, corpse: Brain.view(mob).corpse, looter: mob.corpse && mob.corpse.looter}
end
