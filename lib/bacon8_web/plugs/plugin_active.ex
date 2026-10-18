defmodule Bacon8Web.Plugs.PluginActive do
  @moduledoc """
  The gate in front of every plugin route: 404 while the plugin is inactive.

  Options:

    * `slug:` (required) - the plugin
    * `page: true` - a plugin *page*: assigns `:bacon8_plugin`, which the root
      layout uses to give games a plain black background instead of the
      user's animated one
    * `game_slug:` - an API route: sets `params["game_slug"]` (and
      `path_params`) the way the hub's `/api/games/:game_slug/...` routes do,
      so controllers shared with those routes work unchanged
  """
  import Plug.Conn

  def init(opts) do
    %{slug: Keyword.fetch!(opts, :slug), page: Keyword.get(opts, :page, false), game_slug: Keyword.get(opts, :game_slug)}
  end

  def call(conn, %{slug: slug} = opts) do
    if Bacon8.Plugins.active?(slug) do
      conn
      |> maybe_assign_page(opts)
      |> maybe_put_game_slug(opts)
    else
      conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not found") |> halt()
    end
  end

  defp maybe_assign_page(conn, %{page: true, slug: slug}), do: assign(conn, :bacon8_plugin, slug)
  defp maybe_assign_page(conn, _), do: conn

  defp maybe_put_game_slug(conn, %{game_slug: game_slug}) when is_binary(game_slug) do
    %{
      conn
      | params: Map.put(conn.params, "game_slug", game_slug),
        path_params: Map.put(conn.path_params, "game_slug", game_slug)
    }
  end

  defp maybe_put_game_slug(conn, _), do: conn
end
