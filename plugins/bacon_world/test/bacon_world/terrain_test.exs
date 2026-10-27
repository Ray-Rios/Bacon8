defmodule BaconWorld.TerrainTest do
  # The terrain (2026-10-26) on a small made-up zone: heights between samples, the sea and a named
  # lake, where people may walk, and BaconWorld.Water's rules with a terrain. The client's side is
  # assets/js/__tests__/terrain.test.ts (the same little world).
  use ExUnit.Case, async: false

  alias BaconWorld.{Models, Terrain, Water}

  # 5 x 5 samples, 4 m apart (16 m across), corner at (-8, -8); the west column is the sea, one
  # sample east of the middle is a lake. Heights in metres.
  @metres [
    [-6, -1, 1, 2, 3],
    [-6, -1, 1, 2, 3],
    [-6, -1, 1, -4, 3],
    [-6, -1, 1, 2, 3],
    [-6, -1, 1, 2, 3]
  ]

  setup do
    dir = Path.join(System.tmp_dir!(), "b8_terrain_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "World/Terrain"))
    h = for row <- @metres, m <- row, into: <<>>, do: <<round((m + 10) / 0.05)::little-unsigned-16>>
    w = for row <- @metres, {m, i} <- Enum.with_index(row), into: <<>>, do: <<if(m < 0, do: if(i == 3, do: 2, else: 1), else: 0)>>
    File.write!(Path.join(dir, "World/Terrain/tiny_h.bin"), h)
    File.write!(Path.join(dir, "World/Terrain/tiny_w.bin"), w)

    zone = %{
      id: "tiny", name: "Tiny", dir: "World/Terrain", size_m: 16.0, samples: 5, water_samples: 5,
      x0: -8.0, z0: -8.0, lo: -10.0, step: 0.05, sea: 0.0, margin: 2.0,
      lakes: %{2 => %{id: "tarn", name: "the Tarn"}}
    }

    Application.put_env(:bacon8, Models, roots: [dir])
    Application.put_env(:bacon8, Terrain, zone: "tiny", zones: %{"tiny" => zone})
    Terrain.reload()

    on_exit(fn ->
      # forget the tiny zone's grids, then back to flat (config/test.exs)
      Application.put_env(:bacon8, Terrain, zone: "tiny", zones: %{"tiny" => zone})
      Terrain.reload()
      Application.put_env(:bacon8, Terrain, zone: nil)
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    :ok
  end

  test "heights at the samples and between them" do
    assert_in_delta Terrain.height(-8.0, -8.0), -6.0, 1.0e-6
    assert_in_delta Terrain.height(0.0, 0.0), 1.0, 1.0e-6
    assert_in_delta Terrain.height(-6.0, -8.0), -3.5, 1.0e-6
    assert_in_delta Terrain.height(-100.0, 0.0), -6.0, 1.0e-6
  end

  test "water: the sea, a named lake, land" do
    assert Terrain.water(-8.0, 0.0) == :ocean
    assert Terrain.water(4.0, 0.0) == {:lake, "tarn", "the Tarn"}
    assert Terrain.water(0.0, 0.0) == nil
  end

  test "walking: wading is fine, deep water and the margin are not" do
    assert Terrain.walkable?(0.0, 0.0)
    assert Terrain.walkable?(-4.0, 0.0)
    refute Terrain.walkable?(-7.5, 0.0)
    refute Terrain.walkable?(0.0, 7.5)
  end

  test "Water follows the terrain: kinds, names, the bank, casting" do
    assert Water.kind_at(-8.0, 0.0) == :ocean
    assert Water.kind_at(4.0, 0.0) == :lake
    assert Water.name_at(4.0, 0.0) == "the Tarn"
    assert Water.near(0.0, 0.0, 3.0) == :lake
    assert {:ok, :ocean} = Water.cast(-3.0, 0.0, -7.5, 0.0)
    assert {:error, :not_at_water} = Water.cast(2.0, 6.0, 4.0, 0.0)
  end

  test "the payload carries the files and the numbers in scene units" do
    p = Terrain.payload(2.0)
    assert p.heights == "/models/World/Terrain/tiny_hd.bin"
    assert p.size == 32.0 and p.x0 == -16.0 and p.sea == 0.0
    assert [%{label: 2, id: "tarn"}] = p.lakes
  end

  test "without files the zone is flat and the old island rules hold" do
    Application.put_env(:bacon8, Terrain, zone: nil)
    Terrain.reload()
    assert Terrain.loaded() == nil
    assert Terrain.height(5.0, 5.0) == 0.0
    assert Water.kind_at(0.0, 0.0) == nil
    assert Water.kind_at(200.0, 0.0) == :ocean
    assert Terrain.payload(1.0) == nil
  end
end
