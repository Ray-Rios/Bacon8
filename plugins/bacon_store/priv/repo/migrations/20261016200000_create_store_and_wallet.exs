defmodule Bacon8.Repo.Migrations.CreateStoreAndWallet do
  @moduledoc """
  Milestone 4, first slice (BACON8.md §8): Gems, the store, and the payment
  event inbox.

    * `wallet_accounts`, `wallet_transactions`, `wallet_entries` - a
      double-entry ledger. Every transaction's entries sum to zero; an
      account's `balance` is a cache of its entries' sum, updated in the same
      transaction.
    * `store_products`, `store_orders` - what's for sale (Gem packs now,
      subscription plans and items later) and one order per purchase.
    * `payment_events` - every provider event, stored before it is processed;
      `unique(provider, provider_event_id)` makes a re-delivery a no-op.

  New tables, prefixed `store_` / `wallet_`: the old shop's `products`,
  `orders`, `carts` ... stay untouched until they're retired.

  Seeds the launch Gem packs (100 Gems = US$1, no bonus).
  """
  use Ecto.Migration

  def change do
    create table(:wallet_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # "user" (user_id set) or "system" (name set: "gem_sales", "gem_spend", ...)
      add :owner_type, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :name, :string
      add :currency, :string, null: false
      add :balance, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:wallet_accounts, [:user_id, :currency], where: "user_id IS NOT NULL")
    create unique_index(:wallet_accounts, [:name, :currency], where: "name IS NOT NULL")

    create constraint(:wallet_accounts, :wallet_accounts_owner,
             check: "(owner_type = 'user' AND user_id IS NOT NULL AND name IS NULL) OR (owner_type = 'system' AND name IS NOT NULL AND user_id IS NULL)"
           )

    create table(:wallet_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # gem_purchase | spend | grant | chargeback | adjustment
      add :kind, :string, null: false
      add :idempotency_key, :string, null: false
      add :reference_type, :string
      add :reference_id, :string
      add :game_slug, :string
      add :memo, :text
      add :actor_id, :binary_id
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:wallet_transactions, [:idempotency_key])
    create index(:wallet_transactions, [:reference_type, :reference_id])

    create table(:wallet_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :transaction_id, references(:wallet_transactions, type: :binary_id, on_delete: :restrict), null: false
      add :account_id, references(:wallet_accounts, type: :binary_id, on_delete: :restrict), null: false
      add :amount, :bigint, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:wallet_entries, [:account_id, :inserted_at])
    create index(:wallet_entries, [:transaction_id])

    create table(:store_products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      # gem_pack | subscription_plan | item
      add :kind, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :currency, :string, null: false, default: "usd"
      add :gems, :integer
      # Promotional extra Gems, only between promo_starts_at and promo_ends_at.
      add :bonus_gems, :integer, null: false, default: 0
      add :promo_starts_at, :utc_datetime
      add :promo_ends_at, :utc_datetime
      add :badge, :string
      add :active, :boolean, null: false, default: true
      add :sort_order, :integer, null: false, default: 0
      add :stripe_price_id, :string
      add :paypal_plan_id, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:store_products, [:slug])

    create table(:store_orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :product_id, references(:store_products, type: :binary_id, on_delete: :restrict), null: false
      # awaiting_payment | paid | fulfilled | failed | cancelled | disputed | charged_back
      add :status, :string, null: false
      add :provider, :string, null: false
      add :provider_ref, :string
      # What was bought, as it was at purchase time.
      add :product_name, :string, null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false
      add :gems, :integer, null: false, default: 0
      add :terms_accepted_at, :utc_datetime_usec, null: false
      add :paid_at, :utc_datetime_usec
      add :fulfilled_at, :utc_datetime_usec
      add :failure_reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:store_orders, [:user_id, :inserted_at])
    create unique_index(:store_orders, [:provider, :provider_ref], where: "provider_ref IS NOT NULL")

    create table(:payment_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :provider_event_id, :string, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :processed_at, :utc_datetime_usec
      add :error, :text
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:payment_events, [:provider, :provider_event_id])

    execute(
      """
      INSERT INTO store_products (id, slug, kind, name, price_cents, currency, gems, sort_order, inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), 'gems_500',   'gem_pack', '500 Gems',    500,   'usd', 500,   10, now(), now()),
        (gen_random_uuid(), 'gems_1000',  'gem_pack', '1,000 Gems',  1000,  'usd', 1000,  20, now(), now()),
        (gen_random_uuid(), 'gems_2500',  'gem_pack', '2,500 Gems',  2500,  'usd', 2500,  30, now(), now()),
        (gen_random_uuid(), 'gems_5000',  'gem_pack', '5,000 Gems',  5000,  'usd', 5000,  40, now(), now()),
        (gen_random_uuid(), 'gems_10000', 'gem_pack', '10,000 Gems', 10000, 'usd', 10000, 50, now(), now())
      ON CONFLICT (slug) DO NOTHING
      """,
      "DELETE FROM store_products WHERE slug IN ('gems_500', 'gems_1000', 'gems_2500', 'gems_5000', 'gems_10000')"
    )
  end
end
