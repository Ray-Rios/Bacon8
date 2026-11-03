defmodule BaconWorld.Zone do
  @moduledoc """
  A place characters spawn and meet. Seeded with the default 'lobby' zone (Crater Lake).

  Since 2026-11-02 zones lie on a grid around the lobby (`grid_x`, `grid_z`; +x east, +z south),
  each 4096 m square with its own terrain (`terrain`, its numbers in `meta`), made by
  `BaconWorld.WorldGen` and edited on /admin/bacon_world/world. `number` is what /zone takes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "bacon_world_zones" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :spawn_x, :float, default: 0.0
    field :spawn_y, :float, default: 0.0
    field :spawn_z, :float, default: 0.0
    field :spawn_heading, :float, default: 0.0
    field :number, :integer
    field :grid_x, :integer
    field :grid_z, :integer
    field :terrain, :string
    field :terrain_version, :integer, default: 1
    field :status, :string, default: "ready"
    field :meta, :map, default: %{}
    timestamps(type: :utc_datetime)
  end

  @fields ~w(name slug description spawn_x spawn_y spawn_z spawn_heading number grid_x grid_z terrain terrain_version status meta)a

  def changeset(zone, attrs) do
    zone
    |> cast(attrs, @fields)
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> unique_constraint(:number)
    |> unique_constraint([:grid_x, :grid_z])
  end
end
