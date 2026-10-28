defmodule Feedback.Item do
  @moduledoc "A suggestion or a bug report (see `Feedback`)."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(suggestion bug)
  @statuses ~w(open approved rejected duplicate queued in_progress needs_info ready deploying deployed failed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "feedback_items" do
    field(:number, :integer, read_after_writes: true)
    field(:kind, :string, default: "suggestion")
    field(:area, :string, default: "site")
    field(:title, :string)
    field(:body, :string)
    field(:status, :string, default: "open")
    field(:score, :integer, default: 0)
    field(:admin_note, :string)
    field(:agent_summary, :string)
    field(:commit_sha, :string)
    field(:hold_reason, :string)
    field(:approved_at, :utc_datetime_usec)
    field(:submitted_at, :utc_datetime_usec)
    field(:claimed_at, :utc_datetime_usec)
    field(:deployed_at, :utc_datetime_usec)

    belongs_to(:author, Bacon8.Accounts.User)
    belongs_to(:duplicate_of, __MODULE__)
    belongs_to(:approved_by, Bacon8.Accounts.User)
    belongs_to(:submitted_by, Bacon8.Accounts.User)

    has_many(:shots, Feedback.Shot, preload_order: [asc: :position, asc: :inserted_at])
    has_many(:events, Feedback.Event, preload_order: [asc: :inserted_at])

    # The viewer's own vote (+1, -1 or nil), and the vote counts, filled in by `Feedback` when listing.
    field(:my_vote, :integer, virtual: true)
    field(:upvotes, :integer, virtual: true, default: 0)
    field(:downvotes, :integer, virtual: true, default: 0)

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  @doc "What a member writes (and an admin may change)."
  def content_changeset(item, attrs) do
    item
    |> cast(attrs, [:kind, :area, :title, :body])
    |> update_change(:title, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:kind, :area, :title, :body])
    |> validate_inclusion(:kind, @kinds)
    |> validate_format(:area, ~r/\A[a-z][a-z0-9_]{0,63}\z/)
    |> validate_length(:title, min: 4, max: 140)
    |> validate_length(:body, min: 10, max: 10_000)
  end

  @doc "What only an admin sets: notes for Claude (passed along with the item)."
  def admin_changeset(item, attrs) do
    item
    |> content_changeset(attrs)
    |> cast(attrs, [:admin_note])
    |> validate_length(:admin_note, max: 10_000)
  end
end
