defmodule BaconWorld.Mounts do
  @moduledoc """
  Mounts: dragons you ride, on the ground and in the air (2026-10-24).

  Every mount is the boss's model and rig (`Mobs/B8_Dragon.glb`) scaled down and
  tinted. Owning one is an entitlement of kind `"bacon_world_mount"` whose key is
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

  # Speeds in metres per second; colours for the client's tint of the dragon's materials.
  @mounts [
    %{
      id: "ember_drake",
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
      name: "Frost Drake",
      summary: "A pale dragon from the high peaks. Flies.",
      scale: 0.38,
      ground_speed: 10.0,
      fly_speed: 18.0,
      flies: true,
      colors: %{scales: "#9FB7C9", belly: "#E9EEF2", membrane: "#5D7E96", horn: "#2C3640", eye: "#7FE3FF"},
      price_cents: 1800
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
    Map.new(@mounts, fn m -> {m.id, Map.take(m, [:id, :name, :summary, :scale, :ground_speed, :fly_speed, :flies, :colors])} end)
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

  def owns?(user, id), do: is_binary(id) and not is_nil(get(id)) and id in owned(user)

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
        slug = "mount-" <> String.replace(m.id, "_", "-")

        case apply(catalog, :get_active_product_by_slug, [slug]) do
          nil ->
            apply(catalog, :create_product, [
              %{
                "kind" => "item",
                "slug" => slug,
                "name" => m.name <> " (mount)",
                "summary" => m.summary,
                "description" => m.summary <> " Ride it in Bacon World: summon it with M, double-tap Space to fly.",
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
