defmodule Bacon8.Repo.Migrations.DigitalProducts do
  @moduledoc """
  Digital products in the store (BACON8.md §8): categories, Gem prices,
  product images and downloadable files, a pool of license keys, and what a
  purchase grants (an item a game reads, access to a chat channel, extra
  channel slots).

    * `store_categories` - for the storefront's tabs.
    * `store_products` gains a category, a short summary, a Gem price, and the
      grant fields (`grant_kind`, `grant_key`, `grant_quantity`,
      `duration_days`, `one_per_user`). `price_cents` may now be empty: a
      product can be sold for Gems only.
    * `store_product_files` - images (shown on the product page) and downloads
      (only for buyers). Bodies live in `Bacon8.Storage` by SHA-256, like
      drive files, and are registered in `drive_blobs` so blob GC sees them.
    * `store_license_keys` - codes an admin uploads; each sale takes one. A
      card checkout reserves its key (`order_id` set, `sold_at` empty) so two
      buyers can't pay for the last one.
    * `store_orders.amount_gems` - what a Gem purchase cost; such orders have
      no card amount.
  """
  use Ecto.Migration

  def change do
    create table(:store_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :sort_order, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:store_categories, [:slug])

    alter table(:store_products) do
      modify :price_cents, :integer, null: true, from: {:integer, null: false}
      add :category_id, references(:store_categories, type: :binary_id, on_delete: :nilify_all)
      add :summary, :string
      add :price_gems, :integer
      add :grant_kind, :string
      add :grant_key, :string
      add :grant_quantity, :integer, null: false, default: 1
      add :duration_days, :integer
      add :one_per_user, :boolean, null: false, default: false
    end

    create index(:store_products, [:category_id])

    create table(:store_product_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:store_products, type: :binary_id, on_delete: :delete_all), null: false
      # image | download
      add :role, :string, null: false
      add :sha256, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :label, :string
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create index(:store_product_files, [:product_id, :role, :position])
    create index(:store_product_files, [:sha256])

    create table(:store_license_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:store_products, type: :binary_id, on_delete: :restrict), null: false
      add :code, :string, null: false
      add :order_id, references(:store_orders, type: :binary_id, on_delete: :restrict)
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :reserved_at, :utc_datetime_usec
      add :sold_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:store_license_keys, [:product_id, :code])
    create unique_index(:store_license_keys, [:order_id], where: "order_id IS NOT NULL")
    create index(:store_license_keys, [:product_id, :inserted_at], where: "order_id IS NULL", name: :store_license_keys_available_index)
    create index(:store_license_keys, [:user_id])

    alter table(:store_orders) do
      modify :amount_cents, :integer, null: true, from: {:integer, null: false}
      add :amount_gems, :integer
    end
  end
end
