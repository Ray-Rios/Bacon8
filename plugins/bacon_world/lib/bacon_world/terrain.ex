defmodule BaconWorld.Terrain do
  @moduledoc """
  The lobby zone's ground: a heightfield made from a World Creator map (2026-10-26). One set of
  files, read by the server here and by the browser (`terrain.ts`), so both agree on where the
  ground is and where the water is.

  The files are on the models volume (`World/Terrain/`, made by
  `library/pipeline/scripts/terrain_build.py`, which holds the same numbers as `@zones`):

    * `<zone>_h.bin`: heights, uint16 little-endian `k`, `samples` x `samples`, 2 m apart, row 0
      north, column 0 west; metres = `lo + k * step`. The server reads this one.
    * `<zone>_hd.bin`: the same heights packed smaller for the browser (`.bin.gz` beside it).
    * `<zone>_w.bin`: water bodies, uint8, `water_samples` square, 4 m apart: 0 land, 1 the sea,
      2.. the enclosed lakes, largest first (`lakes` names them).

  Positions here are metres in the zone (the town's centre is the origin, its ground is height 0,
  north is -z). The terrain is optional: without its files (tests, an install that hasn't synced
  the models), `loaded/0` is nil, every height is 0 and `BaconWorld.Water` keeps the old round
  island.
  """

  require Logger

  @zones %{
    "crater_lake" => %{
      id: "crater_lake",
      name: "Crater Lake",
      dir: "World/Terrain",
      size_m: 4096.0,
      samples: 2049,
      water_samples: 1025,
      x0: -2456.0,
      z0: -3824.0,
      lo: -323.0,
      step: 0.05,
      sea: -16.967,
      # how close to the map's edge anyone may go (the edges are ridges or open sea)
      margin: 40.0,
      lakes: %{
        2 => %{id: "crater_lake", name: "Crater Lake"},
        3 => %{id: "upper_pond", name: "the Upper Pond"},
        4 => %{id: "little_pond", name: "the Little Pond"}
      }
    }
  }

  # A walker may stand in water this deep (m), no deeper.
  @wade 1.2

  # how soon to look again for terrain files that were missing
  @retry_secs 20

  @doc "The zone the lobby uses (config `:bacon8, BaconWorld.Terrain, zone:`; nil for none)."
  def zone_id, do: Application.get_env(:bacon8, __MODULE__, []) |> Keyword.get(:zone, "crater_lake")

  def zone, do: zone_id() && Map.get(zones(), zone_id())

  # (tests add small zones of their own: config `zones: %{"id" => %{...}}`)
  defp zones, do: Map.merge(@zones, Application.get_env(:bacon8, __MODULE__, []) |> Keyword.get(:zones, %{}))

  @doc "The loaded zone (its description plus the two grids), or nil when there is none."
  def loaded do
    case zone() do
      nil ->
        nil

      z ->
        key = {__MODULE__, z.id}
        now = System.monotonic_time(:second)

        case :persistent_term.get(key, :unloaded) do
          {:missing, at} when now - at < @retry_secs ->
            nil

          loaded when is_map(loaded) ->
            loaded

          _ ->
            case load(z) do
              nil ->
                # asked before the files were synced? look again shortly, not only after a restart
                :persistent_term.put(key, {:missing, now})
                nil

              value ->
                :persistent_term.put(key, value)
                value
            end
        end
    end
  end

  @doc "Forgets the loaded grids (after new files were synced; tests)."
  def reload do
    if z = zone(), do: :persistent_term.erase({__MODULE__, z.id})
    :ok
  end

  defp load(z) do
    with h when is_binary(h) <- BaconWorld.Models.path("#{z.dir}/#{z.id}_h.bin"),
         w when is_binary(w) <- BaconWorld.Models.path("#{z.dir}/#{z.id}_w.bin"),
         {:ok, hb} <- File.read(h),
         {:ok, wb} <- File.read(w),
         true <- byte_size(hb) == z.samples * z.samples * 2 and byte_size(wb) == z.water_samples * z.water_samples do
      Map.merge(z, %{h: hb, w: wb})
    else
      _ ->
        Logger.info("[bacon_world] no terrain files for #{z.id}; the zone is flat")
        nil
    end
  end

  @doc "The ground's height (m) at a point (m); 0 without terrain."
  def height(x, z), do: height(loaded(), x, z)

  def height(nil, _x, _z), do: 0.0

  def height(t, x, z) do
    n = t.samples
    cell = t.size_m / (n - 1)
    gx = clamp((x - t.x0) / cell, 0.0, n - 1.0)
    gz = clamp((z - t.z0) / cell, 0.0, n - 1.0)
    i0 = min(trunc(gx), n - 2)
    j0 = min(trunc(gz), n - 2)
    fx = gx - i0
    fz = gz - j0
    a = k(t, i0, j0)
    b = k(t, i0 + 1, j0)
    c = k(t, i0, j0 + 1)
    d = k(t, i0 + 1, j0 + 1)
    v = (a * (1 - fx) + b * fx) * (1 - fz) + (c * (1 - fx) + d * fx) * fz
    t.lo + v * t.step
  end

  defp k(t, i, j) do
    <<v::little-unsigned-16>> = :binary.part(t.h, (j * t.samples + i) * 2, 2)
    v
  end

  @doc "The sea's height (m); 0 without terrain."
  def sea, do: (t = loaded()) && t.sea

  @doc """
  The water at a point (m): `:ocean`, `{:lake, id, name}`, or nil on land (and nil everywhere
  without terrain).
  """
  def water(x, z), do: water(loaded(), x, z)

  def water(nil, _x, _z), do: nil

  def water(t, x, z) do
    if height(t, x, z) < t.sea, do: body(t, x, z), else: nil
  end

  # Which body: the nearest labelled cell (the 4 m label grid and the 2 m heights disagree by a
  # cell along the shore); water no label reaches is the sea.
  defp body(t, x, z) do
    n = t.water_samples
    cell = t.size_m / (n - 1)
    i = round((x - t.x0) / cell)
    j = round((z - t.z0) / cell)

    label =
      Enum.find_value([{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1}], 1, fn {di, dj} ->
        ii = i + di
        jj = j + dj

        if ii >= 0 and jj >= 0 and ii < n and jj < n do
          case :binary.at(t.w, jj * n + ii) do
            0 -> nil
            l -> l
          end
        end
      end)

    case Map.get(t.lakes, label) do
      %{id: id, name: name} -> {:lake, id, name}
      nil -> :ocean
    end
  end

  @doc """
  Where someone on foot may be (m): inside the map's margin and no deeper in water than wading.
  Always true without terrain (`BaconWorld.Water.walkable?/2` keeps the island then).
  """
  def walkable?(x, z), do: walkable?(loaded(), x, z)

  def walkable?(nil, _x, _z), do: true

  def walkable?(t, x, z) do
    inside?(t, x, z) and height(t, x, z) >= t.sea - @wade
  end

  @doc "Deep water (m): deeper than wading, so someone there swims."
  def deep?(x, z), do: deep?(loaded(), x, z)

  def deep?(nil, _x, _z), do: false
  def deep?(t, x, z), do: height(t, x, z) < t.sea - @wade

  @doc """
  What someone stands or floats on at a point, in scene units (`u` per metre, scene-unit
  coordinates): the ground, or the water's surface over water; 0 without terrain. The move checks,
  the creatures and dismounting measure heights from it.
  """
  def surface_units(x, z, u) do
    case loaded() do
      nil -> 0.0
      t -> max(height(t, x / u, z / u), t.sea) * u
    end
  end

  @doc "Inside the map, `margin` metres from its edges."
  def inside?(t, x, z) do
    x >= t.x0 + t.margin and z >= t.z0 + t.margin and x <= t.x0 + t.size_m - t.margin and z <= t.z0 + t.size_m - t.margin
  end

  @doc "What the client needs, scene units (`u` per metre) except the file names. Nil without terrain."
  def payload(u) do
    case loaded() do
      nil ->
        nil

      t ->
        %{
          zone: t.id,
          name: t.name,
          heights: "/models/#{t.dir}/#{t.id}_hd.bin",
          water: "/models/#{t.dir}/#{t.id}_w.bin",
          samples: t.samples,
          water_samples: t.water_samples,
          size: t.size_m * u,
          x0: t.x0 * u,
          z0: t.z0 * u,
          lo: t.lo * u,
          step: t.step * u,
          sea: t.sea * u,
          margin: t.margin * u,
          wade: @wade * u,
          lakes: Enum.map(t.lakes, fn {label, l} -> %{label: label, id: l.id, name: l.name} end)
        }
    end
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
end
