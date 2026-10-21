defmodule BaconStore.Store.Product do
  @moduledoc """
  Something the store sells (BACON8.md §8). The `kind` decides what a
  purchase delivers (see `BaconStore.Store.Fulfilment`):

  | kind          | delivers                                                        |
  |---------------|-----------------------------------------------------------------|
  | `gem_pack`    | Gems (`gems`, plus `bonus_gems` while a promotion runs)         |
  | `download`    | the product's download files, kept forever                      |
  | `item`        | an entitlement a game reads: `grant_kind` (declared by a game   |
  |               | plugin's `entitlement_kinds/0`), `grant_key`, `grant_quantity`, |
  |               | optionally for `duration_days`                                  |
  | `access`      | `grant_kind` "channel": membership of the chat channel          |
  |               | `grant_key` for `duration_days` (empty = forever); or           |
  |               | "channel_slots": `grant_quantity` more channels the buyer may   |
  |               | create                                                          |
  | `license_key` | one code from the product's key pool                            |

  Prices: `price_cents` (card, US$) and/or `price_gems`. A Gem pack is card
  only, at the house rate (100 Gems = $1).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(gem_pack download item access license_key)
  @access_kinds ~w(channel channel_slots)

  # Stripe won't take a card payment under US$0.50.
  @min_card_cents 50

  def kinds, do: @kinds
  def access_kinds, do: @access_kinds
  def min_card_cents, do: @min_card_cents

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "store_products" do
    field :slug, :string
    field :kind, :string
    field :name, :string
    field :summary, :string
    field :description, :string
    field :price_cents, :integer
    field :currency, :string, default: "usd"
    field :price_gems, :integer
    field :gems, :integer
    field :bonus_gems, :integer, default: 0
    field :promo_starts_at, :utc_datetime
    field :promo_ends_at, :utc_datetime
    field :grant_kind, :string
    field :grant_key, :string
    field :grant_quantity, :integer, default: 1
    field :duration_days, :integer
    field :one_per_user, :boolean, default: false
    field :badge, :string
    field :active, :boolean, default: true
    field :sort_order, :integer, default: 0
    field :stripe_price_id, :string
    field :paypal_plan_id, :string

    belongs_to :category, BaconStore.Store.Category
    has_many :files, BaconStore.Store.ProductFile

    timestamps(type: :utc_datetime_usec)
  end

  @fields [:slug, :kind, :name, :summary, :description, :category_id, :price_cents, :currency, :price_gems,
           :gems, :bonus_gems, :promo_starts_at, :promo_ends_at, :grant_kind, :grant_key, :grant_quantity,
           :duration_days, :one_per_user, :badge, :active, :sort_order, :stripe_price_id, :paypal_plan_id]

  def changeset(product, attrs) do
    product
    |> cast(attrs, @fields, empty_values: [nil, ""])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:slug, &(&1 && &1 |> String.trim() |> String.downcase()))
    |> validate_required([:slug, :kind, :name, :currency])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:currency, ["usd"])
    |> validate_length(:name, max: 120)
    |> validate_length(:summary, max: 200)
    |> validate_length(:badge, max: 30)
    |> validate_format(:slug, ~r/\A[a-z0-9][a-z0-9_-]*\z/, message: "use lowercase letters, numbers, - and _")
    |> validate_length(:slug, max: 80)
    |> validate_number(:price_cents, greater_than_or_equal_to: @min_card_cents, message: "card prices start at $0.50")
    |> validate_number(:price_gems, greater_than: 0)
    |> validate_number(:bonus_gems, greater_than_or_equal_to: 0)
    |> validate_number(:grant_quantity, greater_than: 0, less_than_or_equal_to: 1_000_000)
    |> validate_number(:duration_days, greater_than: 0, less_than_or_equal_to: 36_500)
    |> validate_number(:sort_order, greater_than_or_equal_to: -1_000_000, less_than_or_equal_to: 1_000_000)
    |> validate_prices()
    |> validate_kind()
    |> validate_promo()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:category_id)
  end

  defp validate_prices(changeset) do
    cents = get_field(changeset, :price_cents)
    gems = get_field(changeset, :price_gems)

    cond do
      get_field(changeset, :kind) == "gem_pack" ->
        changeset
        |> validate_required([:price_cents], message: "a Gem pack needs a card price")
        |> then(&if(gems, do: add_error(&1, :price_gems, "Gems can't be bought with Gems"), else: &1))

      is_nil(cents) and is_nil(gems) ->
        add_error(changeset, :price_cents, "set a card price, a Gem price, or both")

      true ->
        changeset
    end
  end

  # A Gem pack sells Gems at the house rate (BaconStore.Store.gems_per_dollar/0):
  # its Gems are its price. Extra Gems are only ever a time-limited promotion.
  defp validate_kind(changeset) do
    case get_field(changeset, :kind) do
      "gem_pack" ->
        changeset
        |> validate_required([:gems])
        |> validate_number(:gems, greater_than: 0)
        |> then(fn cs ->
          price = get_field(cs, :price_cents)
          gems = get_field(cs, :gems)

          if is_integer(price) and is_integer(gems) and gems * 100 != price * BaconStore.Store.gems_per_dollar(),
            do: add_error(cs, :gems, "must be the price at #{BaconStore.Store.gems_per_dollar()} Gems per dollar; use bonus Gems for a promotion"),
            else: cs
        end)

      "item" ->
        changeset
        |> validate_required([:grant_kind, :grant_key], message: "required for a game item")
        |> validate_format(:grant_kind, ~r/\A[a-z0-9_.:-]+\z/, message: "lowercase letters, numbers and . _ : -")
        |> validate_length(:grant_key, max: 120)

      "access" ->
        changeset
        |> validate_required([:grant_kind], message: "choose channel access or channel slots")
        |> validate_inclusion(:grant_kind, @access_kinds)
        |> then(fn cs ->
          case get_field(cs, :grant_kind) do
            "channel" ->
              cs
              |> validate_required([:grant_key], message: "choose a channel")
              |> validate_change(:grant_key, fn :grant_key, v ->
                if match?({:ok, _}, Ecto.UUID.cast(v)), do: [], else: [grant_key: "choose a channel"]
              end)

            # Slots are permanent: a channel can't be taken away when they lapse.
            "channel_slots" ->
              put_change(cs, :duration_days, nil)

            _ ->
              cs
          end
        end)

      _ ->
        changeset
    end
  end

  defp validate_promo(changeset) do
    starts = get_field(changeset, :promo_starts_at)
    ends = get_field(changeset, :promo_ends_at)

    if starts && ends && DateTime.compare(ends, starts) != :gt,
      do: add_error(changeset, :promo_ends_at, "must be after the start"),
      else: changeset
  end
end
