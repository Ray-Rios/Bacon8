defmodule Bacon8.Building.Placement do
  @moduledoc """
  One thing put in a game's world in build mode (`Bacon8.Building`, 2026-11-14): which game, which
  zone, and in which `frame` of that zone (nil: the zone's own; RaysSpaceSim: the planet it was
  built on, so it rides the planet's orbit), the catalogue `asset`, where it stands (`x`, `y`, `z`,
  metres in that frame; `y` up, where its base stands), `rot` (radians about up), `scale`, and
  `data` (the game's own: Bacon World's creature spawns and NPCs, a full turn as `"q"`).

  Bacon World reads and writes its rows through the `bacon_world_placements` view (its
  `BaconWorld.Placement`); other games through the API.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "game_placements" do
    field :game_slug, :string
    field :zone, :string
    field :frame, :string
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
