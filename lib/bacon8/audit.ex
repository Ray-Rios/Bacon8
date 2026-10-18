defmodule Bacon8.Audit do
  @moduledoc "Simple audit logger that persists audit events to DB (when table exists) and logs to Logger."
  alias Bacon8.Repo
  alias Bacon8.AuditLog
  require Logger

  def log(actor_id, action, target_type \\ nil, target_id \\ nil, metadata \\ %{}) do
    attrs = %{
      actor_id: actor_id,
      action: action,
      target_type: target_type,
      target_id: target_id,
      metadata: metadata
    }

    Logger.info("AUDIT: #{action} actor=#{actor_id} target=#{target_type}(#{target_id}) meta=#{inspect(metadata)}")

    # Best-effort insert: only attempt if Repo and table exist
    try do
      %AuditLog{}
      |> AuditLog.changeset(attrs)
      |> Repo.insert()
    rescue
      _ ->
        :ok
    end
  end
end
