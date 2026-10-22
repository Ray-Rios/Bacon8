defmodule Bacon8Web.Plugs.ModelsGuard do
  @moduledoc """
  Serves only what a 3D client loads from `/models`.

  The models volume also holds what the models were made from: `.blend` and
  `.blend1` scenes, `.zip` downloads and licence text files. Plenty of asset
  licences allow using a model in a product but not handing out its source
  files, and no client needs them, so anything under `/models` that is not a
  runtime format answers 404 here, before `Plug.Static` can serve it.

  Default-deny on purpose: an unknown or percent-encoded extension is refused.

  `Plug.Static` serves `/models` with `gzip: true`: a `model.glb.gz` beside
  `model.glb` is sent in its place. A `.gz` left over from an older version of the
  file would then win over the new one, so when the `.gz` is older than the file
  this plug drops the request's `accept-encoding` and the plain file goes out.
  Option `:root` is the folder `/models` serves.
  """
  import Plug.Conn

  @runtime ~w(.gltf .glb .bin .fbx .obj .mtl .png .jpg .jpeg .webp .ktx2 .tga)

  def init(opts), do: Keyword.get(opts, :root)

  def call(%Plug.Conn{path_info: ["models" | rest]} = conn, root) when rest != [] do
    ext = rest |> List.last() |> Path.extname() |> String.downcase()

    if ext in @runtime do
      skip_stale_gzip(conn, root, rest)
    else
      conn |> send_resp(404, "Not Found") |> halt()
    end
  end

  def call(conn, _root), do: conn

  defp skip_stale_gzip(conn, nil, _rest), do: conn

  defp skip_stale_gzip(conn, root, rest) do
    if Enum.any?(rest, &(&1 in ["", ".", ".."] or String.contains?(&1, ["\\", "\0"]))) do
      conn
    else
      file = Path.join([root | rest])

      with {:ok, %File.Stat{mtime: gz_time}} <- File.stat(file <> ".gz", time: :posix),
           {:ok, %File.Stat{mtime: time}} <- File.stat(file, time: :posix),
           true <- gz_time < time do
        delete_req_header(conn, "accept-encoding")
      else
        _ -> conn
      end
    end
  end
end
