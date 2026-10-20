defmodule Bacon8Web.Plugs.ModelsGuard do
  @moduledoc """
  Serves only what a 3D client loads from `/models`.

  The models volume also holds what the models were made from: `.blend` and
  `.blend1` scenes, `.zip` downloads and licence text files. Plenty of asset
  licences allow using a model in a product but not handing out its source
  files, and no client needs them, so anything under `/models` that is not a
  runtime format answers 404 here, before `Plug.Static` can serve it.

  Default-deny on purpose: an unknown or percent-encoded extension is refused.
  """
  import Plug.Conn

  @runtime ~w(.gltf .glb .bin .fbx .obj .mtl .png .jpg .jpeg .webp .ktx2 .tga)

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["models" | rest]} = conn, _opts) when rest != [] do
    ext = rest |> List.last() |> Path.extname() |> String.downcase()

    if ext in @runtime do
      conn
    else
      conn |> send_resp(404, "Not Found") |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
