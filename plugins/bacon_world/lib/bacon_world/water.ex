defmodule BaconWorld.Water do
  @moduledoc """
  The lobby zone's water: the sea all round the island and the Millpond, a small lake north-west
  of the village (2026-10-26). One description, used by the server (who may fish where, how far
  anyone may walk) and sent to the 3D client, which draws it (`layout/1`, `world-dressing.ts`).

  Positions are metres in the zone's layout (the village is centred on the origin; north is -z).
  The island is the grass disc of radius `shore/0`; the sea starts at its waterline, and nobody
  goes further out than `walk_radius/0` (ankle deep). The lake is an ellipse, axis-aligned.

  Fishing (`BaconWorldWeb.FishingEvents`): stand within `bank/0` metres of the water with a
  fishing pole in hand and cast; the bobber must land on water within `cast_reach/0` metres.
  `roll/2` says what bites: each water has its own fish.

  **With terrain** (`BaconWorld.Terrain`, from 2026-10-26: the Crater Lake map) the sea, the
  crater lake and the ponds are wherever the ground is below the sea's level, and the walkable
  world is the map minus its margin, no deeper than wading. The Millpond stays (carved into the
  town's pad by the terrain pipeline). Without terrain files everything below is the round island.
  """

  alias BaconWorld.Terrain

  @shore 150.0
  @walk_radius 151.5
  @bank 3.0
  @cast_reach 10.0

  @lakes [
    %{id: "millpond", name: "the Millpond", x: -31.0, z: -40.0, rx: 12.0, rz: 8.0}
  ]

  # {item id, weight}; weights are out of their sum
  @catches %{
    lake: [{"pond_perch", 38}, {"brook_trout", 26}, {"mud_carp", 22}, {"golden_carp", 3}, {"old_boot", 11}],
    ocean: [{"sea_mackerel", 36}, {"striped_bass", 24}, {"red_snapper", 18}, {"silver_tuna", 4}, {"tangle_of_kelp", 18}]
  }

  def shore, do: @shore
  def walk_radius, do: @walk_radius
  def bank, do: @bank
  def cast_reach, do: @cast_reach
  def lakes, do: @lakes
  def catches(kind), do: Map.fetch!(@catches, kind)

  @doc "What the client draws, in scene units (`u` per metre)."
  def layout(u) do
    sea = Terrain.sea()

    %{
      sea: sea && sea * u,
      shore: @shore * u,
      walk_radius: @walk_radius * u,
      bank: @bank * u,
      cast_reach: @cast_reach * u,
      lakes: Enum.map(@lakes, fn l -> %{id: l.id, name: l.name, x: l.x * u, z: l.z * u, rx: l.rx * u, rz: l.rz * u} end)
    }
  end

  @doc "The water at a point (metres): `:lake`, `:ocean`, or nil on land."
  def kind_at(x, z) do
    cond do
      Enum.any?(@lakes, &(lake_scale(&1, x, z) <= 1.0)) -> :lake
      t = Terrain.loaded() -> terrain_kind(t, x, z)
      :math.sqrt(x * x + z * z) > @shore -> :ocean
      true -> nil
    end
  end

  @doc "The name of the water at a point (\"the Millpond\", \"Crater Lake\", \"the sea\"), or nil."
  def name_at(x, z) do
    case Enum.find(@lakes, &(lake_scale(&1, x, z) <= 1.0)) do
      %{name: name} ->
        name

      nil ->
        case (t = Terrain.loaded()) && Terrain.water(t, x, z) do
          {:lake, _id, name} -> name
          :ocean -> "the sea"
          nil -> if(is_nil(t) and :math.sqrt(x * x + z * z) > @shore, do: "the sea")
        end
    end
  end

  defp terrain_kind(t, x, z) do
    case Terrain.water(t, x, z) do
      {:lake, _, _} -> :lake
      other -> other
    end
  end

  # Points round a circle of radius `r` (and its middle), for "is there water within r".
  defp ring(x, z, r) do
    [{x, z} | for(i <- 0..15, rr <- [r, r / 2], do: {x + rr * :math.cos(i * :math.pi() / 8), z + rr * :math.sin(i * :math.pi() / 8)})]
  end

  @doc """
  The water within `within` metres of a point on land (the nearest kind, lake first), or nil.
  Distance to the lake is to its ellipse, measured along the line from its middle.
  """
  def near(x, z, within) do
    r = :math.sqrt(x * x + z * z)

    cond do
      Enum.any?(@lakes, &(lake_distance(&1, x, z) <= within)) -> :lake
      t = Terrain.loaded() -> ring(x, z, within) |> Enum.find_value(fn {px, pz} -> terrain_kind(t, px, pz) end)
      r >= @shore - within -> :ocean
      true -> nil
    end
  end

  @doc """
  May someone standing at `{px, pz}` cast a line onto `{bx, bz}` (metres)? `{:ok, kind}` when they
  stand by water of that kind, the spot is that water and within reach; `{:error, reason}` otherwise.
  """
  def cast(px, pz, bx, bz) do
    standing = near(px, pz, @bank)
    landing = kind_at(bx, bz)
    reach = :math.sqrt((bx - px) * (bx - px) + (bz - pz) * (bz - pz))

    cond do
      standing == nil -> {:error, :not_at_water}
      landing == nil -> {:error, :not_on_water}
      reach > @cast_reach -> {:error, :too_far}
      true -> {:ok, landing}
    end
  end

  @doc "Within the walkable world (metres): inside the waterline plus the shallows (or the terrain's rules)."
  def walkable?(x, z) do
    case Terrain.loaded() do
      nil -> :math.sqrt(x * x + z * z) <= @walk_radius
      t -> Terrain.walkable?(t, x, z) and not Enum.any?(@lakes, &(lake_scale(&1, x, z) < 0.85))
    end
  end

  @doc "What bites in `kind` water, for a uniform `r` in [0, 1)."
  def roll(kind, r \\ :rand.uniform()) do
    table = catches(kind)
    total = Enum.reduce(table, 0, fn {_, w}, acc -> acc + w end)
    pick = r * total

    Enum.reduce_while(table, 0.0, fn {id, w}, acc ->
      if pick < acc + w, do: {:halt, id}, else: {:cont, acc + w}
    end)
    |> case do
      id when is_binary(id) -> id
      _ -> table |> List.last() |> elem(0)
    end
  end

  # 1 on the lake's edge, less inside, more outside
  defp lake_scale(l, x, z) do
    dx = (x - l.x) / l.rx
    dz = (z - l.z) / l.rz
    :math.sqrt(dx * dx + dz * dz)
  end

  defp lake_distance(l, x, z) do
    f = lake_scale(l, x, z)
    d = :math.sqrt((x - l.x) * (x - l.x) + (z - l.z) * (z - l.z))
    if f <= 1.0, do: 0.0, else: d - d / f
  end
end
