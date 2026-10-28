defmodule BaconWorld.GroupsTest do
  # Groups (2026-10-28): EverQuest-style invite, accept, leave, kick, lead and disband, up to 20;
  # the experience split; looting as a group.
  use ExUnit.Case, async: false

  alias BaconWorld.{Groups, Progression}
  alias BaconWorld.Mobs.Brain

  setup do
    if Process.whereis(Groups) == nil, do: start_supervised!(Groups)
    :ok
  end

  # A character "in the world": a stand-in LiveView process, registered under a fresh id.
  defp online(name) do
    id = Ecto.UUID.generate()
    pid = spawn(fn -> receive do: (:stop -> :ok) end)
    :ok = Groups.register(id, name, pid)
    Phoenix.PubSub.subscribe(Bacon8.PubSub, Groups.topic(id))
    {id, pid}
  end

  defp uniq(name), do: name <> String.slice(Ecto.UUID.generate(), 0, 6)

  describe "experience" do
    test "alone it is the kill's experience" do
      a = Ecto.UUID.generate()
      assert Groups.shares(5, [{a, 5}]) == %{a => Progression.kill_xp(5, 5)}
    end

    test "split by level, with a bonus; grey cons earn nothing and don't count" do
      {a, b, c} = {"a", "b", "c"}
      s = Groups.shares(10, [{a, 10}, {b, 5}, {c, 1}])
      # a level 1 cons a level 10 red, not grey: three earn
      total = Progression.kill_xp(10, 10) * Groups.bonus(3)
      assert s[a] == round(total * 10 / 16)
      assert s[b] == round(total * 5 / 16)
      assert s[a] > s[b] and s[b] > s[c]

      # a level 40 sees a level 10 as grey: no share, and it doesn't drag the others' down
      s2 = Groups.shares(10, [{a, 10}, {"hi", 40}])
      assert s2["hi"] == 0
      assert s2[a] == Progression.kill_xp(10, 10)

      assert Groups.shares(1, [{"hi", 40}]) == %{"hi" => 0}
      assert Groups.bonus(1) == 1.0 and Groups.bonus(20) > Groups.bonus(6)
    end
  end

  describe "a group" do
    test "invite, accept, chat, the lead passing on, and the last one out ends it" do
      {a, _} = online(uniq("Ann"))
      {b, _} = online(uniq("Bo"))
      {c, _} = online(uniq("Cy"))

      assert {:error, _} = Groups.invite(a, a)
      assert {:ok, _} = Groups.invite(a, b)
      assert_receive {:group_invite, %{from: ^a}}
      assert {:ok, g} = Groups.accept(b)
      assert g.leader == a and Enum.map(g.members, & &1.id) == [a, b]
      assert Groups.same_group?(a, b)
      refute Groups.same_group?(a, c)
      assert Groups.members(c) == [c]

      # only the leader invites; no accepting twice
      assert {:error, msg} = Groups.invite(b, c)
      assert msg =~ "leader"
      assert {:error, _} = Groups.accept(b)

      # by name, any case
      assert {:ok, _} = Groups.invite(a, String.upcase(name_of(c)))
      assert {:ok, _} = Groups.accept(c)
      assert length(Groups.view(a).members) == 3

      :ok = Groups.chat(b, "inc!")
      assert_receive {:group_chat, %{from: ^b, text: "inc!"}}

      # the leader leaves: the next member leads
      :ok = Groups.leave(a)
      assert Groups.view(a) == nil
      assert Groups.view(b).leader == b
      # two left; one more leaves and the group is gone
      :ok = Groups.leave(c)
      assert Groups.view(b) == nil
    end

    test "kick, make leader, disband; only the leader may" do
      {a, _} = online(uniq("Ann"))
      {b, _} = online(uniq("Bo"))
      {c, _} = online(uniq("Cy"))
      for x <- [b, c], do: ({:ok, _} = Groups.invite(a, x)) && Groups.accept(x)

      assert {:error, _} = Groups.kick(b, c)
      assert {:error, _} = Groups.disband(b)
      :ok = Groups.make_leader(a, b)
      assert Groups.view(a).leader == b
      :ok = Groups.kick(b, a)
      assert Groups.view(a) == nil
      assert Groups.view(c).leader == b
      :ok = Groups.disband(b)
      assert Groups.view(b) == nil and Groups.view(c) == nil
    end

    test "declining, a busy target, and someone who leaves the world" do
      {a, _} = online(uniq("Ann"))
      {b, _} = online(uniq("Bo"))
      {c, cpid} = online(uniq("Cy"))
      {:ok, _} = Groups.invite(a, b)
      :ok = Groups.decline(b)
      assert_receive {:group_notice, text}
      assert text =~ "declines"
      assert {:error, _} = Groups.accept(b)

      {:ok, _} = Groups.invite(a, b)
      {:ok, _} = Groups.accept(b)
      assert {:error, _} = Groups.invite(c, a)
      {:ok, _} = Groups.invite(a, c)
      {:ok, _} = Groups.accept(c)
      assert length(Groups.view(a).members) == 3

      # Cy's LiveView goes away (closed tab): out of the group
      send(cpid, :stop)
      Process.sleep(50)
      _ = :sys.get_state(Groups)
      assert Groups.view(c) == nil
      assert length(Groups.view(a).members) == 2
      assert {:error, _} = Groups.invite(a, c)

      # and unregistering (logging out) too
      :ok = Groups.unregister(b)
      assert Groups.view(a) == nil
    end

    test "twenty at most" do
      {lead, _} = online(uniq("Lead"))

      for _ <- 1..19 do
        {x, _} = online(uniq("M"))
        {:ok, _} = Groups.invite(lead, x)
        {:ok, _} = Groups.accept(x)
      end

      assert length(Groups.view(lead).members) == 20
      {late, _} = online(uniq("Late"))
      assert {:error, msg} = Groups.invite(lead, late)
      assert msg =~ "full"
      :ok = Groups.disband(lead)
    end
  end

  describe "looting" do
    test "the killer's group may loot during the lock; others wait" do
      {a, _} = online(uniq("Ann"))
      {b, _} = online(uniq("Bo"))
      {x, _} = online(uniq("Xi"))
      {:ok, _} = Groups.invite(a, b)
      {:ok, _} = Groups.accept(b)

      corpse = %{items: [], coins: 5, owner: a, free_at: 60_000, despawn_at: 240_000, looter: nil, looter_since: 0}
      mob = %{state: :dead, x: 0.0, z: 0.0, corpse: corpse}
      assert {:error, :not_yours_yet} = Brain.loot_open(mob, x, {0.0, 0.0}, 1_000)
      assert {:ok, mob2, 5, []} = Brain.loot_open(mob, b, {0.0, 0.0}, 1_000)
      # one looter at a time, even in the group
      assert {:error, :someone_else_looting} = Brain.loot_open(mob2, a, {0.0, 0.0}, 2_000)
      :ok = Groups.disband(a)
    end
  end

  defp name_of(id), do: :sys.get_state(Groups).online[id].name
end
