defmodule BaconWorld.Merchants do
  @moduledoc """
  Merchants: villagers who sell from a fixed stock and buy what players bring them,
  EverQuest style. Each stands at a market stall; a player within `reach/0` metres
  can open the merchant (right-click), buy from the list, and sell from the bags.

  Money is copper (`BaconWorld.Inventory`): a merchant sells an item for its
  `value` and buys it for a quarter of that (at least a copper for anything worth
  something), so a player can't buy and sell for profit.

  Merchants are fixed data, like the item catalogue. Positions are metres in the
  zone's layout (the client's village, `world-dressing.ts`); `payload/1` converts
  them to scene units.
  """

  alias BaconWorld.Items
  alias BaconWorld.Mobs.Brain

  @reach 6.0
  @buy_rate 0.25

  @merchants [
    # The stablemaster (2026-10-24): no stock; she keeps your mounts. Talking to her
    # (R) opens the stable (BaconWorldWeb.MountEvents): pick which of your mounts you
    # ride, or follow a link to buy one in the Bacon Store.
    %{
      id: "rowena",
      kind: "stable",
      name: "Rowena Ashby",
      title: "Stablemaster",
      zone: "lobby",
      # by the paddock south-east of the plaza, facing the statue
      x: 12.5,
      z: 13.0,
      face: {0.0, 16.0},
      look: %{
        "v" => 1,
        "body" => "female",
        "height" => 1.0,
        "shape" => %{"weight" => 0.1, "muscle" => 0.35, "shoulders" => 0.3, "chest" => 0.0, "belly" => 0.0, "hips" => 0.2, "glutes" => 0.1, "face" => 0.2, "jaw" => 0.2, "nose" => 0.1},
        "skin" => "#C98E68",
        "eyes" => "#5A4632",
        "brows" => nil,
        "hair" => %{"style" => "Ponytail", "color" => "#3A2418"},
        "facial" => %{"style" => "none", "color" => "#3A2418"}
      },
      gear: %{
        "under_top" => "linen_bikini_top",
        "under_bottom" => "linen_bikini_bottom",
        "chest" => "cloth_tunic",
        "legs" => "cloth_trousers",
        "feet" => "leather_boots"
      },
      sells: []
    },
    %{
      kind: "trader",
      id: "tilda",
      name: "Tilda Threadwell",
      title: "Clothier",
      zone: "lobby",
      # behind the stall north-east of the well, facing the plaza
      x: 15.5,
      z: -6.7,
      face: {0.0, 0.0},
      look: %{
        "v" => 1,
        "body" => "female",
        "height" => 0.97,
        "shape" => %{"weight" => 0.15, "muscle" => 0.1, "shoulders" => 0.1, "chest" => 0.25, "belly" => 0.2, "hips" => 0.35, "glutes" => 0.1, "face" => 0.3, "jaw" => 0.1, "nose" => 0.2},
        "skin" => "#E5B08C",
        "eyes" => "#3E6E58",
        "brows" => nil,
        "hair" => %{"style" => "BraidBun", "color" => "#8E5A35"},
        "facial" => %{"style" => "none", "color" => "#8E5A35"}
      },
      gear: %{
        "under_top" => "linen_bikini_top",
        "under_bottom" => "linen_bikini_bottom",
        "chest" => "wool_sweater",
        "legs" => "cloth_trousers",
        "feet" => "leather_boots"
      },
      sells: ~w(linen_bikini_top linen_bikini_bottom athletic_top athletic_bottom rose_lace_top rose_lace_bottom
                coral_top coral_bottom polka_dot_top polka_dot_bottom emerald_top emerald_bottom
                cloth_tunic blue_dyed_tunic cloth_tank wool_sweater cloth_shorts cloth_trousers cloth_shoes leather_boots
                robin_hood_hat)
    },
    # The angler (2026-10-26): on the Millpond's east bank (BaconWorld.Water), facing the water.
    # Sells fishing poles; like every merchant, buys what you bring (the catch included).
    %{
      kind: "trader",
      id: "bram",
      name: "Old Bram",
      title: "Angler",
      zone: "lobby",
      x: -16.5,
      z: -39.0,
      face: {-31.0, -40.0},
      look: %{
        "v" => 1,
        "body" => "male",
        "height" => 0.98,
        "shape" => %{"weight" => 0.35, "muscle" => 0.15, "shoulders" => 0.0, "chest" => 0.0, "belly" => 0.45, "hips" => 0.1, "glutes" => 0.0, "face" => 0.4, "jaw" => 0.3, "nose" => 0.4},
        "skin" => "#D9A17E",
        "eyes" => "#4F6A7A",
        "brows" => nil,
        "hair" => %{"style" => "Short", "color" => "#B9B2A6"},
        "facial" => %{"style" => "FullBeard", "color" => "#B9B2A6"}
      },
      gear: %{
        "under_bottom" => "linen_bikini_bottom",
        "chest" => "wool_sweater",
        "legs" => "cloth_trousers",
        "feet" => "leather_boots"
      },
      sells: ~w(fishing_pole hunting_bow)
    }
  ]

  @by_id Map.new(@merchants, &{&1.id, &1})

  # What build mode can place (2026-10-28, BaconWorld.Building): each kind of person, with a few
  # looks to tell copies apart (picked by the placement's id). Merchants sell their village
  # counterpart's stock.
  @clothes %{"under_top" => "linen_bikini_top", "under_bottom" => "linen_bikini_bottom", "chest" => "cloth_tunic", "legs" => "cloth_trousers", "feet" => "leather_boots"}
  @his_clothes %{"under_bottom" => "linen_bikini_bottom", "chest" => "cloth_tunic", "legs" => "cloth_trousers", "feet" => "cloth_shoes"}
  @villager_looks [
    %{name: "Mira", look: %{"v" => 1, "body" => "female", "height" => 0.99, "shape" => %{"weight" => 0.1, "muscle" => 0.1, "hips" => 0.25, "face" => 0.2}, "skin" => "#E8B898", "eyes" => "#4C6A8A", "brows" => nil, "hair" => %{"style" => "LooseBraid", "color" => "#6B4228"}, "facial" => %{"style" => "none", "color" => "#6B4228"}}, gear: @clothes},
    %{name: "Hob", look: %{"v" => 1, "body" => "male", "height" => 1.0, "shape" => %{"weight" => 0.3, "muscle" => 0.3, "belly" => 0.3, "jaw" => 0.3}, "skin" => "#C98E68", "eyes" => "#4F3A26", "brows" => nil, "hair" => %{"style" => "Messy", "color" => "#2E2016"}, "facial" => %{"style" => "ShortBeard", "color" => "#2E2016"}}, gear: @his_clothes},
    %{name: "Wenna", look: %{"v" => 1, "body" => "female", "height" => 0.96, "shape" => %{"weight" => 0.3, "belly" => 0.2, "hips" => 0.35, "face" => 0.4}, "skin" => "#B57A55", "eyes" => "#3B2B1E", "brows" => nil, "hair" => %{"style" => "Bun", "color" => "#1C1410"}, "facial" => %{"style" => "none", "color" => "#1C1410"}}, gear: Map.put(@clothes, "chest", "wool_sweater")},
    %{name: "Aldric", look: %{"v" => 1, "body" => "male", "height" => 1.03, "shape" => %{"weight" => 0.0, "muscle" => 0.5, "shoulders" => 0.3, "face" => 0.2}, "skin" => "#EBC3A4", "eyes" => "#5E7F4F", "brows" => nil, "hair" => %{"style" => "SweptBack", "color" => "#C89B5B"}, "facial" => %{"style" => "Stubble", "color" => "#C89B5B"}}, gear: Map.put(@his_clothes, "chest", "blue_dyed_tunic")}
  ]
  @templates [
    %{id: "villager", label: "a villager", kind: "villager", title: "Villager", sells: [], looks: @villager_looks,
      greeting: "Fine day, isn't it?"},
    %{id: "clothier", label: "a clothier", kind: "trader", title: "Clothier", sells: @by_id["tilda"].sells,
      looks: [%{name: "Elsa Weaver", look: @by_id["tilda"].look, gear: @by_id["tilda"].gear} | Enum.take(@villager_looks, 1)]},
    %{id: "angler", label: "an angler", kind: "trader", title: "Angler", sells: @by_id["bram"].sells,
      looks: [%{name: "Brann Tull", look: @by_id["bram"].look, gear: @by_id["bram"].gear}, Enum.at(@villager_looks, 1)]},
    %{id: "stablemaster", label: "a stablemaster", kind: "stable", title: "Stablemaster", sells: [],
      looks: [%{name: "Pip Ashby", look: @by_id["rowena"].look, gear: @by_id["rowena"].gear}, Enum.at(@villager_looks, 3)]}
  ]

  @doc "How close (metres) a player must stand to trade."
  def reach, do: @reach

  @doc "A merchant by id, or nil."
  def get("p:" <> _ = id), do: BaconWorld.Building.npc_by_id(id)
  def get(id) when is_binary(id), do: Map.get(@by_id, id)
  def get(_), do: nil

  @doc "The merchants in a zone: the village's own and those placed in build mode (`BaconWorld.Building`)."
  def in_zone(zone), do: Enum.filter(@merchants, &(&1.zone == zone)) ++ BaconWorld.Building.npcs(zone)

  @doc """
  The NPCs build mode can place (`"npc:<id>"` in `BaconWorld.Building`'s catalogue): a villager
  who only greets you, and one of each kind of merchant, with the village merchant's stock.
  """
  def templates, do: @templates

  @doc """
  A placed NPC (a `BaconWorld.Placement` of `"npc:<template>"`) as a merchant: id
  `"p:<placement id>"`, its template's kind, title and stock, a look picked from the template's
  by the placement's id, facing where it was turned to. Nil for an unknown template.
  """
  def placed(template_id, %{id: pid, x: x, z: z, rot: rot, zone: zone, data: data}) do
    case Enum.find(@templates, &(&1.id == template_id)) do
      nil ->
        nil

      t ->
        looks = t.looks
        look = Enum.at(looks, :erlang.phash2(pid, length(looks)))
        name = case (data || %{})["name"] do
          n when is_binary(n) and n != "" -> n
          _ -> look.name
        end

        %{id: "p:" <> pid, kind: t.kind, name: name, title: t.title, zone: zone, x: x, z: z,
          face: {x + :math.sin(rot) * 4.0, z + :math.cos(rot) * 4.0}, look: look.look, gear: look.gear, sells: t.sells, greeting: t[:greeting]}
    end
  end

  @doc "What a merchant asks for an item (copper)."
  def sell_price(item), do: item.value

  @doc "What a merchant pays for one of an item (copper; 0 for worthless things)."
  def buy_price(%{value: v}) when is_integer(v) and v > 0, do: max(1, trunc(v * @buy_rate))
  def buy_price(_), do: 0

  @doc "The merchant's list: `[%{item_id, price}]`, in the order it is shown."
  def stock(%{sells: ids}) do
    for id <- ids, item = Items.get(id), do: %{item_id: id, price: sell_price(item)}
  end

  @doc "True when a position (scene units) is within reach of the merchant."
  def near?(%{x: x, z: z}, {px, pz}) do
    u = Brain.u()
    dx = px / u - x
    dz = pz / u - z
    dx * dx + dz * dz <= @reach * @reach
  end

  @doc "What the client needs to draw a zone's merchants (scene units)."
  def payload(zone) do
    u = Brain.u()

    for m <- in_zone(zone), do: npc_payload(m, u)
  end

  @doc "One merchant as the client draws it (scene units)."
  def npc_payload(m, u \\ Brain.u())
  def npc_payload(nil, _u), do: nil

  def npc_payload(m, u) do
    {fx, fz} = m.face

    %{
      id: m.id,
      name: m.name,
      title: m.title,
      x: m.x * u,
      z: m.z * u,
      face_x: fx * u,
      face_z: fz * u,
      appearance: m.look,
      gear: m.gear,
      kind: Map.get(m, :kind, "trader")
    }
  end
end
