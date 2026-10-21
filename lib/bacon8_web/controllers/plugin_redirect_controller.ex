defmodule Bacon8Web.PluginRedirectController do
  @moduledoc """
  Permanent redirects from a renamed plugin's old paths (BACON8.md §9,
  `c:Bacon8.Plugin.previous_slugs/0`). The routes come from
  `Bacon8Web.PluginRouter.plugin_redirect_routes/0`, which puts
  `{old_prefix, new_prefix}` in `conn.private.plugin_redirect`.
  """
  use Bacon8Web, :controller

  def show(conn, _params) do
    {from, to} = conn.private.plugin_redirect
    # The route only matches `from` itself or `from/...`, so the target always
    # stays under `to` (a local /games/... or /admin/... path).
    path = to <> String.replace_prefix(conn.request_path, from, "")
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
