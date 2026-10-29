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

  test "a new character wears the linen underwear; the starter kit arrives once, at first login", %{user_id: user_id, c: c} do
    assert slots(c.id) == %{"under_top" => "linen_bikini_top", "under_bottom" => "linen_bikini_bottom"}
    assert {:ok, payload} = World.character_login_payload(user_id, c.id)

    assert payload.gear == %{
             "main" => "worn_short_sword",
             "off" => nil,
             "head" => nil,
             "under_top" => "linen_bikini_top",
             "under_bottom" => "linen_bikini_bottom",
             "chest" => nil,
             "legs" => nil,
             "feet" => nil
           }

    assert %{"main" => "worn_short_sword", "bag0" => "worn_round_shield"} = slots(c.id)
    n = length(Inventory.list(c.id))
    assert n == 9
    # the starting purse, once
    assert Inventory.coins(c.id) == 100
    assert {:ok, _} = World.character_login_payload(user_id, c.id)
    assert length(Inventory.list(c.id)) == n
    assert Inventory.coins(c.id) == 100
  end

  test "an older character gets the underwear and the purse at its next login", %{user_id: user_id, c: c} do
    # as if made before clothes were items
    for slot <- ["under_top", "under_bottom"], do: {:ok, _} = Inventory.destroy(c.id, slot)
    World.merge_stats(World.by_id_query(c.id), %{"starter_wear" => false, "starter_purse" => false})
    [view] = World.list_user_characters(user_id)
    assert World.gear_for([view])[c.id]["under_top"] == "linen_bikini_top", "the select screen shows what it will wear"
    assert {:ok, _} = World.character_login_payload(user_id, c.id)
    assert %{"under_top" => "linen_bikini_top", "under_bottom" => "linen_bikini_bottom"} = slots(c.id)
  end

  test "clothes go to their own slot, swap with what is worn, and come off", %{c: c} do
    {:ok, ["bag0"]} = Inventory.add(c.id, "cloth_tunic")
    {:ok, ["bag1"]} = Inventory.add(c.id, "wool_sweater")
    {:ok, ["bag2"]} = Inventory.add(c.id, "rose_lace_top")
    assert {:error, :cannot_equip_there} = Inventory.move(c.id, "bag0", "legs")
    assert {:error, :cannot_equip_there} = Inventory.move(c.id, "bag0", "main")
    assert {:ok, _} = Inventory.auto_equip(c.id, "bag0")
    assert slots(c.id)["chest"] == "cloth_tunic"
    # the sweater takes the tunic's place; the tunic goes where the sweater was
    assert {:ok, _} = Inventory.auto_equip(c.id, "bag1")
    assert %{"chest" => "wool_sweater", "bag1" => "cloth_tunic"} = slots(c.id)
    # underwear swaps the same way
    assert {:ok, _} = Inventory.auto_equip(c.id, "bag2")
    assert %{"under_top" => "rose_lace_top", "bag2" => "linen_bikini_top"} = slots(c.id)
    # and comes off
    assert {:ok, _} = Inventory.unequip(c.id, "under_top")
    refute Map.has_key?(slots(c.id), "under_top")
    assert Inventory.gear_ids(Inventory.equipment(c.id))["chest"] == "wool_sweater"
  end

  test "the grill fork is the starter piercing weapon; the Robin Hood hat goes on the head", %{user_id: user_id, c: c} do
    assert {:ok, _} = World.character_login_payload(user_id, c.id)
    assert "grill_fork" in Map.values(slots(c.id))
    refute "worn_dagger" in Map.values(slots(c.id))
    {:ok, [bag]} = Inventory.add(c.id, "robin_hood_hat")
    assert {:error, :cannot_equip_there} = Inventory.move(c.id, bag, "chest")
    assert {:ok, _} = Inventory.auto_equip(c.id, bag)
    assert slots(c.id)["head"] == "robin_hood_hat"
    assert Inventory.gear_ids(Inventory.equipment(c.id))["head"] == "robin_hood_hat"
    assert {:ok, _} = Inventory.unequip(c.id, "head")
    refute Map.has_key?(slots(c.id), "head")
  end

  test "selling takes a whole bag slot, never what is worn", %{c: c} do
    {:ok, ["bag0"]} = Inventory.add(c.id, "bone_chips", 5)
    assert {:ok, %{item_id: "bone_chips", quantity: 5}} = Inventory.remove(c.id, "bag0")
    assert {:error, :empty_slot} = Inventory.remove(c.id, "bag0")
    assert {:error, :invalid_slot} = Inventory.remove(c.id, "under_top")
  end

  test "stackable items fill stacks before new slots; a full bag refuses", %{c: c} do
    assert {:ok, ["bag0"]} = Inventory.add(c.id, "bone_chips", 15)
    assert {:ok, ["bag0", "bag1"]} = Inventory.add(c.id, "bone_chips", 10)
    assert [%{slot: "bag0", quantity: 20}, %{slot: "bag1", quantity: 5}] = Enum.filter(Inventory.list(c.id), &String.starts_with?(&1.slot, "bag"))

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
    # a new character starts with a gold piece (100 copper)
    assert Inventory.add_coins(c.id, 125) == 225
    assert Inventory.add_coins(c.id, -500) == 0
  end

  test "experience levels a character up, with full HP and a skill point", %{c: c} do
    assert {:ok, %{level: 1, xp: 50, levels_gained: 0}} = Progression.award_xp(c.id, 50)
    assert {:ok, %{level: 2, levels_gained: 1, max_hp: hp, skill_points: 1}} = Progression.award_xp(c.id, 60)
    assert hp == Progression.max_hp(2)
    assert %{level: 2, hp: ^hp, max_hp: ^hp} = World.get_character_for_user(c.user_id, c.id)
  end
end
