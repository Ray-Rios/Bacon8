defmodule BaconWorld.ItemDef do
  @moduledoc "One item's definition (`BaconWorld.Items`), a row of `bacon_world_item_defs` (2026-11-02)."
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "bacon_world_item_defs" do
    field :data, :map, default: %{}
    field :position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end
