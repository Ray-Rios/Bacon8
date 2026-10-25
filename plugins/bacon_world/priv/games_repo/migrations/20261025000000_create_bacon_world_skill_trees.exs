defmodule BaconWorld.GamesRepo.Migrations.CreateBaconWorldSkillTrees do
  use Ecto.Migration

  @moduledoc """
  The shared skill tree (`BaconWorld.SkillTree`), edited at /admin/bacon_world/skills:
  one row per tree (slug "main"), the nodes and edges as JSON. Until a tree is saved
  the game uses the one in code. Characters' learned nodes live in their `stats`
  (`"skill_nodes"`), their hotbars in `settings` (`"hotbars"`).
  """

  def change do
    create table(:bacon_world_skill_trees, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :data, :map, null: false
      add :updated_by, :binary_id
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bacon_world_skill_trees, [:slug])
  end
end
