defmodule BaconWorld.WorldGen do
  @moduledoc """
  The world around Crater Lake (2026-11-02, owner: "200 zones worth of terrain at the same size as the
  starter zone"). Zones lie on a grid (`BaconWorld.Zone` `grid_x`, `grid_z`; the lobby is 0,0) and
  you walk from one into the next, so their edges must meet.

  Every generated zone samples one function of *world* position (`height/2`, metres), so two zones
  that share an edge compute the same heights along it. World position: Crater Lake's own coordinates
  (its town is the origin; +x east, +z south); zone (gx, gz) covers
  `x0 = -2456 + 4096 gx .. + 4096`, `z0 = -3824 + 4096 gz .. + 4096`. Near Crater Lake the function
  bends toward Crater Lake's own edge (`@blend_m`), so the starter zone meets its neighbours too.

  The function: continents (very low frequency), domain-warped hills, ridged mountains where a
  mountain mask allows, and fine detail; sampled every 8 m (with a 2-sample border) and Catmull-Rom
  interpolated to the 2 m grid, plus a 2 m detail octave. Seeded by the world seed only, so the same
  seed always gives the same world.

  A generated zone's files are written to `World/Zones/` on the models volume
  (`BaconWorld.TerrainFiles`), its numbers into the zone's `meta`. Zone-local coordinates put the
  origin at the zone's centre (`x0 = z0 = -2048`).
  """

  import Bitwise
  require Logger

  alias Bacon8.GamesRepo
  alias BaconWorld.{TerrainFiles, Zone}
  import Ecto.Query

  @size 4096.0
  @samples 2049
  @coarse 8.0
  # Crater Lake's map in world coordinates (BaconWorld.Terrain @zones "crater_lake")
  @cl_x0 -2456.0
  @cl_z0 -3824.0
  @sea -16.967
  @blend_m 640.0
  @dir "World/Zones"
  @topic "bacon_world:worldgen"
  @default_seed 8_808

  def size_m, do: @size
  def samples, do: @samples
  def sea, do: @sea
  def dir, do: @dir
  def topic, do: @topic

  # ---------------------------------------------------------------- the grid

  @doc """
  The first `count` cells around the lobby, nearest first (ring by ring, clockwise from north):
  `[{number, gx, gz}]`, numbers from 1.
  """
  def layout(count \\ 200) do
    for(r <- 1..10, gx <- -r..r, gz <- -r..r, max(abs(gx), abs(gz)) == r, do: {r, gx, gz})
    |> Enum.sort_by(fn {r, gx, gz} -> {r, :math.atan2(gx, -gz) |> then(&if(&1 < 0, do: &1 + 2 * :math.pi(), else: &1))} end)
    |> Enum.take(count)
    |> Enum.with_index(1)
    |> Enum.map(fn {{_r, gx, gz}, n} -> {n, gx, gz} end)
  end

  @doc "World x, z of a zone's north-west corner."
  def corner(gx, gz), do: {@cl_x0 + gx * @size, @cl_z0 + gz * @size}

  @doc "World x, z of a generated zone's local origin (its centre)."
  def centre(gx, gz) do
    {x, z} = corner(gx, gz)
    {x + @size / 2, z + @size / 2}
  end

  @doc "World x, z of a zone's local origin: the lobby's is the world's; a generated zone's its centre."
  def origin(%{number: 0}), do: {0.0, 0.0}
  def origin(%{slug: "lobby"}), do: {0.0, 0.0}
  def origin(%{grid_x: gx, grid_z: gz}) when is_integer(gx) and is_integer(gz), do: centre(gx, gz)
  def origin(_), do: {0.0, 0.0}

  # A crossing triggers within @edge_m of an edge and lands @inside_m inside the next zone: well past
  # its own trigger band, or the player is sent straight back (2026-11-02, owner: "zoning between
  # the two sides back-and-forth in an endless cycle": the first version landed 4 m in, inside the
  # 6 m band). The client also re-arms only once the player has walked clear of every edge, and
  # only asks while moving outward; the server holds a cooldown (PlayLive "zone_cross").
  @edge_m 6.0
  @inside_m 20.0

  def edge_m, do: @edge_m
  def inside_m, do: @inside_m

  @doc """
  The zone a player at x, z (scene units, `u` per metre, in `zone`) walks into: when they are within
  #{@edge_m} m of one of its edges (or its margin) and the zone on that side has ground,
  `{:ok, neighbour, x, z}` with where they arrive (scene units in the neighbour, #{@inside_m} m
  past its margin); otherwise `:none`.
  """
  def neighbour_at(zone, x, z, u, moving \\ nil)

  def neighbour_at(zone, x, z, u, moving) do
    case neighbour(zone, x, z, u, moving) do
      {:ok, _, _, _} = r -> r
      _ -> :none
    end
  end

  @doc """
  `neighbour_at/5` with the reason when there's no way across (`{:error, reason}`): the client says
  it, so a refused crossing is never a silent wall (2026-11-02, owner: still "an invisible wall").
  """
  def neighbour(%{grid_x: gx, grid_z: gz} = zone, x, z, u, moving) when is_integer(gx) and is_integer(gz) do
    alias BaconWorld.Terrain

    with {:t, t} when is_map(t) <- {:t, Terrain.loaded()},
         mx = x / u,
         mz = z / u,
         {:side, {dx, dz}} when {dx, dz} != {0, 0} <- {:side, side(t, mx, mz)},
         # moving toward that edge (when the client says how it moves): never pulled back across
         {:out, true} <- {:out, outward?(moving, dx, dz)},
         {:zone, %Zone{status: "ready"} = there} <-
           {:zone, GamesRepo.one(from z in Zone, where: z.grid_x == ^(gx + dx) and z.grid_z == ^(gz + dz)) || {:none, gx + dx, gz + dz}},
         {:ground, nt} when is_map(nt) <- {:ground, Terrain.loaded_terrain(there.terrain)} do
      {ox, oz} = origin(zone)
      {nx0, nz0} = origin(there)
      wx = mx + ox
      wz = mz + oz
      lx = (wx - nx0) |> max(nt.x0 + nt.margin + @inside_m) |> min(nt.x0 + nt.size_m - nt.margin - @inside_m)
      lz = (wz - nz0) |> max(nt.z0 + nt.margin + @inside_m) |> min(nt.z0 + nt.size_m - nt.margin - @inside_m)
      {:ok, there, lx * u, lz * u}
    else
      {:t, _} -> {:error, "this zone's ground isn't loaded on the server"}
      {:side, _} -> {:error, "not at an edge (the server has you at x #{Float.round(x / u * 1.0, 1)}, z #{Float.round(z / u * 1.0, 1)} m)"}
      {:out, _} -> {:error, "not moving outward"}
      {:zone, {:none, ax, az}} -> {:error, "there is no zone that way (grid #{ax}, #{az})"}
      {:zone, %Zone{} = there} -> {:error, "#{there.name} (zone #{there.number}) is #{there.status}, not ready"}
      {:ground, _} -> {:error, "the next zone's ground files are missing on the server"}
      other -> {:error, inspect(other)}
    end
  end

  def neighbour(zone, _, _, _, _), do: {:error, "this zone has no place on the world grid (#{inspect(zone && Map.get(zone, :slug))})"}

  defp outward?({mx, mz}, dx, dz) when is_number(mx) and is_number(mz), do: mx * dx + mz * dz > 0
  defp outward?(_, _, _), do: true

  defp side(t, x, z) do
    near = t.margin + @edge_m

    dx =
      cond do
        x <= t.x0 + near -> -1
        x >= t.x0 + t.size_m - near -> 1
        true -> 0
      end

    dz =
      cond do
        z <= t.z0 + near -> -1
        z >= t.z0 + t.size_m - near -> 1
        true -> 0
      end

    {dx, dz}
  end

  @doc """
  Makes the zone rows for the first `count` cells that have none yet (status "planned", no terrain
  yet). Returns how many it made.
  """
  def plan!(count \\ 200) do
    have = GamesRepo.all(from z in Zone, where: not is_nil(z.number), select: z.number) |> MapSet.new()

    layout(count)
    |> Enum.reject(fn {n, _, _} -> MapSet.member?(have, n) end)
    |> Enum.map(fn {n, gx, gz} ->
      %Zone{}
      |> Zone.changeset(%{
        name: zone_name(n),
        slug: "z#{n}",
        description: "Generated (#{gx}, #{gz})",
        number: n,
        grid_x: gx,
        grid_z: gz,
        terrain: "z#{n}",
        status: "planned",
        meta: %{}
      })
      |> GamesRepo.insert!()
    end)
    |> length()
  end

  # ---------------------------------------------------------------- generating

  @doc """
  Generates every zone that is "planned" or "failed", one at a time, in the background; progress
  is broadcast on `topic/0` as `{:worldgen, %{zone: number, status: ...}}`. Only one run at a time.
  """
  def generate_all(seed \\ @default_seed) do
    case :global.whereis_name(__MODULE__) do
      :undefined ->
        {:ok, pid} =
          Task.start(fn ->
            :global.register_name(__MODULE__, self())
            # "generating" too: a run that was stopped (a restart, the pod killed) leaves its zone so
            zones = GamesRepo.all(from z in Zone, where: z.status in ["planned", "failed", "generating"] and not is_nil(z.number) and z.number > 0, order_by: z.number)
            # each zone in a process of its own: it registers as the zone's worker (a process may hold
            # only one :global name, and this one holds the run's: the first version skipped every zone
            # as "busy"), its memory goes when it ends, and a crash costs that zone only
            Enum.each(zones, fn z ->
              {pid, ref} = spawn_monitor(fn -> generate(z, seed) end)
              receive do
                {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
              end
            end)
            Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, {:worldgen, %{done: true}})
          end)

        {:ok, pid}

      pid ->
        {:running, pid}
    end
  end

  def running?, do: :global.whereis_name(__MODULE__) != :undefined

  # ---------------------------------------------------------------- progress (2026-11-02)
  # A zone being worked on is registered under {WorldGen, :zone, number} by the process doing it,
  # so the admin page can tell a zone in progress from one a stopped run left "generating", and
  # its progress is broadcast on topic/0 as {:worldgen_progress, number, stage, percent}.

  @doc "True while some process is generating zone `number`."
  def active?(number), do: :global.whereis_name({__MODULE__, :zone, number}) != :undefined

  @doc "A zone marked \"generating\" that nothing is working on (the server restarted mid-zone)."
  def stalled?(%Zone{status: "generating", number: n}), do: not active?(n)
  def stalled?(_), do: false

  @doc """
  Runs `fun` as the zone's worker: registered (so `active?/1` says so), `{:error, :busy}` if another
  process is already on it. `fun` gets a `report.(stage, percent)` function.
  """
  def working_on(number, fun) do
    name = {__MODULE__, :zone, number}

    case :global.register_name(name, self()) do
      :yes ->
        try do
          fun.(fn stage, pct -> progress(number, stage, pct) end)
        after
          :global.unregister_name(name)
        end

      :no ->
        {:error, :busy}
    end
  end

  def progress(number, stage, pct),
    do: Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, {:worldgen_progress, number, stage, pct})

  @doc "Generates one zone in the background (the admin page's button). `:ok` or `{:error, :busy}`."
  def generate_one(%Zone{number: n} = zone, seed \\ @default_seed) do
    if active?(n) do
      {:error, :busy}
    else
      Task.start(fn -> generate(zone, seed) end)
      :ok
    end
  end

  @doc "Generates one zone's terrain (replacing any) and marks it ready. `{:ok, zone}` or `{:error, reason}`."
  def generate(%Zone{} = zone, seed \\ @default_seed) do
    case working_on(zone.number, &do_generate(zone, seed, &1)) do
      {:error, :busy} -> {:error, "Zone #{zone.number} is already being generated."}
      other -> other
    end
  end

  defp do_generate(zone, seed, report) do
    t0 = System.monotonic_time(:millisecond)
    zone = zone |> Zone.changeset(%{status: "generating"}) |> GamesRepo.update!()
    notify(zone, "generating")

    try do
      grid = heights(zone.grid_x, zone.grid_z, seed, report)
      report.("writing files", 95)
      root = BaconWorld.Models.write_root()
      meta = TerrainFiles.write_zone(Path.join(root, @dir), zone.terrain, grid, @sea)
      {spawn_x, spawn_y, spawn_z} = spawn_on_land(grid)

      meta =
        Map.merge(meta, %{
          "size_m" => @size,
          "x0" => -@size / 2,
          "z0" => -@size / 2,
          "margin" => 0.0,
          "dir" => @dir,
          "seed" => seed,
          "source" => "generated"
        })

      zone =
        zone
        |> Zone.changeset(%{
          status: "ready",
          meta: meta,
          terrain_version: (zone.terrain_version || 1) + 1,
          spawn_x: spawn_x,
          spawn_y: spawn_y,
          spawn_z: spawn_z
        })
        |> GamesRepo.update!()

      BaconWorld.Terrain.reload(zone.terrain)
      BaconWorld.Terrain.forget_terrain_of(zone.slug)
      BaconWorld.Models.clear_cache()
      Logger.info("[bacon_world] generated zone #{zone.number} in #{System.monotonic_time(:millisecond) - t0} ms")
      notify(zone, "ready")
      {:ok, zone}
    rescue
      e ->
        Logger.error("[bacon_world] zone #{zone.number} failed: " <> Exception.format(:error, e, __STACKTRACE__))
        zone = zone |> Zone.changeset(%{status: "failed"}) |> GamesRepo.update!()
        notify(zone, "failed")
        {:error, Exception.message(e)}
    end
  end

  defp notify(zone, status), do: Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, {:worldgen, %{zone: zone.number, status: status}})

  # the centre, or the nearest land to it on a widening spiral (local metres; y the ground)
  defp spawn_on_land(%{n: n} = g) do
    c = div(n, 2)
    cell = @size / (n - 1)

    {i, j} =
      Enum.find_value(0..200, {c, c}, fn r ->
        Enum.find_value(0..max(8 * r - 1, 0), fn s ->
          a = if r == 0, do: 0.0, else: s / (8 * r) * 2 * :math.pi()
          i = (c + round(r * 8 * :math.cos(a))) |> max(0) |> min(n - 1)
          j = (c + round(r * 8 * :math.sin(a))) |> max(0) |> min(n - 1)
          if TerrainFiles.at(g, i, j) > @sea + 1.0, do: {i, j}
        end)
      end)

    {(i - c) * cell, TerrainFiles.at(g, i, j), (j - c) * cell}
  end

  @doc "The zone's heights (metres) as a `BaconWorld.TerrainFiles` grid, `samples` square, row 0 north."
  def heights(gx, gz, seed \\ @default_seed, report \\ fn _, _ -> :ok end) do
    report.("sampling the world", 0)
    {wx0, wz0} = corner(gx, gz)
    nc = round(@size / @coarse) + 1
    pad = 2
    # coarse samples, -pad .. nc - 1 + pad, in world space
    coarse =
      for cj <- -pad..(nc - 1 + pad) do
        for(ci <- -pad..(nc - 1 + pad), do: height(wx0 + ci * @coarse, wz0 + cj * @coarse, seed)) |> List.to_tuple()
      end
      |> List.to_tuple()

    report.("shaping the land", 30)
    :erlang.garbage_collect()
    up = round(@coarse / (@size / (@samples - 1)))
    near_cl = abs(gx) <= 1 and abs(gz) <= 1
    cl = if near_cl, do: BaconWorld.Terrain.loaded_terrain("crater_lake")
    fine_cell = @size / (@samples - 1)

    # along x for every coarse row, then along z
    xs =
      for cj <- 0..(tuple_size(coarse) - 1) do
        row = elem(coarse, cj)
        for(i <- 0..(@samples - 1), do: cr_at(row, i / up + pad)) |> List.to_tuple()
      end
      |> List.to_tuple()

    # a row at a time into the grid (float32): the whole zone as floats would be over a gigabyte
    TerrainFiles.build(@samples, fn j ->
      if rem(j, 128) == 0, do: report.("detailing", 30 + div(j * 65, @samples))
      u = j / up + pad
      k = trunc(u)
      t = u - k
      r0 = elem(xs, k - 1)
      r1 = elem(xs, k)
      r2 = elem(xs, min(k + 1, tuple_size(xs) - 1))
      r3 = elem(xs, min(k + 2, tuple_size(xs) - 1))
      wz = wz0 + j * fine_cell

      for i <- 0..(@samples - 1) do
        wx = wx0 + i * fine_cell
        h = catmull(elem(r0, i), elem(r1, i), elem(r2, i), elem(r3, i), t) + detail(wx, wz, seed)
        if cl, do: blend_cl(cl, wx, wz, h), else: h
      end
    end)
  end

  defp cr_at(row, u) do
    k = trunc(u)
    t = u - k
    n = tuple_size(row)
    catmull(elem(row, max(k - 1, 0)), elem(row, k), elem(row, min(k + 1, n - 1)), elem(row, min(k + 2, n - 1)), t)
  end

  defp catmull(p0, p1, p2, p3, t) do
    t2 = t * t
    t3 = t2 * t
    0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
  end

  # toward Crater Lake's own heights at the nearest point of its map, within @blend_m of it
  defp blend_cl(cl, wx, wz, h) do
    cx = wx |> max(@cl_x0) |> min(@cl_x0 + @size)
    cz = wz |> max(@cl_z0) |> min(@cl_z0 + @size)
    d = :math.sqrt((wx - cx) * (wx - cx) + (wz - cz) * (wz - cz))

    if d >= @blend_m do
      h
    else
      target = BaconWorld.Terrain.height(cl, cx, cz)
      w = 1.0 - smooth(d / @blend_m)
      h + (target - h) * w
    end
  end

  # ---------------------------------------------------------------- the world function

  @doc "The generated world's ground height (m) at world position x, z."
  def height(x, z, seed \\ @default_seed) do
    # domain warp: hills and ridges bend instead of running in grid lines
    wx = x + 420.0 * (fbm(x / 2600.0, z / 2600.0, seed + 11, 3) - 0.5)
    wz = z + 420.0 * (fbm(x / 2600.0 + 7.3, z / 2600.0 - 3.1, seed + 13, 3) - 0.5)

    # mostly land: seas where the continent value is low, a coast band, then lowlands to uplands
    continent = fbm(wx / 14000.0, wz / 14000.0, seed + 1, 3)
    base = -90.0 + 250.0 * smooth((continent - 0.24) / 0.36)

    hills = (fbm(wx / 900.0, wz / 900.0, seed + 2, 5) - 0.5) * 120.0

    mask = smooth((fbm(x / 6000.0, z / 6000.0, seed + 3, 2) - 0.42) / 0.2)
    ridges = ridged(wx / 1700.0, wz / 1700.0, seed + 4, 5) * 760.0 * mask * smooth((continent - 0.32) / 0.25)

    (base + hills + ridges) |> max(-140.0) |> min(1300.0)
  end

  defp detail(x, z, seed), do: (vnoise(x / 14.0, z / 14.0, seed + 9) - 0.5) * 1.2

  defp fbm(x, z, seed, octaves) do
    {sum, _amp, norm} =
      Enum.reduce(0..(octaves - 1), {0.0, 1.0, 0.0}, fn o, {s, a, n} ->
        f = 1 <<< o
        {s + a * vnoise(x * f, z * f, seed + o * 101), a * 0.5, n + a}
      end)

    sum / norm
  end

  defp ridged(x, z, seed, octaves) do
    {sum, _amp, norm} =
      Enum.reduce(0..(octaves - 1), {0.0, 1.0, 0.0}, fn o, {s, a, n} ->
        f = 1 <<< o
        r = 1.0 - abs(vnoise(x * f, z * f, seed + o * 131) * 2.0 - 1.0)
        {s + a * r * r, a * 0.5, n + a}
      end)

    sum / norm
  end

  # value noise in [0, 1), smoothly interpolated
  defp vnoise(x, z, seed) do
    ix = floor_i(x)
    iz = floor_i(z)
    fx = x - ix
    fz = z - iz
    sx = fx * fx * (3 - 2 * fx)
    sz = fz * fz * (3 - 2 * fz)
    a = hash(ix, iz, seed)
    b = hash(ix + 1, iz, seed)
    c = hash(ix, iz + 1, seed)
    d = hash(ix + 1, iz + 1, seed)
    (a + (b - a) * sx) * (1 - sz) + (c + (d - c) * sx) * sz
  end

  defp floor_i(v) do
    t = trunc(v)
    if v < t, do: t - 1, else: t
  end

  defp hash(ix, iz, seed) do
    h = band(ix * 374_761_393 + iz * 668_265_263 + seed * 2_246_822_519, 0xFFFFFFFF)
    h = band(bxor(h, h >>> 13) * 1_274_126_177, 0xFFFFFFFF)
    band(bxor(h, h >>> 16), 0xFFFFFF) / 16_777_216
  end

  defp smooth(t) do
    t = t |> max(0.0) |> min(1.0)
    t * t * (3 - 2 * t)
  end

  # ---------------------------------------------------------------- names

  @a ~w(Ash Bram Cold Dun Elder Fen Gloam Hollow Iron Kel Lorn Mire North Oak Pale Raven Salt Thorn Umber Vale West Wyrm Yew Amber Black Briar Copper Dusk Ember Frost)
  @b ~w(moor reach fells wood marsh downs barrow crag hollow shore ridge glen weald heath dale mere wold scar holt fen)

  @doc "A name for zone `n` (stable: the same number always gets the same name)."
  def zone_name(n) do
    h = band((n * 2_654_435_761) >>> 3, 0xFFFFFF)
    a = Enum.at(@a, rem(h, length(@a)))
    b = Enum.at(@b, rem(div(h, length(@a)), length(@b)))
    "#{String.capitalize(a <> b)} (#{n})"
  end
end
