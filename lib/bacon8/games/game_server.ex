defmodule Bacon8.Games.GameServer do
  @moduledoc """
  A registered dedicated game server (shard) for a title.

  Rows are written by the dedicated servers themselves via a heartbeat, never
  by players — see `Bacon8Web.Api.GamesController.heartbeat_server/2`,
  which refuses anything not authenticated with the server API key. If a
  player could write here they could advertise a server they control to every
  other player, which is a phishing vector rather than a cheat.

  Liveness is heartbeat-based, not shutdown-based. A crashed server never gets
  the chance to deregister, so the presence of a row means nothing on its own;
  only `last_heartbeat_at` being recent does.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(online draining offline)

  schema "game_servers" do
    field :host, :string
    field :port, :integer
    field :name, :string
    field :region, :string, default: "unknown"
    field :status, :string, default: "online"
    field :current_players, :integer, default: 0
    field :max_players, :integer, default: 64
    field :map_name, :string
    field :version, :string
    field :last_heartbeat_at, :utc_datetime
    field :metadata, :map, default: %{}

    # WHO IS ON THIS SERVER, as of the last heartbeat.
    #
    # Shaped %{"players" => [%{"user_id" =>, "character_id" =>, "name" =>,
    # "joined_at" =>}]}. An object at the top level rather than a bare list so
    # this stays a plain :map, and so more per-instance detail can be added
    # beside it without another migration.
    #
    # A snapshot, not a ledger: it is overwritten wholesale every heartbeat and
    # is only as current as `last_heartbeat_at`. Read the two together or you
    # will show a roster from a server that died ten minutes ago.
    field :roster, :map, default: %{}

    # Instance servers only. Null on a world server.
    #
    # `instance_id` names the game-defined thing this server is running (a
    # player-built world, say). The hub doesn't know what an instance is; the
    # game's plugin owns that table and its foreign key. An instance belongs to
    # that thing, not to a player: many people can join one.
    # launched_by_user_id is attribution - who opened the door first - and is
    # deliberately NOT used for access decisions.
    field :instance_id, :binary_id
    field :launched_by_user_id, :binary_id

    belongs_to :game, Bacon8.Games.Game

    timestamps(type: :utc_datetime)
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [
      :game_id,
      :host,
      :port,
      :name,
      :region,
      :status,
      :current_players,
      :max_players,
      :map_name,
      :version,
      :last_heartbeat_at,
      :metadata,
      :roster,
      :instance_id,
      :launched_by_user_id
    ])
    |> validate_required([:game_id, :host, :port, :name, :last_heartbeat_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:port, greater_than: 0, less_than: 65_536)
    |> validate_number(:current_players, greater_than_or_equal_to: 0)
    |> validate_number(:max_players, greater_than: 0)
    |> foreign_key_constraint(:game_id)
    |> unique_constraint([:game_id, :host, :port], name: :game_servers_game_id_host_port_index)
  end

  def statuses, do: @statuses
end
