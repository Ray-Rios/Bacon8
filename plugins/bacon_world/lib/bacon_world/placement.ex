defmodule BaconWorld.Placement do
  @moduledoc """
  One object put in the world in build mode (`BaconWorld.Building`): `asset` from the
  catalogue, its position (`x`, `y`, `z`, metres; `y` is where its base stands), `rot` (radians
  about the vertical, 0 = its front facing +z), `scale`, and `data` (a creature spawn's `count`
  and `radius`, an NPC's `name`). `placed_by` is the account, `character_id` the character
  that placed it.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "bacon_world_placements" do
    field :zone, :string
    field :asset, :string
    field :x, :float
    field :y, :float, default: 0.0
    field :z, :float
    field :rot, :float, default: 0.0
    field :scale, :float, default: 1.0
    field :data, :map, default: %{}
    field :placed_by, :binary_id
    field :character_id, :binary_id
    timestamps(type: :utc_datetime)
  end
end
