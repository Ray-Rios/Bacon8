defmodule BaconWorld.SkillsTest do
  # The skill tree (BaconWorld.SkillTree, BaconWorld.Skills), casting checks
  # (BaconWorldWeb.SkillEvents) and what spells do to creatures (Brain.root/3,
  # Brain.spell_hit/3, the spin attack through Brain.melee/4).
  use Bacon8.DataCase, async: false

  alias BaconWorld.{Abilities, Items, Models, SkillTree, Skills, World}
  alias BaconWorld.Mobs.Brain
  alias BaconWorldWeb.SkillEvents

  @u 2.2 / 1.8

  setup do
    dir = Path.join(System.tmp_dir!(), "bacon_world_sk_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "heroes"))
    File.write!(Path.join(dir, "heroes/runner.glb"), "glTF")
    Application.put_env(:bacon8, Models, roots: [dir])
    SkillTree.bust()

    on_exit(fn ->
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
      SkillTree.bust()
    end)

    {:ok, c} = World.create_character(Ecto.UUID.generate(), %{"name" => "Learner", "character_type" => "Adventurer", "model_path" => "/models/heroes/runner.glb"})
    %{c: c}
  end

  defp points!(c, n), do: World.merge_stats(World.by_id_query(c.id), %{"skill_points" => n})
  defp node_with(tree, ability), do: Enum.find(tree["nodes"], &(&1["ability"] == ability))["id"]

  describe "the tree" do
    test "the shipped tree: Recall in the middle, the six around it, all joined to it" do
      tree = SkillTree.default()
      assert {:ok, ^tree} = SkillTree.validate(tree)
      assert SkillTree.node(tree, tree["start"])["ability"] == "recall"
      ring = SkillTree.neighbours(tree, "n0")
      assert length(ring) == 6
      assert ring |> Enum.map(&SkillTree.node(tree, &1)["ability"]) |> Enum.sort() == Enum.sort(~w(heal fireball hp_10 mp_10 root spin_attack))
      # one ring out, evenly spaced
      for id <- ring, n = SkillTree.node(tree, id), do: assert_in_delta(:math.sqrt(n["x"] * n["x"] + n["y"] * n["y"]), 1.0, 0.01)
    end

    test "validation refuses what the game can't use" do
      t = SkillTree.default()
      assert {:error, _} = SkillTree.validate(%{t | "start" => "nowhere"})
      assert {:error, _} = SkillTree.validate(%{t | "nodes" => [%{"id" => "n0", "x" => 0, "y" => 0, "ability" => "laser_eyes"}]})
      assert {:error, _} = SkillTree.validate(%{t | "edges" => [["n0", "n99"]]})
      assert {:error, _} = SkillTree.validate(%{t | "nodes" => t["nodes"] ++ [hd(t["nodes"])]})
      # duplicate and reversed edges are kept once
      assert {:ok, clean} = SkillTree.validate(%{t | "edges" => t["edges"] ++ [["n1", "n0"]]})
      assert length(clean["edges"]) == 6
    end

    test "a saved tree is the one in force; reset brings the shipped one back" do
      t = SkillTree.default()
      bigger = %{t | "nodes" => t["nodes"] ++ [%{"id" => "n7", "x" => 0.0, "y" => 2.0, "ability" => "hp_25"}], "edges" => t["edges"] ++ [["n1", "n7"]]}
      assert {:ok, _} = SkillTree.save(bigger)
      assert length(SkillTree.current()["nodes"]) == 8
      assert {:ok, _} = SkillTree.reset()
      assert length(SkillTree.current()["nodes"]) == 7
    end
  end

  describe "a character in the tree" do
    test "level 1: Recall only, no points; a point buys a joined node", %{c: c} do
      {:ok, c} = World.fetch_character(c.id)
      st = Skills.state(c)
      assert st.learned == ["n0"]
      assert st.abilities == ["recall"]
      assert st.points == 0
      tree = SkillTree.current()
      assert {:error, "You have no skill points" <> _} = Skills.learn(c.id, node_with(tree, "fireball"))

      points!(c, 1)
      assert {:ok, p} = Skills.learn(c.id, node_with(tree, "fireball"))
      assert "fireball" in p.abilities
      assert p.points == 0
      # Recall and the new spell went on the spell bar on their own
      assert ["recall", "fireball" | _] = p.hotbars["spells"]
    end

    test "a node must join one you have", %{c: c} do
      t = SkillTree.default()
      far = %{t | "nodes" => t["nodes"] ++ [%{"id" => "far", "x" => 0.0, "y" => 2.0, "ability" => "hp_25"}], "edges" => t["edges"] ++ [["n1", "far"]]}
      {:ok, _} = SkillTree.save(far)
      points!(c, 3)
      assert {:error, "That isn't joined" <> _} = Skills.learn(c.id, "far")
      assert {:ok, _} = Skills.learn(c.id, "n1")
      assert {:ok, %{learned: learned}} = Skills.learn(c.id, "far")
      assert "far" in learned
    end

    test "buffs raise the pools now and on later level ups; a removed node hands its point back", %{c: c} do
      points!(c, 2)
      tree = SkillTree.current()
      {:ok, _} = Skills.learn(c.id, node_with(tree, "hp_10"))
      {:ok, _} = Skills.learn(c.id, node_with(tree, "mp_10"))
      {:ok, c2} = World.fetch_character(c.id)
      assert World.stat(c2, "max_hp") == 40 + 10
      assert World.stat(c2, "max_mp") == 20 + 10
      assert World.stat(c2, "hp") == 50

      {:ok, %{levels_gained: 1}} = BaconWorld.Progression.award_xp(c.id, BaconWorld.Progression.xp_to_next(1))
      {:ok, c3} = World.fetch_character(c.id)
      assert World.stat(c3, "max_hp") == BaconWorld.Progression.max_hp(2) + 10

      # the owner takes the Vigor node out of the tree: its point comes back, the pool shrinks
      hp_node = node_with(tree, "hp_10")
      {:ok, _} = SkillTree.save(%{tree | "nodes" => Enum.reject(tree["nodes"], &(&1["id"] == hp_node)), "edges" => Enum.reject(tree["edges"], &(hp_node in &1))})
      {:ok, c4} = World.fetch_character(c.id)
      assert Skills.state(c4).points == 3 - 1
      {:ok, _} = Skills.sync_stats(c.id)
      {:ok, c5} = World.fetch_character(c.id)
      assert World.stat(c5, "max_hp") == BaconWorld.Progression.max_hp(2)
    end

    test "hotbars keep only what you have, each kind in its own bar", %{c: c} do
      points!(c, 2)
      tree = SkillTree.current()
      {:ok, _} = Skills.learn(c.id, node_with(tree, "spin_attack"))
      {:ok, _} = Skills.learn(c.id, node_with(tree, "heal"))
      {:ok, bars} = Skills.set_hotbars(c.id, %{"skills" => %{"E" => "spin_attack", "Q" => "fireball", "P" => "spin_attack"}, "spells" => ["heal", "spin_attack", "recall"]})
      assert bars["skills"] == %{"E" => "spin_attack"}
      assert Enum.take(bars["spells"], 3) == ["heal", nil, "recall"]
      assert length(bars["spells"]) == 20
    end
  end

  describe "casting" do
    defp socket(c, extra \\ %{}) do
      assigns =
        Map.merge(
          %{__changed__: %{}, mobs_zone: "lobby", current_character_runtime: %{character_id: c.id, name: c.name, position: %{x: 0.0, y: 0.0, z: 0.0, heading: 0.0}}},
          extra
        )

      %Phoenix.LiveView.Socket{assigns: assigns}
    end

    test "only what you have, with the mana, off cooldown, and a target when it needs one", %{c: c} do
      s = socket(c)
      assert {:reply, %{ok: false, error: "You haven't learned Fireball."}, _} = SkillEvents.handle_event("cast", %{"ability" => "fireball"}, s)
      points!(c, 1)
      {:ok, _} = Skills.learn(c.id, node_with(SkillTree.current(), "fireball"))
      assert {:reply, %{ok: false, error: "You need a target."}, _} = SkillEvents.handle_event("cast", %{"ability" => "fireball"}, s)
      World.merge_stats(World.by_id_query(c.id), %{"mp" => 3})
      assert {:reply, %{ok: false, error: "You don't have enough mana."}, _} = SkillEvents.handle_event("cast", %{"ability" => "fireball", "target_id" => "x"}, s)
      assert {:reply, %{ok: false, error: "You can't do that from the saddle."}, _} =
               SkillEvents.handle_event("cast", %{"ability" => "fireball", "target_id" => "x"}, socket(c, %{mount: "ember_drake"}))
      # Recall has a cast time: it starts casting
      assert {:reply, %{ok: true, cast_ms: 4000}, s2} = SkillEvents.handle_event("cast", %{"ability" => "recall"}, s)
      assert s2.assigns.casting.ability == "recall"
      assert {:reply, %{ok: false, error: "You are already casting."}, _} = SkillEvents.handle_event("cast", %{"ability" => "recall"}, s2)
      # moving interrupts it
      moved = put_in(s2.assigns.current_character_runtime.position.x, 3.0 * @u)
      s3 = SkillEvents.cast_complete(s2.assigns.casting.token, moved)
      assert s3.assigns.casting == nil
    end

    test "the abilities' numbers grow with level" do
      assert Abilities.amount(Abilities.get("fireball"), 1) == 10
      assert Abilities.amount(Abilities.get("fireball"), 5) == 22
      assert Abilities.amount(Abilities.get("heal"), 1) == 14
    end
  end

  describe "spells on creatures" do
    defp mob(attrs \\ %{}) do
      %{id: "m1", camp: "test", kind: "decaying_skeleton", x: 60.0, z: 0.0}
      |> Brain.spawn(0)
      |> Map.merge(%{level: 1, hp: 30, max_hp: 30, x: 10.0 * @u, z: 0.0, h: 0.0})
      |> Map.merge(attrs)
    end

    test "roots hold a creature in place but it still turns on you" do
      m = mob()
      {mobs, :ok, events} = Brain.root(%{"m1" => m}, %{id: "p1", target: "m1", ms: 6000, x: 0.0, z: 0.0, range: 25 * @u}, 0)
      assert {:rooted, "m1", 6000} in events
      rooted = mobs["m1"]
      assert rooted.state == :chase
      players = %{"p1" => %{x: 0.0, z: 0.0, y: 0.0, dead: false, level: 1}}
      {after_tick, _} = Brain.tick(rooted, players, 500, 0.5, nil)
      assert after_tick.x == rooted.x and after_tick.z == rooted.z
      # out of range: refused
      assert {_, {:error, :out_of_range}, []} = Brain.root(%{"m1" => m}, %{id: "p1", target: "m1", ms: 6000, x: -100.0 * @u, z: 0.0, range: 25 * @u}, 0)
    end

    test "a spell's damage lands on its target in range" do
      {mobs, hit, _} = Brain.spell_hit(%{"m1" => mob()}, %{id: "p1", target: "m1", damage: 12, crit: false, x: 0.0, z: 0.0, range: 30 * @u}, 0)
      assert %{hit: true, damage: 12, killed: false} = hit
      assert mobs["m1"].hp == 18
      {_, hit2, _} = Brain.spell_hit(%{"m1" => mob(%{hp: 5})}, %{id: "p1", target: "m1", damage: 12, crit: false, x: 0.0, z: 0.0, range: 30 * @u}, 0)
      assert hit2.killed
    end

    test "the spin attack hits all round, behind you too" do
      near = fn id, x, z -> mob(%{id: id, x: x * @u, z: z * @u}) end
      mobs = %{"a" => near.("a", 0.0, 1.0), "b" => near.("b", 0.0, -1.0), "c" => near.("c", 1.0, 0.0), "far" => near.("far", 0.0, 9.0)}
      attack = %{id: "p1", level: 10, x: 0.0, z: 0.0, heading: 0.0, item: Items.fist(), heavy: false, target: nil, sweep: {8, 360}, mult: 0.9, extra_reach: 0.6}
      {_, hits, _} = Brain.melee(mobs, attack, 0, fn -> 0.0 end)
      assert hits |> Enum.map(& &1.id) |> Enum.sort() == ["a", "b", "c"]
    end
  end
end
