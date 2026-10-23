defmodule BaconWorldWeb.GameEvents do
  @moduledoc """
  The fighting, looting and inventory half of `BaconWorldWeb.PlayLive`: its
  `handle_event`/`handle_info` clauses for these call in here with the socket.

  Client events (all reply):

    * `"melee_attack"` `%{hand: "left" | "right", heading, heavy, target_id}` -
      a swing. Each hand has its own swing timer (the weapon's DLY; a two-hander
      shares one); the zone decides what it hits (`BaconWorld.Mobs`). Replies
      `%{ok, hits, delay_ms}` and, after a kill, the new `progress`.
    * `"fetch_mobs"` - every creature and corpse, and the camps to dress.
    * `"loot_open"` `%{mob_id}`, `"loot_take"` `%{mob_id, index}`,
      `"loot_all"` `%{mob_id}`, `"loot_close"` `%{mob_id}` - EverQuest looting.
    * `"inventory_move"` `%{from, to}`, `"inventory_equip"` `%{slot}`,
      `"inventory_unequip"` `%{slot}`, `"inventory_destroy"` `%{slot}`.

  Pushed to the client: `"mob_events"`, `"mob_motion"` (from the zone),
  `"character_stats_update"` when a creature hits you, `"character_died"`,
  `"character_progress"` and `"zone_gear"` (someone's weapons changed).

  The character's own HP lives here: creatures broadcast their attacks and only
  the target's LiveView applies them, so the zone never writes characters.
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]
  require Logger

  alias BaconWorld.{Combat, Inventory, Items, Melee, Mobs, Progression}
  alias BaconWorld.Mobs.{Brain, Spawns}
  alias Bacon8Web.Presence
  alias Phoenix.PubSub

  @respawn_ms 30_000

  # ---------------------------------------------------------------------------
  # Entering and leaving the zone
  # ---------------------------------------------------------------------------

  @doc "Called as the character joins a zone: listen to its creatures, load what it holds."
  def join(socket, payload) do
    slug = payload.zone.slug || "lobby"
    if Phoenix.LiveView.connected?(socket), do: PubSub.subscribe(Bacon8.PubSub, Mobs.topic(slug))

    assign(socket,
      mobs_zone: slug,
      equipment: Inventory.equipment(payload.character_id),
      swing_at: %{},
      level: payload[:level] || 1,
      looting: nil
    )
  end

  @doc "Called as the character leaves the zone."
  def leave(socket) do
    case socket.assigns[:mobs_zone] do
      nil ->
        socket

      slug ->
        if id = socket.assigns[:looting], do: Mobs.loot_close(slug, id, character_id(socket))
        PubSub.unsubscribe(Bacon8.PubSub, Mobs.topic(slug))
        assign(socket, mobs_zone: nil, looting: nil)
    end
  end

  @doc "The extra presence meta other players and the creatures read."
  def presence_meta(payload) do
    %{level: payload[:level] || 1, dead: false, gear: payload[:gear] || %{}}
  end

  # ---------------------------------------------------------------------------
  # Events from the client
  # ---------------------------------------------------------------------------

  def handle_event("fetch_mobs", _params, socket) do
    slug = socket.assigns[:mobs_zone] || "lobby"
    {:reply, %{mobs: Mobs.snapshot(slug), camps: Spawns.camps_payload(Brain.u()), safe_radius: Spawns.safe_radius() * Brain.u()}, socket}
  end

  def handle_event("melee_attack", params, socket) do
    with %{} = me <- current(socket),
         false <- socket.assigns[:is_dead?] || false,
         hand when hand in ["left", "right"] <- params["hand"],
         heading when is_number(heading) <- params["heading"] do
      heavy = params["heavy"] == true
      eq = socket.assigns[:equipment] || %{}
      two = Items.two_handed?(eq["main"])
      item = swing_item(eq, hand)
      timer = if two, do: "both", else: hand
      delay = Melee.delay_ms(item, heavy)
      now = System.monotonic_time(:millisecond)
      # nil until the first swing: monotonic time can be negative, so 0 is no "long ago".
      last = Map.get(socket.assigns[:swing_at] || %{}, timer)

      if last && now - last < delay * 0.8 do
        {:reply, %{ok: false, reason: "cooldown", ready_in: delay - (now - last)}, socket}
      else
        socket = assign(socket, swing_at: Map.put(socket.assigns[:swing_at] || %{}, timer, now))

        attack = %{
          id: me.character_id,
          level: socket.assigns[:level] || 1,
          x: me.position.x,
          z: me.position.z,
          heading: heading * 1.0,
          item: item,
          heavy: heavy,
          target: params["target_id"]
        }

        case Mobs.melee(socket.assigns[:mobs_zone] || "lobby", attack) do
          {:ok, hits} ->
            {socket, progress} = award_kills(socket, hits)
            {:reply, %{ok: true, hits: hits, delay_ms: delay, progress: progress}, socket}

          {:error, _} ->
            {:reply, %{ok: true, hits: [], delay_ms: delay, progress: nil}, socket}
        end
      end
    else
      _ -> {:reply, %{ok: false, reason: "cannot_attack"}, socket}
    end
  end

  def handle_event("loot_open", %{"mob_id" => mob_id}, socket) when is_binary(mob_id) do
    with %{} = me <- current(socket),
         false <- socket.assigns[:is_dead?] || false do
      slug = socket.assigns[:mobs_zone] || "lobby"
      prev = socket.assigns[:looting]
      if prev && prev != mob_id, do: Mobs.loot_close(slug, prev, me.character_id)

      case Mobs.loot_open(slug, mob_id, me.character_id, {me.position.x, me.position.z}) do
        {:ok, coins, items} ->
          total = if coins > 0, do: Inventory.add_coins(me.character_id, coins), else: Inventory.coins(me.character_id)
          {:reply, %{ok: true, coins: coins, total_coins: total, items: indexed(items)}, assign(socket, looting: mob_id)}

        {:error, reason} ->
          {:reply, %{ok: false, error: loot_error(reason)}, socket}
      end
    else
      _ -> {:reply, %{ok: false, error: "You can't loot right now."}, socket}
    end
  end

  def handle_event("loot_take", %{"mob_id" => mob_id, "index" => index}, socket) when is_integer(index) do
    case take_one(socket, mob_id, index) do
      {:ok, item, left} ->
        {:reply, %{ok: true, taken: [item], items: indexed(left), inventory: Inventory.payload(character_id(socket))}, socket}

      {:error, msg, left} ->
        {:reply, %{ok: false, error: msg, items: indexed(left || []), inventory: Inventory.payload(character_id(socket))}, socket}
    end
  end

  def handle_event("loot_all", %{"mob_id" => mob_id}, socket) do
    {taken, left, error} = take_all(socket, mob_id, [])
    {:reply, %{ok: error == nil, error: error, taken: taken, items: indexed(left), inventory: Inventory.payload(character_id(socket))}, socket}
  end

  def handle_event("loot_close", %{"mob_id" => mob_id}, socket) do
    if character_id(socket), do: Mobs.loot_close(socket.assigns[:mobs_zone] || "lobby", mob_id, character_id(socket))
    {:reply, %{ok: true}, assign(socket, looting: nil)}
  end

  def handle_event("inventory_fetch", _params, socket) do
    case character_id(socket) do
      nil -> {:reply, %{ok: false}, socket}
      id -> {:reply, %{ok: true, inventory: Inventory.payload(id)}, socket}
    end
  end

  def handle_event("inventory_move", %{"from" => from, "to" => to}, socket) do
    inventory_change(socket, fn id -> Inventory.move(id, to_string(from), to_string(to)) end)
  end

  def handle_event("inventory_equip", %{"slot" => slot}, socket) do
    inventory_change(socket, fn id -> Inventory.auto_equip(id, to_string(slot)) end)
  end

  def handle_event("inventory_unequip", %{"slot" => slot}, socket) do
    inventory_change(socket, fn id -> Inventory.unequip(id, to_string(slot)) end)
  end

  def handle_event("inventory_destroy", %{"slot" => slot}, socket) do
    inventory_change(socket, fn id -> Inventory.destroy(id, to_string(slot)) end)
  end

  def handle_event(_event, _params, socket), do: {:reply, %{ok: false, error: "bad request"}, socket}

  # ---------------------------------------------------------------------------
  # Messages from the zone
  # ---------------------------------------------------------------------------

  @doc "Creature events: pushed on, and an attack on this character is applied here."
  def mob_events(events, socket) do
    me = character_id(socket)

    socket =
      Enum.reduce(events, socket, fn
        %{t: "attack", target: ^me, hit: true, damage: dmg}, acc when is_integer(dmg) and dmg > 0 -> take_hit(acc, dmg)
        _, acc -> acc
      end)

    push_event(socket, "mob_events", %{events: events})
  end

  def mob_motion(list, socket), do: push_event(socket, "mob_motion", %{m: list})

  @doc "Someone's weapons changed (pushed unless it is us)."
  def zone_gear(%{character_id: id} = payload, socket) do
    if id == character_id(socket), do: socket, else: push_event(socket, "zone_gear", payload)
  end

  @doc "Marks this character dead or alive in its presence meta (creatures stop chasing the dead)."
  def set_dead(socket, dead?) do
    update_presence(socket, %{dead: dead?})
  end

  # ---------------------------------------------------------------------------

  defp take_hit(socket, damage) do
    me = current(socket)

    if socket.assigns[:is_dead?] || is_nil(me) do
      socket
    else
      case Combat.get_character_stats(me.character_id) do
        {:ok, %{hp: hp, max_hp: max_hp, mp: mp, max_mp: max_mp}} ->
          new_hp = max(0, hp - damage)
          {:ok, _} = Combat.update_character_hp_mp(me.character_id, new_hp, mp)
          socket = push_event(socket, "character_stats_update", %{hp: new_hp, max_hp: max_hp, mp: mp, max_mp: max_mp})
          if new_hp == 0, do: die(socket, me), else: socket

        _ ->
          socket
      end
    end
  end

  defp die(socket, me) do
    {:ok, coords} = Combat.respawn_character(me.character_id)
    if timer = socket.assigns[:pending_respawn_timer], do: Process.cancel_timer(timer)
    timer = Process.send_after(self(), {:auto_respawn, me.character_id}, @respawn_ms)
    if id = socket.assigns[:looting], do: Mobs.loot_close(socket.assigns[:mobs_zone] || "lobby", id, me.character_id)

    socket
    |> assign(pending_respawn_timer: timer, pending_spawn_coords: coords, is_dead?: true, looting: nil)
    |> set_dead(true)
    |> push_event("character_died", %{
      spawn_coords: coords,
      hp: me.max_hp,
      max_hp: me.max_hp,
      mp: me.max_mp,
      max_mp: me.max_mp,
      respawn_in_ms: @respawn_ms
    })
  end

  defp award_kills(socket, hits) do
    kills = Enum.filter(hits, & &1.killed)
    me = current(socket)

    if kills == [] or is_nil(me) do
      {socket, nil}
    else
      level = socket.assigns[:level] || 1
      xp = kills |> Enum.map(&Progression.kill_xp(&1.level, level)) |> Enum.sum()

      case Progression.award_xp(me.character_id, xp) do
        {:ok, progress} ->
          progress = Map.put(progress, :gained, xp)

          socket =
            if progress.levels_gained > 0 do
              socket
              |> assign(level: progress.level)
              |> update_presence(%{level: progress.level})
              |> update_runtime(%{max_hp: progress.max_hp, max_mp: progress.max_mp, level: progress.level})
            else
              socket
            end

          {socket, progress}

        _ ->
          {socket, nil}
      end
    end
  end

  # What a hand swings with: its weapon, the two-hander, a shield's bash, or a fist.
  defp swing_item(eq, hand) do
    main = eq["main"]
    off = eq["off"]

    cond do
      Items.two_handed?(main) -> main
      hand == "right" -> main || Items.fist()
      true -> off || Items.fist()
    end
  end

  defp take_one(socket, mob_id, index) do
    slug = socket.assigns[:mobs_zone] || "lobby"
    id = character_id(socket)

    case id && Mobs.loot_take(slug, mob_id, id, index) do
      {:ok, item, left} ->
        case Inventory.add(id, item.item_id, item.quantity) do
          {:ok, _slots} ->
            {:ok, item, left}

          {:error, :inventory_full} ->
            Mobs.loot_return(slug, mob_id, item)
            {:error, "Your inventory is full.", left ++ [item]}

          {:error, _} ->
            {:error, "That can't be taken.", left}
        end

      {:error, reason} ->
        {:error, loot_error(reason), nil}

      _ ->
        {:error, "You aren't looting anything.", nil}
    end
  end

  defp take_all(socket, mob_id, taken) do
    case take_one(socket, mob_id, 0) do
      {:ok, item, []} -> {taken ++ [item], [], nil}
      {:ok, item, _left} -> take_all(socket, mob_id, taken ++ [item])
      {:error, msg, left} -> {taken, left || [], if(msg == "That isn't there any more.", do: nil, else: msg)}
    end
  end

  defp indexed(items), do: items |> Enum.with_index() |> Enum.map(fn {i, n} -> %{index: n, item_id: i.item_id, quantity: i.quantity} end)

  defp loot_error(:too_far), do: "You are too far away to loot that corpse."
  defp loot_error(:not_yours_yet), do: "You may not loot this corpse at this time."
  defp loot_error(:someone_else_looting), do: "Someone is already looting that corpse."
  defp loot_error(:not_a_corpse), do: "That isn't a corpse."
  defp loot_error(:no_such_item), do: "That isn't there any more."
  defp loot_error(:not_looting), do: "You aren't looting that corpse."
  defp loot_error(_), do: "You can't loot right now."

  defp inventory_change(socket, fun) do
    case character_id(socket) do
      nil ->
        {:reply, %{ok: false, error: "Not in the world."}, socket}

      id ->
        case fun.(id) do
          {:ok, _} ->
            socket = refresh_gear(socket, id)
            {:reply, %{ok: true, inventory: Inventory.payload(id), gear: Inventory.gear_ids(socket.assigns.equipment)}, socket}

          {:error, reason} ->
            {:reply, %{ok: false, error: inventory_error(reason), inventory: Inventory.payload(id)}, socket}
        end
    end
  end

  defp inventory_error(:inventory_full), do: "Your inventory is full."
  defp inventory_error(:cannot_equip_there), do: "That doesn't go there."
  defp inventory_error(:off_hand_full), do: "Empty your off hand to wield a two-handed weapon."
  defp inventory_error(:two_hander_equipped), do: "Your hands are full with a two-handed weapon."
  defp inventory_error(:empty_slot), do: "There's nothing there."
  defp inventory_error(_), do: "You can't do that."

  # After an inventory change: the hands may hold something new, which everyone sees.
  defp refresh_gear(socket, id) do
    eq = Inventory.equipment(id)
    old = Inventory.gear_ids(socket.assigns[:equipment] || %{})
    new = Inventory.gear_ids(eq)
    socket = assign(socket, equipment: eq)

    if old != new do
      if topic = socket.assigns[:current_zone_topic] do
        PubSub.broadcast(Bacon8.PubSub, topic, {:zone_gear, %{character_id: id, gear: new}})
      end

      update_presence(socket, %{gear: new})
    else
      socket
    end
  end

  defp update_presence(socket, patch) do
    topic = socket.assigns[:current_zone_topic]
    key = socket.assigns[:current_presence_key]
    if topic && key, do: Presence.update(self(), topic, key, &Map.merge(&1, patch))
    socket
  end

  defp update_runtime(socket, patch) do
    case socket.assigns[:current_character_runtime] do
      nil -> socket
      rt -> assign(socket, current_character_runtime: Map.merge(rt, patch))
    end
  end

  defp current(socket), do: socket.assigns[:current_character_runtime] || socket.assigns[:current_character_payload]

  defp character_id(socket) do
    case current(socket) do
      %{character_id: id} -> id
      _ -> nil
    end
  end
end
