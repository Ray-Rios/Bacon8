defmodule Bacon8Web.StaticReload do
  @moduledoc """
  Reloads a page whose scripts and styles are from an earlier deploy.

  The root layout marks `app.js` and `app.css` with `phx-track-static`. After a deploy, a tab that
  was already open reconnects its LiveView to the new server but keeps running the old JavaScript
  (2026-10-26: new models and features in Bacon World needed a hard refresh). On a connected root
  mount, when `Phoenix.LiveView.static_changed?/1` says the client's assets aren't the deployed
  ones, this sends the browser to the same address with a full page load, which fetches the new
  ones. Every LiveView gets it through `use Bacon8Web, :live_view`.

  Only in production (`static_changed?/1` compares against the digest manifest, which only a
  release has), and only for root LiveViews (nested ones can't ask).
  """
  import Phoenix.LiveView

  def on_mount(:default, params, _session, socket) do
    # (a LiveView rendered by a controller, not the router, has no address and no handle_params)
    if params != :not_mounted_at_router and is_nil(socket.parent_pid) and connected?(socket) and static_changed?(socket) do
      # The address is known in handle_params (LiveView runs this hook even for views without one).
      {:cont, attach_hook(socket, :b8_static_reload, :handle_params, fn _params, uri, socket -> {:halt, redirect(socket, external: uri)} end)}
    else
      {:cont, socket}
    end
  end
end
