defmodule WebLobby.Zone do
  @moduledoc "A place characters spawn and meet. Seeded with the default 'lobby' zone."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "web_lobby_zones" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :spawn_x, :float, default: 0.0
    field :spawn_y, :float, default: 0.0
    field :spawn_z, :float, default: 0.0
    field :spawn_heading, :float, default: 0.0
    timestamps(type: :utc_datetime)
  end
end
