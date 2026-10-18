defmodule Bacon8.Store.ProductFile do
  @moduledoc """
  An image shown on a product's page (`role` "image"; the first is the
  cover) or a file buyers download (`role` "download"). The body is in
  `Bacon8.Storage` under `sha256`; see `Bacon8.Store.Catalog.add_file/5`.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "store_product_files" do
    field :role, :string
    field :sha256, :string
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :label, :string
    field :position, :integer, default: 0
    belongs_to :product, Bacon8.Store.Product
    timestamps(type: :utc_datetime_usec)
  end
end
