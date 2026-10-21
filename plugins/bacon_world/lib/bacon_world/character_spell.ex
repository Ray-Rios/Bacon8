defmodule BaconWorld.CharacterSpell do
  @moduledoc "A spell a character has learned. `character_id` is a platform game_characters id."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bacon_world_character_spells" do
    field :character_id, :binary_id
    field :unlocked_at, :utc_datetime
    belongs_to :spell, BaconWorld.Spell
    timestamps(type: :utc_datetime)
  end
end
