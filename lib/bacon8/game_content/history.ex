defmodule Bacon8.GameContent.History do
  @moduledoc """
  A change made to a game's definitions through the hub (`Bacon8.GameContent`): a row of
  `game_content_history`. `before` nil: it was created; `after` nil: it was deleted.
  """
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "game_content_history" do
    field :game_slug, :string
    field :kind, :string
    field :ref_id, :string
    field :action, :string
    field :before, :map
    field :after, :map
    field :user_id, :string
    field :user_name, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
