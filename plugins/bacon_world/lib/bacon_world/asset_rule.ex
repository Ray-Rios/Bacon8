defmodule BaconWorld.AssetRule do
  @moduledoc """
  The lowest role that may place an asset in build mode (and so move or delete any copy of it),
  set by an admin in game (`BaconWorld.Building.set_rule/3`). Assets without a row use the
  catalogue's default.
  """
  use Ecto.Schema

  @primary_key {:asset, :string, autogenerate: false}
  schema "bacon_world_asset_rules" do
    field :min_role, :string
    field :updated_by, :binary_id
    timestamps(type: :utc_datetime)
  end
end
