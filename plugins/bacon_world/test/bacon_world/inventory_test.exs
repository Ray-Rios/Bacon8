defmodule BaconWorld.InventoryTest do
  # Bags, hands and coins (BaconWorld.Inventory), and levels on the character.
  use Bacon8.DataCase, async: false

  alias BaconWorld.{Inventory, Models, Progression, World}

  setup do
    dir = Path.join(System.tmp_dir!(), "bacon_world_inv_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "heroes"))
    File.write!(Path.join(dir, "heroes/runner.glb"), "glTF")
    Application.put_env(:bacon8, Models, roots: [dir])

    on_exit(fn ->
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    user_id = Ecto.UUID.generate()
    {:ok, c} = World.create_character(user_id, %{"name" => "Packrat", "character_type" => "Adventurer", "model_path" => "/models/heroes/runner.glb"})
    %{user_id: user_id, c: c}
  end

  defp slots(id), do: Map.new(Inventory.list(id), &{&1.slot, &1.item_id})

  test "the starter kit arrives once, at first login", %{user_id: user_id, c: c} do
    assert Inventory.list(c.id) == []
    assert {:ok, payload} = World.character_login_payload(user_id, c.id)
    assert payload.gear == %{"main" => "worn_short_sword", "off" => nil}
    assert %{"main" => "worn_short_sword", "bag0" => "worn_round_shield"} = slots(c.id)
    n = length(Inventory.list(c.id))
    assert n == 7
    assert {:ok, _} = World.character_login_payload(user_id, c.id)
    assert length(Inventory.list(c.id)) == n
  end

  test "stackable items fill stacks before new slots; a full bag refuses", %{c: c} do
    assert {:ok, ["bag0"]} = Inventory.add(c.id, "bone_chips", 15)
    assert {:ok, ["bag0", "bag1"]} = Inventory.add(c.id, "bone_chips", 10)
    assert [%{slot: "bag0", quantity: 20}, %{slot: "bag1", quantity: 5}] = Inventory.list(c.id)

    for _ <- 3..Inventory.bag_slots(), do: {:ok, _} = Inventory.add(c.id, "rusty_dagger")
    assert Inventory.free_bag_slots(c.id) == 0
    assert {:error, :inventory_full} = Inventory.add(c.id, "rusty_dagger")
    # A stack with room still takes more.
    assert Inventory.fits?(c.id, "bone_chips", 15)
    assert {:ok, ["bag1"]} = Inventory.add(c.id, "bone_chips", 15)
    assert {:error, :unknown_item} = Inventory.add(c.id, "excalibur")
  end

  test "equipping follows hands and slots; moving onto an item swaps", %{c: c} do
    {:ok, _} = Inventory.add(c.id, "rusty_short_sword")
    {:ok, _} = Inventory.add(c.id, "worn_round_shield")
    {:ok, _} = Inventory.add(c.id, "rusty_two_handed_sword")
    {:ok, _} = Inventory.add(c.id, "rusty_dagger")

    assert {:error, :cannot_equip_there} = Inventory.move(c.id, "bag1", "main")
    assert {:ok, _} = Inventory.move(c.id, "bag0", "main")
    assert {:ok, _} = Inventory.move(c.id, "bag1", "off")
    # A two-hander needs the off hand empty.
    assert {:error, :off_hand_full} = Inventory.move(c.id, "bag2", "main")
    # Dagger onto the shield: they swap.
    assert {:ok, _} = Inventory.move(c.id, "bag3", "off")
    assert %{"main" => "rusty_short_sword", "off" => "rusty_dagger", "bag3" => "worn_round_shield"} = slots(c.id)

    # auto_equip a two-hander: the off hand goes to a bag first.
    assert {:ok, _} = Inventory.auto_equip(c.id, "bag2")
    s = slots(c.id)
    assert s["main"] == "rusty_two_handed_sword" and is_nil(s["off"])
    assert {:error, :two_hander_equipped} = Inventory.auto_equip(c.id, "bag3")
    assert %{"main" => %{id: "rusty_two_handed_sword"}, "off" => nil} = Inventory.equipment(c.id)

    assert {:ok, _} = Inventory.unequip(c.id, "main")
    assert Inventory.equipment(c.id)["main"] == nil
    assert {:error, :empty_slot} = Inventory.move(c.id, "main", "bag9")
    assert {:error, :invalid_slot} = Inventory.move(c.id, "bag0", "bag99")
    assert {:ok, _} = Inventory.destroy(c.id, "bag3")
    refute Map.has_key?(slots(c.id), "bag3")
  end

  test "coins add up and never go below zero", %{c: c} do
    assert Inventory.add_coins(c.id, 125) == 125
    assert Inventory.add_coins(c.id, -500) == 0
  end

  test "experience levels a character up, with full HP and a skill point", %{c: c} do
    assert {:ok, %{level: 1, xp: 50, levels_gained: 0}} = Progression.award_xp(c.id, 50)
    assert {:ok, %{level: 2, levels_gained: 1, max_hp: hp, skill_points: 1}} = Progression.award_xp(c.id, 60)
    assert hp == Progression.max_hp(2)
    assert %{level: 2, hp: ^hp, max_hp: ^hp} = World.get_character_for_user(c.user_id, c.id)
  end
end
