defmodule Bacon8.Games.ServerCommand do
  @moduledoc """
  An instruction queued for a running game server, delivered on its next heartbeat.

  ## Why a queue and not a call

  Instances heartbeat outward; nothing can call into them. They may be behind
  NAT, inside a Kubernetes pod with no ingress, or started by hand on someone's
  desktop — all three are true at some point in this project's life. Rather than
  add a second transport just so an admin can press a button, the command rides
  back on the response to a request the server was already making.

  That has a property worth stating plainly: a command aimed at a server that
  has stopped heartbeating is never delivered and never expires by itself. That
  is correct — the server is gone, and the command was for that server — but it
  means the admin UI must show `delivered_at` rather than implying the button
  took effect.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @commands ~w(shutdown drain kick)

  schema "server_commands" do
    # shutdown - save and exit now
    # drain    - refuse new joins, exit when empty
    # kick     - remove one player, payload carries "user_id"
    field :command, :string
    field :payload, :map, default: %{}

    field :issued_by_user_id, :binary_id
    field :issued_at, :utc_datetime

    # NULL until a heartbeat carries it away.
    field :delivered_at, :utc_datetime

    belongs_to :server, Bacon8.Games.GameServer

    timestamps(type: :utc_datetime)
  end

  def changeset(command, attrs) do
    command
    |> cast(attrs, [:server_id, :command, :payload, :issued_by_user_id, :issued_at, :delivered_at])
    |> validate_required([:server_id, :command, :issued_at])
    |> validate_inclusion(:command, @commands)
    |> validate_kick_has_target()
    |> foreign_key_constraint(:server_id)
  end

  # A kick with no target is not a smaller kick, it is a no-op that looks like
  # it worked. Rejected here rather than discovered on the server.
  defp validate_kick_has_target(changeset) do
    case get_field(changeset, :command) do
      "kick" ->
        payload = get_field(changeset, :payload) || %{}

        if is_binary(payload["user_id"]) and payload["user_id"] != "" do
          changeset
        else
          add_error(changeset, :payload, "kick requires a user_id")
        end

      _ ->
        changeset
    end
  end

  def commands, do: @commands
end
