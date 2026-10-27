defmodule BaconWorld.Mounts do
  @moduledoc """
  Mounts: dragons you ride, on the ground and in the air (2026-10-24), and the Kraken you
  ride through the water (2026-10-27).

  Every mount is a boss's model and rig scaled down (`model`: "dragon" is
  `Mobs/B8_Dragon.glb`, tinted by `colors`; "kraken" is `Mobs/B8_Kraken.glb`). A mount that
  `swims` crosses deep water at `swim_speed` instead of its rider swimming.

  Mounts fight (`attacks`, `"mount_attack"` in `BaconWorldWeb.GameEvents`): the left and right
  attack buttons are the mount's two moves while riding. Each is a swing the zone resolves like a
  weapon's (`dmg`, `dly` in tenths of a second, `reach` and `arc` metres/degrees, up to `targets`
  creatures), plus `root_ms` (they're held). Creatures only, not players. Owning one is an entitlement of kind `"bacon_world_mount"` whose key is
  the mount's id (`kind/0`): the Bacon Store sells it as a game item
  (`ensure_store_products/0` creates the products, switched off, for an admin to
  price and publish). Admins ride every mount, to test them.

  A rider summons the mount (`"mount_summon"` in `BaconWorldWeb.PlayLive`), rides
  it at its ground speed, and with one that flies double-taps Space to take off
  (RaysSpaceSim's double-tap, without the rolls). The mount rides in the zone
  presence (`mount`), so everyone draws it.
  """

  alias Bacon8.Entitlements

  @kind "bacon_world_mount"

  # The moves (see the moduledoc). A dragon claws (left) and breathes fire in a cone (right).
  @dragon_attacks %{
    "left" => %{move: "claw", name: "Claw Swipe", dmg: 14, dly: 20, reach: 3.2, arc: 110, targets: 2},
    "right" => %{move: "fire", name: "Fire Breath", dmg: 17, dly: 45, reach: 10.0, arc: 50, targets: 6}
  }
  # The Kraken lashes with its arms (left) and drags everything round it into a maelstrom, holding
  # it there (right).
  @kraken_attacks %{
    "left" => %{move: "lash", name: "Tentacle Lash", dmg: 16, dly: 22, reach: 6.0, arc: 140, targets: 3},
    "right" => %{move: "maelstrom", name: "Maelstrom", dmg: 13, dly: 60, reach: 7.5, arc: 360, targets: 8, root_ms: 3_000}
  }

  # Speeds in metres per second; colours for the client's tint of the dragon's materials.
  @mounts [
    %{
      id: "ember_drake",
      model: "dragon",
      swims: false,
      attacks: @dragon_attacks,
      name: "Ember Drake",
      summary: "A young red dragon of Baconator's brood. Flies.",
      scale: 0.38,
      ground_speed: 10.0,
      fly_speed: 17.0,
      flies: true,
      colors: %{scales: "#A8341A", belly: "#D9A55C", membrane: "#6E1C10", horn: "#2B1F19", eye: "#FFB020"},
      price_cents: 1500
    },
    %{
      id: "verdant_drake",
      model: "dragon",
      swims: false,
      attacks: @dragon_attacks,
      name: "Verdant Drake",
      summary: "A green forest dragon. Flies.",
      scale: 0.38,
      ground_speed: 10.0,
      fly_speed: 17.0,
      flies: true,
      colors: %{scales: "#3E6B2A", belly: "#C9C27A", membrane: "#2E4A1E", horn: "#3A3026", eye: "#E8F05A"},
      price_cents: 1500
    },
    %{
      id: "frost_drake",
      model: "dragon",
      swims: false,
      attacks: @dragon_attacks,
      name: "Frost Drake",
      summary: "A pale dragon from the high peaks. Flies.",
      scale: 0.38,
      ground_speed: 10.0,
      fly_speed: 18.0,
      flies: true,
      colors: %{scales: "#9FB7C9", belly: "#E9EEF2", membrane: "#5D7E96", horn: "#2C3640", eye: "#7FE3FF"},
      price_cents: 1800
    },
    %{
      id: "abyssal_kraken",
      model: "kraken",
      name: "Abyssal Kraken",
      summary: "A kraken of the Crater Lake's brood. Can't fly; swims very fast. Slow on land.",
      scale: 0.3,
      ground_speed: 4.0,
      fly_speed: 0.0,
      swim_speed: 22.0,
      flies: false,
      swims: true,
      attacks: @kraken_attacks,
      colors: %{},
      price_cents: 2500
    }
  ]

  @by_id Map.new(@mounts, &{&1.id, &1})

  @doc "The entitlement kind a mount purchase grants."
  def kind, do: @kind

  def all, do: @mounts
  def get(id) when is_binary(id), do: Map.get(@by_id, id)
  def get(_), do: nil

  @doc "What the client needs about every mount."
  def catalog_payload do
    Map.new(@mounts, fn m ->
      spec = Map.take(m, [:id, :model, :name, :summary, :scale, :ground_speed, :fly_speed, :swim_speed, :flies, :swims, :colors])
      {m.id, Map.put(spec, :attacks, Map.new(m.attacks, fn {hand, a} -> {hand, Map.take(a, [:move, :name, :reach, :dly])} end))}
    end)
  end

  @doc "The ids of the mounts a user may ride (admins: all of them)."
  def owned(nil), do: []

  def owned(user) do
    if admin?(user) do
      Enum.map(@mounts, & &1.id)
    else
      keys = user |> Entitlements.active(@kind) |> Enum.map(& &1.key)
      if "*" in keys, do: Enum.map(@mounts, & &1.id), else: Enum.filter(Enum.map(@mounts, & &1.id), &(&1 in keys))
    end
  rescue
    _ -> []
  end

  @doc "A mount's move for a hand (\"left\" | \"right\"), or nil."
  def attack(%{attacks: attacks}, hand), do: Map.get(attacks, hand)
  def attack(_mount, _hand), do: nil

  @doc "The move as a swing for `BaconWorld.Mobs.Brain.melee/4` (an item map) and its sweep."
  def attack_item(a), do: %{id: "mount_" <> a.move, name: a.name, dmg: a.dmg, dly: a.dly, reach: a.reach, hands: 2}

  def owns?(user, id), do: is_binary(id) and not is_nil(get(id)) and id in owned(user)

  @doc "Each mount's page in the Bacon Store (`/store/p/mount-<id>`), for the stable's \"Buy\" links."
  def store_paths, do: Map.new(@mounts, &{&1.id, "/store/p/" <> store_slug(&1.id)})

  defp store_slug(id), do: "mount-" <> String.replace(id, "_", "-")

  defp admin?(%{role: "admin"}), do: true
  defp admin?(%{is_admin: true}), do: true
  defp admin?(_), do: false

  @doc """
  Creates a Bacon Store game item for every mount that has none yet (slug
  `mount-<id>`), switched off. An admin sets the price and publishes it on
  /admin/bacon_store/products. Run once, e.g.
  `bin/bacon8 rpc "BaconWorld.Mounts.ensure_store_products()"`. Needs the store plugin.
  """
  def ensure_store_products do
    catalog = Module.concat([BaconStore, Store, Catalog])

    if Code.ensure_loaded?(catalog) do
      for m <- @mounts do
        slug = store_slug(m.id)

        case apply(catalog, :get_active_product_by_slug, [slug]) do
          nil ->
            apply(catalog, :create_product, [
              %{
                "kind" => "item",
                "slug" => slug,
                "name" => m.name <> " (mount)",
                "summary" => m.summary,
                "description" => m.summary <> if(m.flies, do: " Ride it in Bacon World: summon it with M, double-tap Space to fly.", else: " Ride it in Bacon World: summon it with M."),
                "price_cents" => m.price_cents,
                "price_gems" => m.price_cents,
                "grant_kind" => @kind,
                "grant_key" => m.id,
                "one_per_user" => true,
                "active" => false
              }
            ])

          product ->
            {:exists, product}
        end
      end
    else
      {:error, :no_store}
    end
  end
end
