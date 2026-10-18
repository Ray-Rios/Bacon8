defmodule Bacon8.Games.GameRelease do
  @moduledoc "One client build: a manifest of files by SHA-256. See the migration."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_releases" do
    field :build_id, :string
    field :manifest, :map, default: %{}
    field :total_bytes, :integer, default: 0
    field :notes, :string
    field :is_live, :boolean, default: false
    field :published_at, :utc_datetime

    belongs_to :game, Bacon8.Games.Game

    timestamps(type: :utc_datetime)
  end

  def changeset(release, attrs) do
    release
    |> cast(attrs, [:game_id, :build_id, :manifest, :total_bytes, :notes, :is_live, :published_at])
    |> validate_required([:game_id, :build_id, :manifest])
    |> validate_length(:build_id, max: 100)
    |> unique_constraint([:game_id, :build_id])
    |> foreign_key_constraint(:game_id)
  end
end
