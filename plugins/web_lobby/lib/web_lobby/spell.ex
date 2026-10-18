defmodule WebLobby.Spell do
  @moduledoc "A castable spell. Seeded with 'throw_stone'."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "web_lobby_spells" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :mp_cost, :integer, default: 0
    field :base_damage, :integer, default: 0
    field :range, :float, default: 20.0
    field :recast_ms, :integer, default: 1000
    field :projectile_type, :string, default: "stone"
    field :targeting_type, :string, default: "single"
    timestamps(type: :utc_datetime)
  end
end
