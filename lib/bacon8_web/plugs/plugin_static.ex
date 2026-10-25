defmodule Bacon8Web.Plugs.PluginStatic do
  @moduledoc """
  Serves an installed plugin's own files: `/plugins/<slug>/<path>` comes from
  `plugins/<slug>/priv/static/<path>` (in a release, the copy under
  `priv/plugins/<slug>/static/`; see `Bacon8.Plugins.priv_dir/1`). BACON8.md §9.

  This is how a plugin hooks pictures into the site without touching core, starting
  with its game card (`priv/static/card/`, `Bacon8.GameCards`). Only pictures, video,
  fonts and JSON are served (no HTML, SVG or scripts: those would run on our origin),
  only for installed plugins, and anything else under `/plugins/` is a 404.
  """

  @behaviour Plug
  import Plug.Conn

  @exts ~w(.webp .png .jpg .jpeg .gif .avif .mp4 .webm .woff2 .json)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["plugins", slug | rest]} = conn, _opts) when rest != [] do
    ext = rest |> List.last() |> Path.extname() |> String.downcase()

    with true <- conn.method in ["GET", "HEAD"],
         true <- ext in @exts,
         true <- Enum.all?(rest, &safe_segment?/1),
         mod when not is_nil(mod) <- Bacon8.Plugins.get(slug) do
      opts = static_opts(slug)
      conn = Plug.Static.call(conn, opts)
      if conn.halted, do: conn, else: not_found(conn)
    else
      _ -> not_found(conn)
    end
  end

  def call(%Plug.Conn{path_info: ["plugins" | _]} = conn, _opts), do: not_found(conn)
  def call(conn, _opts), do: conn

  # No "..", ".", empty or slash-carrying segments (Plug.Static raises on those).
  defp safe_segment?(s), do: s not in ["", ".", ".."] and not String.contains?(s, ["/", "\\", ":", <<0>>])

  # Plug.Static's options for one plugin, built once per slug (the directory only
  # changes with a new release).
  defp static_opts(slug) do
    key = {__MODULE__, slug}

    case :persistent_term.get(key, nil) do
      nil ->
        opts =
          Plug.Static.init(
            at: "/plugins/#{slug}",
            from: Path.join(Bacon8.Plugins.priv_dir(slug), "static"),
            gzip: false,
            # Plugins rename a picture to change it; an hour keeps edits visible soon.
            cache_control_for_etags: "public, max-age=3600"
          )

        :persistent_term.put(key, opts)
        opts

      opts ->
        opts
    end
  end

  defp not_found(conn) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(404, "Not found")
    |> halt()
  end
end
