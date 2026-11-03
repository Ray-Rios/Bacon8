defmodule BaconWorld.WorldGenTest do
  use ExUnit.Case, async: true

  alias BaconWorld.{TerrainFiles, WorldGen}

  test "the grid: 200 cells around the lobby, nearest ring first, numbered from 1" do
    l = WorldGen.layout(200)
    assert length(l) == 200
    assert Enum.map(l, &elem(&1, 0)) == Enum.to_list(1..200)
    refute Enum.any?(l, fn {_, x, z} -> x == 0 and z == 0 end)
    assert l |> Enum.take(8) |> Enum.all?(fn {_, x, z} -> max(abs(x), abs(z)) == 1 end)
    assert l |> Enum.map(fn {_, x, z} -> {x, z} end) |> Enum.uniq() |> length() == 200
  end

  test "the world function is the same wherever it is asked (so zones meet)" do
    assert WorldGen.height(1640.0, -100.0) == WorldGen.height(1640.0, -100.0)
    hs = for x <- 0..50, do: WorldGen.height(x * 97.0, x * -61.0)
    assert Enum.all?(hs, &(&1 >= -140.0 and &1 <= 1300.0))
    assert Enum.uniq(hs) |> length() > 10
  end

  test "zone names are stable" do
    assert WorldGen.zone_name(7) == WorldGen.zone_name(7)
    assert WorldGen.zone_name(7) =~ "(7)"
  end

  test "16-bit PNG and RAW heightmaps round-trip" do
    g = TerrainFiles.grid(for j <- 0..32, do: for(i <- 0..32, do: -20.0 + i * 3.0 + j * 0.5))
    {lo, hi} = {-20.0, 102.0}
    raw = TerrainFiles.export_raw16(g, lo, hi)
    le = for <<v::big-16 <- raw>>, into: <<>>, do: <<v::little-16>>

    for {bin, opts} <- [{TerrainFiles.export_png16(g, lo, hi), []}, {raw, [endian: :big]}, {le, [endian: :little]}] do
      {:ok, back} = TerrainFiles.import_heightmap(bin, 33, [min: lo, max: hi] ++ opts)
      for j <- [0, 7, 32], i <- [0, 13, 32] do
        assert_in_delta TerrainFiles.at(back, i, j), TerrainFiles.at(g, i, j), 0.01
      end
    end

    # resampled to another size: the corners stay
    {:ok, small} = TerrainFiles.import_heightmap(raw, 17, min: lo, max: hi, endian: :big)
    assert_in_delta TerrainFiles.at(small, 16, 16), TerrainFiles.at(g, 32, 32), 0.01
  end

  test "a filtered 16-bit PNG (as other tools write it) decodes" do
    # rows filtered with Sub (1) and Up (2) and Paeth (4)
    w = 4
    vals = [[0, 1000, 2000, 3000], [100, 1100, 2100, 3100], [65535, 0, 65535, 0]]
    lines = Enum.map(vals, fn r -> for v <- r, into: <<>>, do: <<v::16>> end)
    [l0, l1, l2] = lines
    sub = fn line -> line |> :binary.bin_to_list() |> then(fn b -> Enum.with_index(b) |> Enum.map(fn {x, i} -> if i >= 2, do: Bitwise.band(x - Enum.at(b, i - 2), 255), else: x end) end) |> :binary.list_to_bin() end
    up = fn line, prev -> Enum.zip(:binary.bin_to_list(line), :binary.bin_to_list(prev)) |> Enum.map(fn {a, b} -> Bitwise.band(a - b, 255) end) |> :binary.list_to_bin() end
    raw = [<<1>>, sub.(l0), <<2>>, up.(l1, l0), <<0>>, l2] |> IO.iodata_to_binary()
    ihdr = <<w::32, 3::32, 16, 0, 0, 0, 0>>
    chunk = fn t, d -> <<byte_size(d)::32>> <> t <> d <> <<:erlang.crc32(t <> d)::32>> end
    png = <<137, 80, 78, 71, 13, 10, 26, 10>> <> chunk.("IHDR", ihdr) <> chunk.("IDAT", :zlib.compress(raw)) <> chunk.("IEND", <<>>)
    # not square: refused with a message
    assert {:error, msg} = TerrainFiles.import_heightmap(png, 3, min: 0, max: 65535)
    assert msg =~ "square"
  end

  test "write_zone writes the files the game reads" do
    dir = Path.join(System.tmp_dir!(), "bw_zone_#{System.unique_integer([:positive])}")
    g = TerrainFiles.grid(for j <- 0..16, do: for(i <- 0..16, do: -30.0 + i * 4.0 + j))
    meta = TerrainFiles.write_zone(dir, "zt", g, -16.967)
    assert meta["samples"] == 17
    assert File.stat!(Path.join(dir, "zt_h.bin")).size == 17 * 17 * 2
    assert File.stat!(Path.join(dir, "zt_hd.bin")).size == 17 * 17 * 2
    assert File.stat!(Path.join(dir, "zt_w.bin")).size == 9 * 9
    back = TerrainFiles.read_grid(Path.join(dir, "zt_h.bin"), 17, meta["lo"], meta["step"])
    assert_in_delta TerrainFiles.at(back, 9, 5), TerrainFiles.at(g, 9, 5), 0.03
    # the browser's file decodes back to the same heights (terrain.ts: undo the row, then the column differences)
    hd = File.read!(Path.join(dir, "zt_hd.bin"))
    half = div(byte_size(hd), 2)
    d2 = for i <- 0..(half - 1), do: (<<v::signed-16>> = <<:binary.at(hd, i), :binary.at(hd, half + i)>>; v)
    rows = Enum.chunk_every(d2, 17)
    {ks, _} =
      Enum.map_reduce(rows, nil, fn r, prev_d ->
        d = case prev_d do
          nil -> r
          p -> [hd(r) | Enum.zip_with(tl(r), tl(p), &(&1 + &2))]
        end
        {k, _} = Enum.map_reduce(Enum.with_index(d), 0, fn {v, i}, acc -> if i == 0, do: {Bitwise.band(v, 0xFFFF), Bitwise.band(v, 0xFFFF)}, else: {acc + v, acc + v} end)
        {k, d}
      end)
    assert_in_delta meta["lo"] + Enum.at(Enum.at(ks, 5), 9) * meta["step"], TerrainFiles.at(g, 9, 5), 0.03
    File.rm_rf!(dir)
  end

  test "a zone left \"generating\" with nothing working on it is stalled; while a worker runs it isn't" do
    z = %BaconWorld.Zone{status: "generating", number: 9_901}
    assert WorldGen.stalled?(z)
    me = self()

    WorldGen.working_on(9_901, fn _report ->
      send(me, {:inside, WorldGen.stalled?(z), WorldGen.working_on(9_901, fn _ -> :again end)})
      :done
    end)

    assert_received {:inside, false, {:error, :busy}}
    assert WorldGen.stalled?(z)
    refute WorldGen.stalled?(%BaconWorld.Zone{status: "ready", number: 9_901})
  end

  test "a process that holds another :global name still can't be a zone's worker (so runs give each zone its own)" do
    :yes = :global.register_name({__MODULE__, :run}, self())
    assert WorldGen.working_on(9_902, fn _ -> :ran end) == {:error, :busy}
    :global.unregister_name({__MODULE__, :run})
    {pid, ref} = spawn_monitor(fn -> exit(WorldGen.working_on(9_902, fn _ -> :ran end)) end)
    assert_receive {:DOWN, ^ref, :process, ^pid, :ran}
  end

  test "a crossing lands well past the next zone's own trigger band (no ping-pong)" do
    assert WorldGen.inside_m() >= WorldGen.edge_m() * 3
    # moving away from the edge never crosses, whatever the position
    assert WorldGen.neighbour_at(%{grid_x: 0, grid_z: 0}, 0.0, 0.0, 1.22, {0.0, 0.0}) == :none
    # and why, for the client to say (no silent walls)
    assert {:error, why} = WorldGen.neighbour(%{grid_x: 0, grid_z: 0}, 0.0, 0.0, 1.22, {0.0, 0.0})
    assert is_binary(why)
    assert {:error, "this zone has no place on the world grid" <> _} = WorldGen.neighbour(%{slug: "x"}, 0.0, 0.0, 1.22, nil)
    # the cooldown with a monotonic clock far below zero (the BEAM's usually is): never crossed is never "too soon"
    # (2026-11-02: a default of -10 s refused every crossing with "wait a moment")
    now = -576_460_752_303
    assert BaconWorldWeb.PlayLive.cross_cooled?(nil, now)
    refute BaconWorldWeb.PlayLive.cross_cooled?(now - 1_000, now)
    assert BaconWorldWeb.PlayLive.cross_cooled?(now - 3_000, now)
  end
end
