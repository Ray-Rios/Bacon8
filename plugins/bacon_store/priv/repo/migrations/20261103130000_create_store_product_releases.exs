defmodule Bacon8.Repo.Migrations.CreateStoreProductReleases do
  use Ecto.Migration

  # Plugins sold as downloads (2026-11-03, BaconStore.Store.Releases): each release of a plugin
  # is a zip packaged from its git release branch (release/<plugin>/<version>), with a
  # RELEASE.json inside naming the plugin, the version, the branch and the commit. The zip is an
  # ordinary download file of the product; this row says which release it is.
  def change do
    create table(:store_product_releases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:store_products, type: :binary_id, on_delete: :delete_all), null: false
      add :product_file_id, references(:store_product_files, type: :binary_id, on_delete: :nilify_all)
      add :plugin, :string, null: false
      add :version, :string, null: false
      add :branch, :string, null: false
      add :commit, :string, null: false
      add :notes, :text
      add :built_at, :utc_datetime
      add :yanked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:store_product_releases, [:product_id, :version])
  end
end
