defmodule BaconWorld.KrakenRoamTest do
  # The Kraken roams the deep water on its own (2026-10-27), on a made-up zone: 1 km square, its
  # east half a deep lake, its west half dry land, far from the village.
  use ExUnit.Case, async: false

  alias BaconWorld.{Models, Terrain}
  alias BaconWorld.Mobs.Brain

  @u 2.2 / 1.8
  @n 21

  setup do
    dir = Path.join(System.tmp_dir!(), "b8_roam_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "World/Terrain"))
    # 21 x 21 samples, 50 m apart, corner at (1000, 1000): columns 0..9 land (+5 m), 10.. deep (-60 m)
    metres = for _j <- 0..(@n - 1), i <- 0..(@n - 1), do: if(i < 10, do: 5.0, else: -60.0)
    h = for m <- metres, into: <<>>, do: <<round((m + 100) / 0.05)::little-unsigned-16>>
    w = for m <- metres, into: <<>>, do: <<if(m < 0, do: 2, else: 0)>>
    File.write!(Path.join(dir, "World/Terrain/roam_h.bin"), h)
    File.write!(Path.join(dir, "World/Terrain/roam_w.bin"), w)

    zone = %{
      id: "roam", name: "Roam", dir: "World/Terrain", size_m: 1000.0, samples: @n, water_samples: @n,
      x0: 1000.0, z0: 1000.0, lo: -100.0, step: 0.05, sea: 0.0, margin: 10.0,
      lakes: %{2 => %{id: "deep", name: "the Deep"}}
    }

    Application.put_env(:bacon8, Models, roots: [dir])
    Application.put_env(:bacon8, Terrain, zone: "roam", zones: %{"roam" => zone})
    Terrain.reload()

    on_exit(fn ->
      Application.put_env(:bacon8, Terrain, zone: "roam", zones: %{"roam" => zone})
      Terrain.reload()
      Application.put_env(:bacon8, Terrain, zone: nil)
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    :rand.seed(:exsss, {3, 3, 3})
    :ok
  end

  test "left alone, it roams the deep water on its own, and never leaves it" do
    point = %{id: "k:0", camp: "k", kind: "kraken", x: 1750.0, z: 1500.0}
    m0 = Brain.spawn(point, 0)
    assert Terrain.deep?(1750.0, 1500.0)

    {m, far, all_deep} =
      Enum.reduce(0..1200, {m0, 0.0, true}, fn i, {m, far, ok} ->
        {m2, _} = Brain.tick(m, %{}, i * 100, 0.1, point)
        d = :math.sqrt(:math.pow(m2.x / @u - 1750.0, 2) + :math.pow(m2.z / @u - 1500.0, 2))
        {m2, max(far, d), ok and Terrain.deep?(m2.x / @u, m2.z / @u)}
      end)

    assert far > 60.0, "it should wander well away from where it spawned (got #{far} m)"
    assert all_deep
    assert m.state in [:idle, :wander]
  end
end
