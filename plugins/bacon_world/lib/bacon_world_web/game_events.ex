defmodule BaconWorldWeb.GameEvents do
  @moduledoc """
  The fighting, looting and inventory half of `BaconWorldWeb.PlayLive`: its
  `handle_event`/`handle_info` clauses for these call in here with the socket.

  Client events (all reply):

    * `"melee_attack"` `%{hand: "left" | "right", heading, heavy, target_id}` -
      a swing. Each hand has its own swing timer (the weapon's DLY; a two-hander
      shares one); the zone decides what it hits (`BaconWorld.Mobs`). Replies
      `%{ok, hits, delay_ms}` and, after a kill, the new `progress`. Everyone in
      the zone sees the swing (`"zone_swing"`). Players in front of the swing are
      hit too when both are flagged for PvP: `pvp_swing/3` rolls it and the
      target's LiveView applies it (`"pvp_hit"` to everyone).
    * `"mount_attack"` `%{hand, heading, target_id}` - the mount's move for that hand while riding
      (`BaconWorld.Mounts` `attacks`: a dragon's claw and fire breath, the Kraken's lash and
      maelstrom). Its own timer per hand; creatures only. Replies like `"melee_attack"` plus
      `move`; everyone sees it (`"zone_swing"` with `mount_move`).
    * `"fetch_mobs"` - every creature and corpse, the camps to dress, the merchants, the water,
      and everything placed in build mode (`BaconWorld.Building`).
    * `"loot_open"` `%{mob_id}`, `"loot_take"` `%{mob_id, index}`,
      `"loot_all"` `%{mob_id}`, `"loot_close"` `%{mob_id}` - EverQuest looting.
    * `"inventory_move"` `%{from, to}`, `"inventory_equip"` `%{slot}`,
      `"inventory_unequip"` `%{slot}`, `"inventory_destroy"` `%{slot}`. Equipping
      clothes changes how the character looks: `"zone_gear"` tells everyone.
    * `"merchant_open"` `%{id}`, `"merchant_buy"` `%{id, item_id}`,
      `"merchant_sell"` `%{id, slot}` - trading with a merchant within reach
      (`BaconWorld.Merchants`).

  Pushed to the client: `"mob_events"`, `"mob_motion"` (from the zone),
  `"character_stats_update"` when a creature or a player hits you,
  `"character_died"`, `"character_progress"`, `"zone_gear"` (someone's weapons
  changed), `"zone_swing"` (someone else swung), `"pvp_hit"`, `"zone_hp"`
  (someone's health changed, they died or came back) and `"stats_sheet"` (the
  live character stats readout).

  The character's own HP lives here: creatures broadcast their attacks and only
  the target's LiveView applies them, so the zone never writes characters.
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]
  require Logger

  alias BaconWorld.{Combat, Inventory, Items, Melee, Merchants, Mobs, Powers, Progression, Skills, Tuning, World}
  alias BaconWorld.Mobs.{Brain, Spawns}
  alias BaconWorldWeb.SkillEvents
  alias Bacon8Web.Presence
  alias Phoenix.PubSub

  @respawn_ms 30_000

  # ---------------------------------------------------------------------------
  # Entering and leaving the zone
  # ---------------------------------------------------------------------------

  @doc "Called as the character joins a zone: listen to its creatures, load what it holds."
  def join(socket, payload) do
    slug = payload.zone.slug || "lobby"
    # this process's ground is the zone's from now on (BaconWorld.Terrain.use_zone/1), and its
    # creatures run somewhere in the cluster (zones beyond the lobby, 2026-11-02)
    BaconWorld.Terrain.use_zone(slug)
    if Phoenix.LiveView.connected?(socket), do: Mobs.ensure_zone(slug)
    if Phoenix.LiveView.connected?(socket), do: PubSub.subscribe(Bacon8.PubSub, Mobs.topic(slug))
    socket = BaconWorldWeb.BuildEvents.join(socket, slug)
    socket = sync_terrain(socket)
    # the map and the minimap: the zone's name, picture and neighbours
    socket = if Phoenix.LiveView.connected?(socket), do: push_event(socket, "zone_info", BaconWorld.WorldEditor.map_info(slug)), else: socket

    assign(socket,
      mobs_zone: slug,
      equipment: Inventory.equipment(payload.character_id),
      swing_at: %{},
      level: payload[:level] || 1,
      looting: nil
    )
  end

  # The page was drawn with the lobby's ground; a character in another zone gets its own (the
  # client rebuilds the ground on "terrain_replaced").
  defp sync_terrain(socket) do
    terrain = BaconWorld.Terrain.payload(Brain.u())

    if terrain != socket.assigns[:terrain] and Phoenix.LiveView.connected?(socket) do
      socket |> assign(terrain: terrain) |> push_event("terrain_replaced", %{terrain: terrain})
    else
      socket
    end
  end

  @doc "Called as the character leaves the zone."
  def leave(socket) do
    case socket.assigns[:mobs_zone] do
      nil ->
        socket

      slug ->
        if id = socket.assigns[:looting], do: Mobs.loot_close(slug, id, character_id(socket))
        PubSub.unsubscribe(Bacon8.PubSub, Mobs.topic(slug))
        BaconWorldWeb.BuildEvents.leave(socket, slug)
        assign(socket, mobs_zone: nil, looting: nil)
    end
  end

  @doc "The extra presence meta other players and the creatures read."
  def presence_meta(payload) do
    %{level: payload[:level] || 1, dead: false, gear: payload[:gear] || %{}, hp: payload[:hp], max_hp: payload[:max_hp],
      pvp: payload[:pvp_flagged] == true}
  end

  # ---------------------------------------------------------------------------
  # Events from the client
  # ---------------------------------------------------------------------------

  def handle_event("fetch_mobs", _params, socket) do
    slug = socket.assigns[:mobs_zone] || "lobby"
    {:reply,
     %{
       mobs: Mobs.snapshot(slug),
       # the camps and the town's safe ring are the lobby's
       camps: if(BaconWorld.Terrain.lobby?(), do: Spawns.camps_payload(Brain.u(), BaconWorld.Building.seeded(slug).camps), else: []),
       safe_radius: if(BaconWorld.Terrain.lobby?(), do: Spawns.safe_radius() * Brain.u(), else: 0),
       merchants: Merchants.payload(slug),
       # what players put in the world in build mode (BaconWorld.Building), metres
       placements: BaconWorld.Building.list(slug),
       # the sea and the lakes (BaconWorld.Water): the client draws them and fishes in them
       water: BaconWorld.Water.layout(Brain.u())
     }, socket}
  end

  def handle_event("melee_attack", params, socket) do
    with %{} = me <- current(socket),
         false <- socket.assigns[:is_dead?] || false,
         # no fighting from the saddle (BaconWorldWeb.MountEvents)
         nil <- socket.assigns[:mount],
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

        if topic = socket.assigns[:current_zone_topic] do
          PubSub.broadcast(Bacon8.PubSub, topic, {:zone_swing, %{character_id: me.character_id, hand: hand, heavy: heavy, delay_ms: delay}})
        end

        buffs = SkillEvents.active_buffs(socket)

        skill_pct =
          case World.fetch_character(me.character_id) do
            {:ok, c} -> Skills.bonus(c, "melee_pct")
            _ -> 0
          end

        attack = %{
          id: me.character_id,
          level: socket.assigns[:level] || 1,
          x: me.position.x,
          z: me.position.z,
          heading: heading * 1.0,
          item: item,
          heavy: heavy,
          target: params["target_id"],
          pct: skill_pct + buffs.dmg_pct,
          crit_bonus: buffs.crit
        }

        # the jeweller's sets (BaconWorld.Powers): crits, starfire, snares, the lasso
        powers = Powers.active(eq)
        {attack, fired} = Powers.swing(powers, attack)

        pvp = pvp_swing(socket, me, attack)
        smash = smash_melee(socket, me, attack, params)

        case Mobs.melee(socket.assigns[:mobs_zone] || "lobby", attack) do
          {:ok, hits} ->
            {socket, progress} = award_kills(socket, hits)
            {hp, mp} = Powers.after_swing(powers, Enum.filter(hits, &Map.get(&1, :hit, true)))
            socket = restore(socket, hp, mp)
            {:reply, %{ok: true, hits: hits, pvp: pvp, smash: smash, delay_ms: delay, progress: progress, powers: fired}, socket}

          {:error, _} ->
            {:reply, %{ok: true, hits: [], pvp: pvp, smash: smash, delay_ms: delay, progress: nil, powers: fired}, socket}
        end
      end
    else
      _ -> {:reply, %{ok: false, reason: "cannot_attack"}, socket}
    end
  end

  # A mount's move (BaconWorld.Mounts `attacks`): resolved by the zone like a swing; creatures only.
  def handle_event("mount_attack", params, socket) do
    with %{} = me <- current(socket),
         false <- socket.assigns[:is_dead?] || false,
         %{} = mount <- BaconWorldWeb.MountEvents.mounted(socket),
         hand when hand in ["left", "right"] <- params["hand"],
         %{} = move <- BaconWorld.Mounts.attack(mount, hand),
         heading when is_number(heading) <- params["heading"] do
      item = BaconWorld.Mounts.attack_item(move)
      delay = Melee.delay_ms(item)
      now = System.monotonic_time(:millisecond)
      timer = "mount_" <> hand
      last = Map.get(socket.assigns[:swing_at] || %{}, timer)

      if last && now - last < delay * 0.8 do
        {:reply, %{ok: false, reason: "cooldown", ready_in: delay - (now - last)}, socket}
      else
        socket = assign(socket, swing_at: Map.put(socket.assigns[:swing_at] || %{}, timer, now))

        if topic = socket.assigns[:current_zone_topic] do
          PubSub.broadcast(Bacon8.PubSub, topic, {:zone_swing, %{character_id: me.character_id, hand: hand, heavy: false, delay_ms: delay, mount_move: move.move}})
        end

        # reach is from the rider; a big mount's body adds to it (the rider sits over its middle)
        attack = %{
          id: me.character_id,
          level: socket.assigns[:level] || 1,
          x: me.position.x,
          z: me.position.z,
          heading: heading * 1.0,
          item: item,
          heavy: false,
          target: params["target_id"],
          sweep: {move.targets, move.arc},
          reach: move.reach + (move[:body] || 0.0)
        }

        slug = socket.assigns[:mobs_zone] || "lobby"
        pvp = pvp_swing(socket, me, attack)
        smash = smash_mount(socket, me, attack, params, move)

        case Mobs.melee(slug, attack) do
          {:ok, hits} ->
            if ms = move[:root_ms] do
              for h <- hits, h.hit and not h.killed do
                Mobs.root(slug, %{id: me.character_id, target: h.id, ms: ms, x: attack.x, z: attack.z, range: (move.reach + 1.0) * Brain.u()})
              end
            end

            {socket, progress} = award_kills(socket, hits)
            {:reply, %{ok: true, move: move.move, hits: hits, pvp: pvp, smash: smash, delay_ms: delay, progress: progress}, socket}

          {:error, _} ->
            {:reply, %{ok: true, move: move.move, hits: [], pvp: pvp, smash: smash, delay_ms: delay, progress: nil}, socket}
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
          # a group splits the coins evenly among the members near (EverQuest's auto-split); the
          # odd coppers are the looter's
          mates = if coins > 0, do: Enum.map(groupmates_near(socket, me), &elem(&1, 0)), else: []
          each = div(coins, length(mates) + 1)
          mine = coins - each * length(mates)

          for id <- mates, each > 0 do
            Inventory.add_coins(id, each)
            PubSub.broadcast(Bacon8.PubSub, BaconWorld.Groups.topic(id), {:group_coins, each})
          end

          total = if mine > 0, do: Inventory.add_coins(me.character_id, mine), else: Inventory.coins(me.character_id)
          {:reply, %{ok: true, coins: mine, split: if(mates != [] and each > 0, do: length(mates) + 1), total_coins: total, items: indexed(items)}, assign(socket, looting: mob_id)}

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
      # the account's Gems beside the coin (owner, 2026-11-01): shown in the inventory and every shop
      id -> {:reply, %{ok: true, inventory: Inventory.payload(id), gems: gem_balance(socket)}, SkillEvents.push_stats_sheet(socket)}
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

  def handle_event("merchant_open", %{"id" => id}, socket) do
    case trader(socket, id) do
      {:ok, _me, m} ->
        # every shop shows the Gems too (2026-11-01); only the jeweller takes them
        gems = gem_balance(socket)
        {:reply, %{ok: true, merchant: %{id: m.id, name: m.name, title: m.title, gems: Merchants.gems?(m)}, stock: Merchants.stock(m), gems: gems}, socket}

      {:error, msg} ->
        {:reply, %{ok: false, error: msg}, socket}
    end
  end

  def handle_event("merchant_buy", %{"id" => id, "item_id" => item_id} = params, socket) do
    case trader(socket, id) do
      {:ok, me, %{gems: true} = m} -> buy_jewel(socket, me, m, item_id, params["nonce"])
      _ -> buy_coins(socket, id, item_id)
    end
  end

  def handle_event("merchant_sell", %{"id" => id, "slot" => slot}, socket) when is_binary(slot) do
    with {:ok, me, _m} <- trader(socket, id),
         %{} = row <- Enum.find(Inventory.list(me.character_id), &(&1.slot == slot)) || {:error, "There's nothing there."},
         true <- String.starts_with?(slot, "bag") || {:error, "Take it off first."},
         %{} = item <- Items.get(row.item_id),
         price when price > 0 <- Merchants.buy_price(item) * row.quantity,
         {:ok, _} <- Inventory.remove(me.character_id, slot) do
      coins = Inventory.add_coins(me.character_id, price)
      {:reply, %{ok: true, sold: item.id, quantity: row.quantity, price: price, coins: coins, inventory: Inventory.payload(me.character_id)}, socket}
    else
      0 -> {:reply, %{ok: false, error: "They aren't interested in that."}, socket}
      {:error, msg} when is_binary(msg) -> {:reply, %{ok: false, error: msg}, socket}
      _ -> {:reply, %{ok: false, error: "You can't sell that right now."}, socket}
    end
  end

  def handle_event("lightning_struck", _params, socket) do
    if socket.assigns[:is_dead?] do
      {:noreply, socket}
    else
      # Extreme damage: deal 99,999 raw damage, instantly shattering the character
      socket = take_hit(socket, 99_999)
      {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:reply, %{ok: false, error: "bad request"}, socket}

  defp buy_coins(socket, id, item_id) do
    with {:ok, me, m} <- trader(socket, id),
         true <- item_id in m.sells || {:error, "They don't sell that."},
         %{} = item <- Items.get(item_id) || {:error, "They don't sell that."},
         price = Merchants.sell_price(item),
         true <- Inventory.coins(me.character_id) >= price || {:error, "You can't afford that."},
         {:ok, _slots} <- buy_add(me.character_id, item.id) do
      coins = Inventory.add_coins(me.character_id, -price)
      {:reply, %{ok: true, bought: item.id, price: price, coins: coins, inventory: Inventory.payload(me.character_id)}, socket}
    else
      {:error, msg} when is_binary(msg) -> {:reply, %{ok: false, error: msg}, socket}
      _ -> {:reply, %{ok: false, error: "You can't buy that right now."}, socket}
    end
  end

  # The character, and the merchant if it is in this zone and within reach.
  defp trader(socket, id) do
    with %{} = me <- current(socket) || {:error, "You aren't in the world."},
         true <- !socket.assigns[:is_dead?] || {:error, "You can't trade while dead."},
         %{} = m <- Merchants.get(id) || {:error, "There's no one to trade with."},
         true <- m.zone == (socket.assigns[:mobs_zone] || "lobby") || {:error, "There's no one to trade with."},
         true <- Merchants.near?(m, {me.position.x, me.position.z}) || {:error, "You are too far away to trade with #{m.name}."} do
      {:ok, me, m}
    end
  end

  # A jeweller's set for Gems (BaconWorld.Jeweller: the pieces into the bags, the Gems spent from the
  # Bacon Store wallet as a recorded transaction). `nonce` (the client's, per click) keeps a retried
  # request from paying twice.
  defp buy_jewel(socket, me, m, item_id, nonce) do
    user = socket.assigns[:current_user]
    body = get_in(me, [Access.key(:appearance, %{}), "body"]) || "female"
    who = %{character_id: me.character_id, name: Map.get(me, :name), body: body}

    case BaconWorld.Jeweller.buy(user, who, item_id, nonce, m.sells) do
      {:ok, r} ->
        {:reply, %{ok: true, bought: item_id, pieces: r.pieces, gems_spent: r.gems_spent, gems: r.balance, price: 0,
                   coins: Inventory.coins(me.character_id), inventory: Inventory.payload(me.character_id)}, socket}

      {:error, msg} ->
        {:reply, %{ok: false, error: msg, gems: BaconWorld.Jeweller.balance(user)}, socket}
    end
  end

  defp gem_balance(socket), do: BaconWorld.Jeweller.balance(socket.assigns[:current_user])

  defp buy_add(character_id, item_id) do
    case Inventory.add(character_id, item_id, 1) do
      {:ok, slots} -> {:ok, slots}
      {:error, :inventory_full} -> {:error, "Your inventory is full."}
      _ -> {:error, "You can't buy that right now."}
    end
  end

  # ---------------------------------------------------------------------------
  # Messages from the zone
  # ---------------------------------------------------------------------------

  @doc "Creature events: pushed on, and an attack on this character is applied here."
  def mob_events(events, socket) do
    me = character_id(socket)

    socket =
      Enum.reduce(events, socket, fn
        %{t: "attack", target: ^me, hit: true, damage: dmg} = ev, acc when is_integer(dmg) and dmg > 0 -> take_hit(acc, dmg, ev[:id])
        _, acc -> acc
      end)

    push_event(socket, "mob_events", %{events: events})
  end

  def mob_motion(list, socket), do: push_event(socket, "mob_motion", %{m: list})

  @doc "Someone's weapons changed (pushed unless it is us)."
  def zone_gear(%{character_id: id} = payload, socket) do
    if id == character_id(socket), do: socket, else: push_event(socket, "zone_gear", payload)
  end

  @doc "Someone else swung: their animation plays on every screen."
  def zone_swing(%{character_id: id} = payload, socket) do
    if id == character_id(socket), do: socket, else: push_event(socket, "zone_swing", payload)
  end

  @doc """
  A PvP swing landed (or missed). The target's LiveView applies the damage, as it
  does a creature's; everyone gets `"pvp_hit"` for the numbers and sounds.
  """
  def pvp_hit(%{target_id: tid} = h, socket) do
    socket =
      if tid == character_id(socket) and h.hit and h.damage > 0, do: take_hit(socket, h.damage), else: socket

    push_event(socket, "pvp_hit", h)
  end

  @doc "Someone's health changed (`state` \"alive\", \"hurt\" or \"dead\")."
  def zone_hp(payload, socket), do: push_event(socket, "zone_hp", payload)

  @doc """
  Tells the zone this character's health (after a hit, regeneration, a death or a
  respawn), and keeps it in the presence meta: every presence sync replaces the
  clients' player list, and without `hp` there a target's bar read full again
  within a tenth of a second (the "instant heal" seen in PvP).
  """
  def broadcast_hp(socket, character_id, hp, max_hp, state) do
    if topic = socket.assigns[:current_zone_topic] do
      PubSub.broadcast(Bacon8.PubSub, topic, {:zone_hp, %{character_id: character_id, hp: hp, max_hp: max_hp, state: state}})
    end

    update_presence(socket, %{hp: hp, max_hp: max_hp})
  end

  @doc """
  The players a swing hits: flagged players (the swinger flagged too) inside the
  weapon's reach and arc, the targeted one first, as many as the weapon sweeps.
  Positions are the zone's presence (at most 100 ms old), so the reach has slack.
  Broadcasts `{:pvp_hit, hit}` for each and returns the hits.
  """
  def pvp_swing(socket, me, attack) do
    topic = socket.assigns[:current_zone_topic]
    {max_targets, arc} = attack[:sweep] || Melee.sweep(attack.item)
    reach = (attack[:reach] || Melee.pvp_reach(attack.item)) * Brain.u()

    victims =
      (socket.assigns[:zone_online_characters] || [])
      |> Enum.filter(fn p ->
        p.character_id != me.character_id and not p.dead and
          Melee.in_arc?({attack.x, attack.z}, attack.heading, {(p.x || 0.0) * 1.0, (p.z || 0.0) * 1.0}, reach, arc)
      end)
      |> Enum.sort_by(fn p -> {if(p.character_id == attack[:target], do: 0, else: 1), :math.pow(p.x - attack.x, 2) + :math.pow(p.z - attack.z, 2)} end)
      |> Enum.take(max_targets)

    if topic && victims != [] && Combat.pvp_flagged?(me.character_id) do
      mult = 1 + (attack[:pct] || 0) / 100
      crit_bonus = attack[:crit_bonus] || 0.0

      victims
      |> Enum.filter(&Combat.pvp_flagged?(&1.character_id))
      |> Enum.map(fn p ->
        hit = :rand.uniform() < Melee.hit_chance(attack.level, p.level || 1)
        {damage, crit} = if hit, do: Melee.roll_damage(attack.item, attack.level, attack.heavy, &:rand.uniform/0, mult: mult, crit_bonus: crit_bonus), else: {0, false}

        h = %{
          attacker_id: me.character_id,
          attacker_name: me.name,
          target_id: p.character_id,
          target_name: p.character_name,
          hit: hit,
          damage: damage,
          crit: crit
        }

        PubSub.broadcast(Bacon8.PubSub, topic, {:pvp_hit, h})
        h
      end)
    else
      []
    end
  end

  @doc "Marks this character dead or alive in its presence meta (creatures stop chasing the dead)."
  def set_dead(socket, dead?) do
    update_presence(socket, %{dead: dead?})
  end

  # ---------------------------------------------------------------------------

  defp smash_melee(socket, _me, attack, params) do
    zone = socket.assigns[:mobs_zone] || "lobby"

    if params["smash"] == true do
      target_id = params["target_id"]
      u = Brain.u()
      reach = (attack[:reach] || Melee.pvp_reach(attack.item)) * u
      {_max_targets, arc} = attack[:sweep] || Melee.sweep(attack.item)

      placement_id =
        cond do
          # in reach (2026-11-01: any piece in the zone could be hit by its id)
          is_binary(target_id) and BaconWorld.Building.near?(zone, target_id, attack.x / u, attack.z / u, reach / u + 2.0) ->
            target_id

          true ->
            placements = BaconWorld.Building.cached(zone)

            placements
            |> Enum.filter(fn p ->
              px = p.x * u
              pz = p.z * u
              Melee.in_arc?({attack.x, attack.z}, attack.heading, {px, pz}, reach, arc)
            end)
            |> Enum.min_by(fn p -> :math.pow(p.x * u - attack.x, 2) + :math.pow(p.z * u - attack.z, 2) end, fn -> nil end)
            |> case do
              %{id: pid} -> pid
              _ -> nil
            end
        end

      if placement_id do
        mult = 1 + (attack[:pct] || 0) / 100
        crit_bonus = attack[:crit_bonus] || 0.0
        {damage, crit} = Melee.roll_damage(attack.item, attack.level, attack.heavy, &:rand.uniform/0, mult: mult, crit_bonus: crit_bonus)
        dmg = max(1, round(damage))

        case BaconWorld.Building.damage_placement(socket.assigns.current_user, zone, placement_id, dmg) do
          {:ok, outcome, placement} ->
            %{id: placement_id, asset: placement.asset, damage: dmg, crit: crit, outcome: outcome, x: placement.x, y: placement.y, z: placement.z}

          _ ->
            nil
        end
      end
    end
  end

  defp smash_mount(socket, _me, attack, params, move) do
    zone = socket.assigns[:mobs_zone] || "lobby"

    if params["smash"] == true do
      target_id = params["target_id"]
      u = Brain.u()
      reach = (move.reach + (move[:body] || 0.0)) * u
      arc = move[:arc] || 90
      max_targets = move[:targets] || 1
      dmg = max(1, round(move[:dmg] || 10))

      targeted_id =
        if is_binary(target_id) and BaconWorld.Building.near?(zone, target_id, attack.x / u, attack.z / u, reach / u + 2.0),
          do: target_id,
          else: nil

      placements = BaconWorld.Building.cached(zone)

      nearby_ids =
        placements
        |> Enum.filter(fn p ->
          px = p.x * u
          pz = p.z * u
          p.id != targeted_id and Melee.in_arc?({attack.x, attack.z}, attack.heading, {px, pz}, reach, arc)
        end)
        |> Enum.sort_by(fn p -> :math.pow(p.x * u - attack.x, 2) + :math.pow(p.z * u - attack.z, 2) end)
        |> Enum.take(if(targeted_id, do: max(0, max_targets - 1), else: max_targets))
        |> Enum.map(& &1.id)

      all_ids = if targeted_id, do: [targeted_id | nearby_ids], else: nearby_ids

      Enum.map(all_ids, fn pid ->
        case BaconWorld.Building.damage_placement(socket.assigns.current_user, zone, pid, dmg) do
          {:ok, outcome, placement} ->
            %{id: pid, asset: placement.asset, damage: dmg, crit: false, outcome: outcome, x: placement.x, y: placement.y, z: placement.z}

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  # Health and mana given back by a power (capped at the maximums), pushed and broadcast.
  defp restore(socket, hp_add, mp_add) when hp_add > 0 or mp_add > 0 do
    me = current(socket)

    with %{} <- me,
         false <- socket.assigns[:is_dead?] || false,
         {:ok, %{hp: hp, max_hp: max_hp, mp: mp, max_mp: max_mp}} <- Combat.get_character_stats(me.character_id),
         true <- hp > 0 do
      new_hp = min(max_hp, hp + hp_add)
      new_mp = min(max_mp, mp + mp_add)
      {:ok, _} = Combat.update_character_hp_mp(me.character_id, new_hp, new_mp)

      socket
      |> update_runtime(%{hp: new_hp, mp: new_mp})
      |> push_event("character_stats_update", %{hp: new_hp, max_hp: max_hp, mp: new_mp, max_mp: max_mp})
      |> broadcast_hp(me.character_id, new_hp, max_hp, "healed")
    else
      _ -> socket
    end
  end

  defp restore(socket, _, _), do: socket

  # Thornbite: the creature that struck takes damage back (and dies of it, for experience).
  defp thorn(socket, me, mob_id, damage) do
    zone = socket.assigns[:mobs_zone] || "lobby"
    attack = %{id: me.character_id, target: mob_id, damage: damage, x: me.position.x, z: me.position.z, range: 1_000.0, crit: false}

    case Mobs.spell_hit(zone, attack) do
      %{killed: true} = hit ->
        {socket, progress} = award_kills(socket, [hit])
        socket = if progress, do: push_event(socket, "xp_gained", progress), else: socket
        push_event(socket, "power_fired", %{power: "thorns", damage: damage})

      %{} ->
        push_event(socket, "power_fired", %{power: "thorns", damage: damage})

      _ ->
        socket
    end
  end

  defp take_hit(socket, raw_damage, from_mob \\ nil) do
    me = current(socket)

    if socket.assigns[:is_dead?] || is_nil(me) do
      socket
    else
      # Apply Armour Class (AC) mitigation + temporary AC buffs, then absorb shields
      eq = socket.assigns[:equipment] || %{}
      buffs = SkillEvents.active_buffs(socket)
      total_ac = Melee.total_ac(eq) + buffs.ac
      mitigated = Tuning.mitigate_ac(raw_damage, total_ac)
      {damage, socket} = SkillEvents.absorb_shield(socket, mitigated)
      powers = Powers.active(eq)

      # Midas Ward and Thornbite (BaconWorld.Powers); lightning (99 999) is beyond both
      {damage, socket} =
        case Powers.on_hit(powers, if(raw_damage >= 99_999, do: 0, else: damage)) do
          {:gold, coins} ->
            Inventory.add_coins(me.character_id, coins)
            {0, push_event(socket, "power_fired", %{power: "midas", coins: coins})}

          {:hit, _, thorns} when thorns > 0 and is_binary(from_mob) ->
            {damage, thorn(socket, me, from_mob, thorns)}

          _ ->
            {damage, socket}
        end

      if damage <= 0 do
        socket
      else
        case Combat.get_character_stats(me.character_id) do
          {:ok, %{hp: hp, max_hp: max_hp, mp: mp, max_mp: max_mp}} ->
            overkill? = damage >= max_hp
            new_hp = max(0, hp - damage)
            now = System.monotonic_time(:millisecond)
            # Phoenix Rebirth (BaconWorld.Powers): a killing blow leaves you standing
            reborn = if raw_damage < 99_999, do: Powers.rebirth(powers, new_hp, max_hp, socket.assigns[:phoenix_at], now)
            {new_hp, overkill?, socket} =
              if reborn,
                do: {reborn, false, socket |> assign(phoenix_at: now) |> push_event("power_fired", %{power: "phoenix"})},
                else: {new_hp, overkill?, socket}
            {:ok, _} = Combat.update_character_hp_mp(me.character_id, new_hp, mp)

            state =
              cond do
                new_hp == 0 && overkill? -> "shattered"
                new_hp == 0 -> "dead"
                true -> "hurt"
              end

            socket =
              socket
              |> update_runtime(%{hp: new_hp})
              |> push_event("character_stats_update", %{hp: new_hp, max_hp: max_hp, mp: mp, max_mp: max_mp})
              |> broadcast_hp(me.character_id, new_hp, max_hp, state)

            if new_hp == 0, do: die(socket, me, shatter: overkill?, reason: "slain"), else: socket

          _ ->
            socket
        end
      end
    end
  end

  @doc "Instantly kills the character (e.g. falling into the abyss, suicide command, lethal overkill)."
  def kill_character(socket, opts \\ []) do
    me = current(socket)

    if socket.assigns[:is_dead?] || is_nil(me) do
      socket
    else
      shatter? = Keyword.get(opts, :shatter, true)
      reason = Keyword.get(opts, :reason, "killed")
      Combat.update_character_hp_mp(me.character_id, 0, 0)

      socket
      |> update_runtime(%{hp: 0})
      |> push_event("character_stats_update", %{hp: 0, max_hp: me.max_hp, mp: 0, max_mp: me.max_mp})
      |> broadcast_hp(me.character_id, 0, me.max_hp, if(shatter?, do: "shattered", else: "dead"))
      |> die(me, shatter: shatter?, reason: reason)
    end
  end

  defp die(socket, me, opts) do
    shatter? = Keyword.get(opts, :shatter, false)
    reason = Keyword.get(opts, :reason, "slain")
    {:ok, coords} = Combat.respawn_character(me.character_id)
    if timer = socket.assigns[:pending_respawn_timer], do: Process.cancel_timer(timer)
    timer = Process.send_after(self(), {:auto_respawn, me.character_id}, @respawn_ms)
    if id = socket.assigns[:looting], do: Mobs.loot_close(socket.assigns[:mobs_zone] || "lobby", id, me.character_id)

    socket
    |> BaconWorldWeb.MountEvents.dismount()
    |> BaconWorldWeb.SkillEvents.cancel("dead")
    |> assign(pending_respawn_timer: timer, pending_spawn_coords: coords, is_dead?: true, looting: nil, combat_buffs: %{})
    |> set_dead(true)
    |> push_event("character_died", %{
      spawn_coords: coords,
      hp: me.max_hp,
      max_hp: me.max_hp,
      mp: me.max_mp,
      max_mp: me.max_mp,
      respawn_in_ms: @respawn_ms,
      shatter: shatter?,
      reason: reason
    })
  end

  @doc false
  # Experience for the creatures in `hits` that died (also a spell's or a skill's:
  # BaconWorldWeb.SkillEvents). In a group it is shared (`BaconWorld.Groups.shares/2`) among the
  # members alive and near: this LiveView awards its own share and tells the others theirs.
  # Returns `{socket, progress | nil}`.
  def award_kills(socket, hits) do
    kills = Enum.filter(hits, & &1.killed)
    me = current(socket)

    if kills == [] or is_nil(me) do
      {socket, nil}
    else
      # Bloom (BaconWorld.Powers): each kill heals
      bloom = Powers.on_kills(Powers.active(socket.assigns[:equipment] || %{}), length(kills), me.max_hp || 0)
      socket = restore(socket, bloom, 0)
      level = socket.assigns[:level] || 1
      near = groupmates_near(socket, me)

      xp =
        Enum.reduce(kills, 0, fn k, acc ->
          # the creature's own worth (its type, rank, elite, a camp's clear: Brain.xp_mult/1, Zone)
          shares = BaconWorld.Groups.shares(k.level, [{me.character_id, level} | near], Map.get(k, :xp_mult, 1.0))
          BaconWorld.Groups.award(me.character_id, shares, k.level)
          acc + Map.get(shares, me.character_id, 0)
        end)

      gain_xp(socket, xp, :kill)
    end
  end

  @doc """
  Awards `xp` and keeps the socket's level in step. `source`: `:kill` (returns `{socket, progress}`,
  the caller replies with it) or `:group` (a groupmate's kill: pushes `"xp_gained"`, returns the
  socket).
  """
  def gain_xp(socket, xp, source) do
    me = current(socket)

    result =
      with %{} <- me, {:ok, progress} <- Progression.award_xp(me.character_id, xp) do
        progress = Map.put(progress, :gained, xp)

        socket =
          if progress.levels_gained > 0 do
            socket
            |> assign(level: progress.level)
            |> update_presence(%{level: progress.level})
            |> update_runtime(%{max_hp: progress.max_hp, max_mp: progress.max_mp, level: progress.level})
            |> SkillEvents.push_stats_sheet()
          else
            socket
          end

        {socket, progress}
      else
        _ -> {socket, nil}
      end

    case {source, result} do
      {:kill, r} -> r
      {:group, {socket, nil}} -> socket
      {:group, {socket, progress}} -> push_event(socket, "xp_gained", Map.put(progress, :group, true))
    end
  end

  # The other members of my group in this zone, alive and within BaconWorld.Groups.share_range_m/0
  # of me (the zone's presence): `[{character_id, level}]`.
  defp groupmates_near(socket, me) do
    case BaconWorld.Groups.members(me.character_id) do
      [_only] ->
        []

      ids ->
        range = BaconWorld.Groups.share_range_m() * Brain.u()
        {mx, mz} = {me.position.x, me.position.z}

        (socket.assigns[:zone_online_characters] || [])
        |> Enum.filter(fn p ->
          p.character_id != me.character_id and p.character_id in ids and not (p[:dead] || false) and
            :math.sqrt(:math.pow((p.x || 0.0) - mx, 2) + :math.pow((p.z || 0.0) - mz, 2)) <= range
        end)
        |> Enum.uniq_by(& &1.character_id)
        |> Enum.map(&{&1.character_id, &1[:level] || 1})
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
            socket = socket |> refresh_gear(id) |> SkillEvents.push_stats_sheet()
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
