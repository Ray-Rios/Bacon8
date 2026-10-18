defmodule Bacon8.Games.GameCharacter do
  @moduledoc """
  A player's character within a specific game.

  `stats` and `settings` are flexible JSONB maps so each game can store its
  own shape of data without new migrations.
  Real-time gameplay state should live in the dedicated game server / Redis;
  this record is the periodic/disconnect checkpoint that gets persisted here.

  `user_id` intentionally has no foreign key constraint - it references the
  `users.id` in the main `Bacon8.Repo` database, which this repo cannot
  reference directly across databases.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_characters" do
    field :user_id, :binary_id
    field :name, :string
    field :stats, :map, default: %{}
    field :settings, :map, default: %{}
    field :last_played_at, :utc_datetime

    # --- Single-session claim ------------------------------------------
    #
    # NONE OF THESE APPEAR IN `cast/3` BELOW, AND THAT IS A SECURITY PROPERTY
    # rather than an oversight.
    #
    # `PUT /api/games/:slug/characters/:id` is reachable with a PLAYER token.
    # Were these castable, a player could clear their own claim with an
    # ordinary character update and then sign in twice - which is exactly what
    # this feature exists to prevent, handed back through the front door. They
    # are written only by `Games.claim_character_session/4` and its siblings,
    # every one of which is a server-API-key path.
    #
    # Liveness is `active_server_id` being set AND that server's heartbeat
    # being fresh; see `Games.character_session/1`. The two timestamps are
    # informational, and a released session deliberately leaves them behind as
    # a readable trace of the session that just ended.
    field :active_server_id, :binary_id
    field :active_session_id, :binary_id
    field :session_started_at, :utc_datetime
    field :session_last_seen_at, :utc_datetime

    # --- Resume-in-instance (2026-10-09) --------------------------------
    #
    # Also NOT castable, for the same reason as the claim fields above: written
    # by an instance server on Logout (server key), cleared when the player
    # leaves the instance. See Games.set_instance_location/5. `instance_location`
    # is opaque to the hub; the game writes and reads it.
    field :instance_id, :binary_id
    field :instance_location, :map

    belongs_to :game, Bacon8.Games.Game

    timestamps(type: :utc_datetime)
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [:user_id, :game_id, :name, :stats, :settings, :last_played_at])
    |> update_change(:name, &(&1 |> to_string() |> String.trim()))
    |> validate_required([:user_id, :game_id, :name])
    |> validate_length(:name, min: 1, max: 24)
    # Letters (any script), digits, spaces, apostrophes and hyphens. Nothing
    # about this is a security boundary - `name` never reaches a shell, a
    # query template, or another player's client unescaped - it is here so a
    # character sheet is a name a player would recognise as their own instead
    # of a swearword-shaped string a client with no validation happened to let
    # through.
    |> validate_format(:name, ~r/^[\p{L}\p{N} '\-]+$/u,
      message: "can only contain letters, numbers, spaces, apostrophes and hyphens")
    |> foreign_key_constraint(:game_id)
    # Unique per game, not per (game, user) - a character name is what other
    # players see, so two different accounts cannot both be "Wesley" in the
    # same game. Matches the games_repo migration's game_characters_game_id_name_index.
    |> unique_constraint([:game_id, :name], name: :game_characters_game_id_name_index)
  end
end
