defmodule BaconWorldWeb.Admin.BestiaryLive do
  @moduledoc """
  /admin/bacon_world/bestiary - the monster creation system (2026-11-03).

    * **Monsters**: monster types (`BaconWorld.Bestiary`, `bacon_world_defs` kind `"monster"`) on a
      form instead of JSON: name, the rig it borrows, rank, levels, health, damage, speeds, gear,
      loot, loot tables, experience; a preview at any level against any player level, and a
      thousand-corpse loot simulation. Save as new copies one into a variant.
    * **Camps**: managed camps (`BaconWorld.Mobs.Camps`): where, how big, their features (decor,
      `BaconWorld.Mobs.CampLayout`), slots with spawn rotation (random, cycle, placeholder and
      rare, day or night only), level band, elites, social aggro, respawn, the clear's reward and
      escalation to a boss; live status of the creatures, Respawn now, Clear out; turning one of
      the lobby's old camps into a managed one (and back).
    * **Loot tables** (`BaconWorld.Loot`): weighted pools, rolled-alone extras, nested tables,
      coins, with a simulator.
    * **Experience**: the World tuning numbers that pace levels and price kills, and the curve.
    * **XP & loot events** (`BaconWorld.LiveEvents`): double-XP weekends and the like, announced in
      every zone's chat.

  Everything is live at once: the zone processes read the definitions every time they spawn.
  """
  use Bacon8Web, :live_view
  import Ecto.Query

  alias Bacon8.GamesRepo
  alias Bacon8.Games.GameCharacter
  alias Bacon8Web.Components.AdminSidebar
  alias BaconWorld.{Bestiary, Building, Defs, LiveEvents, Loot, Mobs, Tuning, World, Zone}
  alias BaconWorld.Mobs.{CampLayout, Camps, Rotation, Spawns}

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @tabs [{"monsters", "🐉 Monsters"}, {"camps", "🏕️ Camps"}, {"loot", "💰 Loot tables"}, {"xp", "⭐ Experience"}, {"events", "🎉 XP & loot events"}]
  @xp_keys ~w(xp_mult xp_curve_mult rank_elite_xp_mult rank_rare_xp_mult rank_boss_xp_mult elite_xp_mult elite_hp_mult elite_dmg_mult mob_hp_mult mob_damage_mult loot_chance_mult coin_mult)
  @status_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    zones =
      GamesRepo.all(from z in Zone, order_by: [asc_nulls_first: z.number], select: %{slug: z.slug, name: z.name, number: z.number, id: z.id})

    if connected?(socket), do: :timer.send_interval(@status_ms, :refresh_status)

    {:ok,
     assign(socket,
       page_title: "Admin - Bacon World - Bestiary",
       tabs: @tabs,
       tab: "monsters",
       zones: zones,
       zone: "lobby",
       # monsters
       mon_q: "",
       mon_id: nil,
       mon_form: nil,
       mon_errors: [],
       mon_preview: %{level: 1, player: 1},
       mon_sim: nil,
       # camps
       camp_id: nil,
       camp_form: nil,
       camp_errors: [],
       camp_status: nil,
       # loot
       loot_id: nil,
       loot_form: nil,
       loot_errors: [],
       loot_sim: nil,
       loot_sim_level: 5,
       # events
       event_errors: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in Enum.map(@tabs, &elem(&1, 0)), do: params["tab"], else: "monsters"
    zone = params["zone"] || socket.assigns.zone
    socket = assign(socket, tab: tab, zone: zone)

    socket =
      case tab do
        "monsters" -> open_monster(socket, params["id"])
        "camps" -> open_camp(socket, params["id"])
        "loot" -> open_table(socket, params["id"])
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_status, %{assigns: %{tab: "camps", camp_id: id, zone: zone}} = socket) when is_binary(id) and id != "new" do
    {:noreply, assign(socket, camp_status: status(zone, id))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ======================================================================= monsters

  @impl true
  def handle_event("mon_filter", %{"q" => q}, socket), do: {:noreply, assign(socket, mon_q: String.trim(q))}

  def handle_event("mon_change", %{"m" => p}, socket), do: {:noreply, assign(socket, mon_form: Map.merge(socket.assigns.mon_form || %{}, p))}

  def handle_event("mon_save", %{"m" => p} = params, socket) do
    copy? = params["as_new"] == "true"
    old = if socket.assigns.mon_id not in [nil, "new"] and not copy?, do: %{id: socket.assigns.mon_id}
    p = if copy?, do: Map.put(p, "id", p["new_id"] || ""), else: p

    case Bestiary.from_form(p, old) do
      {:ok, id, kind} ->
        cond do
          is_nil(old) and Map.has_key?(Spawns.kinds(), id) ->
            {:noreply, assign(socket, mon_form: p, mon_errors: ["There is already a monster type #{id}: pick another id."])}

          not String.match?(id, ~r/^[a-z0-9_]{2,48}$/) ->
            {:noreply, assign(socket, mon_form: p, mon_errors: ["An id is 2-48 lowercase letters, digits and underscores."])}

          true ->
            Defs.put("monster", id, kind)
            Building.forget_catalogue()
            audit(socket, "bacon_world.monster.save", id)
            {:noreply, socket |> put_flash(:info, "#{kind.name} saved: new spawns use it at once.") |> push_patch(to: bpath("monsters", id))}
        end

      {:error, errors} ->
        {:noreply, assign(socket, mon_form: p, mon_errors: errors)}
    end
  end

  def handle_event("mon_delete", _params, socket) do
    id = socket.assigns.mon_id
    camps = Bestiary.used_by(id)
    placed = GamesRepo.aggregate(from(p in BaconWorld.Placement, where: p.asset == ^("mob:" <> id)), :count)
    code = Enum.any?(Spawns.camps(), fn c -> Enum.any?(c.mobs, &(elem(&1, 0) == id)) end)

    cond do
      camps != [] -> {:noreply, put_flash(socket, :error, "#{id} is in camps: #{Enum.map_join(camps, ", ", &elem(&1, 1))}. Take it out of them first.")}
      placed > 0 -> {:noreply, put_flash(socket, :error, "#{placed} placed spawns use #{id} (the Database page's Spawns tab). Remove them first.")}
      code -> {:noreply, put_flash(socket, :error, "The game's own camps use #{id}; it can't be deleted.")}
      true ->
        Defs.delete("monster", id)
        Building.forget_catalogue()
        audit(socket, "bacon_world.monster.delete", id)
        {:noreply, socket |> put_flash(:info, "#{id} deleted.") |> push_patch(to: bpath("monsters", nil))}
    end
  end

  def handle_event("mon_preview", %{"level" => l, "player" => pl}, socket) do
    {:noreply, assign(socket, mon_preview: %{level: int(l, 1) |> max(1) |> min(60), player: int(pl, 1) |> max(1) |> min(60)})}
  end

  def handle_event("mon_sim", %{"level" => l, "n" => n}, socket) do
    case Map.get(Spawns.kinds(), socket.assigns.mon_id) do
      nil -> {:noreply, put_flash(socket, :error, "Save the monster first.")}
      k -> {:noreply, assign(socket, mon_sim: Bestiary.simulate_loot(k, int(l, 1) |> max(1), int(n, 1000) |> max(10) |> min(20_000)))}
    end
  end

  def handle_event("import_examples", _params, socket) do
    {:ok, %{added: added}} = Bestiary.import_examples()
    Building.forget_catalogue()
    audit(socket, "bacon_world.bestiary.import_examples", Enum.join(added, ","))
    msg = if added == [], do: "The examples are all here already.", else: "Added #{Enum.join(added, ", ")}."
    {:noreply, put_flash(socket, :info, msg)}
  end

  # ======================================================================= camps

  def handle_event("camp_zone", %{"zone" => zone}, socket), do: {:noreply, push_patch(socket, to: bpath("camps", nil, zone))}

  def handle_event("camp_change", %{"c" => p}, socket), do: {:noreply, assign(socket, camp_form: merge_camp_form(socket.assigns.camp_form, p))}

  def handle_event("camp_add_slot", _params, socket) do
    f = socket.assigns.camp_form
    slots = f["slots"] || %{}
    i = slots |> Map.keys() |> Enum.map(&int(&1, 0)) |> Enum.max(fn -> -1 end) |> Kernel.+(1)
    blank = %{"count" => "1", "table" => "", "mode" => "random", "rare_kind" => "", "rare_pct" => "", "rare_cooldown_min" => "", "window" => "", "loot_tables" => "", "respawn_s" => ""}
    {:noreply, assign(socket, camp_form: Map.put(f, "slots", Map.put(slots, to_string(i), blank)))}
  end

  def handle_event("camp_remove_slot", %{"i" => i}, socket) do
    f = socket.assigns.camp_form
    {:noreply, assign(socket, camp_form: Map.put(f, "slots", Map.delete(f["slots"] || %{}, i)))}
  end

  def handle_event("camp_my_pos", _params, socket) do
    zone = socket.assigns.camp_form["zone"] || socket.assigns.zone

    case my_position(socket, zone) do
      nil -> {:noreply, put_flash(socket, :error, "None of your characters has a saved position in #{zone}. Walk there in the game first.")}
      {x, z} -> {:noreply, assign(socket, camp_form: Map.merge(socket.assigns.camp_form, %{"x" => fmt(x), "z" => fmt(z)}))}
    end
  end

  def handle_event("camp_save", %{"c" => p}, socket) do
    form = merge_camp_form(socket.assigns.camp_form, p)
    id = socket.assigns.camp_id
    old = if id not in [nil, "new"], do: Camps.get(id), else: nil

    case Camps.from_form(form, old || %{}) do
      {:ok, camp} ->
        id = if id in [nil, "new"], do: unique_camp_id(camp.name), else: id
        Defs.put(Camps.kind(), id, camp)
        if old && old.zone != camp.zone, do: Mobs.put_camp(old.zone, id, nil)
        Mobs.ensure_zone(camp.zone)
        Mobs.put_camp(camp.zone, id, camp)
        audit(socket, "bacon_world.camp.save", id)
        {:noreply, socket |> put_flash(:info, "#{camp.name} saved; its creatures start over.") |> push_patch(to: bpath("camps", id, camp.zone))}

      {:error, errors} ->
        {:noreply, assign(socket, camp_form: form, camp_errors: errors)}
    end
  end

  def handle_event("camp_decor", _params, socket) do
    with {id, camp} <- current_camp(socket) do
      origin = CampLayout.origin(id)
      removed = Building.delete_origin(camp.zone, origin)
      placed = Building.place_system(camp.zone, CampLayout.pieces(id, camp), origin)
      audit(socket, "bacon_world.camp.decor", "#{id} +#{placed} -#{removed}")
      {:noreply, put_flash(socket, :info, "Decor: #{placed} pieces placed (#{removed} old ones removed). Move them in build mode like anything else.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Save the camp first.")}
    end
  end

  def handle_event("camp_decor_clear", _params, socket) do
    with {id, camp} <- current_camp(socket) do
      n = Building.delete_origin(camp.zone, CampLayout.origin(id))
      {:noreply, put_flash(socket, :info, "Removed #{n} decor pieces.")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("camp_respawn", _params, socket) do
    with {id, camp} <- current_camp(socket) do
      Mobs.respawn_camp(camp.zone, id)
      {:noreply, put_flash(socket, :info, "Everything dead or gone in #{camp.name} comes back now.")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("camp_despawn", _params, socket) do
    with {id, camp} <- current_camp(socket) do
      Mobs.despawn_camp(camp.zone, id)
      {:noreply, put_flash(socket, :info, "#{camp.name} cleared out; its creatures return on their timers.")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("camp_delete", _params, socket) do
    with {id, camp} <- current_camp(socket) do
      Defs.delete(Camps.kind(), id)
      Mobs.put_camp(camp.zone, id, nil)
      n = Building.delete_origin(camp.zone, CampLayout.origin(id))
      audit(socket, "bacon_world.camp.delete", id)
      {:noreply, socket |> put_flash(:info, "#{camp.name} deleted (and #{n} decor pieces).") |> push_patch(to: bpath("camps", nil, camp.zone))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("camp_convert", %{"legacy" => legacy_id}, socket) do
    zone = socket.assigns.zone

    with %{} = code_camp <- Enum.find(Spawns.camps(), &(&1.id == legacy_id)),
         placements when placements != [] <- Building.by_origin(zone, "camp:" <> legacy_id),
         camp = Camps.from_legacy(code_camp, zone, placements),
         true <- camp.slots != [] || :no_spawns do
      id = unique_camp_id(camp.name)
      Defs.put(Camps.kind(), id, camp)
      for p <- placements, String.starts_with?(p.asset, "mob:"), do: Building.delete(socket.assigns.current_user, zone, p.id)
      Mobs.put_camp(zone, id, camp)
      audit(socket, "bacon_world.camp.convert", "#{legacy_id} -> #{id}")
      {:noreply, socket |> put_flash(:info, "#{camp.name} is a managed camp now (its decor stays as it was).") |> push_patch(to: bpath("camps", id, zone))}
    else
      _ -> {:noreply, put_flash(socket, :error, "That camp has no placed spawns in #{zone} to take over.")}
    end
  end

  def handle_event("camp_revert", _params, socket) do
    with {id, %{legacy: %{placements: rows}} = camp} <- current_camp(socket) do
      Defs.delete(Camps.kind(), id)
      Mobs.put_camp(camp.zone, id, nil)
      n = Building.restore_spawns(camp.zone, rows)
      audit(socket, "bacon_world.camp.revert", id)
      {:noreply, socket |> put_flash(:info, "#{camp.name} is plain spawns again (#{n} put back).") |> push_patch(to: bpath("camps", nil, camp.zone))}
    else
      _ -> {:noreply, put_flash(socket, :error, "This camp wasn't converted from an old one.")}
    end
  end

  # ======================================================================= loot tables

  def handle_event("loot_save", %{"t" => p}, socket) do
    case Loot.from_form(p) do
      {:ok, table} ->
        id =
          case socket.assigns.loot_id do
            "new" -> Loot.slug(table.name)
            id -> id
          end

        cond do
          id in [nil, ""] ->
            {:noreply, assign(socket, loot_form: p, loot_errors: ["Give the table a name."])}

          socket.assigns.loot_id == "new" and Loot.get(id) != nil ->
            {:noreply, assign(socket, loot_form: p, loot_errors: ["There is already a table #{id}: pick another name."])}

          true ->
            Defs.put(Loot.kind(), id, table)
            audit(socket, "bacon_world.loot_table.save", id)
            {:noreply, socket |> put_flash(:info, "#{table.name} saved.") |> push_patch(to: bpath("loot", id))}
        end

      {:error, errors} ->
        {:noreply, assign(socket, loot_form: p, loot_errors: errors)}
    end
  end

  def handle_event("loot_delete", _params, socket) do
    id = socket.assigns.loot_id
    by_monsters = for {mid, k} <- Spawns.kinds(), id in (k[:loot_tables] || []), do: mid
    by_camps = for {cid, c} <- Camps.list(), get_in(c, [:clear, :loot_table]) == id or Enum.any?(c[:slots] || [], &(id in (&1[:loot_tables] || []))), do: cid
    by_tables = for {tid, t} <- Loot.list(), Enum.any?(t[:tables] || [], &(&1.table == id)), do: tid

    case by_monsters ++ by_camps ++ by_tables do
      [] ->
        Defs.delete(Loot.kind(), id)
        audit(socket, "bacon_world.loot_table.delete", id)
        {:noreply, socket |> put_flash(:info, "#{id} deleted.") |> push_patch(to: bpath("loot", nil))}

      users ->
        {:noreply, put_flash(socket, :error, "#{id} is used by #{Enum.join(users, ", ")}.")}
    end
  end

  def handle_event("loot_sim", %{"level" => l, "n" => n}, socket) do
    case Loot.get(socket.assigns.loot_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Save the table first.")}

      t ->
        level = int(l, 5) |> max(1) |> min(60)
        sim = Loot.simulate(fn -> Loot.roll(t, level) end, int(n, 1000) |> max(10) |> min(20_000))
        {:noreply, assign(socket, loot_sim: sim, loot_sim_level: level)}
    end
  end

  # ======================================================================= experience

  def handle_event("xp_save", %{"x" => p}, socket) do
    changes = Map.take(p, @xp_keys)
    {:ok, _} = Tuning.save(Map.merge(Tuning.current(), changes), socket.assigns.current_user.id)
    audit(socket, "bacon_world.tuning.experience", Enum.map_join(changes, " ", fn {k, v} -> "#{k}=#{v}" end))
    {:noreply, put_flash(socket, :info, "Saved. The next kill uses the new numbers.")}
  end

  # ======================================================================= events

  def handle_event("event_save", %{"e" => p}, socket) do
    case LiveEvents.from_form(p) do
      {:ok, e} ->
        id = "#{Loot.slug(e.name)}_#{System.system_time(:second)}"
        Defs.put(LiveEvents.kind(), id, e)
        audit(socket, "bacon_world.event.save", id)
        {:noreply, socket |> assign(event_errors: []) |> put_flash(:info, "#{e.name} scheduled.")}

      {:error, errors} ->
        {:noreply, assign(socket, event_errors: errors)}
    end
  end

  def handle_event("event_delete", %{"id" => id}, socket) do
    Defs.delete(LiveEvents.kind(), id)
    audit(socket, "bacon_world.event.delete", id)
    {:noreply, put_flash(socket, :info, "Event removed.")}
  end

  def handle_event("event_announce", %{"id" => id}, socket) do
    case List.keyfind(LiveEvents.list(), id, 0) do
      {_, e} ->
        text = "#{e.name}: #{event_summary(e)} until #{e.ends_at |> String.replace("T", " ") |> String.slice(0, 16)} UTC!"
        for z <- socket.assigns.zones, do: Phoenix.PubSub.broadcast(Bacon8.PubSub, "bacon_world:zone:#{z.id}", {:zone_chat_message, %{character_id: nil, character_name: "Bacon World", message: text, zone_wide: true, sent_at: DateTime.utc_now() |> DateTime.to_iso8601()}})
        {:noreply, put_flash(socket, :info, "Announced in every zone.")}

      nil ->
        {:noreply, socket}
    end
  end

  # ======================================================================= opening things

  defp open_monster(socket, nil), do: assign(socket, mon_id: nil, mon_form: nil, mon_errors: [], mon_sim: nil)
  defp open_monster(socket, "new"), do: assign(socket, mon_id: "new", mon_form: Bestiary.to_form(nil, Bestiary.blank()), mon_errors: [], mon_sim: nil)

  defp open_monster(socket, id) do
    case Map.get(Spawns.kinds(), id) do
      nil ->
        socket |> put_flash(:error, "There's no monster type #{id}.") |> open_monster(nil)

      k ->
        lvl = k.levels.first
        assign(socket, mon_id: id, mon_form: Bestiary.to_form(id, k), mon_errors: [], mon_sim: nil, mon_preview: %{level: lvl, player: lvl})
    end
  end

  defp open_camp(socket, nil), do: assign(socket, camp_id: nil, camp_form: nil, camp_errors: [], camp_status: nil)

  defp open_camp(socket, "new") do
    {x, z} = my_position(socket, socket.assigns.zone) || {0.0, 0.0}
    form = Camps.blank(socket.assigns.zone, x, z) |> Camps.to_form()
    assign(socket, camp_id: "new", camp_form: form, camp_errors: [], camp_status: nil)
  end

  defp open_camp(socket, id) do
    case Camps.get(id) do
      nil -> socket |> put_flash(:error, "There's no camp #{id}.") |> open_camp(nil)
      c -> assign(socket, camp_id: id, zone: c.zone, camp_form: Camps.to_form(c), camp_errors: [], camp_status: status(c.zone, id))
    end
  end

  defp current_camp(socket) do
    case socket.assigns.camp_id do
      id when is_binary(id) and id != "new" -> (c = Camps.get(id)) && {id, c}
      _ -> nil
    end
  end

  # the form keeps what was typed (slots added on the page aren't in Defs yet); checkboxes only
  # arrive when ticked, so their hidden "false" fields carry the unticked state
  defp merge_camp_form(old, p) do
    old = old || %{}
    slots = Map.merge(old["slots"] || %{}, p["slots"] || %{}, fn _k, a, b -> Map.merge(a, b) end)
    slots = Map.take(slots, Map.keys(p["slots"] || slots))
    old |> Map.merge(Map.delete(p, "slots")) |> Map.put("slots", slots) |> Map.put("features", List.wrap(p["features"] || old["features"]) -- [""])
  end

  defp unique_camp_id(name) do
    base = case Camps.slug(name) do
      "" -> "camp"
      s -> s
    end

    taken = Defs.map(Camps.kind())
    Enum.find(Stream.concat([base], Stream.map(2..999, &"#{base}_#{&1}")), &(not Map.has_key?(taken, &1)))
  end

  defp status(zone, id) do
    case Mobs.camp_status(zone, id) do
      {:ok, s} -> s
      _ -> nil
    end
  end

  # where the admin's latest character in `zone` last stood (metres), or nil
  defp my_position(socket, zone) do
    user_id = socket.assigns.current_user.id

    with {:ok, game_id} <- World.game_id(),
         %GameCharacter{settings: s} <-
           GamesRepo.one(
             from c in GameCharacter,
               where: c.game_id == ^game_id and c.user_id == ^user_id and fragment("?->>'zone_slug'", c.settings) == ^zone,
               order_by: [desc_nulls_last: c.last_played_at],
               limit: 1
           ),
         %{"x" => x, "z" => z} when is_number(x) and is_number(z) <- s["position"] do
      u = BaconWorld.Mobs.Brain.u()
      {Float.round(x / u, 1), Float.round(z / u, 1)}
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # the lobby's old code camps that still have placed spawns to take over
  defp legacy_camps("lobby") do
    taken = for {_id, c} <- Camps.list(), c[:legacy], do: c.legacy[:camp]
    for c <- Spawns.camps(), c.id not in taken, do: c
  rescue
    _ -> []
  end

  defp legacy_camps(_zone), do: []

  defp open_table(socket, nil), do: assign(socket, loot_id: nil, loot_form: nil, loot_errors: [], loot_sim: nil)
  defp open_table(socket, "new"), do: assign(socket, loot_id: "new", loot_form: Loot.to_form(nil), loot_errors: [], loot_sim: nil)

  defp open_table(socket, id) do
    case Loot.get(id) do
      nil -> socket |> put_flash(:error, "There's no loot table #{id}.") |> open_table(nil)
      t -> assign(socket, loot_id: id, loot_form: Loot.to_form(t), loot_errors: [], loot_sim: nil)
    end
  end

  # ======================================================================= helpers

  defp bpath(tab, id, zone \\ nil) do
    q = [{"tab", tab}, {"id", id}, {"zone", zone}] |> Enum.reject(&is_nil(elem(&1, 1)))
    "/admin/bacon_world/bestiary?" <> URI.encode_query(q)
  end

  defp audit(socket, action, detail) do
    Bacon8.Audit.log(socket.assigns.current_user.id, action, "bacon_world", nil, %{detail: to_string(detail)})
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp event_summary(e) do
    [{:xp_mult, "XP"}, {:loot_mult, "loot"}, {:coin_mult, "coins"}]
    |> Enum.filter(fn {k, _} -> (e[k] || 1.0) != 1.0 end)
    |> Enum.map_join(", ", fn {k, label} -> "#{fmt(e[k])}× #{label}" end)
    |> case do
      "" -> "nothing multiplied"
      s -> s
    end
  end

  defp int(v, d) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> d
    end
  end

  defp fmt(f) when is_float(f), do: :erlang.float_to_binary(f, [:compact, decimals: 2])
  defp fmt(v), do: to_string(v)

  defp con_class(:red), do: "text-red-400"
  defp con_class(:yellow), do: "text-yellow-300"
  defp con_class(:white), do: "text-white"
  defp con_class(:blue), do: "text-blue-400"
  defp con_class(:light_blue), do: "text-sky-300"
  defp con_class(:green), do: "text-green-400"
  defp con_class(_), do: "text-gray-500"

  defp rank_badge("boss"), do: "bg-red-900 text-red-200"
  defp rank_badge("rare"), do: "bg-purple-900 text-purple-200"
  defp rank_badge("elite"), do: "bg-amber-900 text-amber-200"
  defp rank_badge(_), do: "bg-gray-800 text-gray-400"

  defp zone_name(zones, slug), do: Enum.find_value(zones, slug, &(&1.slug == slug && (&1.name || &1.slug)))

  # ======================================================================= render

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/bacon_world">
      <div class="max-w-7xl mx-auto space-y-4 text-sm text-gray-300">
        <div class="dark-glass p-6 rounded-xl flex flex-wrap items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-white">Bestiary</h1>
            <p class="mt-1 text-gray-400">Monster types, camps and their spawn rotation, loot tables, experience and events. Changes are live at once.</p>
          </div>
          <div class="flex flex-wrap gap-1">
            <.link :for={{id, label} <- @tabs} patch={bpath(id, nil, @zone)} class={"px-3 py-1.5 rounded " <> if(@tab == id, do: "bg-sky-700 text-white", else: "bg-gray-800 hover:bg-gray-700")}>{label}</.link>
            <.link navigate="/admin/bacon_world" class="px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-white">Back</.link>
          </div>
        </div>

        {case @tab do
          "monsters" -> monsters(assigns)
          "camps" -> camps(assigns)
          "loot" -> loot(assigns)
          "xp" -> xp(assigns)
          "events" -> events(assigns)
        end}
      </div>
    </AdminSidebar.admin_layout>
    """
  end

  # ----------------------------------------------------------------------- monsters

  defp monsters(assigns) do
    q = String.downcase(assigns.mon_q)

    list =
      for {id, k} <- Bestiary.list(), q == "" or String.contains?(String.downcase(id <> " " <> (k[:name] || "") <> " " <> (k[:family] || "")), q), do: {id, k}

    kind = assigns.mon_id && Map.get(Spawns.kinds(), assigns.mon_id)
    pv = kind && Bestiary.preview(kind, assigns.mon_preview.level, assigns.mon_preview.player)
    assigns = assign(assigns, list: list, kind: kind, pv: pv, used_by: (kind && Bestiary.used_by(assigns.mon_id)) || [])

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-4 gap-4">
      <div class="dark-glass rounded-xl p-4 space-y-3">
        <form phx-change="mon_filter" phx-submit="mon_filter"><input name="q" value={@mon_q} placeholder="Find a monster type" class="w-full bg-gray-900 rounded px-2 py-1" phx-debounce="200" /></form>
        <div class="flex gap-2">
          <.link patch={bpath("monsters", "new")} class="flex-1 text-center bg-sky-700 hover:bg-sky-600 text-white px-3 py-1.5 rounded">New monster</.link>
          <button phx-click="import_examples" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded" title="Adds example monsters and loot tables that aren't here yet">Examples</button>
        </div>
        <ul class="space-y-1 max-h-[65vh] overflow-auto">
          <li :for={{id, k} <- @list}>
            <.link patch={bpath("monsters", id)} class={"flex items-center justify-between gap-2 px-2 py-1 rounded " <> if(@mon_id == id, do: "bg-sky-900 text-white", else: "hover:bg-gray-800")}>
              <span class="truncate">{k[:name] || id} <span class="text-gray-500">{BaconWorld.Loot.range_text(k[:levels])}</span></span>
              <span class={"text-[10px] px-1.5 rounded " <> rank_badge(Spawns.rank(k))}>{Spawns.rank(k)}</span>
            </.link>
          </li>
        </ul>
      </div>

      <div :if={@mon_form} class="dark-glass rounded-xl p-4 lg:col-span-3 space-y-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-xl text-white font-semibold">{if @mon_id == "new", do: "New monster type", else: @mon_form["name"]}<span :if={@mon_id != "new"} class="ml-2 text-gray-500 text-sm">{@mon_id}</span></h2>
          <div :if={@used_by != []} class="text-xs text-gray-400">In camps: {Enum.map_join(@used_by, ", ", &elem(&1, 1))}</div>
        </div>
        <ul :if={@mon_errors != []} class="bg-red-950/60 border border-red-800 rounded p-2 text-red-200 list-disc list-inside">
          <li :for={e <- @mon_errors}>{e}</li>
        </ul>

        <form phx-change="mon_change" phx-submit="mon_save" class="space-y-4">
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
            <.inp :if={@mon_id == "new"} label="id (letters, digits, _)" name="m[id]" value={@mon_form["id"]} />
            <.inp label="name (a goblin shaman, Grubnak the Cruel)" name="m[name]" value={@mon_form["name"]} />
            <label>looks like (rig)
              <select name="m[model]" class="w-full bg-gray-900 rounded px-2 py-1">
                <option :for={m <- Bestiary.models()} value={m} selected={@mon_form["model"] == m}>{m}</option>
              </select>
            </label>
            <label>rank
              <select name="m[rank]" class="w-full bg-gray-900 rounded px-2 py-1">
                <option :for={r <- Spawns.ranks()} value={r} selected={@mon_form["rank"] == r}>{r}</option>
              </select>
            </label>
            <.inp label="family (for sorting)" name="m[family]" value={@mon_form["family"]} />
            <.inp label="levels (3-5)" name="m[levels]" value={@mon_form["levels"]} />
            <.inp label="health at level 0" name="m[hp_base]" value={@mon_form["hp_base"]} />
            <.inp label="health per level" name="m[hp_per]" value={@mon_form["hp_per"]} />
            <.inp label="damage (2-6, grows with level)" name="m[dmg]" value={@mon_form["dmg"]} />
            <.inp label="swing delay ms" name="m[dly_ms]" value={@mon_form["dly_ms"]} />
            <.inp label="walk m/s" name="m[walk]" value={@mon_form["walk"]} />
            <.inp label="run m/s" name="m[run]" value={@mon_form["run"]} />
            <.inp label="aggro range m" name="m[aggro]" value={@mon_form["aggro"]} />
            <.inp label="leash m (blank: 30)" name="m[leash]" value={@mon_form["leash"]} />
            <.inp label="reach m" name="m[reach]" value={@mon_form["reach"]} />
            <.inp label="hide radius m (blank: 0.4)" name="m[radius]" value={@mon_form["radius"]} />
            <.inp label="size × (blank: 1)" name="m[scale]" value={@mon_form["scale"]} />
            <.inp label="respawn seconds (70-110)" name="m[respawn_s]" value={@mon_form["respawn_s"]} />
            <.inp label="copper × level (2-8)" name="m[coins]" value={@mon_form["coins"]} />
            <.inp label="weapon drop %" name="m[weapon_drop]" value={@mon_form["weapon_drop"]} />
            <.inp label="experience ×" name="m[xp_mult]" value={@mon_form["xp_mult"]} />
            <.inp label="roams within m (blank: no)" name="m[roam]" value={@mon_form["roam"]} />
            <.inp label="loot tables (ids, commas)" name="m[loot_tables]" value={@mon_form["loot_tables"]} list="bw-loot-tables" />
            <div class="flex flex-wrap items-end gap-3 col-span-2">
              <.check label="boss" name="m[boss]" checked={@mon_form["boss"] in [true, "true"]} />
              <.check label="ranged (shoots)" name="m[ranged]" checked={@mon_form["ranged"] in [true, "true"]} />
              <.check label="aquatic (deep water)" name="m[aquatic]" checked={@mon_form["aquatic"] in [true, "true"]} />
            </div>
          </div>
          <datalist id="bw-loot-tables"><option :for={{id, _} <- Loot.list()} value={id} /></datalist>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-2">
            <.area label="weapons (item weight; none for bare hands)" name="m[weapons]" value={@mon_form["weapons"]} />
            <.area label="off hand (item weight)" name="m[offhand]" value={@mon_form["offhand"]} />
            <.area label="moves (bite 5, claw 3)" name="m[moves]" value={@mon_form["moves"]} />
            <.area label="loot (item chance% qty)" name="m[loot]" value={@mon_form["loot"]} />
            <.area label="rare drops (item chance%)" name="m[drops]" value={@mon_form["drops"]} />
            <.area label="advanced (JSON: breath, specials...)" name="m[advanced]" value={@mon_form["advanced"]} />
          </div>
          <div class="flex flex-wrap items-end gap-2">
            <button type="submit" class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-2 rounded">Save</button>
            <span :if={@mon_id not in [nil, "new"]} class="flex items-end gap-2">
              <input name="new_id" placeholder="new id for a copy" class="bg-gray-900 rounded px-2 py-2" />
              <button type="submit" name="as_new" value="true" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded">Save as new</button>
            </span>
            <button :if={@mon_id not in [nil, "new"]} type="button" phx-click="mon_delete" data-confirm="Delete this monster type?" class="ml-auto bg-red-800 hover:bg-red-700 text-white px-4 py-2 rounded">Delete</button>
          </div>
        </form>

        <div :if={@kind} class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="rounded bg-gray-900/60 p-3 space-y-2">
            <form phx-change="mon_preview" class="flex gap-2 items-end">
              <.inp label="its level" name="level" value={@mon_preview.level} />
              <.inp label="player's level" name="player" value={@mon_preview.player} />
            </form>
            <div class="grid grid-cols-2 gap-x-4 gap-y-1">
              <span class="text-gray-500">health</span><span>{@pv.hp}</span>
              <span class="text-gray-500">damage a hit</span><span>{@pv.dmg_lo}-{@pv.dmg_hi}</span>
              <span class="text-gray-500">hits the player</span><span>{@pv.hit_pct}%</span>
              <span class="text-gray-500">damage a second</span><span>{@pv.dps}</span>
              <span class="text-gray-500">cons</span><span class={con_class(@pv.con)}>{@pv.con}</span>
              <span class="text-gray-500">experience</span><span>{@pv.xp}</span>
              <span class="text-gray-500">copper</span><span>{@pv.coins_lo}-{@pv.coins_hi}</span>
            </div>
          </div>
          <div class="rounded bg-gray-900/60 p-3 space-y-2">
            <form phx-submit="mon_sim" class="flex gap-2 items-end">
              <.inp label="level" name="level" value={@mon_preview.level} />
              <.inp label="corpses" name="n" value="1000" />
              <button class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Simulate loot</button>
            </form>
            <.sim_table sim={@mon_sim} />
          </div>
        </div>
      </div>

      <div :if={!@mon_form} class="dark-glass rounded-xl p-6 lg:col-span-3 text-gray-400 space-y-2">
        <p>Pick a monster type, or make a new one. A new type borrows a rig the game can already draw (a goblin, an orc, a skeleton, a rat, the dragon, the Kraken) with its own name, numbers, gear and loot.</p>
        <p><b class="text-gray-200">Examples</b> adds a goblin shaman, a bone knight, an orc berserker, two rares (Grubnak the Cruel, the Rat King) and a camp boss (the goblin warchief), with the loot tables they use. Put them in a camp on the Camps tab.</p>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------- camps

  defp camps(assigns) do
    camps = for {id, c} <- Camps.list(), c[:zone] == assigns.zone, do: {id, c}
    assigns = assign(assigns, camps: camps, legacy: legacy_camps(assigns.zone), kinds: Spawns.kinds() |> Map.keys() |> Enum.sort())

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-4 gap-4">
      <div class="dark-glass rounded-xl p-4 space-y-3">
        <form phx-change="camp_zone">
          <label>zone
            <select name="zone" class="w-full bg-gray-900 rounded px-2 py-1">
              <option :for={z <- @zones} value={z.slug} selected={z.slug == @zone}>{z.name || z.slug}{if z.number, do: " (#{z.number})"}</option>
            </select>
          </label>
        </form>
        <.link patch={bpath("camps", "new", @zone)} class="block text-center bg-sky-700 hover:bg-sky-600 text-white px-3 py-1.5 rounded">New camp</.link>
        <ul class="space-y-1 max-h-[45vh] overflow-auto">
          <li :for={{id, c} <- @camps}>
            <.link patch={bpath("camps", id, @zone)} class={"flex justify-between gap-2 px-2 py-1 rounded " <> if(@camp_id == id, do: "bg-sky-900 text-white", else: "hover:bg-gray-800")}>
              <span class="truncate">{c.name}</span>
              <span class="text-gray-500">{Camps.population(c)}{if c[:enabled] == false, do: " · off"}</span>
            </.link>
          </li>
          <li :if={@camps == []} class="text-gray-500 px-2">No managed camps in {zone_name(@zones, @zone)} yet.</li>
        </ul>
        <form :if={@legacy != []} phx-submit="camp_convert" class="space-y-1 border-t border-gray-800 pt-3">
          <label class="text-gray-400">Turn an old camp into a managed one
            <select name="legacy" class="w-full bg-gray-900 rounded px-2 py-1">
              <option :for={c <- @legacy} value={c.id}>{c.name}</option>
            </select>
          </label>
          <button class="w-full bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded" data-confirm="Its placed spawns are replaced by the managed camp (Revert puts them back). Go on?">Convert</button>
        </form>
      </div>

      <div :if={@camp_form} class="dark-glass rounded-xl p-4 lg:col-span-3 space-y-4">
        <h2 class="text-xl text-white font-semibold">{if @camp_id == "new", do: "New camp", else: @camp_form["name"]}</h2>
        <ul :if={@camp_errors != []} class="bg-red-950/60 border border-red-800 rounded p-2 text-red-200 list-disc list-inside">
          <li :for={e <- @camp_errors}>{e}</li>
        </ul>

        <form phx-change="camp_change" phx-submit="camp_save" class="space-y-4">
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
            <.inp label="name" name="c[name]" value={@camp_form["name"]} />
            <label>zone
              <select name="c[zone]" class="w-full bg-gray-900 rounded px-2 py-1">
                <option :for={z <- @zones} value={z.slug} selected={z.slug == @camp_form["zone"]}>{z.name || z.slug}</option>
              </select>
            </label>
            <.inp label="x (metres)" name="c[x]" value={@camp_form["x"]} />
            <.inp label="z (metres)" name="c[z]" value={@camp_form["z"]} />
            <label>size
              <select name="c[size]" class="w-full bg-gray-900 rounded px-2 py-1">
                <option :for={{s, r, n} <- Camps.sizes()} value={s} selected={@camp_form["size"] == s}>{s} ({round(r)} m, ~{n})</option>
                <option value="custom" selected={@camp_form["size"] == "custom"}>custom radius</option>
              </select>
            </label>
            <.inp label="radius m (custom)" name="c[radius]" value={@camp_form["radius"]} />
            <.inp label="turn (radians)" name="c[rot]" value={@camp_form["rot"]} />
            <label>theme
              <select name="c[theme]" class="w-full bg-gray-900 rounded px-2 py-1">
                <option :for={t <- Camps.themes()} value={t} selected={@camp_form["theme"] == t}>{t}</option>
              </select>
            </label>
            <.inp label="level band (blank: each kind's)" name="c[levels]" value={@camp_form["levels"]} />
            <.inp label="elite chance %" name="c[elite_pct]" value={@camp_form["elite_pct"]} />
            <.inp label="assist radius m (0: off)" name="c[assist_radius]" value={@camp_form["assist_radius"]} />
            <.inp label="respawn seconds (blank: kinds')" name="c[respawn_s]" value={@camp_form["respawn_s"]} />
            <div class="flex items-end gap-3 col-span-2">
              <.check label="faster respawn with players near" name="c[dynamic_respawn]" checked={@camp_form["dynamic_respawn"] in [true, "true"]} />
              <.check label="enabled" name="c[enabled]" checked={@camp_form["enabled"] in [true, "true"]} />
              <button type="button" phx-click="camp_my_pos" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded" title="Where your character last stood in this zone">Use my position</button>
            </div>
          </div>

          <fieldset class="rounded bg-gray-900/50 p-3">
            <legend class="px-1 text-gray-400">features (decor)</legend>
            <input type="hidden" name="c[features][]" value="" />
            <div class="flex flex-wrap gap-3">
              <label :for={f <- Camps.features()} class="flex items-center gap-1">
                <input type="checkbox" name="c[features][]" value={f} checked={f in (@camp_form["features"] || [])} /> {String.replace(f, "_", " ")}
              </label>
            </div>
          </fieldset>

          <fieldset class="rounded bg-gray-900/50 p-3 space-y-2">
            <legend class="px-1 text-gray-400">slots: who spawns, and the rotation</legend>
            <datalist id="bw-kinds"><option :for={k <- @kinds} value={k} /></datalist>
            <div :for={{i, s} <- Enum.sort_by(@camp_form["slots"] || %{}, fn {k, _} -> int(k, 0) end)} class="grid grid-cols-2 md:grid-cols-6 gap-2 items-end border-b border-gray-800 pb-2">
              <.inp label="count" name={"c[slots][#{i}][count]"} value={s["count"]} />
              <div class="col-span-2"><.inp label="creatures (goblin 70, goblin_archer 30)" name={"c[slots][#{i}][table]"} value={s["table"]} list="bw-kinds" /></div>
              <label>rotation
                <select name={"c[slots][#{i}][mode]"} class="w-full bg-gray-900 rounded px-2 py-1">
                  <option :for={m <- Rotation.modes()} value={m} selected={s["mode"] == m}>{m}</option>
                </select>
              </label>
              <label>time of day
                <select name={"c[slots][#{i}][window]"} class="w-full bg-gray-900 rounded px-2 py-1">
                  <option value="" selected={s["window"] in [nil, ""]}>always</option>
                  <option value="day" selected={s["window"] == "day"}>day only</option>
                  <option value="night" selected={s["window"] == "night"}>night only</option>
                </select>
              </label>
              <button type="button" phx-click="camp_remove_slot" phx-value-i={i} class="bg-gray-800 hover:bg-red-800 text-white px-2 py-1 rounded">Remove</button>
              <.inp label="rare (kind)" name={"c[slots][#{i}][rare_kind]"} value={s["rare_kind"]} list="bw-kinds" />
              <.inp label="rare chance %" name={"c[slots][#{i}][rare_pct]"} value={s["rare_pct"]} />
              <.inp label="rare cooldown min" name={"c[slots][#{i}][rare_cooldown_min]"} value={s["rare_cooldown_min"]} />
              <.inp label="loot tables" name={"c[slots][#{i}][loot_tables]"} value={s["loot_tables"]} />
              <.inp label="respawn s" name={"c[slots][#{i}][respawn_s]"} value={s["respawn_s"]} />
            </div>
            <button type="button" phx-click="camp_add_slot" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Add a slot</button>
          </fieldset>

          <fieldset class="rounded bg-gray-900/50 p-3">
            <legend class="px-1 text-gray-400">when the last one falls</legend>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
              <.inp label="clear loot table" name="c[clear_loot_table]" value={@camp_form["clear_loot_table"]} list="bw-loot-tables2" />
              <.inp label="clear experience ×" name="c[clear_xp_mult]" value={@camp_form["clear_xp_mult"]} />
              <.inp label="boss after N clears (0: never)" name="c[clear_escalate_after]" value={@camp_form["clear_escalate_after"]} />
              <.inp label="boss (kind)" name="c[clear_boss]" value={@camp_form["clear_boss"]} list="bw-kinds" />
            </div>
            <datalist id="bw-loot-tables2"><option :for={{id, _} <- Loot.list()} value={id} /></datalist>
          </fieldset>

          <div class="flex flex-wrap gap-2">
            <button type="submit" class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-2 rounded">Save (creatures start over)</button>
          </div>
        </form>

        <div :if={@camp_id not in [nil, "new"]} class="flex flex-wrap gap-2 border-t border-gray-800 pt-3">
          <button phx-click="camp_decor" data-confirm="Replace this camp's generated decor?" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Generate decor</button>
          <button phx-click="camp_decor_clear" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Remove decor</button>
          <button phx-click="camp_respawn" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Respawn now</button>
          <button phx-click="camp_despawn" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Clear out</button>
          <button :if={Camps.get(@camp_id)[:legacy]} phx-click="camp_revert" data-confirm="Put the old placed spawns back and delete this managed camp?" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Revert to plain spawns</button>
          <button phx-click="camp_delete" data-confirm="Delete this camp, its creatures and its generated decor?" class="ml-auto bg-red-800 hover:bg-red-700 text-white px-3 py-1.5 rounded">Delete camp</button>
        </div>

        <div :if={@camp_id not in [nil, "new"]} class="rounded bg-gray-900/60 p-3">
          <div class="flex justify-between text-gray-400 mb-2">
            <span>Live (every 2 s)</span>
            <span :if={@camp_status}>clears since the boss: {@camp_status.clears}{if @camp_status.boss_up, do: " · boss is up"}</span>
          </div>
          <p :if={!@camp_status} class="text-gray-500">The zone's creatures aren't running (nobody is in {zone_name(@zones, @zone)}, or it is starting).</p>
          <table :if={@camp_status} class="w-full text-left">
            <thead class="text-gray-500"><tr><th>creature</th><th>level</th><th>state</th><th>health</th><th>back in</th></tr></thead>
            <tbody>
              <tr :for={m <- @camp_status.mobs} class="border-t border-gray-800">
                <td>{m.name}<span :if={m.boss} class="ml-1 text-red-300">boss</span></td>
                <td>{m.level}</td>
                <td>{m.state}{if m.target, do: " (fighting)"}</td>
                <td>{m.hp}/{m.max_hp}</td>
                <td>{cond do
                  m.respawn_in_s -> "#{m.respawn_in_s} s"
                  m.decays_in_s -> "corpse #{m.decays_in_s} s"
                  true -> ""
                end}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={!@camp_form} class="dark-glass rounded-xl p-6 lg:col-span-3 text-gray-400 space-y-2">
        <p>A managed camp puts its creatures on one spot with rules: <b class="text-gray-200">slots</b> of creatures picked at every respawn (random, in turn, or EverQuest placeholders with a <b class="text-gray-200">rare</b> on a timer), by day or by night, an optional <b class="text-gray-200">level band</b> and <b class="text-gray-200">elites</b>, <b class="text-gray-200">assist</b> (pull one, its friends come too), and a reward when the last one falls, calling a <b class="text-gray-200">boss</b> every few clears.</p>
        <p>New camps start at your character's last position in the zone. Generate decor puts its features (tents, palisade, campfire...) in as ordinary build pieces.</p>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------- loot

  defp loot(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-4 gap-4">
      <div class="dark-glass rounded-xl p-4 space-y-3">
        <.link patch={bpath("loot", "new")} class="block text-center bg-sky-700 hover:bg-sky-600 text-white px-3 py-1.5 rounded">New loot table</.link>
        <ul class="space-y-1 max-h-[65vh] overflow-auto">
          <li :for={{id, t} <- Loot.list()}>
            <.link patch={bpath("loot", id)} class={"block px-2 py-1 rounded " <> if(@loot_id == id, do: "bg-sky-900 text-white", else: "hover:bg-gray-800")}>{t[:name] || id} <span class="text-gray-500">{id}</span></.link>
          </li>
        </ul>
      </div>

      <div :if={@loot_form} class="dark-glass rounded-xl p-4 lg:col-span-3 space-y-4">
        <ul :if={@loot_errors != []} class="bg-red-950/60 border border-red-800 rounded p-2 text-red-200 list-disc list-inside">
          <li :for={e <- @loot_errors}>{e}</li>
        </ul>
        <form phx-submit="loot_save" class="space-y-3">
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
            <.inp label="name" name="t[name]" value={@loot_form["name"]} />
            <.inp label="picks (1 or 1-3)" name="t[rolls]" value={@loot_form["rolls"]} />
            <.inp label="weight of nothing" name="t[empty]" value={@loot_form["empty"]} />
            <.inp label="copper × level (0 or 4-10)" name="t[coins]" value={@loot_form["coins"]} />
          </div>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-2">
            <.area label="pool: item weight [qty] [levels]" name="t[pool]" value={@loot_form["pool"]} rows="10" />
            <.area label="always rolled: item chance [qty]" name="t[always]" value={@loot_form["always"]} rows="10" />
            <.area label="nested tables: table chance" name="t[tables]" value={@loot_form["tables"]} rows="10" />
          </div>
          <p class="text-gray-500">Each pick takes one line of the pool by weight (or nothing, by its weight); levels limit a line to creatures of those levels (rusty_dagger 10 1 1-8). Chances are 0.25 or 25%.</p>
          <div class="flex gap-2">
            <button class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-2 rounded">Save</button>
            <button :if={@loot_id != "new"} type="button" phx-click="loot_delete" data-confirm="Delete this loot table?" class="ml-auto bg-red-800 hover:bg-red-700 text-white px-4 py-2 rounded">Delete</button>
          </div>
        </form>
        <div :if={@loot_id != "new"} class="rounded bg-gray-900/60 p-3 space-y-2">
          <form phx-submit="loot_sim" class="flex gap-2 items-end">
            <.inp label="creature level" name="level" value={@loot_sim_level} />
            <.inp label="rolls" name="n" value="1000" />
            <button class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Simulate</button>
          </form>
          <.sim_table sim={@loot_sim} />
        </div>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------- experience

  defp xp(assigns) do
    specs = Enum.filter(Tuning.specs(), &(&1.key in @xp_keys))
    assigns = assign(assigns, specs: specs, values: Tuning.current(), table: Bestiary.xp_table())

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <div class="dark-glass rounded-xl p-4 space-y-3">
        <h2 class="text-lg text-white font-semibold">Pacing and worth</h2>
        <p class="text-gray-400">The same numbers as World tuning. A kill's experience is the level formula × experience multiplier × the creature's own (its type's ×, its rank's, an elite's, a camp clear's) × any event running.</p>
        <form phx-submit="xp_save" class="grid grid-cols-1 md:grid-cols-2 gap-2">
          <label :for={s <- @specs} title={s.desc}>{s.label}
            <input name={"x[#{s.key}]"} value={fmt(Map.get(@values, s.key, s[:default]))} type="number" step={s.step} min={s.min} max={s.max} class="w-full bg-gray-900 rounded px-2 py-1" />
          </label>
          <div class="md:col-span-2"><button class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-2 rounded">Save</button></div>
        </form>
        <p class="text-gray-500">Running now: {Enum.map_join(LiveEvents.active(), ", ", fn {_, e} -> e.name end) |> then(&if(&1 == "", do: "no events", else: &1))} (XP × {fmt(LiveEvents.mult(:xp))}, loot × {fmt(LiveEvents.mult(:loot))}, coins × {fmt(LiveEvents.mult(:coin))}).</p>
      </div>
      <div class="dark-glass rounded-xl p-4">
        <h2 class="text-lg text-white font-semibold mb-2">The curve (an even-con, normal creature)</h2>
        <div class="max-h-[70vh] overflow-auto">
          <table class="w-full text-left">
            <thead class="text-gray-500 sticky top-0 bg-gray-950"><tr><th>level</th><th>to next</th><th>a kill</th><th>kills</th><th>total</th></tr></thead>
            <tbody>
              <tr :for={r <- @table} class="border-t border-gray-800"><td>{r.level}</td><td>{r.to_next}</td><td>{r.kill_xp}</td><td>{r.kills}</td><td>{r.total}</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------- events

  defp events(assigns) do
    assigns = assign(assigns, list: LiveEvents.list(), now: DateTime.utc_now())

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="dark-glass rounded-xl p-4 space-y-3">
        <h2 class="text-lg text-white font-semibold">New event</h2>
        <ul :if={@event_errors != []} class="bg-red-950/60 border border-red-800 rounded p-2 text-red-200 list-disc list-inside">
          <li :for={e <- @event_errors}>{e}</li>
        </ul>
        <form phx-submit="event_save" class="space-y-2">
          <.inp label="name" name="e[name]" value="" />
          <div class="grid grid-cols-3 gap-2">
            <.inp label="XP ×" name="e[xp_mult]" value="2" />
            <.inp label="loot ×" name="e[loot_mult]" value="1" />
            <.inp label="coins ×" name="e[coin_mult]" value="1" />
          </div>
          <label>starts (UTC) <input type="datetime-local" name="e[starts_at]" class="w-full bg-gray-900 rounded px-2 py-1" /></label>
          <label>ends (UTC) <input type="datetime-local" name="e[ends_at]" class="w-full bg-gray-900 rounded px-2 py-1" /></label>
          <button class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-2 rounded">Schedule</button>
        </form>
        <p class="text-gray-500">Overlapping events multiply (capped at {fmt(LiveEvents.max_mult())}×). Times are UTC.</p>
      </div>
      <div class="dark-glass rounded-xl p-4 lg:col-span-2">
        <table class="w-full text-left">
          <thead class="text-gray-500"><tr><th>event</th><th>multiplies</th><th>from</th><th>to</th><th></th><th></th></tr></thead>
          <tbody>
            <tr :for={{id, e} <- @list} class="border-t border-gray-800">
              <td>{e.name} <span class={"ml-1 text-[10px] px-1.5 rounded " <> case LiveEvents.status(e, @now) do
                :running -> "bg-green-900 text-green-200"
                :upcoming -> "bg-sky-900 text-sky-200"
                :over -> "bg-gray-800 text-gray-500"
              end}>{LiveEvents.status(e, @now)}</span></td>
              <td>{event_summary(e)}</td>
              <td>{String.slice(e.starts_at || "", 0, 16)}</td>
              <td>{String.slice(e.ends_at || "", 0, 16)}</td>
              <td><button phx-click="event_announce" phx-value-id={id} class="bg-gray-700 hover:bg-gray-600 text-white px-2 py-1 rounded">Announce</button></td>
              <td><button phx-click="event_delete" phx-value-id={id} data-confirm="Remove this event?" class="bg-red-800 hover:bg-red-700 text-white px-2 py-1 rounded">Remove</button></td>
            </tr>
            <tr :if={@list == []}><td colspan="6" class="text-gray-500 py-2">No events yet.</td></tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------- bits

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :list, :string, default: nil

  defp inp(assigns) do
    ~H"""
    <label class="block">{@label}
      <input name={@name} value={@value} list={@list} class="w-full bg-gray-900 rounded px-2 py-1" autocomplete="off" />
    </label>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :rows, :string, default: "5"

  defp area(assigns) do
    ~H"""
    <label class="block">{@label}
      <textarea name={@name} rows={@rows} class="w-full bg-gray-900 rounded px-2 py-1 font-mono text-xs">{@value}</textarea>
    </label>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :checked, :boolean, default: false

  defp check(assigns) do
    ~H"""
    <label class="flex items-center gap-1">
      <input type="hidden" name={@name} value="false" />
      <input type="checkbox" name={@name} value="true" checked={@checked} /> {@label}
    </label>
    """
  end

  attr :sim, :any, default: nil

  defp sim_table(assigns) do
    ~H"""
    <div :if={@sim} class="space-y-1">
      <p class="text-gray-400">{@sim.n} rolls: copper {@sim.coins_min}-{@sim.coins_max} (average {@sim.coins_avg}); nothing at all {@sim.nothing_pct}%.</p>
      <div class="max-h-64 overflow-auto">
        <table class="w-full text-left">
          <thead class="text-gray-500"><tr><th>item</th><th>in</th><th>each</th></tr></thead>
          <tbody>
            <tr :for={r <- @sim.rows} class="border-t border-gray-800"><td>{r.name}</td><td>{r.pct}%</td><td>{r.per_kill}</td></tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
