defmodule BaconWorldWeb.Admin.WorldLive do
  @moduledoc """
  /admin/bacon_world/world - the world generator and zone editor (2026-11-02).

    * **The world map**: every zone on its grid cell around Crater Lake (the lobby, 0,0), with its
      shaded heightmap; scroll it, click a zone to open it.
    * **Plan / generate**: makes the 200 zone rows (`BaconWorld.WorldGen.plan!/1`) and generates their
      terrain in the background, one zone at a time (progress shows as it goes).
    * **A zone**: its heightmap with what stands on it (binding stones, NPCs, creature spawns, objects;
      hover a node for its details), export for World Creator (16-bit PNG or RAW) and import back
      (`BaconWorld.WorldEditor`): the new ground goes live at once, with the zone's nodes re-seated on
      it or cleared.
  """
  use Bacon8Web, :live_view

  alias Bacon8Web.Components.AdminSidebar
  alias BaconWorld.{WorldEditor, WorldGen}

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @cell 76
  @kinds ~w(binding npc mob object)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, WorldGen.topic())

    {:ok,
     socket
     |> assign(page_title: "Admin - Bacon World - World", busy: nil, report: nil, kinds: @kinds, generating: WorldGen.running?(), progress: %{})
     |> load_grid()
     |> assign(zone: nil, nodes: [], frame: nil, preview: nil, form: import_form(nil))
     # :any: ".r16" has no MIME type LiveView knows (it refused the page); the extension is checked on import
     |> allow_upload(:heightmap, accept: :any, max_entries: 1, max_file_size: 80_000_000)}
  end

  @impl true
  def handle_params(%{"zone" => n}, _uri, socket) do
    case Integer.parse(n) do
      {num, _} -> {:noreply, open_zone(socket, num)}
      _ -> {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, assign(socket, zone: nil)}

  defp load_grid(socket) do
    zones = WorldEditor.grid()
    planned = MapSet.new(zones, & &1.number)
    missing = Enum.count(WorldGen.layout(200), fn {n, _, _} -> not MapSet.member?(planned, n) end)
    counts = Enum.frequencies_by(zones, & &1.status)
    {xs, zs} = if zones == [], do: {[0], [0]}, else: {Enum.map(zones, & &1.grid_x), Enum.map(zones, & &1.grid_z)}
    min_x = Enum.min(xs ++ [-7])
    min_z = Enum.min(zs ++ [-7])
    assign(socket, zones: zones, counts: counts, missing: missing, min_x: min_x, min_z: min_z,
      cols: Enum.max(xs ++ [7]) - min_x + 1, rows: Enum.max(zs ++ [7]) - min_z + 1)
  end

  defp open_zone(socket, num) do
    case WorldEditor.get(num) do
      nil ->
        put_flash(socket, :error, "No zone #{num}.")

      zone ->
        assign(socket,
          zone: zone,
          nodes: WorldEditor.nodes(zone),
          frame: WorldEditor.frame(zone),
          preview: WorldEditor.preview_url(zone),
          report: nil,
          form: import_form(WorldEditor.frame(zone))
        )
    end
  end

  defp import_form(frame) do
    to_form(%{"min" => frame && frame.lo, "max" => frame && frame.hi, "endian" => "big", "nodes" => "keep", "match_edges" => "true"}, as: :imp)
  end

  # ---------------------------------------------------------------- events

  @impl true
  def handle_event("plan", _params, socket) do
    n = WorldGen.plan!(200)
    {:noreply, socket |> load_grid() |> put_flash(:info, "#{n} zones planned. Generate them to give them ground.")}
  end

  def handle_event("generate_all", _params, socket) do
    case WorldGen.generate_all() do
      {:ok, _} -> {:noreply, socket |> assign(generating: true) |> put_flash(:info, "Generating, one zone at a time. You can leave this page; it carries on.")}
      {:running, _} -> {:noreply, put_flash(socket, :info, "Already generating.")}
    end
  end

  def handle_event("regenerate", %{"nodes" => nodes}, socket) do
    zone = socket.assigns.zone
    lv = self()
    Task.start(fn -> send(lv, {:replaced, WorldEditor.regenerate(zone, nodes: node_opt(nodes))}) end)
    {:noreply, assign(socket, busy: "Generating #{zone.name}...")}
  end

  # a stalled zone (left "generating" by a run that stopped), or a planned one: generate it now
  def handle_event("generate_one", _params, socket) do
    case WorldGen.generate_one(socket.assigns.zone) do
      :ok -> {:noreply, socket |> assign(progress: Map.put(socket.assigns.progress, socket.assigns.zone.number, %{stage: "starting", pct: 0})) |> put_flash(:info, "Generating #{socket.assigns.zone.name}.")}
      {:error, :busy} -> {:noreply, put_flash(socket, :info, "It's already being generated.")}
    end
  end

  # the zone's name (owner, 2026-11-02: the generated names are a start; the admin names zones)
  def handle_event("rename", %{"name" => name} = p, socket) do
    zone = socket.assigns.zone
    name = String.trim(name)

    if name == "" or String.length(name) > 60 do
      {:noreply, put_flash(socket, :error, "A zone's name is 1 to 60 characters.")}
    else
      attrs = %{name: name, description: String.trim(p["description"] || zone.description || "")}

      case zone |> BaconWorld.Zone.changeset(attrs) |> Bacon8.GamesRepo.update() do
        {:ok, z} -> {:noreply, socket |> assign(zone: z) |> load_grid() |> put_flash(:info, "Zone #{z.number} is now #{z.name}.")}
        {:error, _} -> {:noreply, put_flash(socket, :error, "That name couldn't be saved.")}
      end
    end
  end

  def handle_event("toggle_kind", %{"kind" => k}, socket) do
    kinds = if k in socket.assigns.kinds, do: List.delete(socket.assigns.kinds, k), else: [k | socket.assigns.kinds]
    {:noreply, assign(socket, kinds: kinds)}
  end

  def handle_event("validate_import", %{"imp" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :imp))}
  end

  def handle_event("import", %{"imp" => params}, socket) do
    zone = socket.assigns.zone

    with {min, _} <- Float.parse(to_string(params["min"])),
         {max, _} <- Float.parse(to_string(params["max"])),
         true <- max > min do
      [bin] =
        consume_uploaded_entries(socket, :heightmap, fn %{path: path}, entry ->
          ext = entry.client_name |> Path.extname() |> String.downcase()
          {:ok, if(ext in ~w(.png .r16 .raw), do: File.read!(path), else: {:bad, ext})}
        end) ++ [nil]
        |> Enum.take(1)

      bin = if match?({:bad, _}, bin), do: :bad_type, else: bin

      cond do
        bin == :bad_type ->
          {:noreply, put_flash(socket, :error, "A heightmap is a .png, .r16 or .raw file.")}

        bin ->
        opts = [min: min, max: max, endian: if(params["endian"] == "little", do: :little, else: :big), nodes: node_opt(params["nodes"]), match_edges: params["match_edges"] == "true"]
        lv = self()
        Task.start(fn -> send(lv, {:replaced, WorldEditor.import_heightmap(zone, bin, opts)}) end)
        {:noreply, assign(socket, busy: "Importing into #{zone.name}...", form: to_form(params, as: :imp))}

        true ->
          {:noreply, put_flash(socket, :error, "Choose a heightmap file first.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Min and max must be numbers, max above min (metres, World Creator's readout).")}
    end
  end

  defp node_opt("clear"), do: :clear
  defp node_opt(_), do: :keep

  # ---------------------------------------------------------------- messages

  @impl true
  def handle_info({:worldgen, %{done: true}}, socket), do: {:noreply, socket |> assign(generating: false) |> load_grid()}

  def handle_info({:worldgen, %{zone: n, status: s}}, socket) do
    socket = socket |> assign(generating: WorldGen.running?(), progress: if(s == "generating", do: socket.assigns.progress, else: Map.delete(socket.assigns.progress, n))) |> load_grid()
    # the open zone: its new status, and when it's done its new ground
    cond do
      socket.assigns.zone && socket.assigns.zone.number == n and s == "ready" -> {:noreply, open_zone(socket, n)}
      socket.assigns.zone && socket.assigns.zone.number == n -> {:noreply, assign(socket, zone: WorldEditor.get(n))}
      true -> {:noreply, socket}
    end
  end

  def handle_info({:worldgen_progress, n, stage, pct}, socket) do
    {:noreply, assign(socket, progress: Map.put(socket.assigns.progress, n, %{stage: stage, pct: pct}))}
  end

  def handle_info({:replaced, {:ok, report}}, socket) do
    zone = WorldEditor.get(socket.assigns.zone.number)
    msg = "New ground is live (#{report.terrain}). Nodes #{report.nodes}" <> flagged_note(report)
    {:noreply, socket |> assign(busy: nil) |> load_grid() |> open_zone(zone.number) |> assign(report: report) |> put_flash(:info, msg)}
  end

  def handle_info({:replaced, {:error, msg}}, socket) do
    {:noreply, socket |> assign(busy: nil) |> put_flash(:error, msg)}
  end

  defp flagged_note(%{flagged: [_ | _] = f}), do: "; #{length(f)} need a look (listed below)."
  defp flagged_note(_), do: "."

  # ---------------------------------------------------------------- page

  @impl true
  def render(assigns) do
    assigns = assign(assigns, cell: @cell)

    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/bacon_world">
      <div class="max-w-7xl mx-auto space-y-6">
        <div class="dark-glass p-6 rounded-xl flex flex-wrap items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-white">World</h1>
            <p class="mt-1 text-sm text-gray-400">
              Zones around Crater Lake, 4096 m each. <%= length(@zones) %> on the grid
              (<%= for {s, n} <- @counts do %><span class="mr-2"><%= n %> <%= s %></span><% end %>).
            </p>
            <p :for={{n, p} <- @progress} class="mt-1 text-sm text-emerald-300">
              Zone <%= n %>: <%= p.stage %>, <%= p.pct %>%
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <button :if={@missing > 0} phx-click="plan" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium">
              Plan <%= @missing %> zones
            </button>
            <button phx-click="generate_all" disabled={@generating} class="bg-emerald-700 hover:bg-emerald-600 disabled:opacity-50 text-white px-4 py-2 rounded-md text-sm font-medium">
              <%= if @generating, do: "Generating...", else: "Generate planned zones" %>
            </button>
            <.link navigate="/admin/bacon_world" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium">Back</.link>
          </div>
        </div>

        <div class="dark-glass rounded-xl p-3">
          <div class="overflow-auto" style="max-height: 70vh">
            <div class="relative" style={"width: #{@cols * @cell}px; height: #{@rows * @cell}px"}>
              <%= for z <- @zones do %>
                <.link
                  patch={"/admin/bacon_world/world?zone=#{z.number}"}
                  class={"absolute block border text-[10px] leading-tight overflow-hidden " <>
                    if(@zone && @zone.number == z.number, do: "border-yellow-300 ring-2 ring-yellow-300 z-10", else: "border-gray-800 hover:border-sky-400")}
                  style={"left: #{(z.grid_x - @min_x) * @cell}px; top: #{(z.grid_z - @min_z) * @cell}px; width: #{@cell}px; height: #{@cell}px; background: #{tile_bg(z)}"}
                  title={"#{z.name} · #{z.status} · grid #{z.grid_x}, #{z.grid_z}"}
                >
                  <img :if={z.status == "ready" and z.terrain} src={"/models/World/Zones/#{z.terrain}_preview.png?v=#{z.terrain_version}"} class="absolute inset-0 w-full h-full object-cover" loading="lazy" onerror="this.style.display='none'" />
                  <span class="absolute left-0 top-0 px-1 bg-black/60 text-white"><%= z.number %></span>
                </.link>
              <% end %>
            </div>
          </div>
        </div>

        <div :if={@zone} class="dark-glass rounded-xl p-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div class="lg:col-span-2">
            <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
              <h2 class="text-xl font-semibold text-white"><%= @zone.name %> <span class="text-sm text-gray-400">zone <%= @zone.number %> · grid <%= @zone.grid_x %>, <%= @zone.grid_z %> · <%= @zone.status %></span></h2>
              <div class="flex gap-1 text-xs">
                <%= for k <- ~w(binding npc mob object) do %>
                  <button phx-click="toggle_kind" phx-value-kind={k} class={"px-2 py-1 rounded " <> if(k in @kinds, do: "bg-sky-800 text-white", else: "bg-gray-800 text-gray-500")}>
                    <%= kind_label(k) %> (<%= Enum.count(@nodes, &(&1.kind == k)) %>)
                  </button>
                <% end %>
              </div>
            </div>
            <div
              :if={@frame && @preview}
              id={"zone-map-#{@zone.number}"}
              phx-hook="BaconWorldZoneMap"
              data-map={Jason.encode!(%{image: @preview, detail: "/admin/bacon_world/world/detail/#{@zone.number}.png?v=#{@zone.terrain_version}", size_m: @frame.size_m, x0: @frame.x0, z0: @frame.z0})}
              data-nodes={Jason.encode!(@nodes)}
              data-kinds={Enum.join(@kinds, ",")}
            >
              <div id={"zone-map-host-#{@zone.number}"} phx-update="ignore" data-canvas-host></div>
            </div>
            <p :if={!@frame} class="text-gray-400">No terrain yet. Generate it, or import a heightmap.</p>
          </div>

          <div class="space-y-6 text-sm text-gray-300">
            <form id={"zone-name-#{@zone.number}"} phx-submit="rename" class="space-y-2">
              <h3 class="text-white font-semibold">Name</h3>
              <input name="name" value={@zone.name} maxlength="60" class="w-full bg-gray-900 rounded px-2 py-1" />
              <textarea name="description" rows="2" placeholder="Description (optional)" class="w-full bg-gray-900 rounded px-2 py-1"><%= @zone.description %></textarea>
              <button class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Save name</button>
            </form>

            <div :if={@busy} class="p-3 rounded bg-amber-900/40 text-amber-200"><%= @busy %></div>

            <div :if={@zone.status == "generating" and not WorldGen.stalled?(@zone)} class="p-3 rounded bg-emerald-900/40 text-emerald-200 space-y-2">
              <div>Generating: <%= (@progress[@zone.number] || %{stage: "working"}).stage %></div>
              <div class="h-2 rounded bg-gray-800 overflow-hidden"><div class="h-full bg-emerald-500 transition-all" style={"width: #{(@progress[@zone.number] || %{pct: 2}).pct}%"}></div></div>
            </div>

            <div :if={WorldGen.stalled?(@zone) or @zone.status in ["planned", "failed"]} class="p-3 rounded bg-orange-900/40 text-orange-200 space-y-2">
              <div :if={WorldGen.stalled?(@zone)}>Its generation stopped (the server restarted while it ran). Nothing is working on it now.</div>
              <div :if={@zone.status == "planned"}>Not generated yet.</div>
              <div :if={@zone.status == "failed"}>Its last generation failed (see the server log).</div>
              <button phx-click="generate_one" class="bg-emerald-700 hover:bg-emerald-600 text-white px-3 py-1.5 rounded">Generate it now</button>
            </div>

            <div :if={@frame}>
              <h3 class="text-white font-semibold mb-2">Export for World Creator</h3>
              <p class="text-gray-400 mb-2">4096 m, <%= @frame.samples %>² samples. 0..65535 = <%= @frame.lo %> .. <%= @frame.hi %> m (set these as World Creator's Min/Max). Sea <%= Float.round(@frame.sea, 2) %> m.</p>
              <div class="flex gap-2">
                <a href={"/admin/bacon_world/world/export/#{@zone.number}?format=png"} class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">16-bit PNG</a>
                <a href={"/admin/bacon_world/world/export/#{@zone.number}?format=raw"} class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">RAW 16 (big-endian)</a>
              </div>
            </div>

            <.form for={@form} phx-change="validate_import" phx-submit="import" class="space-y-2">
              <h3 class="text-white font-semibold">Import a heightmap</h3>
              <p class="text-gray-400">16-bit greyscale PNG or 16-bit RAW, square, any size (resampled to 2049²). It goes live at once.</p>
              <.live_file_input upload={@uploads.heightmap} class="block w-full text-xs" />
              <%= for e <- @uploads.heightmap.entries do %>
                <div class="text-xs text-gray-400"><%= e.client_name %> · <%= e.progress %>%</div>
                <%= for err <- upload_errors(@uploads.heightmap, e) do %><div class="text-red-400 text-xs"><%= inspect(err) %></div><% end %>
              <% end %>
              <div class="grid grid-cols-2 gap-2">
                <label>Min (m) <input type="text" name="imp[min]" value={@form[:min].value} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
                <label>Max (m) <input type="text" name="imp[max]" value={@form[:max].value} class="w-full bg-gray-900 rounded px-2 py-1" /></label>
              </div>
              <label class="block">RAW byte order
                <select name="imp[endian]" class="w-full bg-gray-900 rounded px-2 py-1">
                  <option value="big" selected={@form[:endian].value == "big"}>Big-endian (World Creator)</option>
                  <option value="little" selected={@form[:endian].value == "little"}>Little-endian</option>
                </select>
              </label>
              <label class="block">Nodes in the zone
                <select name="imp[nodes]" class="w-full bg-gray-900 rounded px-2 py-1">
                  <option value="keep" selected={@form[:nodes].value == "keep"}>Keep, re-seat on the new ground</option>
                  <option value="clear" selected={@form[:nodes].value == "clear"}>Clear them all</option>
                </select>
              </label>
              <label class="flex items-center gap-2">
                <input type="hidden" name="imp[match_edges]" value="false" />
                <input type="checkbox" name="imp[match_edges]" value="true" checked={@form[:match_edges].value == "true"} />
                Blend the edges into the neighbouring zones (256 m)
              </label>
              <button type="submit" disabled={@busy != nil} class="bg-sky-700 hover:bg-sky-600 disabled:opacity-50 text-white px-4 py-2 rounded">Import and go live</button>
            </.form>

            <div :if={@zone.number != 0}>
              <h3 class="text-white font-semibold mb-2">Generate again</h3>
              <div class="flex gap-2">
                <button phx-click="regenerate" phx-value-nodes="keep" disabled={@busy != nil} class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Keep nodes</button>
                <button phx-click="regenerate" phx-value-nodes="clear" disabled={@busy != nil} data-confirm="Delete everything placed in this zone?" class="bg-red-800 hover:bg-red-700 text-white px-3 py-1.5 rounded">Clear nodes</button>
              </div>
            </div>

            <div :if={@report && @report[:flagged] not in [nil, []]}>
              <h3 class="text-white font-semibold mb-2">Need a look</h3>
              <ul class="space-y-1 text-xs">
                <%= for f <- @report.flagged do %>
                  <li><%= f.asset %> at <%= Float.round(f.x * 1.0, 1) %>, <%= Float.round(f.z * 1.0, 1) %>: <%= f.problem %></li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end

  defp tile_bg(%{status: "ready"}), do: "#1f2a1f"
  defp tile_bg(%{status: "generating"} = z), do: if(WorldGen.stalled?(z), do: "#6b2a10", else: "#5a4a10")
  defp tile_bg(%{status: "failed"}), do: "#5a1414"
  defp tile_bg(_), do: "#1a1f2b"

  defp kind_label("binding"), do: "Binding stones"
  defp kind_label("npc"), do: "NPCs"
  defp kind_label("mob"), do: "Spawns"
  defp kind_label("object"), do: "Objects"
end
