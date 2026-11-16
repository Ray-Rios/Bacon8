defmodule Bacon8.GameContent.Def do
  @moduledoc "One definition of a game's (`Bacon8.GameContent`): a row of `game_defs`."
  use Ecto.Schema

  @primary_key false
  schema "game_defs" do
    field :game_slug, :string, primary_key: true
    field :kind, :string, primary_key: true
    field :id, :string, primary_key: true
    field :data, :map, default: %{}
    field :position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end
