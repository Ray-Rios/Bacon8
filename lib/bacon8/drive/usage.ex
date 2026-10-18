defmodule Bacon8.Drive.Usage do
  @moduledoc """
  Per-user drive totals, plus the Guest/Banned lock.

  This row is what `Bacon8.Drive` locks (`SELECT ... FOR UPDATE`) while adding a
  file, so two concurrent uploads cannot both pass the quota check.
  """
  use Ecto.Schema

  @primary_key {:user_id, :binary_id, autogenerate: false}
  schema "drive_usage" do
    field :bytes_used, :integer, default: 0
    field :file_count, :integer, default: 0
    field :locked_at, :utc_datetime_usec
    field :purge_after, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
