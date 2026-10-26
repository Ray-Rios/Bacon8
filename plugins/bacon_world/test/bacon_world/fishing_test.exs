defmodule BaconWorld.FishingTest do
  # The water (BaconWorld.Water) and fishing (BaconWorldWeb.FishingEvents), 2026-10-26: where the
  # sea and the Millpond are, who may cast where, the bite and the reel, what is caught, and Old
  # Bram who sells the poles.
  use Bacon8.DataCase, async: false

  alias BaconWorld.{Inventory, Items, Merchants, Models, Water, World}
  alias BaconWorld.Mobs.Brain
  alias BaconWorldWeb.FishingEvents

  setup do
    dir = Path.join(System.tmp_dir!(), "bacon_world_fish_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "heroes"))
    File.write!(Path.join(dir, "heroes/runner.glb"), "glTF")
    Application.put_env(:bacon8, Models, roots: [dir])

    on_exit(fn ->
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    {:ok, c} = World.create_character(Ecto.UUID.generate(), %{"name" => "Angler", "character_type" => "Adventurer", "model_path" => "/models/heroes/runner.glb"})
    %{c: c, lake: hd(Water.lakes())}
  end

  defp socket(c, {x, z}, extra \\ %{}) do
    u = Brain.u()
    assigns = Map.merge(%{__changed__: %{}, mobs_zone: "lobby", current_character_runtime: %{character_id: c.id, position: %{x: x * u, y: 0.0, z: z * u}}}, extra)
    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  # on the lake's east bank (1.5 m from the water), and a spot on the water in front
  defp bank(l), do: {l.x + l.rx + 1.5, l.z}
  defp on_lake(l), do: %{"x" => (l.x + l.rx - 3.0) * Brain.u(), "z" => l.z * Brain.u()}

  defp hold_pole(c) do
    {:ok, [slot]} = Inventory.add(c.id, "fishing_pole")
    :ok = Inventory.move(c.id, slot, "main") |> then(fn {:ok, _} -> :ok; other -> other end)
  end

  defp cast!(s, l) do
    {:reply, %{ok: true, water: "lake"}, s} = FishingEvents.handle_event("fish_cast", on_lake(l), s)
    s
  end

  describe "the water" do
    test "the sea all round, the Millpond, land between", %{lake: l} do
      assert Water.kind_at(l.x, l.z) == :lake
      assert Water.kind_at(0.0, 0.0) == nil
      assert Water.kind_at(Water.shore() + 5, 0.0) == :ocean
      assert Water.kind_at(0.0, -(Water.shore() + 1)) == :ocean
      assert Water.kind_at(l.x + l.rx + 0.5, l.z) == nil
    end

    test "near: the bank of the lake, the beach, not the village", %{lake: l} do
      assert Water.near(l.x + l.rx + 2.0, l.z, Water.bank()) == :lake
      assert Water.near(l.x, l.z + l.rz + 2.5, Water.bank()) == :lake
      assert Water.near(l.x + l.rx + 5.0, l.z, Water.bank()) == nil
      assert Water.near(Water.shore() - 1.0, 0.0, Water.bank()) == :ocean
      assert Water.near(0.0, 0.0, Water.bank()) == nil
    end

    test "casting: from the bank onto the water, within reach", %{lake: l} do
      {px, pz} = bank(l)
      assert {:ok, :lake} = Water.cast(px, pz, l.x + l.rx - 3.0, l.z)
      assert {:error, :not_at_water} = Water.cast(0.0, 0.0, l.x, l.z)
      assert {:error, :not_on_water} = Water.cast(px, pz, px + 1.0, pz)
      assert {:error, :too_far} = Water.cast(px, pz, l.x - l.rx + 1.0, l.z)
      assert {:ok, :ocean} = Water.cast(Water.shore() - 1.0, 0.0, Water.shore() + 4.0, 0.0)
    end

    test "nobody walks out to sea" do
      assert Water.walkable?(Water.shore(), 0.0)
      refute Water.walkable?(Water.walk_radius() + 0.5, 0.0)
    end

    test "the client gets it in scene units", %{lake: l} do
      u = Brain.u()
      layout = Water.layout(u)
      assert_in_delta layout.shore, Water.shore() * u, 1.0e-9
      assert [%{id: "millpond", x: x, rx: rx}] = layout.lakes
      assert_in_delta x, l.x * u, 1.0e-9
      assert_in_delta rx, l.rx * u, 1.0e-9
    end
  end

  describe "what bites" do
    test "every catch is a real item, sells, stacks and has its own icon" do
      for kind <- [:lake, :ocean], {id, w} <- Water.catches(kind) do
        item = Items.get(id)
        assert item, id
        assert w > 0
        assert item.kind == "junk" and item.stack == 20 and item.value > 0
        assert item.icon_url == "/plugins/bacon_world/icons/#{id}.png"
        assert Merchants.buy_price(item) >= 1
      end
    end

    test "the roll walks the weights: low rolls the first, high rolls the last" do
      [{first, _} | _] = Water.catches(:lake)
      {last, _} = List.last(Water.catches(:ocean))
      assert Water.roll(:lake, 0.0) == first
      assert Water.roll(:ocean, 0.99999) == last
      # every fish turns up over many rolls
      seen = MapSet.new(for i <- 0..999, do: Water.roll(:lake, i / 1000))
      assert MapSet.size(seen) == length(Water.catches(:lake))
    end

    test "Old Bram sells the pole, which is held two-handed" do
      bram = Merchants.get("bram")
      assert bram.title == "Angler" and bram.sells == ["fishing_pole"]
      assert Water.near(bram.x, bram.z, Water.bank()) == :lake
      pole = Items.get("fishing_pole")
      assert %{hands: 2, model: "FishingPole", slots: ["main"]} = pole
      assert Items.catalog_payload()["fishing_pole"].icon_url == "/plugins/bacon_world/icons/fishing_pole.png"
    end
  end

  describe "fishing" do
    test "no pole, no fishing; and not from the village", %{c: c, lake: l} do
      assert {:reply, %{ok: false, error: "You need a fishing pole" <> _}, _} = FishingEvents.handle_event("fish_cast", on_lake(l), socket(c, bank(l)))
      hold_pole(c)
      assert {:reply, %{ok: false, error: "You need to stand at the water's edge" <> _}, _} = FishingEvents.handle_event("fish_cast", on_lake(l), socket(c, {0.0, 0.0}))
      assert {:reply, %{ok: false, error: "Your line has to land on the water."}, _} =
               FishingEvents.handle_event("fish_cast", %{"x" => 0.0, "z" => 0.0}, socket(c, bank(l)))
    end

    test "reeling in before a bite catches nothing", %{c: c, lake: l} do
      hold_pole(c)
      s = cast!(socket(c, bank(l)), l)
      assert %{token: _, kind: :lake, bite_at: nil} = s.assigns.fishing
      assert {:reply, %{ok: false, result: "early"}, s} = FishingEvents.handle_event("fish_reel", %{}, s)
      assert s.assigns.fishing == nil
    end

    test "a bite, reeled in at once, lands lake fish in the bags (mostly)", %{c: c, lake: l} do
      hold_pole(c)
      :rand.seed(:exsss, {7, 8, 9})

      results =
        for _ <- 1..20 do
          s = cast!(socket(c, bank(l)), l)
          s = FishingEvents.bite(s.assigns.fishing.token, s)
          assert s.assigns.fishing.bite_at
          {:reply, %{result: r}, _} = FishingEvents.handle_event("fish_reel", %{}, s)
          r
        end

      assert Enum.all?(results, &(&1 in ["caught", "slipped"]))
      assert Enum.count(results, &(&1 == "caught")) >= 10
      # (a new character also carries its starter kit: look at the fish only)
      lake_fish = MapSet.new(Water.catches(:lake), &elem(&1, 0))
      sea_fish = MapSet.new(Water.catches(:ocean), &elem(&1, 0))
      caught = for i <- Inventory.list(c.id), MapSet.member?(lake_fish, i.item_id) or MapSet.member?(sea_fish, i.item_id), do: i.item_id
      assert caught != [] and Enum.all?(caught, &MapSet.member?(lake_fish, &1))
    end

    test "too late, or walked off: the fish is gone", %{c: c, lake: l} do
      hold_pole(c)
      s = cast!(socket(c, bank(l)), l)
      s = FishingEvents.bite(s.assigns.fishing.token, s)
      late = %{s | assigns: %{s.assigns | fishing: %{s.assigns.fishing | bite_at: System.monotonic_time(:millisecond) - 5_000}}}
      assert {:reply, %{result: "late"}, _} = FishingEvents.handle_event("fish_reel", %{}, late)

      s = cast!(socket(c, bank(l)), l)
      s = FishingEvents.bite(s.assigns.fishing.token, s)
      {bx, bz} = bank(l)
      walked = socket(c, {bx + 6.0, bz}, %{fishing: s.assigns.fishing})
      assert {:reply, %{result: "moved"}, _} = FishingEvents.handle_event("fish_reel", %{}, walked)
    end

    test "an unanswered bite escapes; a stale message does nothing", %{c: c, lake: l} do
      hold_pole(c)
      s = cast!(socket(c, bank(l)), l)
      token = s.assigns.fishing.token
      assert FishingEvents.bite(make_ref(), s).assigns.fishing.bite_at == nil
      s = FishingEvents.bite(token, s)
      assert FishingEvents.escape(make_ref(), s).assigns.fishing
      assert FishingEvents.escape(token, s).assigns.fishing == nil
    end

    test "fish_stop brings the line in", %{c: c, lake: l} do
      hold_pole(c)
      s = cast!(socket(c, bank(l)), l)
      assert {:reply, %{ok: true}, s} = FishingEvents.handle_event("fish_stop", %{}, s)
      assert s.assigns.fishing == nil
    end
  end
end
