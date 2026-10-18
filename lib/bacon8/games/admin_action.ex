defmodule Bacon8.Games.AdminAction do
  @moduledoc """
  A record of something an administrator did to live game state.

  Written on every privileged action — killing an instance, kicking a player,
  toggling the launch switch. Worth having from the first day there are two
  admins, and impossible to backfill from the day it is first wanted, which is
  always the day something was destroyed and nobody remembers doing it.

  `actor_user_id` is deliberately not a foreign key. Users live in the main
  repo, not this one, and an audit row has to outlive the account it refers to —
  an audit log with cascading deletes is not an audit log. `actor_email` is
  denormalised for the same reason: so the entry stays legible after the account
  is gone.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Core's subject types. Plugins log their own; any lowercase name is
  # accepted, for the same reason `action` is free-form.
  @subject_types ~w(server instance character game)

  schema "admin_actions" do
    field :actor_user_id, :binary_id
    field :actor_email, :string

    # Free-form verb: "server.shutdown", "server.kick", "launches.disabled".
    # Not an enum - a new admin control should be a code change, and an audit
    # table that rejects unfamiliar verbs silently loses the entries that matter
    # most, which are the unusual ones.
    field :action, :string

    field :subject_type, :string
    field :subject_id, :binary_id

    # Whatever makes this legible a year from now: the instance's name, the player
    # removed, the reason given.
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [:actor_user_id, :actor_email, :action, :subject_type, :subject_id, :details])
    |> validate_required([:actor_user_id, :action])
    |> validate_format(:subject_type, ~r/\A[a-z][a-z0-9_]*\z/)
  end

  def subject_types, do: @subject_types
end
