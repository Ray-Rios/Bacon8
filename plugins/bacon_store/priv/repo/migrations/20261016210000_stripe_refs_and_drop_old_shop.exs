defmodule Bacon8.Repo.Migrations.StripeRefsAndDropOldShop do
  @moduledoc """
  Milestone 4b (BACON8.md §8):

    * store_orders.provider_payment_ref - the payment's own id once paid
      (a Stripe PaymentIntent). Disputes name it, not the checkout session.
    * The old physical-goods shop is retired: its tables held only test data
      and nothing reads them any more. So are the users columns that only it
      used (its subscription tier and feature list, and the storage quota the
      drive's plans replaced in milestone 1).

  Not reversible: the dropped tables' data is gone.
  """
  use Ecto.Migration

  def up do
    alter table(:store_orders) do
      add :provider_payment_ref, :string
    end

    create index(:store_orders, [:provider, :provider_payment_ref], where: "provider_payment_ref IS NOT NULL")

    # Children before parents; CASCADE takes any constraint this list misses.
    for table <- ~w(download_tokens subscriptions cart_items carts order_items orders products categories) do
      execute "DROP TABLE IF EXISTS #{table} CASCADE"
    end

    for column <- ~w(subscription_tier subscription_features storage_quota_bytes storage_used_bytes) do
      execute "ALTER TABLE users DROP COLUMN IF EXISTS #{column}"
    end
  end

  def down do
    raise Ecto.MigrationError, message: "the old shop's tables were dropped with their data and can't be restored"
  end
end
