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
  """
  use GenServer
  require Logger

  alias BaconWorld.Mobs
  alias BaconWorld.Mobs.{Brain, Spawns}
  alias BaconWorld.World
  alias Bacon8Web.Presence

  @tick_ms 100
  @motion_every 2
  @players_every 2

  def name(slug), do: {:global, {__MODULE__, slug}}

  def start_link(slug), do: GenServer.start_link(__MODULE__, slug, name: name(slug))

  @impl true
  def init(slug) do
    send(self(), :setup)

    {:ok,
     %{slug: slug, topic: Mobs.topic(slug), zone_topic: nil, mobs: %{}, points: %{}, players: %{}, n: 0, last: now(), moving: MapSet.new()}}
  end

  @impl true
  def handle_info(:setup, state) do
    case zone_id(state.slug) do
      nil ->
        # No database yet, or the zone isn't seeded: try again shortly.
        Process.send_after(self(), :setup, 10_000)
        {:noreply, state}

      id ->
        t = now()
        points = Map.new(Spawns.points(), &{&1.id, &1})
        mobs = Map.new(points, fn {id, p} -> {id, Brain.spawn(p, t)} end)
        Logger.info("bacon_world:mobs zone=#{state.slug} node=#{node()} creatures=#{map_size(mobs)}")
        Process.send_after(self(), :tick, @tick_ms)
        {:noreply, %{state | zone_topic: "bacon_world:zone:#{id}", points: points, mobs: mobs, last: t}}
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

    broadcast_events(state.topic, events)
    state = %{state | mobs: mobs, last: t, n: state.n + 1}
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
    {mobs, hits, events} = Brain.melee(state.mobs, attack, now())
    broadcast_events(state.topic, events)
    {:reply, {:ok, hits}, %{state | mobs: mobs}}
  end

  def handle_call({:spell_hit, attack}, _from, state) do
    {mobs, result, events} = Brain.spell_hit(state.mobs, attack, now())
    broadcast_events(state.topic, events)
    {:reply, result, %{state | mobs: mobs}}
  end

  def handle_call({:root, attack}, _from, state) do
    {mobs, result, events} = Brain.root(state.mobs, attack, now())
    broadcast_events(state.topic, events)
    {:reply, result, %{state | mobs: mobs}}
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
