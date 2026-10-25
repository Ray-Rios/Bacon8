defmodule BaconWorldWeb.MountEvents do
  @moduledoc """
  Riding (`BaconWorld.Mounts`), the mount half of `BaconWorldWeb.PlayLive`.

  Client events (all reply):

    * `"mounts_fetch"` - the mounts there are, the ones you may ride, and the one you
      are on (`%{catalog, owned, mount}`).
    * `"mount_summon"` `%{id}` - climb on (`id` optional: your last mount, else the
      first you own). Refused while dead or if you don't own it.
    * `"mount_dismount"` - climb off.

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

  @doc "The mount being ridden (its catalogue map), or nil."
  def mounted(socket), do: Mounts.get(socket.assigns[:mount])

  def handle_event("mounts_fetch", _params, socket) do
    {:reply, %{catalog: Mounts.catalog_payload(), owned: Mounts.owned(socket.assigns.current_user), mount: socket.assigns[:mount]}, socket}
  end

  def handle_event("mount_summon", params, socket) do
    user = socket.assigns.current_user
    owned = Mounts.owned(user)
    want = params["id"] || socket.assigns[:last_mount] || List.first(owned)

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
    {:reply, %{ok: true}, dismount(socket)}
  end

  @doc "Climbs off (on death, logout, or asked). Safe when not mounted."
  def dismount(socket) do
    if socket.assigns[:mount], do: socket |> set_mount(nil) |> push_event("mount_changed", %{mount: nil}), else: socket
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
