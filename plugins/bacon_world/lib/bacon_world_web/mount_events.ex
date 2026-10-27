defmodule BaconWorldWeb.MountEvents do
  @moduledoc """
  Riding (`BaconWorld.Mounts`), the mount half of `BaconWorldWeb.PlayLive`.

  Client events (all reply):

    * `"mounts_fetch"` - the mounts there are, the ones you may ride, and the one you
      are on (`%{catalog, owned, mount}`).
    * `"mount_summon"` `%{id}` - climb on (`id` optional: the mount you chose at the
      stable, `settings["mount"]`, else the first you own). Refused while dead or if you
      don't own it.
    * `"mount_dismount"` - climb off. Refused in the air (`reason` "airborne"): land
      first. For a few seconds after climbing off, the moves are checked as if still
      mounted (`move_mount/1`), so a fall from the saddle isn't "corrected" in mid-air.
    * `"stable_open"` `%{id}` - the stablemaster (`BaconWorld.Merchants`, kind
      "stable"): every mount, which you own, the one you ride.
    * `"stable_choose"` `%{id, mount}` - ride that one from now on (saved on the
      character; if you are riding another, you switch).

  The mount is in the socket (`:mount`, the mount's id) and in the zone presence
  (`mount`), so everyone draws you on it; `"zone_mount"` tells the zone at once.
  `PlayLive` reads `mounted/1` for the move checks (a flying mount may go high and
  fast) and `GameEvents` refuses swings from the saddle and dismounts the dead.
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias BaconWorld.Mounts
  alias Bacon8Web.Presence
  alias Phoenix.PubSub

  # after climbing off, this long the moves are checked as if mounted (a fall)
  @grace_ms 8_000
  # higher than this (scene units, ~2 m) is in the air: no climbing off
  @ground_y 2.5

  @doc "The mount being ridden (its catalogue map), or nil."
  def mounted(socket), do: Mounts.get(socket.assigns[:mount])

  @doc """
  The mount the move checks should allow for: the one being ridden, or, just after
  climbing off (or being knocked off by dying), the one you were on.
  """
  def move_mount(socket) do
    mounted(socket) ||
      case socket.assigns[:mount_grace] do
        {id, until} -> if System.monotonic_time(:millisecond) < until, do: Mounts.get(id), else: nil
        _ -> nil
      end
  end

  def handle_event("mounts_fetch", _params, socket) do
    {:reply, %{catalog: Mounts.catalog_payload(), owned: Mounts.owned(socket.assigns.current_user), mount: socket.assigns[:mount]}, socket}
  end

  def handle_event("mount_summon", params, socket) do
    user = socket.assigns.current_user
    owned = Mounts.owned(user)
    chosen = preferred(socket)
    want = params["id"] || (chosen in owned && chosen) || List.first(owned)

    cond do
      socket.assigns[:is_dead?] -> {:reply, %{ok: false, reason: "dead"}, socket}
      is_nil(want) -> {:reply, %{ok: false, reason: "no_mount"}, socket}
      not Mounts.owns?(user, want) -> {:reply, %{ok: false, reason: "not_owned"}, socket}
      true ->
        socket = set_mount(socket, want)
        {:reply, %{ok: true, mount: want, spec: Mounts.catalog_payload()[want]}, socket}
    end
  end

  def handle_event("mount_dismount", _params, socket) do
    me = socket.assigns[:current_character_runtime]
    pos = (me && me[:position]) || %{}
    y = pos[:y] || 0.0
    # height above what's under you (the terrain or the water's surface; 0 on flat ground)
    above = y - BaconWorld.Terrain.surface_units(pos[:x] || 0.0, pos[:z] || 0.0, BaconWorld.Mobs.Brain.u())

    if socket.assigns[:mount] && above > @ground_y,
      do: {:reply, %{ok: false, reason: "airborne"}, socket},
      else: {:reply, %{ok: true}, dismount(socket)}
  end

  def handle_event("stable_open", %{"id" => id}, socket) do
    case stablemaster(socket, id) do
      {:ok, m} ->
        {:reply,
         %{
           ok: true,
           stable: %{id: m.id, name: m.name, title: m.title},
           catalog: Mounts.catalog_payload(),
           order: Enum.map(Mounts.all(), & &1.id),
           owned: Mounts.owned(socket.assigns.current_user),
           chosen: preferred(socket),
           riding: socket.assigns[:mount],
           store: Mounts.store_paths()
         }, socket}

      {:error, msg} ->
        {:reply, %{ok: false, error: msg}, socket}
    end
  end

  def handle_event("stable_choose", %{"id" => id, "mount" => mount}, socket) do
    user = socket.assigns.current_user

    with {:ok, _m} <- stablemaster(socket, id),
         true <- Mounts.owns?(user, mount) || {:error, "That mount isn't yours."},
         %{character_id: cid} <- socket.assigns[:current_character_runtime] || {:error, "You aren't in the world."} do
      BaconWorld.World.merge_settings(BaconWorld.World.by_id_query(cid), %{"mount" => mount})
      socket = assign(socket, chosen_mount: mount)
      riding = socket.assigns[:mount]
      socket = if riding && riding != mount, do: set_mount(socket, mount), else: socket
      {:reply, %{ok: true, chosen: mount, riding: socket.assigns[:mount], spec: Mounts.catalog_payload()[mount]}, socket}
    else
      {:error, msg} -> {:reply, %{ok: false, error: msg}, socket}
      _ -> {:reply, %{ok: false, error: "You can't do that right now."}, socket}
    end
  end

  @doc "Climbs off (on death, logout, or asked). Safe when not mounted."
  def dismount(socket) do
    case socket.assigns[:mount] do
      nil ->
        socket

      id ->
        socket
        |> assign(mount_grace: {id, System.monotonic_time(:millisecond) + @grace_ms})
        |> set_mount(nil)
        |> push_event("mount_changed", %{mount: nil})
    end
  end

  # The mount chosen at the stable (cached in the socket after the first read).
  defp preferred(socket) do
    case socket.assigns[:chosen_mount] do
      nil ->
        with %{character_id: cid} <- socket.assigns[:current_character_runtime],
             {:ok, c} <- BaconWorld.World.fetch_character(cid) do
          (c.settings || %{})["mount"]
        else
          _ -> nil
        end

      id ->
        id
    end
  end

  defp stablemaster(socket, id) do
    me = socket.assigns[:current_character_runtime]

    with %{} <- me || {:error, "You aren't in the world."},
         %{kind: "stable"} = m <- BaconWorld.Merchants.get(id) || {:error, "There's no stablemaster here."},
         true <- BaconWorld.Merchants.near?(m, {me.position.x, me.position.z}) || {:error, "You are too far away to talk to #{m.name}."} do
      {:ok, m}
    else
      %{} -> {:error, "There's no stablemaster here."}
      err -> err
    end
  end

  defp set_mount(socket, id) do
    me = socket.assigns[:current_character_runtime]
    topic = socket.assigns[:current_zone_topic]
    key = socket.assigns[:current_presence_key]

    if topic && key do
      Presence.update(self(), topic, key, &Map.put(&1, :mount, id))
      if me, do: PubSub.broadcast(Bacon8.PubSub, topic, {:zone_mount, %{character_id: me.character_id, mount: id}})
    end

    assign(socket, mount: id, last_mount: id || socket.assigns[:last_mount])
  end

  @doc "Someone's mount changed (pushed unless it is us)."
  def zone_mount(%{character_id: id} = payload, socket) do
    me = socket.assigns[:current_character_runtime]
    if me && me.character_id == id, do: socket, else: push_event(socket, "zone_mount", payload)
  end
end
