defmodule BaconWorld.InventoryItem do
  @moduledoc """
  One item a character carries: which catalogue item (`BaconWorld.Items`), where it
  sits (`"main"`, `"off"` or `"bag0"`..`"bag23"`) and how many (stackable junk).
  `character_id` is a platform `game_characters` id; deleting the character deletes
  its items.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bacon_world_items" do
    field :character_id, :binary_id
    field :item_id, :string
    field :slot, :string
    field :quantity, :integer, default: 1
    timestamps(type: :utc_datetime)
  end
end
