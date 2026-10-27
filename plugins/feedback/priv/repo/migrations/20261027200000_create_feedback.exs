defmodule Feedback.Repo.Migrations.CreateFeedback do
  @moduledoc """
  Suggestions & Bugs (the `feedback` plugin, 2026-10-27).

    * `feedback_items` - a suggestion or a bug about the site or one game, its status
      (open -> approved -> queued for Claude -> in progress -> ready -> deploying -> live, or
      rejected, duplicate, needs info, failed), the vote score kept beside it, and what Claude
      reported back (`agent_summary`, `commit_sha`, `hold_reason`).
    * `feedback_votes` - one up (+1) or down (-1) vote per member per item.
    * `feedback_shots` - screenshots. Bodies live in `Bacon8.Storage` by SHA-256 and are
      registered in `drive_blobs`, like the store's files, so blob GC sees them.
    * `feedback_events` - the item's history: who changed what, and Claude's reports.
    * `feedback_agent` - one row: the hashed token Claude's runner uses, whether it may deploy
      on its own, whether it is paused, and when it last called.
  """
  use Ecto.Migration

  def change do
    create table(:feedback_items, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:number, :serial, null: false)
      add(:kind, :string, null: false)
      add(:area, :string, null: false)
      add(:title, :string, null: false)
      add(:body, :text, null: false)
      add(:status, :string, null: false, default: "open")
      add(:score, :integer, null: false, default: 0)
      add(:author_id, references(:users, type: :binary_id, on_delete: :nilify_all))
      add(:duplicate_of_id, references(:feedback_items, type: :binary_id, on_delete: :nilify_all))
      add(:admin_note, :text)
      add(:agent_summary, :text)
      add(:commit_sha, :string)
      add(:hold_reason, :text)
      add(:approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all))
      add(:approved_at, :utc_datetime_usec)
      add(:submitted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all))
      add(:submitted_at, :utc_datetime_usec)
      add(:claimed_at, :utc_datetime_usec)
      add(:deployed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:feedback_items, [:number]))
    create(index(:feedback_items, [:status]))
    create(index(:feedback_items, [:author_id]))

    create table(:feedback_votes, primary_key: false) do
      add(:item_id, references(:feedback_items, type: :binary_id, on_delete: :delete_all),
        primary_key: true
      )

      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true
      )

      add(:value, :smallint, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(constraint(:feedback_votes, :value_is_one, check: "value IN (-1, 1)"))

    create table(:feedback_shots, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:item_id, references(:feedback_items, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:sha256, :string, null: false)
      add(:filename, :string, null: false)
      add(:content_type, :string, null: false)
      add(:byte_size, :bigint, null: false)
      add(:position, :integer, null: false, default: 0)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:feedback_shots, [:item_id]))

    create table(:feedback_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:item_id, references(:feedback_items, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:actor_id, references(:users, type: :binary_id, on_delete: :nilify_all))
      # "user" (a person, actor_id) or "agent" (Claude's runner)
      add(:actor_kind, :string, null: false, default: "user")
      add(:from_status, :string)
      add(:to_status, :string)
      add(:note, :text)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:feedback_events, [:item_id, :inserted_at]))

    create table(:feedback_agent, primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:token_hash, :string)
      add(:token_hint, :string)
      add(:token_created_at, :utc_datetime_usec)
      add(:auto_deploy, :boolean, null: false, default: false)
      add(:paused, :boolean, null: false, default: false)
      add(:last_seen_at, :utc_datetime_usec)
      add(:last_seen_note, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(constraint(:feedback_agent, :single_row, check: "id = 1"))
  end
end
