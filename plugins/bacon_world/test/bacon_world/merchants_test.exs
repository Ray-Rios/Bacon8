defmodule BaconWorld.MerchantsTest do
  # Tilda the clothier (BaconWorld.Merchants) and trading through PlayLive's events
  # (BaconWorldWeb.GameEvents): reach, prices, buying, selling.
  use Bacon8.DataCase, async: false

  alias BaconWorld.{Inventory, Items, Merchants, Models, World}
  alias BaconWorld.Mobs.Brain
  alias BaconWorldWeb.GameEvents

  setup do
    dir = Path.join(System.tmp_dir!(), "bacon_world_mer_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "heroes"))
    File.write!(Path.join(dir, "heroes/runner.glb"), "glTF")
    Application.put_env(:bacon8, Models, roots: [dir])

    on_exit(fn ->
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    user_id = Ecto.UUID.generate()
    {:ok, c} = World.create_character(user_id, %{"name" => "Shopper", "character_type" => "Adventurer", "model_path" => "/models/heroes/runner.glb"})
    %{c: c, tilda: Merchants.get("tilda")}
  end

  # A LiveView socket standing at (x, z) metres.
  defp socket(c, {x, z}) do
    u = Brain.u()
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, mobs_zone: "lobby", current_character_runtime: %{character_id: c.id, position: %{x: x * u, y: 0.0, z: z * u}}}}
  end

  defp beside(m), do: {m.x - 1.5, m.z}

  test "the catalogue: every item Tilda sells exists, is worn, and costs its value", %{tilda: m} do
    assert m.title == "Clothier"
    stock = Merchants.stock(m)
    assert length(stock) == length(m.sells)

    for %{item_id: id, price: price} <- stock do
      item = Items.get(id)
      assert item, id
      assert Items.wearable?(item)
      assert price == item.value
      assert Merchants.buy_price(item) < price
    end

    # underwear sets (including chain bikinis, 2026-11-01), top and bottom each, 6 copper a piece
    n_under = length(Items.underwear_sets())
    assert Enum.count(m.sells, &String.ends_with?(&1, "_top")) == n_under
    assert Enum.count(m.sells, &String.ends_with?(&1, "_bottom")) == n_under
    # cloth 6 copper a piece; Gemini's metal bikinis more, with a little armour
    for set <- Items.underwear_sets(), part <- ~w(top bottom) do
      item = Items.get("#{set}_#{part}")
      if String.starts_with?(set, ["chain_", "plate_"]), do: assert(item.value > 6 and item.ac > 0), else: assert(item.value == 6)
    end
    assert Merchants.buy_price(Items.get("bone_chips")) == 1
    assert Merchants.buy_price(%{value: 0}) == 0
  end

  test "reach and the client payload", %{tilda: m} do
    u = Brain.u()
    assert Merchants.near?(m, {m.x * u, m.z * u})
    refute Merchants.near?(m, {(m.x + 10) * u, m.z * u})
    list = Merchants.payload("lobby")
    assert %{id: "tilda", name: "Tilda Threadwell", kind: "trader", gear: %{"chest" => "frost_chest"}} = p = Enum.find(list, &(&1.id == "tilda"))
    # the stablemaster keeps the mounts (BaconWorldWeb.MountEvents), and sells nothing
    assert %{kind: "stable", title: "Stablemaster"} = Enum.find(list, &(&1.id == "rowena"))
    assert Merchants.get("rowena").sells == []
    assert_in_delta p.x, m.x * u, 1.0e-9
    assert Merchants.payload("nowhere") == []
  end

  test "buying: coins go, the item arrives; too poor, too far or not sold is refused", %{c: c, tilda: m} do
    s = socket(c, beside(m))
    assert {:reply, %{ok: true, stock: [_ | _]}, _} = GameEvents.handle_event("merchant_open", %{"id" => "tilda"}, s)
    # the starting purse is 100 copper
    assert {:reply, %{ok: true, price: 25, coins: 75}, _} = GameEvents.handle_event("merchant_buy", %{"id" => "tilda", "item_id" => "wayfarer_feet"}, s)
    assert Enum.any?(Inventory.list(c.id), &(&1.item_id == "wayfarer_feet"))
    assert {:reply, %{ok: false, error: "You can't afford that."}, _} = GameEvents.handle_event("merchant_buy", %{"id" => "tilda", "item_id" => "duelist_feet"}, s)
    assert {:reply, %{ok: false, error: "They don't sell that."}, _} = GameEvents.handle_event("merchant_buy", %{"id" => "tilda", "item_id" => "rusty_halberd"}, s)
    far = socket(c, {m.x + 20, m.z})
    assert {:reply, %{ok: false, error: "You are too far away" <> _}, _} = GameEvents.handle_event("merchant_buy", %{"id" => "tilda", "item_id" => "wayfarer_feet"}, far)
    assert {:reply, %{ok: false}, _} = GameEvents.handle_event("merchant_open", %{"id" => "nobody"}, s)
    assert Inventory.coins(c.id) == 75
  end

  test "selling: a quarter of the value for the whole stack; worn things and junk worth nothing are refused", %{c: c, tilda: m} do
    s = socket(c, beside(m))
    {:ok, [bag]} = Inventory.add(c.id, "rusty_scimitar")
    before = Inventory.coins(c.id)
    assert {:reply, %{ok: true, price: 4, sold: "rusty_scimitar"}, _} = GameEvents.handle_event("merchant_sell", %{"id" => "tilda", "slot" => bag}, s)
    assert Inventory.coins(c.id) == before + 4
    refute Enum.any?(Inventory.list(c.id), &(&1.slot == bag))
    {:ok, [chips]} = Inventory.add(c.id, "bone_chips", 7)
    assert {:reply, %{ok: true, price: 7, quantity: 7}, _} = GameEvents.handle_event("merchant_sell", %{"id" => "tilda", "slot" => chips}, s)
    assert {:reply, %{ok: false, error: "Take it off first."}, _} = GameEvents.handle_event("merchant_sell", %{"id" => "tilda", "slot" => "under_top"}, s)
    assert {:reply, %{ok: false, error: "There's nothing there."}, _} = GameEvents.handle_event("merchant_sell", %{"id" => "tilda", "slot" => "bag20"}, s)
  end

  test "the jeweller sells whole sets for Gems, and buys nothing back" do
    m = Merchants.get("rosalind")
    assert Merchants.gems?(m)
    stock = Merchants.stock(m)
    assert length(stock) == 2 * length(Items.jewel_sets()) and length(stock) == 20

    # the heels: on their own, run faster
    for %{item_id: id, gems: 100, pieces: [id]} <- Enum.filter(stock, &String.ends_with?(&1.item_id, "_shoes")) do
      shoes = Items.get(id)
      assert shoes.slots == ["feet"] and shoes.run_speed == 1.5 and shoes.power == "swift"
      assert shoes.wear["male"]["part"] =~ "Garments/Male/uw_jw_"
    end

    for %{item_id: id, gems: gems, pieces: pieces, price: 0} <- Enum.reject(stock, &String.ends_with?(&1.item_id, "_shoes")) do
      item = Items.get(id)
      assert gems == Items.jewel_price_gems() and gems == 100
      assert BaconWorld.Powers.get(item.power), id
      assert pieces == ["#{item.jewel}_top", "#{item.jewel}_bottom"]
      assert Items.jewel_pieces(item.jewel, "male") == ["#{item.jewel}_bottom"]
      for p <- pieces, do: assert(Merchants.buy_price(Items.get(p)) == 0)
    end

    # every power is a different one
    powers = for s <- Items.jewel_sets(), do: Items.get("#{s}_bottom").power
    assert length(Enum.uniq(powers)) == 10
    refute Merchants.gems?(Merchants.get("tilda"))
  end
end
