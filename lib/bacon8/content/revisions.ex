defmodule Bacon8.Content.Revisions do
  @moduledoc """
  Earlier versions of pages and posts, so an edit can be undone.

  `Bacon8.Content.update_page/2` and `update_post/2` call `record_before_update/3` after every
  successful save. When the title, excerpt or body changed, the version *before* the save is kept,
  but not more often than every #{5} minutes per record (the editors autosave every few seconds,
  and a version for each would bury the useful ones). At most #{50} are kept per record; the
  oldest go first. Restoring a version keeps the current one first, so a restore can be undone too.
  """
  import Ecto.Query, warn: false

  alias Bacon8.Content.{Page, Post, Revision}
  alias Bacon8.Repo

  @min_gap_seconds 5 * 60
  @keep 50

  @doc "The kind (`:page` or `:post`) of a record."
  def kind(%Page{}), do: :page
  def kind(%Post{}), do: :post

  @doc "Keeps `old` (the record before the save) when the save changed what is worth keeping."
  def record_before_update(old, new, user_id \\ nil) do
    if changed?(old, new) and not blank?(old.content) do
      kind = Atom.to_string(kind(old))
      cutoff = DateTime.add(DateTime.utc_now(), -@min_gap_seconds, :second)

      recent? = Repo.exists?(from r in Revision, where: r.kind == ^kind and r.record_id == ^old.id and r.inserted_at > ^cutoff)
      unless recent?, do: keep(old, user_id)
    end

    :ok
  end

  @doc "Keeps the record as it is now, whatever happened a moment ago."
  def keep(record, user_id \\ nil) do
    kind = Atom.to_string(kind(record))

    {:ok, _} =
      Repo.insert(%Revision{
        kind: kind,
        record_id: record.id,
        title: record.title,
        excerpt: record.excerpt,
        content: record.content,
        user_id: user_id
      })

    prune(kind, record.id)
    :ok
  end

  @doc "A record's versions, newest first (without their bodies' weight for the list: all fields are loaded)."
  def list(kind, record_id) when kind in [:page, :post] do
    k = Atom.to_string(kind)
    Repo.all(from r in Revision, where: r.kind == ^k and r.record_id == ^record_id, order_by: [desc: r.inserted_at, desc: r.id])
  end

  @doc """
  Puts the version `revision_id` back on `record` (title, excerpt and body), keeping the current
  version first. `{:error, :not_found}` when it isn't a version of this record.
  """
  def restore(record, revision_id, user_id \\ nil) do
    kind = Atom.to_string(kind(record))

    with {:ok, uuid} <- Ecto.UUID.cast(revision_id),
         %Revision{} = rev <- Repo.one(from r in Revision, where: r.id == ^uuid and r.kind == ^kind and r.record_id == ^record.id) do
      keep(record, user_id)
      attrs = %{title: rev.title, excerpt: rev.excerpt, content: rev.content}

      # (the changeset goes straight to the repo: this save is the restore, already kept above)
      changeset =
        case record do
          %Page{} -> Page.changeset(record, attrs)
          %Post{} -> Post.changeset(record, attrs)
        end

      Repo.update(changeset)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Removes every version of a record (when the record is deleted)."
  def delete_for(record) do
    kind = Atom.to_string(kind(record))
    Repo.delete_all(from r in Revision, where: r.kind == ^kind and r.record_id == ^record.id)
    :ok
  end

  defp changed?(old, new), do: old.title != new.title or old.excerpt != new.excerpt or old.content != new.content

  defp blank?(nil), do: true
  defp blank?(text), do: String.trim(text) == ""

  defp prune(kind, record_id) do
    keep_ids = from(r in Revision, where: r.kind == ^kind and r.record_id == ^record_id, order_by: [desc: r.inserted_at, desc: r.id], limit: ^@keep, select: r.id)
    Repo.delete_all(from r in Revision, where: r.kind == ^kind and r.record_id == ^record_id and r.id not in subquery(keep_ids))
  end
end
