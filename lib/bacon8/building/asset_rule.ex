defmodule Bacon8.Building.AssetRule do
  @moduledoc """
  An admin's rule for one catalogue asset, the same in every game (2026-11-14: one catalogue, one
  set of rules): the lowest role that may place it (and so move, delete or smash any copy of it) and
  its hit points. Assets without a row use the catalogue's defaults. Bacon World's
  `BaconWorld.AssetRule` is the same rows through the `bacon_world_asset_rules` view.
  """
  use Ecto.Schema

  @primary_key {:asset, :string, autogenerate: false}
  schema "game_asset_rules" do
    field :min_role, :string
    field :hp, :integer, default: 10
    field :updated_by, :binary_id
    timestamps(type: :utc_datetime)
  end
end
