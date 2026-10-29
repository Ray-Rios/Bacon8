defmodule Bacon8.Repo.Migrations.BasketsAndOrderNumbers do
  use Ecto.Migration

  # Several items in one purchase (2026-10-29). Each item stays its own store_orders row, so
  # delivery, license keys and disputes work per item exactly as before; the rows of one checkout
  # share a basket_id and an order number (the receipt's "Order #8008"), and a card basket shares
  # one provider checkout (provider_ref), so the (provider, provider_ref) index can't be unique any
  # more. The cart is a table so it follows the buyer from phone to desktop.
  #
  # Existing orders become baskets of one: basket_id = their id, a number from the new sequence.
  # `down` puts the unique index back only if no basket has more than one order.

  def up do
    execute "CREATE SEQUENCE IF NOT EXISTS store_order_number_seq START WITH 8001"

    alter table(:store_orders) do
      add :basket_id, :binary_id
      add :number, :bigint
    end

    execute """
    UPDATE store_orders o SET basket_id = o.id, number = n.num
    FROM (SELECT id, nextval('store_order_number_seq') AS num FROM (SELECT id FROM store_orders ORDER BY inserted_at, id) s) n
    WHERE o.id = n.id
    """

    create index(:store_orders, [:basket_id])
    create index(:store_orders, [:number])

    drop_if_exists unique_index(:store_orders, [:provider, :provider_ref], where: "provider_ref IS NOT NULL")
    create index(:store_orders, [:provider, :provider_ref], where: "provider_ref IS NOT NULL", name: :store_orders_provider_ref_index)

    create table(:store_cart_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, references(:store_products, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:store_cart_items, [:user_id, :product_id])
  end

  def down do
    drop table(:store_cart_items)
    drop_if_exists index(:store_orders, [:provider, :provider_ref], name: :store_orders_provider_ref_index)
    create unique_index(:store_orders, [:provider, :provider_ref], where: "provider_ref IS NOT NULL")
    drop index(:store_orders, [:number])
    drop index(:store_orders, [:basket_id])

    alter table(:store_orders) do
      remove :number
      remove :basket_id
    end

    execute "DROP SEQUENCE IF EXISTS store_order_number_seq"
  end
end
