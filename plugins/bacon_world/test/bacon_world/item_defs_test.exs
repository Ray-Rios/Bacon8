defmodule BaconWorld.ItemDefsTest do
  # The item catalogue in the database (2026-11-02): seeded from priv/seed/items.json on first read,
  # edited from /admin/bacon_world/database.
  use Bacon8.DataCase, async: false

  alias BaconWorld.Items

  setup do
    old = Application.get_env(:bacon8, Items)
    Application.put_env(:bacon8, Items, source: :db)
    Items.reload()

    on_exit(fn ->
      Application.put_env(:bacon8, Items, old)
      Items.reload()
    end)
  end

  test "the first read fills the table from the seed, and an edit is seen at once" do
    seed = Items.seed_rows()
    assert length(Items.all()) == length(seed)
    assert Items.get("worn_short_sword").dmg == 6
    assert "homespun" in Items.underwear_sets()
    assert Items.jewel_sets() |> length() == 10

    {:ok, sword} = Items.save_def(Items.get("worn_short_sword") |> Items.to_data() |> Map.put("dmg", 9))
    assert sword.dmg == 9
    assert Items.get("worn_short_sword").dmg == 9

    {:ok, new} = Items.save_def(%{"id" => "test_pebble", "name" => "Pebble", "kind" => "junk", "stack" => 20, "value" => 1})
    assert new.stack == 20
    assert :ok == Items.delete_def("test_pebble")
    refute Items.get("test_pebble")

    assert {:error, _} = Items.save_def(%{"id" => "Bad Id", "name" => "x", "kind" => "junk"})
  end
end

defmodule BaconWorld.DefsTest do
  # Monster types and merchants in the database (2026-11-02).
  use Bacon8.DataCase, async: false

  alias BaconWorld.Defs

  setup do
    old = Application.get_env(:bacon8, Defs)
    Application.put_env(:bacon8, Defs, source: :db)
    Defs.reload("monster")
    Defs.reload("merchant")

    on_exit(fn ->
      Application.put_env(:bacon8, Defs, old)
      Defs.reload("monster")
      Defs.reload("merchant")
    end)
  end

  test "seeded on first read; the game's terms come back as they were; an edit is seen at once" do
    sk = BaconWorld.Mobs.Spawns.kind("skeleton")
    assert %Range{} = sk.levels
    assert is_tuple(sk.hp)
    assert [{_, _} | _] = sk.weapons
    assert BaconWorld.Merchants.get("tilda").sells != []
    assert is_binary(BaconWorld.Merchants.get("tilda").look["body"])

    Defs.put("monster", "skeleton", %{sk | name: "a rattling skeleton"})
    assert BaconWorld.Mobs.Spawns.kind("skeleton").name == "a rattling skeleton"
    assert Defs.decode(Defs.encode(sk)) == sk
  end
end
