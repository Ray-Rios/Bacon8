defmodule Bacon8.GameContentTest do
  # Every game's definitions on the hub (2026-11-15): stored per game and kind, read from a cache
  # with a revision, changed by staff with a history that undoes, seeded once by a plugin, and loot
  # tables rolled.
  use Bacon8.DataCase, async: false

  alias Bacon8.GameContent
  alias Bacon8.GameContent.Loot

  @game "tears_of_babylon"

  setup do
    GameContent.reset()
    on_exit(&GameContent.reset/0)
    %{gm: user_fixture(%{role: "gm", name: "gm#{System.unique_integer([:positive])}"})}
  end

  describe "definitions" do
    test "saved, read back, listed in order, kept apart by game and kind", %{gm: gm} do
      assert GameContent.list(@game, "camp") == []
      assert GameContent.revision(@game, "camp") == 0

      assert {:ok, %{id: "outskirts_01:Camp1", position: 1}} = GameContent.put(@game, "camp", "outskirts_01:Camp1", %{"zone" => "outskirts_01", "slots" => 4}, gm)
      assert {:ok, %{position: 2}} = GameContent.put(@game, "camp", "outskirts_02:Camp1", %{"zone" => "outskirts_02", "slots" => 6}, gm)
      assert {:ok, _} = GameContent.put(@game, "monster", "pack", %{"name" => "Pack"}, gm)
      assert {:ok, _} = GameContent.put("rays_space_sim", "camp", "outskirts_01:Camp1", %{"zone" => "elsewhere"}, gm)

      assert GameContent.get(@game, "camp", "outskirts_01:Camp1") == %{"zone" => "outskirts_01", "slots" => 4}
      assert Enum.map(GameContent.list(@game, "camp"), & &1.id) == ["outskirts_01:Camp1", "outskirts_02:Camp1"]
      assert [%{id: "outskirts_02:Camp1"}] = GameContent.list(@game, "camp", where: %{"zone" => "outskirts_02"})
      assert GameContent.list(@game, "camp", where: %{"slots" => "4"}) |> length() == 1
      assert GameContent.get("rays_space_sim", "camp", "outskirts_01:Camp1") == %{"zone" => "elsewhere"}
      assert Enum.sort(Enum.map(GameContent.kinds(@game), &{&1.kind, &1.count})) == [{"camp", 2}, {"monster", 1}]
    end

    test "a kind's revision changes with every change, and only then", %{gm: gm} do
      {:ok, _} = GameContent.put(@game, "camp", "a", %{"slots" => 1}, gm)
      r1 = GameContent.revision(@game, "camp")
      assert r1 != 0
      {:ok, _} = GameContent.put(@game, "camp", "a", %{"slots" => 1}, gm)
      assert GameContent.revision(@game, "camp") == r1
      {:ok, _} = GameContent.put(@game, "camp", "a", %{"slots" => 2}, gm)
      r2 = GameContent.revision(@game, "camp")
      assert r2 != r1
      {:ok, _} = GameContent.put(@game, "monster", "pack", %{}, gm)
      assert GameContent.revision(@game, "camp") == r2
      assert :ok = GameContent.delete(@game, "camp", "a", gm)
      assert GameContent.revision(@game, "camp") == 0
    end

    test "what isn't a definition is refused", %{gm: gm} do
      assert {:error, _} = GameContent.put(@game, "Camp", "a", %{}, gm)
      assert {:error, _} = GameContent.put(@game, "history", "a", %{}, gm)
      assert {:error, _} = GameContent.put(@game, "camp", "../a", %{}, gm)
      assert {:error, _} = GameContent.put(@game, "camp", "", %{}, gm)
      assert {:error, _} = GameContent.put(@game, "camp", "a", [1, 2], gm)
      assert {:error, _} = GameContent.put(@game, "camp", "a", %{"blob" => String.duplicate("x", 300_000)}, gm)
      assert {:error, _} = GameContent.delete(@game, "camp", "nobody", gm)
      assert GameContent.list(@game, "camp") == []
    end

    test "Bacon World's rows are served, not written: it has its own editor", %{gm: gm} do
      assert GameContent.read_only?("bacon_world")
      assert {:error, message} = GameContent.put("bacon_world", "monster", "goblin", %{}, gm)
      assert message =~ "Studio"
      assert {:error, _} = GameContent.delete("bacon_world", "monster", "goblin", gm)
    end

    test "staff are admins and GMs who are active" do
      assert GameContent.staff?(%{role: "admin", status: "active"})
      assert GameContent.staff?(%{role: "gm", status: "active"})
      refute GameContent.staff?(%{role: "gm", status: "disabled"})
      refute GameContent.staff?(%{role: "editor", status: "active"})
      refute GameContent.staff?(%{role: "member", status: "active"})
      refute GameContent.staff?(nil)
    end
  end

  describe "history" do
    test "every change is kept with who made it, and each can be undone, a deletion too", %{gm: gm} do
      {:ok, _} = GameContent.put(@game, "camp", "a", %{"slots" => 1}, gm)
      {:ok, _} = GameContent.put(@game, "camp", "a", %{"slots" => 5}, gm)
      :ok = GameContent.delete(@game, "camp", "a", gm)

      assert [deleted, changed, created] = GameContent.history(@game, kind: "camp")
      assert {deleted.action, changed.action, created.action} == {"delete", "update", "create"}
      assert changed.before == %{"slots" => 1} and changed.after == %{"slots" => 5}
      assert created.user_name == gm.name

      # undo the deletion: it is back as it was
      assert {:ok, _} = GameContent.undo(@game, deleted.id, gm)
      assert GameContent.get(@game, "camp", "a") == %{"slots" => 5}
      # undo the change: the first value
      assert {:ok, _} = GameContent.undo(@game, changed.id, gm)
      assert GameContent.get(@game, "camp", "a") == %{"slots" => 1}
      # undo the creation: gone
      assert {:ok, nil} = GameContent.undo(@game, created.id, gm)
      assert GameContent.get(@game, "camp", "a") == nil
      # the undos are changes too
      assert length(GameContent.history(@game, id: "a")) == 6
      assert {:error, _} = GameContent.undo("rays_space_sim", deleted.id, gm)
    end
  end

  describe "seeding" do
    test "fills a kind once; what an admin changed since is left alone", %{gm: gm} do
      rows = [%{"id" => "outskirts_01", "data" => %{"name" => "The RoT"}}, %{"id" => "outskirts_02", "data" => %{"name" => "Two"}}, %{"id" => "bad id!", "data" => %{}}, %{"data" => %{}}]
      assert GameContent.seed(@game, "zone", rows) == 2
      assert Enum.map(GameContent.list(@game, "zone"), & &1.id) == ["outskirts_01", "outskirts_02"]
      {:ok, _} = GameContent.put(@game, "zone", "outskirts_01", %{"name" => "Rivers of Tears"}, gm)
      more = rows ++ [%{"id" => "outskirts_03", "data" => %{"name" => "Three"}}]
      # a kind that has rows is left alone at the next start...
      assert GameContent.seed(@game, "zone", more) == 0
      :ok = GameContent.delete(@game, "zone", "outskirts_02", gm)
      assert GameContent.seed(@game, "zone", more) == 0
      # ...until someone asks for what's missing: the new one, and the one deleted
      assert GameContent.seed(@game, "zone", more, missing: true) == 2
      assert GameContent.get(@game, "zone", "outskirts_01") == %{"name" => "Rivers of Tears"}
      # seeding writes no history
      assert Enum.map(GameContent.history(@game, kind: "zone"), & &1.action) == ["delete", "update"]
    end
  end

  describe "loot" do
    setup %{gm: gm} do
      {:ok, _} = GameContent.put(@game, "loot_table", "always_two", %{"always" => [%{"item" => "pelt", "qty" => 2}], "coins" => 3}, gm)
      {:ok, _} = GameContent.put(@game, "loot_table", "pool", %{"rolls" => [2, 2], "empty" => 0, "pool" => [%{"item" => "scrap", "weight" => 1, "qty" => [1, 3]}, %{"item" => "elite_core", "weight" => 1000, "min_level" => 30}]}, gm)
      {:ok, _} = GameContent.put(@game, "loot_table", "nested", %{"tables" => [%{"table" => "always_two", "chance" => 1.0}, %{"table" => "nested", "chance" => 1.0}]}, gm)
      {:ok, _} = GameContent.put(@game, "loot_table", "rare", %{"always" => [%{"item" => "gem", "chance" => 0.1}]}, gm)
      :ok
    end

    test "always-drops, coins times the level, and a table by its id or its data" do
      assert Loot.roll(@game, "always_two", 4) == %{items: [%{item_id: "pelt", quantity: 2}], coins: 12}
      assert Loot.roll(@game, %{"always" => [%{"item" => "x"}]}, 1) == %{items: [%{item_id: "x", quantity: 1}], coins: 0}
      assert Loot.roll(@game, "no_such_table", 1) == %{items: [], coins: 0}
      assert Loot.roll(@game, "always_two", 4, coin_mult: 2.0).coins == 24
    end

    test "the pool: that many picks, quantities in range, level bands kept" do
      for _ <- 1..50 do
        assert %{items: items} = Loot.roll(@game, "pool", 5)
        assert length(items) == 2
        assert Enum.all?(items, &(&1.item_id == "scrap" and &1.quantity in 1..3))
      end

      # at level 30 the heavy one is nearly every pick
      picks = for _ <- 1..50, i <- Loot.roll(@game, "pool", 30).items, do: i.item_id
      assert Enum.count(picks, &(&1 == "elite_core")) > 90
    end

    test "tables inside tables, without ever looping" do
      assert %{items: items, coins: coins} = Loot.roll(@game, "nested", 1)
      # itself, as deep as tables may go (4), each of those levels adding the always-two
      assert length(items) == 4 and coins == 12
    end

    test "chances scale with the multiplier and never pass certain" do
      one = Loot.simulate(@game, "rare", 1, 4000)
      ten = Loot.simulate(@game, "rare", 1, 4000, chance_mult: 20.0)
      got = fn sim -> Enum.find_value(sim.items, 0, &(&1.item_id == "gem" && &1.kills)) end
      assert got.(one) in 280..520
      assert got.(ten) == 4000
      assert one.kills == 4000 and one.empty == 4000 - got.(one)
    end

    test "an item the game no longer has is skipped, once the game has items at all", %{gm: gm} do
      assert Loot.roll(@game, "always_two", 1).items != []
      {:ok, _} = GameContent.put(@game, "item", "scrap", %{"name" => "Scrap"}, gm)
      assert Loot.roll(@game, "always_two", 1).items == []
      assert Loot.roll(@game, "always_two", 1, item_ok: fn _ -> true end).items != []
    end
  end
end
