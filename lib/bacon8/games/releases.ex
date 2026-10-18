defmodule Bacon8.Games.Releases do
  @moduledoc """
  Client releases and their content-addressed file store.

  Storage is a directory of blobs named by SHA-256 on its own volume
  (`/app/client_releases` in the cluster, `client_releases/` in development) - deliberately
  NOT under `/app/uploads`, which Plug.Static serves to anyone. Every byte of
  the client goes out through `ReleasesController`, which checks the player.

  Publishing (deploy-game.sh) is three steps:

    1. `missing_blobs/1` - which of this build's hashes are not stored yet
    2. stream just those into `blobs/` (kubectl exec, no HTTP size limits)
    3. `publish/2` - record the manifest and make it live

  so an update uploads only the files that actually changed.
  """

  import Ecto.Query
  alias Bacon8.GamesRepo
  alias Bacon8.Games.GameRelease

  @sha_re ~r/\A[0-9a-f]{64}\z/

  def root_dir do
    Application.get_env(:bacon8, :releases_dir) ||
      if File.dir?("/app/client_releases"), do: "/app/client_releases", else: "client_releases"
  end

  def blob_dir, do: Path.join(root_dir(), "blobs")

  @doc "Absolute path of a blob, or :error for anything that is not a SHA-256."
  def blob_path(sha) when is_binary(sha) do
    sha = String.downcase(sha)
    if Regex.match?(@sha_re, sha), do: {:ok, Path.join(blob_dir(), sha)}, else: :error
  end

  def blob_path(_), do: :error

  def valid_sha?(sha), do: is_binary(sha) and Regex.match?(@sha_re, String.downcase(sha))

  def live_release(game_id) do
    GameRelease
    |> where([r], r.game_id == ^game_id and r.is_live == true)
    |> order_by([r], desc: r.published_at)
    |> limit(1)
    |> GamesRepo.one()
  end

  def list_releases(game_id, limit \\ 20) do
    GameRelease
    |> where([r], r.game_id == ^game_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> GamesRepo.all()
  end

  @doc "Every hash in `shas` that has no blob on disk (or a blob of the wrong size)."
  def missing_blobs(entries) when is_list(entries) do
    entries
    |> Enum.filter(fn %{"sha256" => sha} = e ->
      case blob_path(sha) do
        {:ok, path} ->
          case File.stat(path) do
            {:ok, %File.Stat{size: size}} -> is_integer(e["size"]) and size != e["size"]
            _ -> true
          end

        :error ->
          true
      end
    end)
    |> Enum.map(& &1["sha256"])
    |> Enum.uniq()
  end

  @doc """
  Record a release and make it the live one.

  Refuses unless every file (and the launcher, when given) is already stored at
  the right size - a live manifest that points at a missing blob is a launcher
  that fails halfway through every player's update.
  """
  def publish(game_id, %{"build_id" => build_id, "files" => files} = params)
      when is_binary(build_id) and is_list(files) do
    launcher = params["launcher"]
    entries = files ++ if(is_map(launcher), do: [launcher], else: [])

    cond do
      files == [] ->
        {:error, "A release needs at least one file."}

      not Enum.all?(entries, &valid_entry?/1) ->
        {:error, "Every entry needs a sha256 (64 hex chars) and an integer size; files also need a path."}

      Enum.any?(files, &unsafe_path?(&1["path"])) ->
        {:error, "File paths must be relative and stay inside the install folder."}

      is_binary(params["exe"]) and not Enum.any?(files, &(&1["path"] == params["exe"])) ->
        {:error, "exe must be one of the release's files."}

      (missing = missing_blobs(entries)) != [] ->
        {:error, "#{length(missing)} blob(s) are not uploaded yet, e.g. #{hd(missing)}."}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        total = Enum.reduce(files, 0, &(&1["size"] + &2))

        manifest = %{
          "files" => Enum.map(files, &Map.take(&1, ["path", "size", "sha256"])),
          "launcher" => if(is_map(launcher), do: Map.take(launcher, ["size", "sha256", "version", "filename"]), else: nil),
          # The game executable the launcher starts, relative to the install
          # folder. Recorded rather than guessed so a renamed target cannot
          # leave the launcher starting the wrong exe.
          "exe" => params["exe"],
          # Run once per machine before the first launch (VC++ redist etc.).
          "prereq" => params["prereq"]
        }

        GamesRepo.transaction(fn ->
          from(r in GameRelease, where: r.game_id == ^game_id and r.is_live == true)
          |> GamesRepo.update_all(set: [is_live: false, updated_at: now])

          existing = GamesRepo.get_by(GameRelease, game_id: game_id, build_id: build_id)

          (existing || %GameRelease{})
          |> GameRelease.changeset(%{
            game_id: game_id,
            build_id: build_id,
            manifest: manifest,
            total_bytes: total,
            notes: params["notes"],
            is_live: true,
            published_at: now
          })
          |> GamesRepo.insert_or_update()
          |> case do
            {:ok, release} -> release
            {:error, changeset} -> GamesRepo.rollback(changeset)
          end
        end)
    end
  end

  def publish(_game_id, _params), do: {:error, "build_id and files are required."}

  @doc "Make an older release live again (rollback)."
  def set_live(game_id, build_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case GamesRepo.get_by(GameRelease, game_id: game_id, build_id: build_id) do
      nil ->
        {:error, "No release #{build_id}."}

      release ->
        GamesRepo.transaction(fn ->
          from(r in GameRelease, where: r.game_id == ^game_id)
          |> GamesRepo.update_all(set: [is_live: false, updated_at: now])

          release
          |> GameRelease.changeset(%{is_live: true, published_at: now})
          |> GamesRepo.update!()
        end)
    end
  end

  defp valid_entry?(%{"sha256" => sha, "size" => size} = e) when is_integer(size) and size >= 0 do
    valid_sha?(sha) and (not Map.has_key?(e, "path") or is_binary(e["path"]))
  end

  defp valid_entry?(_), do: false

  defp unsafe_path?(path) when is_binary(path) do
    parts = String.split(path, ["/", "\\"])
    path == "" or String.starts_with?(path, ["/", "\\"]) or String.contains?(path, ":") or
      ".." in parts
  end

  defp unsafe_path?(_), do: true
end
