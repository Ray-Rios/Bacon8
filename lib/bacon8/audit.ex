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

  import Ecto.Query, only: [from: 2]

  @doc """
  The audit log for admins (/admin/audit, 2026-10-29), newest first: `%{entry, actor}` with the actor
  as `%{name, email}` or nil. `opts`: `:query` (part of an action, e.g. "user." or "plugin"),
  `:limit` (100), `:before` (an `inserted_at`, for the next page).
  """
  def list(opts \\ []) do
    q = from(a in AuditLog, order_by: [desc: a.inserted_at, desc: a.id], limit: ^Keyword.get(opts, :limit, 100))

    q =
      case opts[:query] do
        text when is_binary(text) and text != "" -> from(a in q, where: ilike(a.action, ^"%#{String.replace(text, ~r/[%_\\]/, "")}%"))
        _ -> q
      end

    q = if opts[:before], do: from(a in q, where: a.inserted_at < ^opts[:before]), else: q

    entries = Repo.all(q)
    ids = entries |> Enum.map(& &1.actor_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    actors =
      from(u in Bacon8.Accounts.User, where: u.id in ^ids, select: {u.id, %{name: u.name, email: u.email}})
      |> Repo.all()
      |> Map.new()

    Enum.map(entries, &%{entry: &1, actor: &1.actor_id && actors[&1.actor_id]})
  end
end
