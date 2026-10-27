defmodule Feedback.Agent do
  @moduledoc """
  The one row describing Claude's runner (the program on the owner's PC that takes queued items,
  has Claude Code work on them and reports back): the SHA-256 of its token (the token itself is
  shown once, when an admin makes it), whether it may deploy on its own, whether it is paused, and
  when it last called.
  """
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "feedback_agent" do
    field(:token_hash, :string, redact: true)
    field(:token_hint, :string)
    field(:token_created_at, :utc_datetime_usec)
    field(:auto_deploy, :boolean, default: false)
    field(:paused, :boolean, default: false)
    field(:last_seen_at, :utc_datetime_usec)
    field(:last_seen_note, :string)
    timestamps(type: :utc_datetime_usec)
  end
end
