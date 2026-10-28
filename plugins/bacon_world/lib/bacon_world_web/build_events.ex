defmodule BaconWorldWeb.BuildEvents do
  @moduledoc """
  Build mode's half of `BaconWorldWeb.PlayLive` (2026-10-28; `BaconWorld.Building` has the rules,
  `build-world.ts` the client).

  Client events (all reply `%{ok, ...}` or `%{ok: false, error}`):

    * `"build_open"` - the catalogue as this account sees it (each entry's rule and whether it
      may use it), its role, and whether it may change the rules (admins).
    * `"build_place"` `%{asset, x, y, z, rot, scale, data}` - puts something in the world
      (metres, radians). Replies `%{ok, placement}`.
    * `"build_move"` `%{id, x, y, z, rot, scale, data}` - moves, turns, resizes or retunes one.
    * `"build_delete"` `%{id}` - removes one. Replies `%{ok, placement}` (what it was, so the
      client can undo it by placing it again).
    * `"build_rule"` `%{asset, role}` - admins: the lowest role that may place an asset.
    * `"bind_stone"` - bind your soul at the binding stone you stand by (within 5 m): Recall and
      death bring you back there. Replies `%{ok, bind}` (scene units) or the reason it can't.

  Pushed to the client: `"build_placed"` (a placement, new or changed) and `"build_removed"`
  `%{id, asset}`, for everyone in the zone. Placements arrive first with `"fetch_mobs"`.

  Nothing here trusts the client: the role, the asset and the numbers are all checked by
  `BaconWorld.Building`. A burst limit (`@burst` changes in `@window_ms`) keeps a stuck key or a
  script from flooding the zone; there is no other limit (the owner, 2026-10-26).
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias BaconWorld.Building
  alias Phoenix.PubSub

  @burst 40
  @window_ms 10_000

  @doc "Called as the character joins a zone: hear its building."
  def join(socket, slug) do
    if Phoenix.LiveView.connected?(socket), do: PubSub.subscribe(Bacon8.PubSub, Building.topic(slug))
    socket
  end

  @doc "Called as the character leaves the zone."
  def leave(socket, nil), do: socket

  def leave(socket, slug) do
    PubSub.unsubscribe(Bacon8.PubSub, Building.topic(slug))
    socket
  end

  def handle_event("build_open", _params, socket) do
    user = socket.assigns.current_user

    {:reply,
     %{ok: true, role: Building.role_of(user), admin: Building.admin?(user), roles: Building.roles(),
       catalogue: Building.catalogue_for(user)}, socket}
  end

  def handle_event("build_place", params, socket) when is_map(params) do
    act(socket, fn me, zone -> Building.place(socket.assigns.current_user, me.character_id, zone, params) end)
  end

  def handle_event("build_move", %{"id" => id} = params, socket) do
    act(socket, fn _me, zone -> Building.move(socket.assigns.current_user, zone, id, params) end)
  end

  def handle_event("build_delete", %{"id" => id}, socket) do
    act(socket, fn _me, zone -> Building.delete(socket.assigns.current_user, zone, id) end)
  end

  def handle_event("build_rule", %{"asset" => asset, "role" => role}, socket) do
    case Building.set_rule(socket.assigns.current_user, asset, role) do
      {:ok, role} -> {:reply, %{ok: true, asset: asset, role: role}, socket}
      {:error, msg} -> {:reply, %{ok: false, error: msg}, socket}
    end
  end

  def handle_event("bind_stone", _params, socket) do
    me = socket.assigns[:current_character_runtime] || socket.assigns[:current_character_payload]

    with %{position: pos, character_id: cid} <- me || {:error, "You aren't in the world."},
         false <- (socket.assigns[:is_dead?] || false) && {:error, "The dead can't bind."},
         {:ok, bind} <- Building.bind(socket.assigns.current_user, cid, socket.assigns[:mobs_zone] || "lobby", pos) do
      {:reply, %{ok: true, bind: bind}, socket}
    else
      {:error, msg} when is_binary(msg) -> {:reply, %{ok: false, error: msg}, socket}
      _ -> {:reply, %{ok: false, error: "That can't be done right now."}, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:reply, %{ok: false, error: "bad request"}, socket}

  @doc "A placement changed somewhere in the zone."
  def placed(view, socket), do: push_event(socket, "build_placed", view)

  @doc "A placement was removed."
  def removed(id, asset, socket), do: push_event(socket, "build_removed", %{id: id, asset: asset})

  # In the world, alive, not over the burst limit: run `fun` and reply with its placement.
  defp act(socket, fun) do
    now = System.monotonic_time(:millisecond)
    recent = Enum.filter(socket.assigns[:build_ops] || [], &(now - &1 < @window_ms))

    with %{} = me <- socket.assigns[:current_character_runtime] || socket.assigns[:current_character_payload] || {:error, "You aren't in the world."},
         false <- (socket.assigns[:is_dead?] || false) && {:error, "You can't build while dead."},
         true <- length(recent) < @burst || {:error, "Slow down a little."},
         {:ok, view} <- fun.(me, socket.assigns[:mobs_zone] || "lobby") do
      {:reply, %{ok: true, placement: view}, assign(socket, build_ops: [now | recent])}
    else
      # (a refused attempt counts too: it still costs the server a look at the rules)
      {:error, "Slow down a little." = msg} -> {:reply, %{ok: false, error: msg}, assign(socket, build_ops: recent)}
      {:error, msg} when is_binary(msg) -> {:reply, %{ok: false, error: msg}, assign(socket, build_ops: [now | recent])}
      _ -> {:reply, %{ok: false, error: "That can't be done right now."}, socket}
    end
  end
end
