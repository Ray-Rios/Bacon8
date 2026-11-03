defmodule BaconWorld.TerrainFiles do
  @moduledoc """
  Reading and writing a zone's terrain files (2026-11-02), the same formats
  `library/pipeline/scripts/terrain_build.py` writes for Crater Lake (`BaconWorld.Terrain`):

    * `<id>_h.bin`   heights for the server: uint16 LE `k`, `samples`², row 0 north; metres = `lo + k * step`
    * `<id>_hd.bin`  the same `k` for the browser: int16 2-D differences, high bytes then low bytes
                     (and `.bin.gz` beside it, which `/models` serves gzip-encoded); `terrain.ts` decodes it
    * `<id>_w.bin`   water, uint8, `water_samples`², 0 land, 1 water
    * `<id>_preview.png`  a 512 px shaded picture for /admin/bacon_world/world
    * `<id>.json`    the numbers (also in the zone's `meta`)

  And the heightmaps World Creator reads and writes: 16-bit greyscale PNG and 16-bit RAW (big- or
  little-endian), square, any size, 0..65535 between a minimum and a maximum (World Creator's
  Min/Max readout) given beside the file.

  **Heights are a grid**: `%{n: samples, bin: <<float32 native, row by row>>}` (`grid/2`, `at/3`,
  `row/2`), 17 MB for a 2049² zone. They were tuples of floats until the first production run
  (2026-11-02): over a gigabyte for one zone, and the pod (1 GiB limit) was killed mid-zone. Everything
  here works a row at a time.
  """

  import Bitwise

  @step 0.05

  def step, do: @step

  # ---------------------------------------------------------------- the grid

  @doc "A grid from rows (each a list or tuple of floats): mostly for tests."
  def grid(rows) do
    rows = Enum.map(Enum.to_list(rows_list(rows)), &rows_list/1)
    n = length(rows)
    %{n: n, bin: IO.iodata_to_binary(for(r <- rows, do: for(h <- r, into: <<>>, do: <<h * 1.0::float-32-native>>)))}
  end

  defp rows_list(t) when is_tuple(t), do: Tuple.to_list(t)
  defp rows_list(l) when is_list(l), do: l

  @doc "A grid from `n` rows given by `fun.(j)` (a list of `n` floats each), built a row at a time."
  def build(n, fun) do
    bin =
      IO.iodata_to_binary(
        for j <- 0..(n - 1) do
          # each row's lists are garbage at once: collect every 64 rows so the heap doesn't grow
          # to hundreds of MB before the VM gets round to it (the pod's memory limit is 1 GiB)
          if rem(j, 64) == 63, do: :erlang.garbage_collect()
          for(h <- fun.(j), into: <<>>, do: <<h * 1.0::float-32-native>>)
        end
      )

    true = byte_size(bin) == n * n * 4
    %{n: n, bin: bin}
  end

  @doc "Height at column `i`, row `j`."
  def at(%{n: n, bin: bin}, i, j) do
    <<v::float-32-native>> = :binary.part(bin, (j * n + i) * 4, 4)
    v
  end

  @doc "Row `j` as a list of floats."
  def row(%{n: n, bin: bin}, j), do: for(<<v::float-32-native <- :binary.part(bin, j * n * 4, n * 4)>>, do: v)

  @doc "{lowest, highest}."
  def range(%{n: n} = g) do
    Enum.reduce(0..(n - 1), {1.0e9, -1.0e9}, fn j, {lo, hi} ->
      r = row(g, j)
      {min(lo, Enum.min(r)), max(hi, Enum.max(r))}
    end)
  end

  # ---------------------------------------------------------------- the zone's files

  @doc """
  Writes a zone's terrain files from a grid (metres) into `dir`. `sea` is the water level (m).
  Returns the numbers for the zone's `meta` (`lo`, `hi`, `step`, `samples`, `water_samples`, `sea`).
  """
  def write_zone(dir, id, %{n: n} = g, sea) do
    File.mkdir_p!(dir)
    {lo, hi} = range(g)
    lo = Float.floor(lo)
    hi = Float.ceil(hi)

    # one pass over the rows: the server's heights, and the browser's 2-D differences
    {h_parts, highs, lows, _prev} =
      Enum.reduce(0..(n - 1), {[], [], [], nil}, fn j, {hs, his, los, prev_d} ->
        if rem(j, 64) == 63, do: :erlang.garbage_collect()
        k = Enum.map(row(g, j), &(round((&1 - lo) / @step) |> max(0) |> min(65535)))
        d = row_diff(k)

        d2 =
          case prev_d do
            nil -> d
            p -> [hd(d) | Enum.zip_with(tl(d), tl(p), &(&1 - &2))]
          end

        hrow = for v <- k, into: <<>>, do: <<v::little-unsigned-16>>
        hi_row = for v <- d2, into: <<>>, do: <<band(v, 0xFFFF) >>> 8>>
        lo_row = for v <- d2, into: <<>>, do: <<band(v, 0xFF)>>
        {[hrow | hs], [hi_row | his], [lo_row | los], d}
      end)

    File.write!(Path.join(dir, "#{id}_h.bin"), Enum.reverse(h_parts))
    hd = IO.iodata_to_binary([Enum.reverse(highs), Enum.reverse(lows)])
    File.write!(Path.join(dir, "#{id}_hd.bin"), hd)
    File.write!(Path.join(dir, "#{id}_hd.bin.gz"), :zlib.gzip(hd))

    wn = div(n - 1, 2) + 1

    water =
      for j <- 0..(wn - 1) do
        r = row(g, min(j * 2, n - 1)) |> List.to_tuple()
        for i <- 0..(wn - 1), into: <<>>, do: if(elem(r, min(i * 2, n - 1)) < sea, do: <<1>>, else: <<0>>)
      end

    File.write!(Path.join(dir, "#{id}_w.bin"), water)
    File.write!(Path.join(dir, "#{id}_preview.png"), preview_png(g, 512, lo, hi, sea))

    meta = %{"lo" => lo, "hi" => hi, "step" => @step, "samples" => n, "water_samples" => wn, "sea" => sea}
    File.write!(Path.join(dir, "#{id}.json"), Jason.encode!(meta, pretty: true))
    meta
  end

  defp row_diff([first | rest]) do
    {_, out} = Enum.reduce(rest, {first, [first]}, fn v, {prev, acc} -> {v, [v - prev | acc]} end)
    Enum.reverse(out)
  end

  @doc "Reads `<id>_h.bin` back as a grid of metres."
  def read_grid(path, samples, lo, step) do
    bin = File.read!(path)
    build(samples, fn j -> for <<v::little-unsigned-16 <- :binary.part(bin, j * samples * 2, samples * 2)>>, do: lo + v * step end)
  end

  # ---------------------------------------------------------------- the preview

  @doc "A shaded colour picture of the heights, `size` px square (PNG)."
  def preview_png(%{n: n} = g, size, _lo, _hi, sea) do
    f = (n - 1) / (size - 1)
    at = fn i, j -> at(g, clampi(i, n), clampi(j, n)) end

    pixels =
      for y <- 0..(size - 1) do
        j = round(y * f)

        for x <- 0..(size - 1), into: <<>> do
          i = round(x * f)
          h = at.(i, j)
          # light from the north-west
          dx = at.(i + 2, j) - at.(i - 2, j)
          dz = at.(i, j + 2) - at.(i, j - 2)
          shade = clampf(0.75 + (-dx - dz) * 0.02, 0.35, 1.25)
          {r, gr, b} = colour(h, sea)
          <<clamp8(r * shade), clamp8(gr * shade), clamp8(b * shade)>>
        end
      end

    png(size, size, 8, 2, pixels)
  end

  defp colour(h, sea) when h < sea do
    d = clampf((sea - h) / 60.0, 0.0, 1.0)
    {40 - 20 * d, 110 - 50 * d, 170 - 60 * d}
  end

  defp colour(h, sea) do
    a = h - sea

    cond do
      a < 3 -> {200, 190, 140}
      a < 120 -> {80 + a * 0.3, 140 - a * 0.1, 70}
      a < 350 -> {120 + (a - 120) * 0.2, 128 - (a - 120) * 0.1, 80}
      a < 600 -> {140, 130, 120}
      true -> {235, 235, 240}
    end
  end

  # ---------------------------------------------------------------- World Creator heightmaps

  @doc "A 16-bit greyscale PNG of the heights, 0..65535 between `lo` and `hi`."
  def export_png16(%{n: n} = g, lo, hi) do
    span = max(hi - lo, 1.0e-6)
    lines = for j <- 0..(n - 1), do: for(h <- row(g, j), into: <<>>, do: <<norm16(h, lo, span)::big-unsigned-16>>)
    png(n, n, 16, 0, lines)
  end

  @doc "16-bit RAW (big-endian, as World Creator writes it) of the heights, 0..65535 between `lo` and `hi`."
  def export_raw16(%{n: n} = g, lo, hi) do
    span = max(hi - lo, 1.0e-6)
    IO.iodata_to_binary(for j <- 0..(n - 1), do: for(h <- row(g, j), into: <<>>, do: <<norm16(h, lo, span)::big-unsigned-16>>))
  end

  defp norm16(h, lo, span), do: round((h - lo) / span * 65535) |> max(0) |> min(65535)

  @doc """
  A World Creator heightmap (PNG or RAW 16-bit) as a grid of metres, resampled to `samples` square.
  `opts`: `:min`, `:max` (metres for 0 and 65535), `:endian` (`:big` or `:little`, RAW only).
  `{:ok, grid}` or `{:error, message}`.
  """
  def import_heightmap(bin, samples, opts) do
    lo = opts[:min] * 1.0
    hi = opts[:max] * 1.0

    with {:ok, n, big} <- decode(bin, opts[:endian] || :big) do
      # big: n² unsigned 16-bit big-endian samples, one binary
      scale = (hi - lo) / 65535
      {:ok, resample16(big, n, samples, fn v -> lo + v * scale end)}
    end
  end

  # -> {:ok, n, <<n² uint16 big-endian>>}
  defp decode(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = png, _), do: decode_png16(png)

  defp decode(raw, endian) do
    count = div(byte_size(raw), 2)
    n = round(:math.sqrt(count))

    cond do
      rem(byte_size(raw), 2) != 0 or n * n != count ->
        {:error, "A RAW heightmap must be 16-bit and square (this one is #{byte_size(raw)} bytes)."}

      endian == :little ->
        {:ok, n, for(<<v::little-unsigned-16 <- raw>>, into: <<>>, do: <<v::big-unsigned-16>>)}

      true ->
        {:ok, n, raw}
    end
  end

  # 16-bit greyscale PNGs only (World Creator's height export); not interlaced
  defp decode_png16(<<_sig::binary-8, rest::binary>>) do
    chunks = png_chunks(rest, [])

    case List.keyfind(chunks, "IHDR", 0) do
      {"IHDR", <<w::32, h::32, 16, 0, _c, _f, 0>>} when w == h ->
        data = chunks |> Enum.filter(&(elem(&1, 0) == "IDAT")) |> Enum.map(&elem(&1, 1)) |> IO.iodata_to_binary()
        raw = :zlib.uncompress(data)
        {:ok, w, unfilter(raw, w * 2, 2, h)}

      {"IHDR", <<w::32, h::32, depth, colour, _::binary>>} ->
        {:error, "The PNG must be square 16-bit greyscale, not interlaced (this one is #{w}x#{h}, #{depth}-bit, colour type #{colour})."}

      _ ->
        {:error, "That isn't a PNG I can read."}
    end
  end

  defp png_chunks(<<len::32, type::binary-4, data::binary-size(len), _crc::32, rest::binary>>, acc),
    do: png_chunks(rest, [{type, data} | acc])

  defp png_chunks(_, acc), do: Enum.reverse(acc)

  # undo the PNG row filters; the image's bytes, row after row
  defp unfilter(raw, stride, bpp, h) do
    {rows, _} =
      Enum.map_reduce(0..(h - 1), :binary.copy(<<0>>, stride), fn j, prev ->
        <<filter, line::binary-size(stride)>> = :binary.part(raw, j * (stride + 1), stride + 1)
        cur = unfilter_line(filter, line, prev, bpp)
        {cur, cur}
      end)

    IO.iodata_to_binary(rows)
  end

  defp unfilter_line(0, line, _prev, _bpp), do: line

  defp unfilter_line(2, line, prev, _bpp) do
    for {a, b} <- Enum.zip(:binary.bin_to_list(line), :binary.bin_to_list(prev)), into: <<>>, do: <<band(a + b, 255)>>
  end

  defp unfilter_line(f, line, prev, bpp) when f in [1, 3, 4] do
    up = prev |> :binary.bin_to_list() |> List.to_tuple()

    {out, _} =
      line
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {x, i}, {acc, seen} ->
        a = if i >= bpp, do: Map.fetch!(seen, i - bpp), else: 0
        b = elem(up, i)
        c = if i >= bpp, do: elem(up, i - bpp), else: 0

        p =
          case f do
            1 -> a
            3 -> div(a + b, 2)
            4 -> paeth(a, b, c)
          end

        v = band(x + p, 255)
        {[v | acc], Map.put(seen, i, v)}
      end)

    out |> Enum.reverse() |> :binary.list_to_bin()
  end

  defp paeth(a, b, c) do
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  # bilinear resampling of n² uint16 (big-endian, one binary) to a `samples` grid, through `f`
  defp resample16(big, n, samples, f) do
    s = (n - 1) / (samples - 1)
    v = fn i, j -> <<x::big-unsigned-16>> = :binary.part(big, (j * n + i) * 2, 2); x end

    build(samples, fn j ->
      gj = j * s
      j0 = min(trunc(gj), n - 2)
      fj = gj - j0

      for i <- 0..(samples - 1) do
        gi = i * s
        i0 = min(trunc(gi), n - 2)
        fi = gi - i0
        a = v.(i0, j0) * (1 - fi) + v.(i0 + 1, j0) * fi
        b = v.(i0, j0 + 1) * (1 - fi) + v.(i0 + 1, j0 + 1) * fi
        f.(a * (1 - fj) + b * fj)
      end
    end)
  end

  # ---------------------------------------------------------------- PNG writing

  # colour 0 grey, 2 RGB; `lines` one binary per row (unfiltered)
  defp png(w, h, depth, colour, lines) do
    idat = :zlib.compress(Enum.map(lines, &[0, &1]))
    ihdr = <<w::32, h::32, depth, colour, 0, 0, 0>>
    <<137, 80, 78, 71, 13, 10, 26, 10>> <> chunk("IHDR", ihdr) <> chunk("IDAT", idat) <> chunk("IEND", <<>>)
  end

  defp chunk(type, data), do: <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>

  defp clampi(i, n), do: i |> max(0) |> min(n - 1)
  defp clampf(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp clamp8(v), do: v |> round() |> max(0) |> min(255)
end
