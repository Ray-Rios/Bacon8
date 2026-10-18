defmodule Bacon8.Store.Category do
  @moduledoc "A storefront tab (\"Software\", \"Music\", \"Game items\" ...)."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "store_categories" do
    field :name, :string
    field :slug, :string
    field :sort_order, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :sort_order], empty_values: [nil, ""])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> then(fn cs ->
      if get_field(cs, :slug), do: cs, else: put_change(cs, :slug, Bacon8.Store.Catalog.slugify(get_field(cs, :name) || ""))
    end)
    |> validate_required([:name, :slug])
    |> validate_length(:name, max: 60)
    |> validate_format(:slug, ~r/\A[a-z0-9][a-z0-9_-]*\z/)
    |> unique_constraint(:slug, message: "a category with this name already exists")
  end
end
