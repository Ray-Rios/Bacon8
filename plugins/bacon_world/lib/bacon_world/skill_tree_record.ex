defmodule BaconWorld.SkillTreeRecord do
  @moduledoc """
  The stored skill tree (`BaconWorld.SkillTree`): one row per tree (`slug` "main"),
  the whole tree in `data`. `updated_by` is the admin who saved it last.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "bacon_world_skill_trees" do
    field :slug, :string
    field :data, :map
    field :updated_by, :binary_id
    timestamps(type: :utc_datetime)
  end
end
