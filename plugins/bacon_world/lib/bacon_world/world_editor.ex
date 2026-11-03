defmodule BaconWorld.WorldEditor do
  @moduledoc """
  What /admin/bacon_world/world does to a zone (2026-11-02): lists its nodes, exports its heights for
  World Creator, imports them back and puts the new ground live.

  **Nodes** are what stands in the zone: binding stones, NPCs (placed, and the merchants in code),
  creature spawns and placed objects, in zone metres.

  **Replacing a zone's ground** (`import_heightmap/3`, `regenerate/2`): the new heights get a new terrain id
  (`<slug>_r<version>`, so no browser or service worker cache answers with the old file and a models
  sync can't overwrite it), then, as the owner chose:

    * `nodes: :keep` - every placement keeps its x, z and its height above the ground (re-seated);
      the ones that end up under water or on a slope steeper than 40° are reported for review;
    * `nodes: :clear` - every placement in the zone is deleted.

  Players in the zone get the new terrain at once (`"terrain_replaced"`, the client rebuilds the
  ground and resyncs), and stand on the new ground. Creatures read the ground live.

  **Edges**: with `match_edges: true` the imported heights are blended, within 256 m of each side, to
  the neighbouring zones' current edges, so walking across stays seamless.
  """

  require Logger
  import Ecto.Query

  alias Bacon8.GamesRepo
  alias BaconWorld.{Building, Placement, Terrain, TerrainFiles, WorldGen, Zone}

  @edge_band 256.0
  @steep 40.0

  # ---------------------------------------------------------------- zones and nodes

  @doc "Every zone on the grid, for the map: `[%{number, slug, name, gx, gz, status, terrain, version}]`."
  def grid do
    GamesRepo.all(from z in Zone, where: not is_nil(z.number), order_by: z.number)
  end

  def get(number) when is_integer(number), do: GamesRepo.get_by(Zone, number: number)

  @doc """
  What stands in a zone, in zone metres: `[%{id, kind, label, x, y, z, info}]`, `kind` one of
  `"binding"`, `"npc"`, `"mob"`, `"object"`.
  """
  def nodes(%Zone{slug: slug}) do
    placed =
      GamesRepo.all(from p in Placement, where: p.zone == ^slug)
      |> Enum.map(fn p ->
        {kind, label} = classify(p.asset, p.data || %{})

        %{id: p.id, kind: kind, label: label, x: p.x, y: p.y, z: p.z,
          info: %{asset: p.asset, rot: Float.round(p.rot || 0.0, 2), scale: p.scale, data: p.data || %{}, placed: p.inserted_at && to_string(p.inserted_at)}}
      end)

    coded =
      for m <- BaconWorld.Merchants.in_zone(slug), not String.starts_with?(to_string(m.id), "p:") do
        %{id: m.id, kind: "npc", label: "#{m.name}#{if Map.get(m, :title), do: " (#{m.title})"}", x: m.x, y: nil, z: m.z,
          info: %{source: "code (BaconWorld.Merchants)", sells: length(Map.get(m, :sells, []))}}
      end

    placed ++ coded
  end

  defp classify("P_Waystone", _), do: {"binding", "Binding stone"}
  defp classify("npc:" <> t, data), do: {"npc", data["name"] || t}
  defp classify("mob:" <> kind, data), do: {"mob", "#{kind}#{if data["count"], do: " ×#{data["count"]}"}"}
  defp classify(asset, _), do: {"object", asset}

  @doc """
  The zone's shaded picture for the map (`/models/World/Zones/<terrain>_preview.png`), made from its
  heights if it's missing (Crater Lake's files come without one). The URL, or nil without terrain.
  """
  def preview_url(%Zone{} = zone) do
    with t when is_map(t) <- Terrain.loaded_terrain(zone.terrain) do
      rel = "#{WorldGen.dir()}/#{t.id}_preview.png"

      unless BaconWorld.Models.path(rel) do
        grid = TerrainFiles.read_grid(path(t), t.samples, t.lo, t.step)
        file = Path.join(BaconWorld.Models.write_root(), rel)
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, TerrainFiles.preview_png(grid, 512, t.lo, t.hi, t.sea))
      end

      "/models/#{rel}?v=#{zone.terrain_version || 1}"
    end
  rescue
    e ->
      Logger.warning("[bacon_world] no preview for #{zone.slug}: #{Exception.message(e)}")
      nil
  end

  @doc """
  A 2048 px shaded picture of the zone, for zooming in on the map (made on first request for each
  terrain version and kept beside the terrain: `<terrain>_detail.png`). `{:ok, path}` or `{:error, msg}`.
  """
  def detail_png(%Zone{} = zone) do
    with t when is_map(t) <- Terrain.loaded_terrain(zone.terrain) || {:error, "This zone has no terrain yet."} do
      rel = "#{WorldGen.dir()}/#{t.id}_detail.png"

      case BaconWorld.Models.path(rel) do
        nil ->
          grid = TerrainFiles.read_grid(path(t), t.samples, t.lo, t.step)
          file = Path.join(BaconWorld.Models.write_root(), rel)
          File.mkdir_p!(Path.dirname(file))
          File.write!(file, TerrainFiles.preview_png(grid, 2048, t.lo, t.hi, t.sea))
          :erlang.garbage_collect()
          {:ok, file}

        file ->
          {:ok, file}
      end
    end
  end

  @doc """
  What the player's map needs about the zone they're in (2026-11-02, owner: "players need a map and
  a mini-map"): its number and name, its shaded picture (`/models/World/Zones/<terrain>_preview.png`,
  made in the background if missing), and the eight around it (`dx`, `dz`: -1 west/north .. 1
  east/south) with their names and pictures when they have ground.
  """
  def map_info(slug) do
    zone = BaconWorld.World.zone_for(slug)
    ensure_preview_soon(zone)

    neighbours =
      if is_integer(zone.grid_x) and is_integer(zone.grid_z) do
        for z <- GamesRepo.all(from z in Zone, where: z.grid_x in ^Enum.to_list((zone.grid_x - 1)..(zone.grid_x + 1)) and z.grid_z in ^Enum.to_list((zone.grid_z - 1)..(zone.grid_z + 1))),
            {z.grid_x, z.grid_z} != {zone.grid_x, zone.grid_z} do
          %{dx: z.grid_x - zone.grid_x, dz: z.grid_z - zone.grid_z, number: z.number, name: z.name, ready: z.status == "ready",
            preview: if(z.status == "ready" and z.terrain, do: "/models/#{WorldGen.dir()}/#{z.terrain}_preview.png?v=#{z.terrain_version}")}
        end
      else
        []
      end

    %{number: zone.number, name: zone.name, preview: zone.terrain && "/models/#{WorldGen.dir()}/#{zone.terrain}_preview.png?v=#{zone.terrain_version || 1}",
      neighbours: neighbours}
  rescue
    _ -> %{number: nil, name: nil, preview: nil, neighbours: []}
  end

  # Crater Lake comes without a picture: make it once, off the player's process
  defp ensure_preview_soon(%Zone{terrain: t} = zone) when is_binary(t) do
    key = {__MODULE__, :preview_made, t}

    if !:persistent_term.get(key, false) and !BaconWorld.Models.path("#{WorldGen.dir()}/#{t}_preview.png") do
      :persistent_term.put(key, true)
      Task.start(fn -> preview_url(zone) end)
    end

    :ok
  end

  defp ensure_preview_soon(_), do: :ok

  @doc "The map's frame for the zone (metres): `%{size_m, x0, z0}`, or nil without terrain."
  def frame(%Zone{} = zone) do
    case Terrain.loaded_terrain(zone.terrain) do
      nil -> nil
      t -> %{size_m: t.size_m, x0: t.x0, z0: t.z0, lo: t.lo, hi: t.hi, sea: t.sea, samples: t.samples}
    end
  end

  # ---------------------------------------------------------------- export

  @doc """
  The zone's heights for World Creator: `{:ok, %{filename, bytes, min, max, samples, size_m}}`.
  `format`: `:png` (16-bit greyscale) or `:raw` (16-bit big-endian). 0..65535 spans `min`..`max` metres.
  """
  def export(%Zone{} = zone, format) do
    with t when is_map(t) <- Terrain.loaded_terrain(zone.terrain) || {:error, "This zone has no terrain yet."} do
      grid = TerrainFiles.read_grid(path(t), t.samples, t.lo, t.step)
      {lo, hi} = TerrainFiles.range(grid)
      lo = Float.floor(lo)
      hi = Float.ceil(hi)

      {bytes, ext} =
        case format do
          :raw -> {TerrainFiles.export_raw16(grid, lo, hi), "r16"}
          _ -> {TerrainFiles.export_png16(grid, lo, hi), "png"}
        end

      {:ok, %{filename: "#{zone.slug}_#{t.samples}_#{trunc(lo)}m_#{trunc(hi)}m.#{ext}", bytes: bytes, min: lo, max: hi, samples: t.samples, size_m: t.size_m, sea: t.sea}}
    end
  end

  defp path(t), do: BaconWorld.Models.path("#{t.dir}/#{t.id}_h.bin")

  # ---------------------------------------------------------------- import / regenerate

  @doc """
  Replaces a zone's ground with a World Creator heightmap. `opts`: `:min`, `:max` (metres), `:endian`
  (RAW), `:nodes` (`:keep` or `:clear`), `:match_edges` (default true).
  `{:ok, report}` or `{:error, message}`.
  """
  def import_heightmap(%Zone{} = zone, bin, opts) do
    samples = WorldGen.samples()

    with {:ok, grid} <- TerrainFiles.import_heightmap(bin, samples, opts) do
      grid = if Keyword.get(opts, :match_edges, true), do: match_edges(zone, grid), else: grid
      replace(zone, grid, Keyword.put(opts, :source, "World Creator import"))
    end
  end

  @doc "Generates a zone's ground again from the world function (the same nodes options)."
  def regenerate(%Zone{grid_x: gx, grid_z: gz} = zone, opts \\ []) do
    case WorldGen.working_on(zone.number, fn report ->
           grid = WorldGen.heights(gx, gz, 8_808, report)
           report.("writing files", 95)
           replace(zone, grid, Keyword.put(opts, :source, "generated"))
         end) do
      {:error, :busy} -> {:error, "This zone is already being generated."}
      other -> other
    end
  end

  defp replace(%Zone{} = zone, grid, opts) do
    old = Terrain.loaded_terrain(zone.terrain)
    version = (zone.terrain_version || 1) + 1
    id = "#{zone.slug}_r#{version}"
    dir = WorldGen.dir()
    meta = TerrainFiles.write_zone(Path.join(BaconWorld.Models.write_root(), dir), id, grid, WorldGen.sea())
    n = meta["samples"]
    size = WorldGen.size_m()
    # the zone keeps its own frame: Crater Lake's town stays the lobby's origin
    {x0, z0} = if old, do: {old.x0, old.z0}, else: {-size / 2, -size / 2}

    meta =
      Map.merge(meta, %{"size_m" => size, "x0" => x0, "z0" => z0, "margin" => (old && old.margin) || 0.0, "dir" => dir, "source" => opts[:source] || "import"})

    {:ok, zone} =
      zone
      |> Zone.changeset(%{terrain: id, terrain_version: version, meta: meta, status: "ready"})
      |> GamesRepo.update()

    Terrain.reload(id)
    Terrain.forget_lobby_terrain()
    Terrain.forget_terrain_of(zone.slug)
    new = Terrain.loaded_terrain(id)
    report = place_nodes(zone, old, new, Keyword.get(opts, :nodes, :keep))
    cleanup(old, id)
    BaconWorld.Models.clear_cache()
    announce(zone, report)
    Logger.info("[bacon_world] zone #{zone.number} terrain replaced (#{id}, #{n}²): #{inspect(report)}")
    {:ok, Map.put(report, :terrain, id)}
  end

  # The old generated/imported files go (Crater Lake's own, from the models sync, stay).
  defp cleanup(nil, _), do: :ok
  defp cleanup(%{id: "crater_lake"}, _), do: :ok
  defp cleanup(%{id: same}, same), do: :ok

  defp cleanup(%{id: id, dir: dir}, _) do
    root = Path.join(BaconWorld.Models.write_root(), dir)
    for suffix <- ~w(_h.bin _hd.bin _hd.bin.gz _w.bin _preview.png _detail.png .json), do: File.rm(Path.join(root, id <> suffix))
    Terrain.reload(id)
    :ok
  end

  defp place_nodes(zone, _old, _new, :clear) do
    {n, _} = GamesRepo.delete_all(from p in Placement, where: p.zone == ^zone.slug)
    Building.list(zone.slug)
    %{nodes: "cleared", removed: n}
  end

  defp place_nodes(zone, old, new, _keep) when is_map(new) do
    rows = GamesRepo.all(from p in Placement, where: p.zone == ^zone.slug)

    flagged =
      Enum.flat_map(rows, fn p ->
        was = if old, do: Terrain.height(old, p.x, p.z), else: 0.0
        now = Terrain.height(new, p.x, p.z)
        y = (p.y || 0.0) + (now - was)
        p |> Ecto.Changeset.change(y: y) |> GamesRepo.update!()
        problem = cond do
          now < new.sea - 1.2 -> "under water"
          slope(new, p.x, p.z) > @steep -> "on a steep slope"
          true -> nil
        end

        if problem, do: [%{id: p.id, asset: p.asset, x: p.x, z: p.z, problem: problem}], else: []
      end)

    Building.list(zone.slug)
    %{nodes: "re-seated", moved: length(rows), flagged: flagged}
  end

  defp place_nodes(_zone, _old, _new, _), do: %{nodes: "kept"}

  defp slope(t, x, z) do
    d = 2.0
    gx = (Terrain.height(t, x + d, z) - Terrain.height(t, x - d, z)) / (2 * d)
    gz = (Terrain.height(t, x, z + d) - Terrain.height(t, x, z - d)) / (2 * d)
    :math.atan(:math.sqrt(gx * gx + gz * gz)) * 180 / :math.pi()
  end

  defp announce(zone, report) do
    payload = %{
      terrain: Terrain.payload_for(zone.terrain, BaconWorld.Mobs.Brain.u()),
      message: "The land here has changed.",
      report: Map.take(report, [:nodes])
    }

    Phoenix.PubSub.broadcast(Bacon8.PubSub, "bacon_world:zone:#{zone.id}", {:terrain_replaced, payload})
  end

  # ---------------------------------------------------------------- edges

  # Within @edge_band of each side that has a neighbour with terrain, bend the heights toward the
  # neighbour's edge (its samples along the shared side), so the seam stays continuous.
  defp match_edges(%Zone{grid_x: gx, grid_z: gz}, %{n: n} = grid) when is_integer(gx) and is_integer(gz) do
    cell = WorldGen.size_m() / (n - 1)
    band = round(@edge_band / cell)

    edges =
      for {side, dx, dz} <- [{:west, -1, 0}, {:east, 1, 0}, {:north, 0, -1}, {:south, 0, 1}],
          z = GamesRepo.one(from z in Zone, where: z.grid_x == ^(gx + dx) and z.grid_z == ^(gz + dz) and z.status == "ready"),
          t = z && Terrain.loaded_terrain(z.terrain),
          t != nil,
          into: %{} do
        {side, neighbour_edge(t, side, n)}
      end

    if edges == %{} do
      grid
    else
      # this map's own edges, before any change
      top = grid |> TerrainFiles.row(0) |> List.to_tuple()
      bottom = grid |> TerrainFiles.row(n - 1) |> List.to_tuple()

      TerrainFiles.build(n, fn j ->
        row = grid |> TerrainFiles.row(j) |> List.to_tuple()
        west = elem(row, 0)
        east = elem(row, n - 1)

        for i <- 0..(n - 1) do
          Enum.reduce(edges, elem(row, i), fn {side, edge}, h ->
            {d, k, own} =
              case side do
                :west -> {i, j, west}
                :east -> {n - 1 - i, j, east}
                :north -> {j, i, elem(top, i)}
                :south -> {n - 1 - j, i, elem(bottom, i)}
              end

            # shift by the edge's difference, fading inward (keeps this map's shape)
            if d < band, do: h + (elem(edge, k) - own) * (1.0 - smooth(d / band)), else: h
          end)
        end
      end)
    end
  end

  defp match_edges(_, grid), do: grid

  # the neighbour's samples along the side it shares with us, as n heights
  defp neighbour_edge(t, side, n) do
    x1 = t.x0 + t.size_m
    z1 = t.z0 + t.size_m

    for k <- 0..(n - 1) do
      s = k * (t.size_m / (n - 1))

      case side do
        :west -> Terrain.height(t, x1, t.z0 + s)
        :east -> Terrain.height(t, t.x0, t.z0 + s)
        :north -> Terrain.height(t, t.x0 + s, z1)
        :south -> Terrain.height(t, t.x0 + s, t.z0)
      end
    end
    |> List.to_tuple()
  end

  defp smooth(t) do
    t = t |> max(0.0) |> min(1.0)
    t * t * (3 - 2 * t)
  end
end
