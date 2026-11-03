defmodule BaconWorldWeb.Admin.DatabaseLive do
  @moduledoc """
  /admin/bacon_world/database - the game's database editor (2026-11-02, first pass).

    * **Players**: find a character, edit its level, HP, mana, money, zone and position, and its
      inventory (remove a stack, give an item). A character in the world keeps playing from what
      its session holds, so edits to someone online can be overwritten: they apply on next login.
    * **Objects**, **NPCs**, **Monsters**: what is placed in a zone (`BaconWorld.Building`
      placements: objects, `npc:` NPCs, `mob:` creature spawns), with position, turn, size and the
      NPC's name or the spawn's count and radius; delete.
    * **Monster types**, **Merchants**: their definitions (`BaconWorld.Defs`) as JSON, edited, added,
      deleted, live at once.
    * **Items**: the item catalogue (`bacon_world_item_defs`, `BaconWorld.Items`): edit any field, add, delete
      (not while a character owns one).
  """
  use Bacon8Web, :live_view
  import Ecto.Query

  alias Bacon8.Games.GameCharacter
  alias Bacon8.GamesRepo
  alias Bacon8Web.Components.AdminSidebar
  alias BaconWorld.{Building, Inventory, Items, Placement, World, Zone}

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @tabs [{"players", "Players"}, {"objects", "Objects"}, {"npcs", "Placed NPCs"}, {"monsters", "Spawns"}, {"items", "Items"},
         {"monster_types", "Monster types"}, {"merchants", "Merchants"}]
  # tab => BaconWorld.Defs kind
  @def_tabs %{"monster_types" => "monster", "merchants" => "merchant"}

  @impl true
  def mount(_params, _session, socket) do
    zones = GamesRepo.all(from z in Zone, order_by: [asc_nulls_first: z.number], select: %{slug: z.slug, name: z.name, number: z.number})

    {:ok,
     assign(socket,
       page_title: "Admin - Bacon World - Database",
       tabs: @tabs,
       tab: "players",
       q: "",
       zones: zones,
       zone: "lobby",
       characters: [],
       character: nil,
       inventory: nil,
       rows: [],
       edit: nil,
       item_q: "",
       item_edit: nil,
       it: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in Enum.map(@tabs, &elem(&1, 0)), do: params["tab"], else: "players"
    socket = assign(socket, tab: tab, zone: params["zone"] || socket.assigns.zone, edit: nil)

    socket =
      case tab do
        "players" -> socket |> search(socket.assigns.q) |> open_character(params["ch"])
        t when t in ["objects", "npcs", "monsters"] -> load_rows(socket)
        _ -> socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------- players

  defp search(socket, q) do
    {:ok, game_id} = World.game_id()

    query =
      from c in GameCharacter,
        where: c.game_id == ^game_id,
        order_by: [desc_nulls_last: c.last_played_at],
        limit: 50

    query = if q != "", do: from(c in query, where: ilike(c.name, ^"%#{q}%")), else: query
    assign(socket, q: q, characters: GamesRepo.all(query))
  end

  defp open_character(socket, nil), do: assign(socket, character: nil, inventory: nil)

  defp open_character(socket, id) do
    case GamesRepo.one(World.by_id_query(id)) do
      nil -> assign(socket, character: nil, inventory: nil)
      c -> assign(socket, character: c, inventory: Inventory.payload(c.id))
    end
  rescue
    _ -> assign(socket, character: nil, inventory: nil)
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket), do: {:noreply, search(socket, String.trim(q))}

  def handle_event("save_character", %{"c" => p}, socket) do
    c = socket.assigns.character
    q = World.by_id_query(c.id)

    stats =
      for k <- ~w(level hp max_hp mp max_mp xp), v = int(p[k]), v != nil, into: %{}, do: {k, v}

    World.merge_stats(q, stats)

    pos = c.settings["position"] || %{}

    pos =
      for k <- ~w(x y z), v = float(p[k]), v != nil, reduce: pos do
        acc -> Map.put(acc, k, v)
      end

    World.merge_settings(q, %{"position" => pos, "zone_slug" => p["zone_slug"] || c.settings["zone_slug"] || "lobby"})

    case int(p["coins"]) do
      nil -> :ok
      want -> Inventory.add_coins(c.id, want - Inventory.coins(c.id))
    end

    {:noreply, socket |> open_character(c.id) |> put_flash(:info, "#{c.name} saved (applies on their next login if they're in the world now).")}
  end

  def handle_event("remove_item", %{"slot" => slot}, socket) do
    c = socket.assigns.character
    Inventory.destroy(c.id, slot)
    {:noreply, open_character(socket, c.id)}
  end

  def handle_event("give_item", %{"item" => id, "qty" => qty}, socket) do
    c = socket.assigns.character

    msg =
      case {Items.get(id), int(qty) || 1} do
        {nil, _} -> {:error, "No item #{id}."}
        {item, n} -> case Inventory.add(c.id, item.id, max(n, 1)) do
          {:ok, _} -> {:info, "Gave #{n} × #{item.name}."}
          {:error, r} -> {:error, "Couldn't: #{inspect(r)}."}
        end
      end

    {:noreply, socket |> open_character(c.id) |> put_flash(elem(msg, 0), elem(msg, 1))}
  end

  # ---------------------------------------------------------------- placements

  def handle_event("edit", %{"id" => id}, socket), do: {:noreply, assign(socket, edit: id)}
  def handle_event("cancel", _, socket), do: {:noreply, assign(socket, edit: nil)}

  def handle_event("save_placement", %{"p" => p}, socket) do
    zone = socket.assigns.zone
    BaconWorld.Terrain.use_zone(zone)
    data = Map.take(p, ~w(name count radius)) |> Map.reject(fn {_, v} -> v in [nil, ""] end)
    attrs = Map.take(p, ~w(x y z scale)) |> Map.put("rot", (float(p["rot_deg"]) || 0.0) * :math.pi() / 180) |> Map.put("data", data)

    case Building.move(socket.assigns.current_user, zone, p["id"], attrs) do
      {:ok, _} -> {:noreply, socket |> assign(edit: nil) |> load_rows() |> put_flash(:info, "Saved.")}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("delete_placement", %{"id" => id}, socket) do
    zone = socket.assigns.zone
    BaconWorld.Terrain.use_zone(zone)

    case Building.delete(socket.assigns.current_user, zone, id) do
      {:ok, _} -> {:noreply, socket |> load_rows() |> put_flash(:info, "Deleted.")}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("save_def", %{"def_id" => id, "json" => json} = p, socket) do
    kind = Map.fetch!(@def_tabs, socket.assigns.tab)
    id = String.trim(p["new_id"] || id)

    with true <- String.match?(id, ~r/^[a-z0-9_]{2,60}$/) || {:error, "An id is 2-60 lowercase letters, digits and underscores."},
         {:ok, data} when is_map(data) <- Jason.decode(json) |> then(fn {:ok, d} -> {:ok, d}; _ -> {:error, "That isn't valid JSON."} end) do
      BaconWorld.Defs.put(kind, id, BaconWorld.Defs.decode(data))
      {:noreply, socket |> assign(edit: nil) |> put_flash(:info, "#{id} saved; the game uses it at once.")}
    else
      {:ok, _} -> {:noreply, put_flash(socket, :error, "The definition must be a JSON object.")}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("delete_def", %{"id" => id}, socket) do
    BaconWorld.Defs.delete(Map.fetch!(@def_tabs, socket.assigns.tab), id)
    {:noreply, socket |> assign(edit: nil) |> put_flash(:info, "#{id} deleted.")}
  end

  def handle_event("item_search", %{"q" => q}, socket), do: {:noreply, assign(socket, item_q: String.trim(q))}

  def handle_event("edit_item", %{"id" => id}, socket) do
    it = if id == "new", do: Items.item(%{"kind" => "junk"}), else: Items.get(id)
    {:noreply, assign(socket, item_edit: it && id, it: it)}
  end
  def handle_event("cancel_item", _, socket), do: {:noreply, assign(socket, item_edit: nil)}

  def handle_event("save_item", %{"i" => p}, socket) do
    data =
      %{
        "id" => String.trim(p["id"] || ""),
        "name" => p["name"],
        "kind" => p["kind"],
        "slots" => (p["slots"] || "") |> String.split(~r/[\s,]+/, trim: true),
        "ranged" => p["ranged"] == "true"
      }
      |> Map.merge(for(k <- ~w(hands dmg dly ac stack value gems), v = int(p[k]), v != nil, into: %{}, do: {k, v}))
      |> Map.merge(for(k <- ~w(reach run_speed), v = float(p[k]), v != nil, into: %{}, do: {k, v}))
      |> Map.merge(for(k <- ~w(set skill model icon icon_url power jewel group), v = blank(p[k]), into: %{}, do: {k, v}))

    with {:ok, colors} <- json(p["colors"]),
         {:ok, wear} <- json(p["wear"]),
         {:ok, item} <- Items.save_def(Map.merge(data, %{"colors" => colors, "wear" => wear})) do
      {:noreply, socket |> assign(item_edit: nil) |> put_flash(:info, "#{item.name} saved.")}
    else
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    case Items.delete_def(id) do
      :ok -> {:noreply, socket |> assign(item_edit: nil) |> put_flash(:info, "#{id} deleted.")}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  defp blank(nil), do: nil
  defp blank(v), do: if(String.trim(v) == "", do: nil, else: String.trim(v))

  defp json(nil), do: {:ok, nil}

  defp json(v) do
    case String.trim(v) do
      "" -> {:ok, nil}
      t -> case Jason.decode(t) do
        {:ok, m} when is_map(m) -> {:ok, m}
        _ -> {:error, "Colours and wear must be JSON objects (or empty)."}
      end
    end
  end

  defp load_rows(socket) do
    zone = socket.assigns.zone
    base = from p in Placement, where: p.zone == ^zone, order_by: p.asset, limit: 500

    query =
      case socket.assigns.tab do
        "npcs" -> from p in base, where: like(p.asset, "npc:%")
        "monsters" -> from p in base, where: like(p.asset, "mob:%")
        _ -> from p in base, where: not like(p.asset, "npc:%") and not like(p.asset, "mob:%")
      end

    assign(socket, rows: GamesRepo.all(query))
  end

  defp def_tabs, do: @def_tabs

  defp int(nil), do: nil
  defp int(""), do: nil
  defp int(v) when is_integer(v), do: v
  defp int(v), do: (case Integer.parse(to_string(v)) do {n, _} -> n; _ -> nil end)

  defp float(nil), do: nil
  defp float(""), do: nil
  defp float(v), do: (case Float.parse(to_string(v)) do {n, _} -> n; _ -> nil end)

  # ---------------------------------------------------------------- page

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/bacon_world">
      <div class="max-w-7xl mx-auto space-y-4 text-sm text-gray-300">
        <div class="dark-glass p-6 rounded-xl flex flex-wrap items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-white">Database</h1>
            <p class="mt-1 text-gray-400">Players, what's placed in each zone, and the item catalogue.</p>
          </div>
          <div class="flex flex-wrap gap-1">
            <%= for {id, label} <- @tabs do %>
              <.link patch={"/admin/bacon_world/database?tab=#{id}&zone=#{@zone}"} class={"px-3 py-1.5 rounded " <> if(@tab == id, do: "bg-sky-700 text-white", else: "bg-gray-800 hover:bg-gray-700")}><%= label %></.link>
            <% end %>
            <.link navigate="/admin/bacon_world" class="px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-white">Back</.link>
          </div>
        </div>

        <%= if @tab == "players" do %>
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div class="dark-glass rounded-xl p-4">
              <form phx-change="search" phx-submit="search"><input name="q" value={@q} placeholder="Find a character" class="w-full bg-gray-900 rounded px-2 py-1" phx-debounce="300" /></form>
              <ul class="mt-3 space-y-1 max-h-[60vh] overflow-auto">
                <%= for c <- @characters do %>
                  <li>
                    <.link patch={"/admin/bacon_world/database?tab=players&ch=#{c.id}"} class={"block px-2 py-1 rounded " <> if(@character && @character.id == c.id, do: "bg-sky-900 text-white", else: "hover:bg-gray-800")}>
                      <%= c.name %> <span class="text-gray-500">lvl <%= c.stats["level"] || 1 %> · <%= c.settings["zone_slug"] || "lobby" %></span>
                    </.link>
                  </li>
                <% end %>
              </ul>
            </div>

            <div :if={@character} class="dark-glass rounded-xl p-4 lg:col-span-2 space-y-4">
              <h2 class="text-xl text-white font-semibold"><%= @character.name %></h2>
              <.form for={%{}} as={:c} phx-submit="save_character" class="grid grid-cols-2 md:grid-cols-4 gap-2">
                <%= for k <- ~w(level hp max_hp mp max_mp xp) do %>
                  <label><%= k %> <input name={"c[#{k}]"} value={@character.stats[k]} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <% end %>
                <label>copper <input name="c[coins]" value={@inventory && @inventory.coins} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <label>zone
                  <select name="c[zone_slug]" class="w-full bg-gray-900 rounded px-2 py-1">
                    <%= for z <- @zones do %><option value={z.slug} selected={z.slug == (@character.settings["zone_slug"] || "lobby")}><%= z.number %> <%= z.name %></option><% end %>
                  </select>
                </label>
                <%= for k <- ~w(x y z) do %>
                  <label><%= k %> <input name={"c[#{k}]"} value={get_in(@character.settings, ["position", k])} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <% end %>
                <div class="col-span-full"><button class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-1.5 rounded">Save</button></div>
              </.form>

              <div :if={@inventory}>
                <h3 class="text-white font-semibold mb-2">Inventory</h3>
                <table class="w-full text-xs">
                  <tr class="text-gray-500 text-left"><th>slot</th><th>item</th><th>qty</th><th></th></tr>
                  <%= for i <- @inventory.items do %>
                    <tr class="border-t border-gray-800">
                      <td><%= i.slot %></td><td><%= (Items.get(i.item_id) || %{name: i.item_id}).name %> <span class="text-gray-500"><%= i.item_id %></span></td><td><%= i[:quantity] %></td>
                      <td class="text-right"><button phx-click="remove_item" phx-value-slot={i.slot} data-confirm="Remove this stack?" class="text-red-400 hover:text-red-300">remove</button></td>
                    </tr>
                  <% end %>
                </table>
                <form phx-submit="give_item" class="flex gap-2 mt-2">
                  <input name="item" placeholder="item id (Items tab)" class="flex-1 bg-gray-900 rounded px-2 py-1" />
                  <input name="qty" value="1" class="w-16 bg-gray-900 rounded px-2 py-1" />
                  <button class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1 rounded">Give</button>
                </form>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @tab in ~w(objects npcs monsters) do %>
          <div class="dark-glass rounded-xl p-4 space-y-3">
            <div class="flex gap-2 items-center">
              <span>Zone</span>
              <select onchange={"window.location='/admin/bacon_world/database?tab=#{@tab}&zone='+this.value"} class="bg-gray-900 rounded px-2 py-1">
                <%= for z <- @zones do %><option value={z.slug} selected={z.slug == @zone}><%= z.number %> <%= z.name %></option><% end %>
              </select>
            </div>
            <p class="text-gray-500"><%= length(@rows) %> shown (at most 500).</p>
            <table class="w-full text-xs">
              <tr class="text-gray-500 text-left"><th>asset</th><th>x</th><th>y</th><th>z</th><th>turn°</th><th>size</th><th>data</th><th></th></tr>
              <%= for p <- @rows do %>
                <%= if @edit == p.id do %>
                  <tr class="border-t border-gray-800">
                    <td colspan="8">
                      <.form for={%{}} as={:p} phx-submit="save_placement" class="flex flex-wrap gap-2 items-end py-2">
                        <input type="hidden" name="p[id]" value={p.id} />
                        <span class="text-white"><%= p.asset %></span>
                        <%= for {k, v} <- [{"x", p.x}, {"y", p.y}, {"z", p.z}, {"rot_deg", Float.round((p.rot || 0.0) * 180 / :math.pi(), 1)}, {"scale", p.scale}] do %>
                          <label><%= k %> <input name={"p[#{k}]"} value={v} class="w-20 bg-gray-900 rounded px-1" /></label>
                        <% end %>
                        <label :if={String.starts_with?(p.asset, "npc:")}>name <input name="p[name]" value={p.data["name"]} class="w-32 bg-gray-900 rounded px-1" /></label>
                        <label :if={String.starts_with?(p.asset, "mob:")}>count <input name="p[count]" value={p.data["count"]} class="w-14 bg-gray-900 rounded px-1" /></label>
                        <label :if={String.starts_with?(p.asset, "mob:")}>radius <input name="p[radius]" value={p.data["radius"]} class="w-14 bg-gray-900 rounded px-1" /></label>
                        <button class="bg-sky-700 text-white px-2 py-1 rounded">Save</button>
                        <button type="button" phx-click="cancel" class="bg-gray-700 text-white px-2 py-1 rounded">Cancel</button>
                      </.form>
                    </td>
                  </tr>
                <% else %>
                  <tr class="border-t border-gray-800">
                    <td><%= p.asset %></td><td><%= Float.round(p.x * 1.0, 1) %></td><td><%= Float.round((p.y || 0.0) * 1.0, 1) %></td><td><%= Float.round(p.z * 1.0, 1) %></td>
                    <td><%= Float.round((p.rot || 0.0) * 180 / :math.pi(), 0) %></td><td><%= p.scale %></td>
                    <td class="text-gray-500"><%= p.data |> Map.drop(["origin"]) |> Jason.encode!() %></td>
                    <td class="text-right whitespace-nowrap">
                      <button phx-click="edit" phx-value-id={p.id} class="text-sky-400 hover:text-sky-300">edit</button>
                      <button phx-click="delete_placement" phx-value-id={p.id} data-confirm="Delete this?" class="ml-2 text-red-400 hover:text-red-300">delete</button>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </table>
          </div>
        <% end %>

        <%= if Map.has_key?(def_tabs(), @tab) do %>
          <div class="dark-glass rounded-xl p-4 space-y-3">
            <p class="text-gray-500">
              <%= if @tab == "monster_types", do: "Creature types (BaconWorld.Mobs.Spawns): name, levels, hp {base, per level}, dmg, speeds, weapons/offhand [[item, weight]], loot [[item, chance, qty range]], coins. ", else: "The merchants and NPCs in code's place (BaconWorld.Merchants): position (zone metres), look, gear, sells. " %>
              JSON; <code><%= ~s({"$range": [a, b]}) %></code> is a range, <code><%= ~s({"$tuple": [...]}) %></code> a tuple, <code><%= ~s({"$s": {...}}) %></code> a map with text keys. Saved definitions are live at once.
            </p>
            <button phx-click="edit" phx-value-id="__new" class="bg-emerald-700 hover:bg-emerald-600 text-white px-3 py-1 rounded">New</button>
            <%= for {id, term} <- BaconWorld.Defs.list(def_tabs()[@tab]) ++ if(@edit == "__new", do: [{"__new", %{name: "new"}}], else: []) do %>
              <div class="border-t border-gray-800 pt-2">
                <div class="flex items-center gap-2">
                  <span class="text-white"><%= if id == "__new", do: "new", else: id %></span>
                  <span class="text-gray-500"><%= term[:name] %></span>
                  <button :if={@edit != id} phx-click="edit" phx-value-id={id} class="ml-auto text-sky-400 hover:text-sky-300">edit</button>
                </div>
                <form :if={@edit == id} phx-submit="save_def" class="space-y-2 mt-2">
                  <input type="hidden" name="def_id" value={id} />
                  <input :if={id == "__new"} name="new_id" placeholder="id" class="bg-gray-900 rounded px-2 py-1" />
                  <textarea name="json" rows="18" class="w-full bg-gray-900 rounded px-2 py-1 font-mono text-xs"><%= Jason.encode!(BaconWorld.Defs.encode(term), pretty: true) %></textarea>
                  <div class="flex gap-2">
                    <button class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-1.5 rounded">Save</button>
                    <button type="button" phx-click="cancel" class="bg-gray-700 text-white px-3 py-1.5 rounded">Cancel</button>
                    <button :if={id != "__new"} type="button" phx-click="delete_def" phx-value-id={id} data-confirm="Delete this definition? Anything that uses it will stop working." class="ml-auto bg-red-800 hover:bg-red-700 text-white px-3 py-1.5 rounded">Delete</button>
                  </div>
                </form>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @tab == "items" do %>
          <div class="dark-glass rounded-xl p-4 space-y-3">
            <div class="flex gap-2">
              <form phx-change="item_search" class="flex-1"><input name="q" value={@item_q} placeholder="Filter by id or name" class="w-full bg-gray-900 rounded px-2 py-1" phx-debounce="200" /></form>
              <button phx-click="edit_item" phx-value-id="new" class="bg-emerald-700 hover:bg-emerald-600 text-white px-3 py-1 rounded">New item</button>
            </div>
            <p class="text-gray-500">The item catalogue (bacon_world_item_defs). Changes apply at once on the server; players see new looks and tooltips on their next page load.</p>

            <%= if @item_edit do %>
              <.form :if={@it} for={%{}} as={:i} phx-submit="save_item" class="grid grid-cols-2 md:grid-cols-4 gap-2 p-3 rounded bg-gray-900/60">
                <label>id <input name="i[id]" value={@it.id} readonly={@item_edit != "new"} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <label class="md:col-span-2">name <input name="i[name]" value={@it.name} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <label>kind
                  <select name="i[kind]" class="w-full bg-gray-900 rounded px-2 py-1">
                    <%= for k <- ~w(weapon shield light armor junk) do %><option selected={@it.kind == k}><%= k %></option><% end %>
                  </select>
                </label>
                <label class="md:col-span-2">slots (comma separated) <input name="i[slots]" value={Enum.join(@it.slots || [], ", ")} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <%= for k <- ~w(hands dmg dly reach ac stack value gems run_speed)a do %>
                  <label><%= k %> <input name={"i[#{k}]"} value={Map.get(@it, k)} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <% end %>
                <%= for k <- ~w(set skill model icon icon_url power jewel group)a do %>
                  <label><%= k %> <input name={"i[#{k}]"} value={Map.get(@it, k)} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <% end %>
                <label class="flex items-center gap-2"><input type="hidden" name="i[ranged]" value="false" /><input type="checkbox" name="i[ranged]" value="true" checked={@it.ranged == true} /> ranged (bow)</label>
                <label class="col-span-full">colours (JSON) <textarea name="i[colors]" rows="2" class="w-full bg-gray-900 rounded px-2 py-1 font-mono text-xs"><%= @it.colors && Jason.encode!(@it.colors) %></textarea></label>
                <label class="col-span-full">wear (JSON) <textarea name="i[wear]" rows="2" class="w-full bg-gray-900 rounded px-2 py-1 font-mono text-xs"><%= @it.wear && Jason.encode!(@it.wear) %></textarea></label>
                <div class="col-span-full flex gap-2">
                  <button class="bg-sky-700 hover:bg-sky-600 text-white px-4 py-1.5 rounded">Save</button>
                  <button type="button" phx-click="cancel_item" class="bg-gray-700 text-white px-3 py-1.5 rounded">Cancel</button>
                  <button :if={@item_edit != "new"} type="button" phx-click="delete_item" phx-value-id={@it.id} data-confirm="Delete this item's definition?" class="ml-auto bg-red-800 hover:bg-red-700 text-white px-3 py-1.5 rounded">Delete</button>
                </div>
              </.form>
            <% end %>

            <table class="w-full text-xs">
              <tr class="text-gray-500 text-left"><th>id</th><th>name</th><th>kind</th><th>slots</th><th>dmg/dly</th><th>ac</th><th>value</th><th>gems</th><th></th></tr>
              <%= for i <- Items.all() |> Enum.filter(&(@item_q == "" or String.contains?(String.downcase(&1.id <> " " <> &1.name), String.downcase(@item_q)))) |> Enum.take(400) do %>
                <tr class="border-t border-gray-800">
                  <td><%= i.id %></td><td><%= i.name %></td><td><%= i.kind %></td><td><%= Enum.join(i[:slots] || [], ", ") %></td>
                  <td><%= if (i[:dmg] || 0) > 0, do: "#{i[:dmg]}/#{i[:dly]}" %></td><td><%= i[:ac] %></td><td><%= i[:value] %></td><td><%= i[:gems] %></td>
                  <td class="text-right"><button phx-click="edit_item" phx-value-id={i.id} class="text-sky-400 hover:text-sky-300">edit</button></td>
                </tr>
              <% end %>
            </table>
          </div>
        <% end %>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
