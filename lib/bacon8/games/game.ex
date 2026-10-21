defmodule Bacon8.Games.Game do
  @moduledoc """
  A registered game/title in the games platform (e.g. "bacon_world").

  New games are added here first; `GameCharacter` records reference a game
  by `game_id` so the schema stays generic across future titles.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "games" do
    field :slug, :string
    field :name, :string
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:slug, :name, :is_active])
    |> validate_required([:slug, :name])
    # Underscores allowed since 2026-10-15: plugin slugs (e.g. "bacon_world") are
    # also game slugs, and plugin slugs map to Elixir module names.
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9_\-]*$/, message: "must be lowercase letters, digits, hyphens or underscores")
    |> unique_constraint(:slug)
  end
end
