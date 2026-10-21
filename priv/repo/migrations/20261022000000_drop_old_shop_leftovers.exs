defmodule Bacon8.Repo.Migrations.DropOldShopLeftovers do
  use Ecto.Migration

  @moduledoc """
  The site baseline still creates the retired physical-goods shop's tables and
  four `users` columns only it used. Bacon Store's migration
  20261016210000_stripe_refs_and_drop_old_shop drops them, but since the store
  became a plugin (ADR 0001, phase 3) a site without it never runs that one.
  This does the same drops, so core alone ends with the same core schema as
  production. Everywhere they are already gone it changes nothing.
  """

  def up do
    # Children before parents; CASCADE takes any constraint this list misses.
    for table <- ~w(download_tokens subscriptions cart_items carts order_items orders products categories) do
      execute "DROP TABLE IF EXISTS #{table} CASCADE"
    end

    for column <- ~w(subscription_tier subscription_features storage_quota_bytes storage_used_bytes) do
      execute "ALTER TABLE users DROP COLUMN IF EXISTS #{column}"
    end
  end

  def down, do: :ok
end
