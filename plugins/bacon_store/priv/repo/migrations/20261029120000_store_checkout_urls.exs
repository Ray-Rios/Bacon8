defmodule Bacon8.Repo.Migrations.StoreCheckoutUrls do
  use Ecto.Migration

  # Unfinished checkouts (2026-10-29c). A card basket remembers its provider checkout's address
  # and when the provider will close it, so the buyer can go back and pay, or cancel it, from
  # Purchases and the store instead of the order sitting at "Pending". Nothing to backfill: the
  # sweeper asks the provider about older open checkouts and settles them.

  def change do
    alter table(:store_orders) do
      add :checkout_url, :text
      add :checkout_expires_at, :utc_datetime_usec
    end

    create index(:store_orders, [:user_id, :status])
  end
end
