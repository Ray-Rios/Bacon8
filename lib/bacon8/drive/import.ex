defmodule Bacon8.Drive.Import do
  @moduledoc """
  One-off migration of legacy user files into `Bacon8.Drive` (BACON8.md §7).

  Sources, per user:

    1. `user_folders` rows        -> drive folders (by their path strings)
    2. `user_files` rows (Arc)    -> drive files, in their `folder_path`;
                                     `is_public` -> visibility "public"
    3. `uploads/users/<id>/**`    -> drive files under the same folder names
                                     (what the old desktop explorer wrote)

  Safe to re-run: each imported file records a `legacy_ref`
  ("user_file:<id>" / "fs:users/<id>/<path>") and is skipped next time.
  Nothing legacy is modified or deleted. Quotas are not enforced during the
  import (a user may end up over quota: they keep their files but cannot
  upload until under it). Users whose role is already guest/banned are
  imported and then locked, which starts their 30-day hold.

  Run in production:

      bin/bacon8 eval "Bacon8.Drive.Import.run()"

  or in development: `mix drive.import`. Pass `dry_run: true` to only count.
  """

  import Ecto.Query
  require Logger

  alias Bacon8.Repo
  alias Bacon8.Accounts.User
  alias Bacon8.Drive
  alias Bacon8.Drive.{Folder, Names, Policy}
  alias Bacon8.Drive.File, as: DFile
  alias Bacon8.Files.{UserFile, UserFolder}

  def run(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    base = Bacon8.Uploads.base_dir()

    user_ids =
      (Repo.all(from f in UserFile, distinct: true, select: f.user_id) ++
         Repo.all(from f in UserFolder, distinct: true, select: f.user_id) ++
         fs_user_ids(base))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    Logger.info("Drive import: #{length(user_ids)} user(s) with legacy files#{if dry_run, do: " (dry run)"}")

    totals =
      Enum.reduce(user_ids, %{users: 0, files: 0, skipped: 0, failed: 0, missing: 0}, fn uid, acc ->
        case Repo.get(User, uid) do
          nil ->
            acc

          user ->
            r = import_user(user, base, dry_run)
            %{acc | users: acc.users + 1, files: acc.files + r.files, skipped: acc.skipped + r.skipped,
                    failed: acc.failed + r.failed, missing: acc.missing + r.missing}
        end
      end)

    Logger.info("Drive import finished: #{inspect(totals)}")
    totals
  end

  defp import_user(%User{} = user, base, dry_run) do
    stats = %{files: 0, skipped: 0, failed: 0, missing: 0}

    # 1. Folders that exist only as user_folders rows (possibly empty).
    unless dry_run do
      from(f in UserFolder, where: f.user_id == ^user.id, select: f.path)
      |> Repo.all()
      |> Enum.each(&ensure_folder_path(user, &1))
    end

    # 2. Arc user_files.
    stats =
      from(f in UserFile, where: f.user_id == ^user.id)
      |> Repo.all()
      |> Enum.reduce(stats, fn uf, st ->
        ref = "user_file:#{uf.id}"
        name = uf.original_filename || uf.filename || "file"
        visibility = if uf.is_public, do: "public", else: "private"
        import_one(user, ref, legacy_user_file_path(uf, base), uf.folder_path || "/", name, visibility, dry_run, st)
      end)

    # 3. Raw files written by the old desktop explorer.
    root = Path.join([base, "users", to_string(user.id)])

    stats =
      root
      |> walk_files()
      |> Enum.reduce(stats, fn abs, st ->
        rel = Path.relative_to(abs, root)
        ref = "fs:users/#{user.id}/#{rel}"
        folder = rel |> Path.dirname() |> then(&if(&1 == ".", do: "/", else: "/" <> &1))
        import_one(user, ref, abs, folder, Path.basename(rel), "private", dry_run, st)
      end)

    unless dry_run do
      Drive.recompute_usage(user.id)
      if Policy.no_storage_role?(user.role), do: Drive.lock!(user.id)
    end

    Logger.info("Drive import: user #{user.id}: #{inspect(stats)}")
    stats
  end

  defp import_one(user, ref, path, folder_path, name, visibility, dry_run, st) do
    cond do
      Repo.exists?(from f in DFile, where: f.legacy_ref == ^ref) ->
        %{st | skipped: st.skipped + 1}

      is_nil(path) or not File.regular?(path) ->
        Logger.warning("Drive import: #{ref}: body not found (#{inspect(path)})")
        %{st | missing: st.missing + 1}

      dry_run ->
        %{st | files: st.files + 1}

      true ->
        with {:ok, folder_id} <- ensure_folder_path(user, folder_path),
             {:ok, _} <- Drive.add_file(user, folder_id, path, clean_name(name),
                           legacy_ref: ref, visibility: visibility) do
          %{st | files: st.files + 1}
        else
          error ->
            Logger.warning("Drive import: #{ref}: #{inspect(error)}")
            %{st | failed: st.failed + 1}
        end
    end
  end

  # Where Arc put the original: ask Arc for its URL, then map it onto the
  # uploads volume (Uploads.url_to_path confines it to that directory).
  defp legacy_user_file_path(%UserFile{} = uf, base) do
    from_arc =
      try do
        if uf.file do
          case Bacon8.UserFileUpload.url({uf.file, uf}, :original) do
            url when is_binary(url) -> url |> String.split("?") |> hd() |> Bacon8.Uploads.url_to_path()
            _ -> nil
          end
        end
      rescue
        _ -> nil
      end

    cond do
      from_arc && File.regular?(from_arc) -> from_arc
      is_binary(uf.file_path) -> Bacon8.SafePath.resolve!(base, String.replace_prefix(uf.file_path, "/uploads/", ""))
      true -> from_arc
    end
  end

  # "/a/b" -> creates a, a/b as needed (directly, bypassing lock/role checks -
  # this is an operator migration). Returns {:ok, folder_id | nil}.
  defp ensure_folder_path(user, path) do
    path
    |> to_string()
    |> String.split("/", trim: true)
    |> Enum.map(&clean_name/1)
    |> Enum.reduce_while({:ok, nil}, fn name, {:ok, parent_id} ->
      existing =
        from(f in Folder, where: f.owner_id == ^user.id and f.name == ^name)
        |> then(fn q -> if parent_id, do: where(q, [f], f.parent_id == ^parent_id), else: where(q, [f], is_nil(f.parent_id)) end)
        |> Repo.one()

      case existing do
        %Folder{id: id} ->
          {:cont, {:ok, id}}

        nil ->
          case %Folder{owner_id: user.id} |> Folder.changeset(%{name: name, parent_id: parent_id}) |> Repo.insert() do
            {:ok, f} -> {:cont, {:ok, f.id}}
            {:error, cs} -> {:halt, {:error, {:folder, path, cs.errors}}}
          end
      end
    end)
  end

  defp clean_name(name) do
    cleaned = Bacon8.SafePath.filename(to_string(name)) || "file"
    if Names.problem(cleaned), do: "file", else: cleaned
  end

  # Regular files under `dir`, recursively, never following symlinks.
  defp walk_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn e ->
          p = Path.join(dir, e)

          case File.lstat(p) do
            {:ok, %{type: :directory}} -> walk_files(p)
            {:ok, %{type: :regular}} -> [p]
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  defp fs_user_ids(base) do
    case File.ls(Path.join(base, "users")) do
      {:ok, dirs} -> Enum.filter(dirs, &match?({:ok, _}, Ecto.UUID.cast(&1)))
      _ -> []
    end
  end
end
