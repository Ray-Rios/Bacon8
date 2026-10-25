defmodule Bacon8.GameCards.Card do
  @moduledoc "An admin's changes to a plugin game's card on /games. See `Bacon8.GameCards`."
  use Ecto.Schema

  @primary_key {:plugin_slug, :string, autogenerate: false}
  @foreign_key_type :binary_id
  schema "game_cards" do
    # "fronts", "back", "tagline", "details", "play_label", "seconds"
    field :data, :map, default: %{}
    belongs_to :updated_by, Bacon8.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end
end
