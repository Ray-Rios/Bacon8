defmodule Bacon8.Repo.Migrations.CreatePushSubscriptions do
  use Ecto.Migration

  # Phone and desktop notifications (2026-11-03, Bacon8.Push): one row per browser or installed
  # web app that said yes. `endpoint` is the push service's URL for that device; `p256dh` and
  # `auth` are the device's keys, so only it can read what we send.
  def change do
    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
      add :user_agent, :string
      # false: the lock screen says only that something is new, not what
      add :previews, :boolean, null: false, default: true
      add :failures, :integer, null: false, default: 0
      add :last_used_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_subscriptions, [:endpoint])
    create index(:push_subscriptions, [:user_id])
  end
end
