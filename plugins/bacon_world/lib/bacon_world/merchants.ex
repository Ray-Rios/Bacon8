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
    %{
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
                cloth_tunic blue_dyed_tunic cloth_tank wool_sweater cloth_shorts cloth_trousers cloth_shoes leather_boots)
    }
  ]

  @by_id Map.new(@merchants, &{&1.id, &1})

  @doc "How close (metres) a player must stand to trade."
  def reach, do: @reach

  @doc "A merchant by id, or nil."
  def get(id) when is_binary(id), do: Map.get(@by_id, id)
  def get(_), do: nil

  @doc "The merchants in a zone."
  def in_zone(zone), do: Enum.filter(@merchants, &(&1.zone == zone))

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

    for m <- in_zone(zone) do
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
        gear: m.gear
      }
    end
  end
end
