defmodule BaconWorldWeb.GroupEvents do
  @moduledoc """
  Groups' half of `BaconWorldWeb.PlayLive` (2026-10-28; `BaconWorld.Groups` keeps the groups,
  `group-ui.ts` draws the group window and the invitation).

  Client events (all reply `%{ok, ...}` or `%{ok: false, error}`):

    * `"group_invite"` `%{target}` - a character id (your target) or a name (/invite Name).
    * `"group_accept"`, `"group_decline"` - the invitation waiting for you.
    * `"group_leave"`, `"group_disband"` (the leader).
    * `"group_kick"` `%{target}`, `"group_leader"` `%{target}` (the leader; id or name).
    * `"group_chat"` `%{text}` - /g.
    * `"group_fetch"` - your group, if any.

  Pushed: `"group_update"` `%{group: view | nil}`, `"group_invite"` `%{from, from_name}`,
  `"group_notice"` `%{text}`, `"group_chat"` `%{from, name, text}`. A groupmate's kill comes as
  `{:group_xp, ...}` and is awarded here like your own (`BaconWorldWeb.GameEvents.gain_xp/3`).
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias BaconWorld.Groups
  alias Phoenix.PubSub

  @events ~w(group_invite group_accept group_decline group_leave group_disband group_kick group_leader group_chat group_fetch)
  def events, do: @events

  @doc "The character entered the world (or zoned): hear its group news, be findable by name."
  def enter(socket, %{character_id: id} = payload) do
    if Phoenix.LiveView.connected?(socket) and socket.assigns[:group_character] != id do
      if old = socket.assigns[:group_character], do: exit_world(socket, old)
      PubSub.subscribe(Bacon8.PubSub, Groups.topic(id))
      Groups.register(id, payload[:name] || "Someone")
      assign(socket, group_character: id)
    else
      socket
    end
  end

  def enter(socket, _payload), do: socket

  @doc "The character left the world: out of its group."
  def leave_world(socket) do
    case socket.assigns[:group_character] do
      nil -> socket
      id -> exit_world(socket, id) && assign(socket, group_character: nil)
    end
  end

  defp exit_world(_socket, id) do
    PubSub.unsubscribe(Bacon8.PubSub, Groups.topic(id))
    Groups.unregister(id)
    true
  end

  def handle_event("group_fetch", _params, socket), do: {:reply, %{ok: true, group: me(socket) && Groups.view(me(socket))}, socket}

  def handle_event("group_invite", %{"target" => target}, socket) when is_binary(target) do
    with_me(socket, fn id ->
      case Groups.invite(id, target) do
        {:ok, name} -> {:reply, %{ok: true, name: name}, socket}
        {:error, msg} -> {:reply, %{ok: false, error: msg}, socket}
      end
    end)
  end

  def handle_event("group_accept", _params, socket) do
    with_me(socket, fn id ->
      case Groups.accept(id) do
        {:ok, g} -> {:reply, %{ok: true, group: g}, socket}
        {:error, msg} -> {:reply, %{ok: false, error: msg}, socket}
      end
    end)
  end

  def handle_event("group_decline", _p, socket), do: simple(socket, &Groups.decline/1)
  def handle_event("group_leave", _p, socket), do: simple(socket, &Groups.leave/1)
  def handle_event("group_disband", _p, socket), do: simple(socket, &Groups.disband/1)

  def handle_event("group_kick", %{"target" => t}, socket) when is_binary(t), do: simple(socket, &Groups.kick(&1, t))
  def handle_event("group_leader", %{"target" => t}, socket) when is_binary(t), do: simple(socket, &Groups.make_leader(&1, t))
  def handle_event("group_chat", %{"text" => t}, socket) when is_binary(t), do: simple(socket, &Groups.chat(&1, t))

  def handle_event(_event, _params, socket), do: {:reply, %{ok: false, error: "bad request"}, socket}

  @doc "Group news from `BaconWorld.Groups` (PlayLive's handle_info)."
  def info({:group_update, g}, socket), do: push_event(socket, "group_update", %{group: g})
  def info({:group_invite, inv}, socket), do: push_event(socket, "group_invite", inv)
  def info({:group_notice, text}, socket), do: push_event(socket, "group_notice", %{text: text})
  def info({:group_chat, msg}, socket), do: push_event(socket, "group_chat", msg)

  def info({:group_xp, %{xp: xp}}, socket) do
    # (the dead earn nothing: the killer's LiveView only counted the living, but one may have
    # died since)
    if socket.assigns[:is_dead?], do: socket, else: BaconWorldWeb.GameEvents.gain_xp(socket, xp, :group)
  end

  def info({:group_coins, coins}, socket) do
    total = if id = me(socket), do: BaconWorld.Inventory.coins(id), else: nil
    push_event(socket, "group_coins", %{coins: coins, total_coins: total})
  end

  def info(_msg, socket), do: socket

  defp simple(socket, fun) do
    with_me(socket, fn id ->
      case fun.(id) do
        :ok -> {:reply, %{ok: true}, socket}
        {:error, msg} -> {:reply, %{ok: false, error: msg}, socket}
      end
    end)
  end

  defp with_me(socket, fun) do
    case me(socket) do
      nil -> {:reply, %{ok: false, error: "You aren't in the world."}, socket}
      id -> fun.(id)
    end
  end

  defp me(socket), do: socket.assigns[:group_character]
end
