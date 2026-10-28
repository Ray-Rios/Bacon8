defmodule BaconWorld.Groups do
  @moduledoc """
  Player groups, EverQuest style (2026-10-28): invite, accept or decline, leave, kick, hand the
  lead over, disband. Up to #{20} in a group; no raids (the owner, 2026-10-28).

  Groups live in memory, not the database: a group lasts while its members are in the world. A
  member who logs out, closes the tab or loses the connection leaves it (each member's LiveView is
  monitored), and a group left with one member ends. Zoning keeps you in it.

  Everything is keyed by character id. Reads (`view/1`, `members/1`, `same_group?/2`) go straight
  to an ETS table, so the creature zones (`BaconWorld.Mobs.Brain`, looting) and the LiveViews ask
  without waiting on this process; changes go through it, one at a time.

  Each member hears about their group on `topic/1` (their character's topic):

    * `{:group_update, view | nil}` - the group changed (nil: you are no longer in one)
    * `{:group_invite, %{from, from_name}}` - someone invites you
    * `{:group_notice, text}` - a line for the chat log ("Tilda has joined the group.")
    * `{:group_chat, %{from, name, text}}` - /g
    * `{:group_xp, %{xp, mob_level}}` - your share of a groupmate's kill (`award/3`)

  Experience (`shares/2`): the kill's experience, worked out against the highest-level member
  who earns any, plus a small bonus per member, split in proportion to each member's level.
  Members the creature cons grey to get nothing, and nor do the dead or anyone more than
  `share_range_m/0` from the kill (the caller decides who is near).
  """

  use GenServer

  alias BaconWorld.Progression
  alias Phoenix.PubSub

  @max 20
  @invite_ms 60_000
  @share_range_m 100.0
  @table :bacon_world_groups

  def max_size, do: @max
  def share_range_m, do: @share_range_m

  @doc "The PubSub topic a character's group news comes on."
  def topic(character_id), do: "bacon_world:group_member:#{character_id}"

  # ---------------------------------------------------------------------------
  # Reads (ETS; never block)
  # ---------------------------------------------------------------------------

  @doc "The group a character is in: `%{id, leader, members: [%{id, name}]}` or nil."
  def view(character_id) do
    with tab when tab != :undefined <- :ets.whereis(@table),
         [{_, gid}] <- :ets.lookup(tab, {:member, character_id}),
         [{_, g}] <- :ets.lookup(tab, {:group, gid}) do
      g
    else
      _ -> nil
    end
  end

  @doc "The character ids in a character's group, itself included (`[id]` when not in one)."
  def members(character_id) do
    case view(character_id) do
      %{members: ms} -> Enum.map(ms, & &1.id)
      nil -> [character_id]
    end
  end

  @doc "True when two characters are in the same group."
  def same_group?(a, b) when is_binary(a) and is_binary(b) do
    case view(a) do
      %{members: ms} -> Enum.any?(ms, &(&1.id == b))
      nil -> false
    end
  end

  def same_group?(_a, _b), do: false

  # ---------------------------------------------------------------------------
  # Changes
  # ---------------------------------------------------------------------------

  @doc "A character entered the world (its LiveView, `pid`, is watched: it leaving leaves the group)."
  def register(character_id, name, pid \\ self()), do: call({:register, character_id, name, pid})

  @doc "A character left the world: it leaves its group."
  def unregister(character_id), do: call({:unregister, character_id})

  @doc "Invites `target` (a character id, or a name of someone in the world). `{:ok, name}` or `{:error, msg}`."
  def invite(from, target), do: call({:invite, from, target})

  @doc "Accepts the invite waiting for you. `{:ok, view}` or `{:error, msg}`."
  def accept(character_id), do: call({:accept, character_id})

  @doc "Declines the invite waiting for you."
  def decline(character_id), do: call({:decline, character_id})

  @doc "Leaves your group."
  def leave(character_id), do: call({:leave, character_id})

  @doc "The leader removes a member (by id or name)."
  def kick(leader, target), do: call({:kick, leader, target})

  @doc "The leader hands the lead to a member (by id or name)."
  def make_leader(leader, target), do: call({:make_leader, leader, target})

  @doc "The leader ends the group."
  def disband(leader), do: call({:disband, leader})

  @doc "/g: a line to everyone in your group. `:ok` or `{:error, msg}`."
  def chat(character_id, text), do: call({:chat, character_id, text})

  @doc """
  Tells each groupmate in `shares` (`%{character_id => xp}`) their share of a kill; the killer's
  own share is the caller's to award. Each member's LiveView awards its own (`{:group_xp, ...}`).
  """
  def award(killer, shares, mob_level) do
    for {id, xp} <- shares, id != killer, xp > 0 do
      PubSub.broadcast(Bacon8.PubSub, topic(id), {:group_xp, %{xp: xp, mob_level: mob_level, from: killer}})
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Experience (pure)
  # ---------------------------------------------------------------------------

  @doc """
  Each eligible member's share of a kill: `levels` is `[{character_id, level}]` of the members
  near enough and alive (the killer included). Returns `%{character_id => xp}` (grey cons: 0).

  Alone this is `Progression.kill_xp/2`. In a group: the kill's experience against the highest
  level among those who earn any, times `bonus/1`, split by level (a level 20 earns twice a
  level 10's share).
  """
  def shares(mob_level, levels) do
    {earning, grey} = Enum.split_with(levels, fn {_id, l} -> Progression.con(mob_level, l) != :grey end)
    zero = Map.new(grey, fn {id, _} -> {id, 0} end)

    case earning do
      [] ->
        zero

      _ ->
        top = earning |> Enum.map(&elem(&1, 1)) |> Enum.max()
        total = Progression.kill_xp(mob_level, top) * bonus(length(earning))
        sum = earning |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        Map.merge(zero, Map.new(earning, fn {id, l} -> {id, round(total * l / sum)} end))
    end
  end

  @doc "The group bonus: 2% more experience per member beyond the first who earns a share."
  def bonus(n) when n >= 1, do: 1.0 + 0.02 * (n - 1)

  # ---------------------------------------------------------------------------
  # The server
  # ---------------------------------------------------------------------------

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  defp call(msg) do
    GenServer.call(__MODULE__, msg)
  catch
    :exit, _ -> {:error, "Groups aren't available right now."}
  end

  @impl true
  def init(_) do
    tab = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    # online: id => %{name, pid, ref}; invites: target id => %{from, at}
    {:ok, %{tab: tab, online: %{}, invites: %{}, seq: 0}}
  end

  @impl true
  def handle_call({:register, id, name, pid}, _from, s) do
    s =
      case s.online[id] do
        %{ref: ref} -> Process.demonitor(ref, [:flush]) && s
        _ -> s
      end

    ref = Process.monitor(pid)
    s = put_in(s.online[id], %{name: name, pid: pid, ref: ref})
    # still in a group (a reconnect): tell the new LiveView
    if g = view(id), do: tell(id, {:group_update, g})
    {:reply, :ok, s}
  end

  def handle_call({:unregister, id}, _from, s), do: {:reply, :ok, gone(s, id)}

  def handle_call({:invite, from, target}, _from, s) do
    g = view(from)

    with %{name: from_name} <- s.online[from] || {:error, "You aren't in the world."},
         {:ok, tid} <- find(s, target, from),
         true <- tid != from || {:error, "You can't invite yourself."},
         true <- is_nil(g) or g.leader == from || {:error, "Only the group leader may invite."},
         true <- is_nil(g) or length(g.members) < @max || {:error, "Your group is full (#{@max})."},
         nil <- view(tid) && {:error, "#{name(s, tid)} is already in a group."},
         true <- pending(s, tid, from) || {:error, "#{name(s, tid)} is considering another invitation."} do
      tell(tid, {:group_invite, %{from: from, from_name: from_name}})
      {:reply, {:ok, name(s, tid)}, put_in(s.invites[tid], %{from: from, at: now()})}
    else
      {:error, _} = e -> {:reply, e, s}
    end
  end

  def handle_call({:accept, id}, _from, s) do
    {inv, invites} = Map.pop(s.invites, id)
    s = %{s | invites: invites}

    with %{from: from, at: at} <- inv || {:error, "You have no invitation."},
         true <- now() - at < @invite_ms || {:error, "That invitation has expired."},
         true <- Map.has_key?(s.online, from) || {:error, "They are no longer in the world."},
         true <- Map.has_key?(s.online, id) || {:error, "You aren't in the world."},
         nil <- view(id) && {:error, "You are already in a group."} do
      case view(from) do
        nil ->
          {s, gid} = next_id(s)
          g = %{id: gid, leader: from, members: [member(s, from), member(s, id)]}
          store(s, g)
          :ets.insert(s.tab, [{{:member, from}, gid}, {{:member, id}, gid}])
          notice(g, "#{name(s, id)} has joined the group.")
          {:reply, {:ok, g}, s}

        %{leader: ^from} = g when length(g.members) < @max ->
          g = %{g | members: g.members ++ [member(s, id)]}
          store(s, g)
          :ets.insert(s.tab, {{:member, id}, g.id})
          notice(g, "#{name(s, id)} has joined the group.")
          {:reply, {:ok, g}, s}

        %{leader: ^from} ->
          {:reply, {:error, "That group is full."}, s}

        _ ->
          {:reply, {:error, "They are no longer leading a group."}, s}
      end
    else
      {:error, _} = e -> {:reply, e, s}
    end
  end

  def handle_call({:decline, id}, _from, s) do
    case Map.pop(s.invites, id) do
      {%{from: from}, invites} ->
        tell(from, {:group_notice, "#{name(s, id)} declines your invitation."})
        {:reply, :ok, %{s | invites: invites}}

      {nil, _} ->
        {:reply, {:error, "You have no invitation."}, s}
    end
  end

  def handle_call({:leave, id}, _from, s) do
    case view(id) do
      nil -> {:reply, {:error, "You aren't in a group."}, s}
      _ -> {:reply, :ok, drop(s, id, "has left the group.")}
    end
  end

  def handle_call({:kick, leader, target}, _from, s) do
    with %{leader: ^leader} = g <- view(leader) || {:error, "You aren't in a group."},
         {:ok, tid} <- find_member(s, g, target),
         true <- tid != leader || {:error, "Use /disband or /leave to leave your own group."} do
      tell(tid, {:group_notice, "You have been removed from the group."})
      {:reply, :ok, drop(s, tid, "has been removed from the group.")}
    else
      %{} -> {:reply, {:error, "Only the group leader may do that."}, s}
      {:error, _} = e -> {:reply, e, s}
    end
  end

  def handle_call({:make_leader, leader, target}, _from, s) do
    with %{leader: ^leader} = g <- view(leader) || {:error, "You aren't in a group."},
         {:ok, tid} <- find_member(s, g, target) do
      g = %{g | leader: tid}
      store(s, g)
      notice(g, "#{name(s, tid)} is now the leader of the group.")
      {:reply, :ok, s}
    else
      %{} -> {:reply, {:error, "Only the group leader may do that."}, s}
      {:error, _} = e -> {:reply, e, s}
    end
  end

  def handle_call({:disband, leader}, _from, s) do
    case view(leader) do
      %{leader: ^leader} = g ->
        notice(g, "The group has been disbanded.")
        end_group(s, g)
        {:reply, :ok, s}

      %{} ->
        {:reply, {:error, "Only the group leader may disband the group. (/leave to leave it.)"}, s}

      nil ->
        {:reply, {:error, "You aren't in a group."}, s}
    end
  end

  def handle_call({:chat, id, text}, _from, s) do
    text = text |> to_string() |> String.trim() |> String.slice(0, 220)

    case view(id) do
      nil ->
        {:reply, {:error, "You aren't in a group."}, s}

      _ when text == "" ->
        {:reply, :ok, s}

      g ->
        for m <- g.members, do: tell(m.id, {:group_chat, %{from: id, name: name(s, id), text: text}})
        {:reply, :ok, s}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _}, s) do
    case Enum.find(s.online, fn {_id, o} -> o.ref == ref end) do
      {id, _} -> {:noreply, gone(s, id)}
      nil -> {:noreply, s}
    end
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # ---------------------------------------------------------------------------

  # A character left the world: out of its group, its invites dropped.
  defp gone(s, id) do
    s = if view(id), do: drop(s, id, "has left the group."), else: s
    if o = s.online[id], do: Process.demonitor(o.ref, [:flush])
    invites = s.invites |> Map.delete(id) |> Enum.reject(fn {_t, i} -> i.from == id end) |> Map.new()
    %{s | online: Map.delete(s.online, id), invites: invites}
  end

  # Takes a member out; the lead passes on; a group of one ends.
  defp drop(s, id, why) do
    g = view(id)
    who = name(s, id)
    :ets.delete(s.tab, {:member, id})
    tell(id, {:group_update, nil})
    rest = Enum.reject(g.members, &(&1.id == id))

    case rest do
      [last] ->
        tell(last.id, {:group_notice, "#{who} #{why}"})
        tell(last.id, {:group_notice, "Your group has disbanded."})
        end_group(s, %{g | members: rest})

      [next | _] ->
        g2 = %{g | members: rest, leader: if(g.leader == id, do: next.id, else: g.leader)}
        store(s, g2)
        notice(g2, "#{who} #{why}")
        if g.leader == id, do: notice(g2, "#{next.name} is now the leader of the group.")
    end

    s
  end

  defp end_group(s, g) do
    for m <- g.members do
      :ets.delete(s.tab, {:member, m.id})
      tell(m.id, {:group_update, nil})
    end

    :ets.delete(s.tab, {:group, g.id})
  end

  defp store(s, g) do
    :ets.insert(s.tab, {{:group, g.id}, g})
    for m <- g.members, do: tell(m.id, {:group_update, g})
  end

  defp notice(g, text), do: for(m <- g.members, do: tell(m.id, {:group_notice, text}))

  defp tell(id, msg), do: PubSub.broadcast(Bacon8.PubSub, topic(id), msg)

  # Someone in the world, by id or by name (any case).
  defp find(s, target, _from) when is_binary(target) do
    cond do
      Map.has_key?(s.online, target) ->
        {:ok, target}

      true ->
        t = String.downcase(String.trim(target))

        case Enum.find(s.online, fn {_id, o} -> String.downcase(o.name || "") == t end) do
          {id, _} -> {:ok, id}
          nil -> {:error, "There is no one called #{String.trim(target)} in the world."}
        end
    end
  end

  defp find(_s, _target, _from), do: {:error, "Invite whom?"}

  defp find_member(_s, g, target) when is_binary(target) do
    t = String.downcase(String.trim(target))

    case Enum.find(g.members, &(&1.id == target or String.downcase(&1.name || "") == t)) do
      %{id: id} -> {:ok, id}
      nil -> {:error, "#{String.trim(target)} isn't in your group."}
    end
  end

  defp find_member(_s, _g, _target), do: {:error, "Who?"}

  # An invite may go out unless the target has a fresh one from someone else.
  defp pending(s, tid, from) do
    case s.invites[tid] do
      %{from: ^from} -> true
      %{at: at} -> now() - at >= @invite_ms
      nil -> true
    end
  end

  defp member(s, id), do: %{id: id, name: name(s, id)}
  defp name(s, id), do: (s.online[id] || %{})[:name] || "Someone"

  defp next_id(s), do: {%{s | seq: s.seq + 1}, "g#{s.seq + 1}"}

  defp now, do: System.monotonic_time(:millisecond)
end
