defmodule Bacon8.Repo.Migrations.CreateModeration do
  use Ecto.Migration

  # Trust & safety (2026-11-03, Bacon8.Moderation): reports and takedown requests, what staff did
  # about them, files nobody may upload again, and evidence kept for the law. Drive files gain
  # `quarantined_at`: a file under review that no one can open through the site.
  def change do
    create table(:moderation_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # report | ncii_takedown | dmca
      add :kind, :string, null: false, default: "report"
      add :category, :string, null: false
      # open | actioned | dismissed
      add :status, :string, null: false, default: "open"
      # 0 (most urgent) .. 3
      add :priority, :integer, null: false, default: 2
      add :due_at, :utc_datetime
      # drive_file | upload | user | url | a plugin's (chat_message ...)
      add :subject_type, :string
      add :subject_id, :string
      add :subject_url, :text
      add :subject_owner_id, :binary_id
      add :subject_snapshot, :map, null: false, default: %{}
      add :details, :text
      add :reporter_id, :binary_id
      add :reporter_name, :string
      add :reporter_email, :string
      add :reporter_ip, :string
      add :signature, :string
      add :sworn, :boolean, null: false, default: false
      add :ncmec_report_id, :string
      add :resolution, :text
      add :resolved_by, :binary_id
      add :resolved_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:moderation_reports, [:status, :priority, :inserted_at])
    create index(:moderation_reports, [:subject_type, :subject_id])

    create table(:moderation_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :report_id, references(:moderation_reports, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_id, :binary_id
      add :action, :string, null: false
      add :note, :text
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:moderation_actions, [:report_id])

    create table(:moderation_blocked_hashes, primary_key: false) do
      add :sha256, :string, primary_key: true
      add :reason, :string
      add :report_id, :binary_id
      add :added_by, :binary_id
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:moderation_holds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :report_id, references(:moderation_reports, type: :binary_id, on_delete: :restrict), null: false
      add :sha256, :string
      add :subject_type, :string
      add :subject_id, :string
      add :owner_id, :binary_id
      add :evidence, :map, null: false, default: %{}
      add :preserve_until, :utc_datetime, null: false
      add :released_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:moderation_holds, [:sha256])

    alter table(:drive_files) do
      add :quarantined_at, :utc_datetime_usec
    end
  end
end
