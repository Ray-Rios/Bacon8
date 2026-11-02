defmodule BaconWorld.JewellerTest do
  # Buying a jeweller's set for Gems (BaconWorld.Jeweller): the pieces arrive, the wallet records the spend.
  use Bacon8.DataCase, async: false

  alias BaconStore.Wallet
  alias BaconWorld.{Inventory, Items, Jeweller, Merchants, Models, World}

  setup do
    dir = Path.join(System.tmp_dir!(), "bacon_world_jw_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "heroes"))
    File.write!(Path.join(dir, "heroes/runner.glb"), "glTF")
    Application.put_env(:bacon8, Models, roots: [dir])

    on_exit(fn ->
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    user = user_fixture()
    {:ok, c} = World.create_character(user.id, %{"name" => "Rosebud", "character_type" => "Adventurer", "model_path" => "/models/heroes/runner.glb"})
    %{user: user, c: c, sells: Merchants.get("rosalind").sells}
  end

  defp bag_items(id), do: for(i <- Inventory.list(id), String.starts_with?(i.slot, "bag"), do: i.item_id)

  test "a set costs 100 Gems, recorded as a spend on the owner's ledger", %{user: user, c: c, sells: sells} do
    {:ok, _} = Wallet.grant(user, 250, idempotency_key: "jw-test-grant")
    who = %{character_id: c.id, name: "Rosebud", body: "female"}

    assert {:ok, %{pieces: ["jw_rose_top", "jw_rose_bottom"], gems_spent: 100, balance: 150}} =
             Jeweller.buy(user, who, "jw_rose_bottom", "click-1", sells)

    assert Enum.sort(bag_items(c.id)) == ["jw_rose_bottom", "jw_rose_top"]
    assert Wallet.balance(user) == 150

    assert [%{amount: 100, memo: "Rose Wire set, for Rosebud", game_slug: "bacon_world", reference_type: "bacon_world_jewel", reference_id: "jw_rose"}] =
             Wallet.spends(user)

    # the same click again (a retried request): no second charge, no second set
    assert {:ok, %{gems_spent: 0, balance: 150}} = Jeweller.buy(user, who, "jw_rose_bottom", "click-1", sells)
    assert length(bag_items(c.id)) == 2
    assert length(Wallet.spends(user)) == 1
  end

  test "the male gets the bottom only; too few Gems buys nothing", %{user: user, c: c, sells: sells} do
    {:ok, _} = Wallet.grant(user, 150, idempotency_key: "jw-test-grant-2")
    him = %{character_id: c.id, name: "Rosebud", body: "male"}
    assert {:ok, %{pieces: ["jw_thorn_bottom"]}} = Jeweller.buy(user, him, "jw_thorn_bottom", "a", sells)
    assert {:error, msg} = Jeweller.buy(user, him, "jw_phoenix_bottom", "b", sells)
    assert msg =~ "100 Gems"
    assert bag_items(c.id) == ["jw_thorn_bottom"]
    assert Wallet.balance(user) == 50
    assert {:error, _} = Jeweller.buy(user, him, "homespun_bottom", "c", sells)
    {:ok, _} = Wallet.grant(user, 100, idempotency_key: "jw-test-grant-3")
    assert {:ok, %{pieces: ["jw_rose_shoes"], gems_spent: 100}} = Jeweller.buy(user, him, "jw_rose_shoes", "d", sells)
    assert [%{memo: "Rose Wire Heels, for Rosebud", reference_id: "jw_rose_shoes"} | _] = Wallet.spends(user)
    assert Items.jewel_price_gems() == 100
  end
end
