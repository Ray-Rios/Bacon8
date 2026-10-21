defmodule Bacon8.Drive do
  @moduledoc """
  User file storage (BACON8.md §7). The database is the only source of truth
  for what exists; `Bacon8.Storage` holds bodies by SHA-256 and nothing else.

  ## Concurrency rules

  * **Quota** - every operation that changes a user's total locks that user's
    `drive_usage` row (`FOR UPDATE`) first, so concurrent uploads cannot both
    pass the check.
  * **Blobs vs GC** - an upload upserts the blob row (which takes its row lock
    and bumps `last_referenced_at`) *before* making sure the body is on disk.
    GC selects blobs `FOR UPDATE SKIP LOCKED` and deletes their bodies inside
    the same transaction. So an upload either waits for GC to finish and then
    re-writes the body, or holds the lock and GC skips that blob.

  ## Lock (Guest / Banned)

  When a user's role becomes guest or banned (`on_role_change/3`), their drive is
  locked and scheduled for purge in 30 days. While locked the owner can do
  nothing; staff can still read for moderation. Restoring the role before the
  purge unlocks it.
  """

  import Ecto.Query
  require Logger

  alias Bacon8.Repo
  alias Bacon8.Accounts.User
  alias Bacon8.Entitlements
  alias Bacon8.Storage
  alias Bacon8.SafePath
  alias Bacon8.Drive.{Blob, Folder, Names, Policy, Sniff, Usage}
  alias Bacon8.Drive.File, as: DFile

  @purge_after_days 30

  def purge_after_days, do: @purge_after_days

  # ---------------------------------------------------------------------------
  # Quota & usage
  # ---------------------------------------------------------------------------

  @doc "Quota in bytes, or `:unlimited`."
  def quota_bytes(%User{} = user) do
    Policy.quota_bytes(user, Entitlements.active(user, Entitlements.storage_tier_kind()))
  end

  @doc "Everything the UI needs for a usage meter."
  def summary(%User{} = user) do
    usage = get_usage(user.id)
    quota = quota_bytes(user)

    %{
      bytes_used: usage.bytes_used,
      file_count: usage.file_count,
      quota_bytes: quota,
      over_quota?: quota != :unlimited and usage.bytes_used > quota,
      locked?: not is_nil(usage.locked_at),
      purge_after: usage.purge_after
    }
  end

  def get_usage(user_id) do
    Repo.get(Usage, user_id) || %Usage{user_id: user_id, bytes_used: 0, file_count: 0}
  end

  def locked?(user_id) do
    Repo.exists?(from u in Usage, where: u.user_id == ^user_id and not is_nil(u.locked_at))
  end

  defp lock_usage!(user_id) do
    now = DateTime.utc_now()

    Repo.insert_all(Usage, [%{user_id: user_id, bytes_used: 0, file_count: 0, inserted_at: now, updated_at: now}],
      on_conflict: :nothing,
      conflict_target: :user_id
    )

    Repo.one!(from u in Usage, where: u.user_id == ^user_id, lock: "FOR UPDATE")
  end

  defp bump_usage!(user_id, bytes, files) do
    {1, _} =
      from(u in Usage, where: u.user_id == ^user_id)
      |> Repo.update_all(inc: [bytes_used: bytes, file_count: files], set: [updated_at: DateTime.utc_now()])

    :ok
  end

  @doc "Recomputes a user's totals from their files (repair / after import)."
  def recompute_usage(user_id) do
    Repo.transaction(fn ->
      lock_usage!(user_id)

      {bytes, count} =
        from(f in DFile, where: f.owner_id == ^user_id, select: {coalesce(sum(f.size), 0), count(f.id)})
        |> Repo.one()

      from(u in Usage, where: u.user_id == ^user_id)
      |> Repo.update_all(set: [bytes_used: to_int(bytes), file_count: count, updated_at: DateTime.utc_now()])

      {to_int(bytes), count}
    end)
  end

  # ---------------------------------------------------------------------------
  # Listing & navigation
  # ---------------------------------------------------------------------------

  @doc """
  Contents of a folder (`nil` = root) owned by `user`, with breadcrumbs.
  Returns `{:error, :not_found}` for a folder the user does not own, and
  `{:error, :locked}` while the drive is locked.
  """
  def list_folder(%User{} = user, folder_id) do
    with :ok <- owner_can_act(user),
         {:ok, folder} <- fetch_owned_folder(user, folder_id) do
      folders =
        from(f in Folder, where: f.owner_id == ^user.id, order_by: fragment("lower(?)", f.name))
        |> where_parent(folder_id)
        |> Repo.all()

      files =
        from(f in DFile, where: f.owner_id == ^user.id, order_by: fragment("lower(?)", f.name))
        |> where_folder(folder_id)
        |> Repo.all()

      {:ok, %{folder: folder, folders: folders, files: files, breadcrumbs: breadcrumbs(user, folder_id)}}
    end
  end

  @doc """
  Resolves folder names from the root (`["Photos", "2026"]`) to a folder id.
  `[]` is the root (`{:ok, nil}`). Names are matched exactly; anything that
  does not resolve - including "." and ".." - is `{:error, :not_found}`.
  """
  def resolve_path(%User{id: uid}, segments) when is_list(segments) do
    Enum.reduce_while(segments, {:ok, nil}, fn name, {:ok, parent_id} ->
      q = from(f in Folder, where: f.owner_id == ^uid and f.name == ^name, select: f.id)

      case Repo.one(where_parent(q, parent_id)) do
        nil -> {:halt, {:error, :not_found}}
        id -> {:cont, {:ok, id}}
      end
    end)
  end

  @doc "Root-to-folder path as `[%{id, name}]` (empty for root)."
  def breadcrumbs(_user, nil), do: []

  def breadcrumbs(%User{} = user, folder_id) do
    sql = """
    WITH RECURSIVE up AS (
      SELECT id, parent_id, name, 0 AS depth FROM drive_folders WHERE id = $1 AND owner_id = $2
      UNION ALL
      SELECT f.id, f.parent_id, f.name, up.depth + 1
        FROM drive_folders f JOIN up ON f.id = up.parent_id
    )
    SELECT id, name FROM up ORDER BY depth DESC
    """

    %{rows: rows} = Repo.query!(sql, [dump!(folder_id), dump!(user.id)])
    Enum.map(rows, fn [id, name] -> %{id: Ecto.UUID.load!(id), name: name} end)
  end

  defp fetch_owned_folder(_user, nil), do: {:ok, nil}

  defp fetch_owned_folder(%User{id: uid}, folder_id) do
    with {:ok, fid} <- Ecto.UUID.cast(folder_id),
         %Folder{} = folder <- Repo.get_by(Folder, id: fid, owner_id: uid) do
      {:ok, folder}
    else
      _ -> {:error, :not_found}
    end
  end

  defp where_parent(q, nil), do: where(q, [f], is_nil(f.parent_id))
  defp where_parent(q, id), do: where(q, [f], f.parent_id == ^id)
  defp where_folder(q, nil), do: where(q, [f], is_nil(f.folder_id))
  defp where_folder(q, id), do: where(q, [f], f.folder_id == ^id)

  # ---------------------------------------------------------------------------
  # Folders
  # ---------------------------------------------------------------------------

  def create_folder(%User{} = user, parent_id, name) do
    with :ok <- owner_can_act(user),
         :ok <- storage_allowed(user),
         {:ok, _} <- fetch_owned_folder(user, parent_id) do
      %Folder{owner_id: user.id}
      |> Folder.changeset(%{name: name, parent_id: parent_id})
      |> Repo.insert()
    end
  end

  def rename_folder(%User{} = user, folder_id, name) do
    with :ok <- owner_can_act(user),
         {:ok, %Folder{} = folder} <- fetch_owned_folder(user, folder_id) do
      folder |> Folder.changeset(%{name: name}) |> Repo.update()
    else
      {:ok, nil} -> {:error, :not_found}
      other -> other
    end
  end

  @doc "Moves a folder under `new_parent_id` (nil = root). Refuses moves into its own subtree."
  def move_folder(%User{} = user, folder_id, new_parent_id) do
    with :ok <- owner_can_act(user),
         {:ok, %Folder{} = folder} <- fetch_owned_folder(user, folder_id),
         {:ok, _} <- fetch_owned_folder(user, new_parent_id),
         false <- new_parent_id != nil and new_parent_id in subtree_ids(user, folder.id) do
      folder |> Folder.changeset(%{parent_id: new_parent_id}) |> Repo.update()
    else
      true -> {:error, :cannot_move_into_itself}
      {:ok, nil} -> {:error, :not_found}
      other -> other
    end
  end

  @doc "Deletes a folder, everything below it, and gives the space back."
  def delete_folder(%User{} = user, folder_id) do
    with :ok <- owner_can_act(user),
         {:ok, %Folder{} = folder} <- fetch_owned_folder(user, folder_id) do
      Repo.transaction(fn ->
        lock_usage!(user.id)
        ids = subtree_ids(user, folder.id)

        {bytes, count} =
          from(f in DFile, where: f.owner_id == ^user.id and f.folder_id in ^ids,
            select: {coalesce(sum(f.size), 0), count(f.id)})
          |> Repo.one()

        # drive_files.folder_id and drive_folders.parent_id cascade on delete.
        Repo.delete!(folder)
        bump_usage!(user.id, -to_int(bytes), -count)
        %{deleted_files: count, freed_bytes: to_int(bytes)}
      end)
    else
      {:ok, nil} -> {:error, :not_found}
      other -> other
    end
  end

  defp subtree_ids(%User{id: uid}, root_id) do
    sql = """
    WITH RECURSIVE sub AS (
      SELECT id FROM drive_folders WHERE id = $1 AND owner_id = $2
      UNION ALL
      SELECT f.id FROM drive_folders f JOIN sub ON f.parent_id = sub.id
    )
    SELECT id FROM sub
    """

    %{rows: rows} = Repo.query!(sql, [dump!(root_id), dump!(uid)])
    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  # ---------------------------------------------------------------------------
  # Files
  # ---------------------------------------------------------------------------

  @doc """
  Adds the file at `src_path` (e.g. a LiveView upload's temp file) to `user`'s
  drive in `folder_id` (nil = root) as `name`.

  Options:
    * `on_conflict: :rename` (default) - "a.png" becomes "a (1).png" if taken
    * `on_conflict: :error`
    * `visibility:` - default "private"
    * `legacy_ref:` - set by the importer; skips the quota check
  """
  def add_file(%User{} = user, folder_id, src_path, name, opts \\ []) do
    name = Names.normalize(name)
    legacy? = Keyword.has_key?(opts, :legacy_ref)

    with :ok <- if(legacy?, do: :ok, else: owner_can_act(user)),
         :ok <- if(legacy?, do: :ok, else: storage_allowed(user)),
         nil <- Names.problem(name),
         false <- SafePath.active_content?(name),
         {:ok, %{size: size, type: :regular}} <- Elixir.File.stat(src_path),
         :ok <- if(legacy?, do: :ok, else: within_upload_limit(user, size)),
         {:ok, _} <- fetch_owned_folder(user, folder_id) do
      sha = Storage.sha256_file(src_path)
      sniffed = Sniff.sniff_file(src_path)
      quota = if legacy?, do: :unlimited, else: quota_bytes(user)

      Repo.transaction(fn ->
        usage = lock_usage!(user.id)
        if usage.locked_at && not legacy?, do: Repo.rollback(:locked)
        unless Policy.fits?(quota, usage.bytes_used, size), do: Repo.rollback(:quota_exceeded)

        final_name =
          case Keyword.get(opts, :on_conflict, :rename) do
            :rename -> Names.dedupe(name, sibling_names(user.id, folder_id))
            :error -> name
          end

        now = DateTime.utc_now()

        Repo.insert_all(
          Blob,
          [%{sha256: sha, size: size, content_type: sniffed, last_referenced_at: now, inserted_at: now}],
          on_conflict: [set: [last_referenced_at: now]],
          conflict_target: :sha256
        )

        case Storage.put_new(sha, src_path) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback({:storage_failed, reason})
        end

        file =
          %DFile{owner_id: user.id}
          |> DFile.create_changeset(%{
            name: final_name,
            folder_id: folder_id,
            blob_sha256: sha,
            size: size,
            content_type: Sniff.content_type(sniffed, final_name),
            visibility: Keyword.get(opts, :visibility, "private"),
            legacy_ref: Keyword.get(opts, :legacy_ref)
          })
          |> Repo.insert()
          |> case do
            {:ok, file} -> file
            {:error, changeset} -> Repo.rollback(changeset)
          end

        bump_usage!(user.id, size, 1)
        file
      end)
    else
      true -> {:error, :file_type_not_allowed}
      msg when is_binary(msg) -> {:error, {:invalid_name, msg}}
      {:ok, %{type: _}} -> {:error, :not_a_file}
      {:error, _} = error -> error
    end
  end

  defp within_upload_limit(user, size) do
    case Policy.max_upload_bytes(user) do
      :unlimited -> :ok
      max when size <= max -> :ok
      _ -> {:error, :too_large}
    end
  end

  defp sibling_names(user_id, folder_id) do
    files = from(f in DFile, where: f.owner_id == ^user_id, select: f.name) |> where_folder(folder_id)
    folders = from(f in Folder, where: f.owner_id == ^user_id, select: f.name) |> where_parent(folder_id)
    Repo.all(files) ++ Repo.all(folders)
  end

  @doc """
  Every file a user owns, across all folders, newest first. `category` is
  "all", "image", "video", "audio" or "other" (by stored content type).
  """
  def list_all_files(%User{} = user, category \\ "all") do
    with :ok <- owner_can_act(user) do
      q = from(f in DFile, where: f.owner_id == ^user.id, order_by: [desc: f.inserted_at], preload: [:folder])

      q =
        case category do
          "image" -> where(q, [f], like(f.content_type, "image/%"))
          "video" -> where(q, [f], like(f.content_type, "video/%"))
          "audio" -> where(q, [f], like(f.content_type, "audio/%"))
          "other" ->
            where(q, [f], not like(f.content_type, "image/%") and not like(f.content_type, "video/%") and
                            not like(f.content_type, "audio/%"))
          _ -> q
        end

      {:ok, Repo.all(q)}
    end
  end

  @doc "Deletes several of a user's files in one transaction. Ids the user doesn't own are ignored."
  def delete_files(%User{} = user, ids) when is_list(ids) do
    ids = Enum.flat_map(ids, fn id -> case Ecto.UUID.cast(id) do {:ok, uuid} -> [uuid]; :error -> [] end end)

    with :ok <- owner_can_act(user) do
      Repo.transaction(fn ->
        lock_usage!(user.id)

        {count, sizes} =
          from(f in DFile, where: f.owner_id == ^user.id and f.id in ^ids, select: f.size)
          |> Repo.delete_all()

        bump_usage!(user.id, -Enum.sum(sizes), -count)
        count
      end)
    end
  end

  @doc "A file by id regardless of owner. Use `can_read?/3` before serving it."
  def get_file(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(DFile, uuid)
      :error -> nil
    end
  end

  def get_file_by_share_token(token) when is_binary(token) and byte_size(token) in 16..64 do
    Repo.get_by(DFile, share_token: token, visibility: "link")
  end

  def get_file_by_share_token(_), do: nil

  defp fetch_owned_file(%User{id: uid}, file_id) do
    with {:ok, fid} <- Ecto.UUID.cast(file_id),
         %DFile{} = file <- Repo.get_by(DFile, id: fid, owner_id: uid) do
      {:ok, file}
    else
      _ -> {:error, :not_found}
    end
  end

  def rename_file(%User{} = user, file_id, name) do
    with :ok <- owner_can_act(user),
         {:ok, file} <- fetch_owned_file(user, file_id),
         false <- SafePath.active_content?(name || "") do
      file |> DFile.rename_changeset(%{name: name}) |> Repo.update()
    else
      true -> {:error, :file_type_not_allowed}
      other -> other
    end
  end

  def move_file(%User{} = user, file_id, folder_id) do
    with :ok <- owner_can_act(user),
         {:ok, file} <- fetch_owned_file(user, file_id),
         {:ok, _} <- fetch_owned_folder(user, folder_id) do
      file |> DFile.rename_changeset(%{folder_id: folder_id}) |> Repo.update()
    end
  end

  def delete_file(%User{} = user, file_id) do
    with :ok <- owner_can_act(user),
         {:ok, file} <- fetch_owned_file(user, file_id) do
      Repo.transaction(fn ->
        lock_usage!(user.id)
        Repo.delete!(file)
        bump_usage!(user.id, -file.size, -1)
        file
      end)
    end
  end

  @doc """
  Sets visibility. Moving to "link" mints a share token; leaving "link" (or
  calling `reset_share_link/2`) invalidates the old one.
  """
  def set_visibility(%User{} = user, file_id, visibility) when visibility in ~w(private link public) do
    with :ok <- owner_can_act(user),
         {:ok, file} <- fetch_owned_file(user, file_id) do
      token =
        cond do
          visibility != "link" -> nil
          file.visibility == "link" and file.share_token -> file.share_token
          true -> new_share_token()
        end

      file |> DFile.visibility_changeset(visibility, token) |> Repo.update()
    end
  end

  def set_visibility(_, _, _), do: {:error, :invalid_visibility}

  def reset_share_link(%User{} = user, file_id) do
    with :ok <- owner_can_act(user),
         {:ok, %DFile{visibility: "link"} = file} <- fetch_owned_file(user, file_id) do
      file |> DFile.visibility_changeset("link", new_share_token()) |> Repo.update()
    else
      {:ok, _} -> {:error, :not_shared_by_link}
      other -> other
    end
  end

  defp new_share_token, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

  # ---------------------------------------------------------------------------
  # Access
  # ---------------------------------------------------------------------------

  @doc """
  May `viewer` (a user or nil) read `file`? `via` is `:id` for `/files/:id` and
  `:share` for `/s/:token`. A locked owner's files are readable by staff only.
  """
  def can_read?(viewer, %DFile{} = file, via) when via in [:id, :share] do
    cond do
      Policy.staff_reader?(viewer) -> true
      locked?(file.owner_id) -> false
      owner?(viewer, file) -> true
      file.visibility == "public" -> true
      file.visibility == "link" and via == :share -> true
      true -> false
    end
  end

  defp owner?(%User{id: id, status: "active"}, %DFile{owner_id: id}), do: true
  defp owner?(_, _), do: false

  @doc "Local path of a file's body, for `send_file`."
  def body_path(%DFile{blob_sha256: sha}), do: Storage.local_path(sha)

  # The owner may act on their own drive unless it is locked or they are not active.
  defp owner_can_act(%User{status: status}) when status != "active", do: {:error, :account_inactive}

  defp owner_can_act(%User{id: id}) do
    if locked?(id), do: {:error, :locked}, else: :ok
  end

  defp storage_allowed(%User{role: role}) do
    if Policy.no_storage_role?(role), do: {:error, :no_storage}, else: :ok
  end

  # ---------------------------------------------------------------------------
  # Role changes, purge, GC
  # ---------------------------------------------------------------------------

  @doc """
  Called by `Bacon8.Accounts.change_role/3` inside its transaction.

    * becoming guest/banned: lock the drive, schedule purge in 30 days, revoke
      storage tiers (subscriptions are cancelled by Accounts)
    * leaving guest/banned: unlock and cancel the purge (revoked tiers are not
      restored - the user is back on the free tier)
  """
  def on_role_change(%User{} = user, old_role, new_role) do
    old_none = Policy.no_storage_role?(old_role)
    new_none = Policy.no_storage_role?(new_role)

    cond do
      new_none and not old_none ->
        lock!(user.id)
        Entitlements.revoke_all(user, Entitlements.storage_tier_kind(), "role:#{new_role}")
        :locked

      old_none and not new_none ->
        unlock!(user.id)
        :unlocked

      true ->
        :unchanged
    end
  end

  @doc false
  def lock!(user_id, now \\ DateTime.utc_now()) do
    lock_usage!(user_id)
    purge_at = DateTime.add(now, @purge_after_days * 86_400, :second)

    from(u in Usage, where: u.user_id == ^user_id and is_nil(u.locked_at))
    |> Repo.update_all(set: [locked_at: now, purge_after: purge_at, updated_at: now])

    :ok
  end

  @doc false
  def unlock!(user_id) do
    from(u in Usage, where: u.user_id == ^user_id)
    |> Repo.update_all(set: [locked_at: nil, purge_after: nil, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc "Purges every locked drive whose 30 days are up. Returns the user ids purged."
  def purge_due(now \\ DateTime.utc_now()) do
    from(u in Usage,
      where: not is_nil(u.locked_at) and not is_nil(u.purge_after) and u.purge_after <= ^now,
      select: u.user_id
    )
    |> Repo.all()
    |> Enum.filter(&(purge_user_files(&1, now) == :purged))
  end

  @doc false
  def purge_user_files(user_id, now \\ DateTime.utc_now()) do
    {:ok, result} =
      Repo.transaction(fn ->
        usage = lock_usage!(user_id)

        # Re-check under the lock: the role may have been restored meanwhile.
        if usage.locked_at && usage.purge_after && DateTime.compare(usage.purge_after, now) != :gt do
          {files, _} = Repo.delete_all(from f in DFile, where: f.owner_id == ^user_id)
          Repo.delete_all(from f in Folder, where: f.owner_id == ^user_id)

          from(u in Usage, where: u.user_id == ^user_id)
          |> Repo.update_all(set: [bytes_used: 0, file_count: 0, purge_after: nil, updated_at: now])

          Logger.info("Drive purge: user #{user_id}, #{files} files deleted after #{@purge_after_days}-day hold")
          :purged
        else
          :skipped
        end
      end)

    result
  end

  @doc """
  Deletes blobs no file references, whose last reference is older than
  `grace_seconds`. Bodies are deleted inside the transaction (see moduledoc).
  Returns the number deleted.
  """
  def gc_blobs(grace_seconds \\ 3600, limit \\ 500) do
    # Plugins share the blob store (the store's product images and downloads):
    # keep what they still use. If one can't say, delete nothing this round.
    case Bacon8.Plugins.storage_refs() do
      {:ok, plugin_refs} ->
        gc_unreferenced_blobs(grace_seconds, limit, MapSet.to_list(plugin_refs))

      {:error, slug} ->
        Logger.warning("Drive: blob GC skipped; plugin #{slug} could not list the blobs it uses")
        0
    end
  end

  defp gc_unreferenced_blobs(grace_seconds, limit, plugin_refs) do
    cutoff = DateTime.add(DateTime.utc_now(), -grace_seconds, :second)

    {:ok, count} =
      Repo.transaction(fn ->
        shas =
          from(b in Blob,
            as: :blob,
            where: b.last_referenced_at < ^cutoff,
            where: not exists(from f in DFile, where: f.blob_sha256 == parent_as(:blob).sha256, select: 1),
            where: b.sha256 not in ^plugin_refs,
            select: b.sha256,
            limit: ^limit,
            lock: "FOR UPDATE SKIP LOCKED"
          )
          |> Repo.all()

        Enum.each(shas, fn sha ->
          case Storage.delete(sha) do
            :ok -> :ok
            {:error, reason} -> Repo.rollback({:storage_delete_failed, sha, reason})
          end
        end)

        {n, _} = Repo.delete_all(from b in Blob, where: b.sha256 in ^shas)
        n
      end)

    count
  end

  # ---------------------------------------------------------------------------

  defp dump!(uuid), do: Ecto.UUID.dump!(uuid)
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n
  defp to_int(nil), do: 0
end
