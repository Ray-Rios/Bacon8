defmodule Bacon8Web.Api.ReleasesController do
  @moduledoc """
  Client releases for a game's launcher - see `Bacon8.Games.Releases`.

  Reading (the launcher, as a signed-in player):
    GET  /api/games/:slug/releases/latest      the live manifest
    GET  /api/games/:slug/releases/blobs/:sha  one file, with Range support

  Publishing (deploy-game.sh, with the server API key):
    POST /api/games/:slug/releases/missing     which blobs still need uploading
    POST /api/games/:slug/releases             record + make live
    POST /api/games/:slug/releases/:build_id/live   roll back to an older one

  RANGES ARE THE POINT of the blob endpoint, not a nicety. The ingress cuts any
  response at 300 s, and the client pak is gigabytes; the launcher fetches each
  file in 64 MB ranges, which also makes every download resumable.
  """

  use Bacon8Web, :controller
  require Logger

  alias Bacon8.Games
  alias Bacon8.Games.Releases

  plug Bacon8Web.Plugs.GamesApiKeyOrAuth

  def latest(conn, %{"game_slug" => slug}) do
    with {:ok, game} <- fetch_game(slug) do
      case Releases.live_release(game.id) do
        nil ->
          error(conn, 404, "No release has been published yet.")

        release ->
          json(conn, %{
            success: true,
            build_id: release.build_id,
            published_at: release.published_at,
            total_bytes: release.total_bytes,
            files: release.manifest["files"] || [],
            launcher: release.manifest["launcher"],
            exe: release.manifest["exe"],
            prereq: release.manifest["prereq"]
          })
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  def blob(conn, %{"game_slug" => slug, "sha" => sha}) do
    with {:ok, _game} <- fetch_game(slug),
         {:ok, path} <- blob_path(sha),
         {:ok, %File.Stat{size: size}} <- stat(path) do
      send_blob(conn, path, size)
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  def missing(conn, %{"game_slug" => slug} = params) do
    with :ok <- require_server(conn),
         {:ok, _game} <- fetch_game(slug),
         entries when is_list(entries) <- params["entries"] do
      valid = Enum.filter(entries, &(is_map(&1) and Releases.valid_sha?(&1["sha256"])))
      json(conn, %{success: true, missing: Releases.missing_blobs(valid)})
    else
      {:error, status, message} -> error(conn, status, message)
      _ -> error(conn, 400, "entries must be a list of {sha256, size}.")
    end
  end

  def publish(conn, %{"game_slug" => slug} = params) do
    with :ok <- require_server(conn),
         {:ok, game} <- fetch_game(slug) do
      case Releases.publish(game.id, params) do
        {:ok, release} ->
          Logger.info("Release #{release.build_id} published for #{slug} (#{release.total_bytes} bytes).")
          json(conn, %{success: true, build_id: release.build_id, total_bytes: release.total_bytes})

        {:error, %Ecto.Changeset{} = cs} ->
          error(conn, 422, inspect(cs.errors))

        {:error, message} ->
          error(conn, 422, message)
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  def set_live(conn, %{"game_slug" => slug, "build_id" => build_id}) do
    with :ok <- require_server(conn),
         {:ok, game} <- fetch_game(slug) do
      case Releases.set_live(game.id, build_id) do
        {:ok, release} -> json(conn, %{success: true, build_id: release.build_id})
        {:error, message} when is_binary(message) -> error(conn, 404, message)
        {:error, other} -> error(conn, 422, inspect(other))
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  # ---------------------------------------------------------------------------

  @doc false
  def send_blob(conn, path, size, filename \\ nil) do
    conn =
      conn
      |> put_resp_content_type("application/octet-stream", nil)
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("cache-control", "private, max-age=0")

    conn =
      if filename,
        do: put_resp_header(conn, "content-disposition", ~s(attachment; filename="#{filename}")),
        else: conn

    case parse_range(get_req_header(conn, "range"), size) do
      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :full ->
        send_file(conn, 200, path)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  # One range only - all the launcher ever asks for.
  defp parse_range(["bytes=" <> spec | _], size) do
    case String.split(spec, "-", parts: 2) do
      [first, ""] -> range(Integer.parse(first), {size - 1, ""}, size)
      ["", suffix] ->
        case Integer.parse(suffix) do
          {n, ""} when n > 0 -> {:ok, max(size - n, 0), size - 1}
          _ -> :unsatisfiable
        end

      [first, last] -> range(Integer.parse(first), Integer.parse(last), size)
      _ -> :unsatisfiable
    end
  end

  defp parse_range(_, _size), do: :full

  defp range({first, ""}, {last, ""}, size) when first >= 0 and first < size and last >= first,
    do: {:ok, first, min(last, size - 1)}

  defp range(_, _, _), do: :unsatisfiable

  defp blob_path(sha) do
    case Releases.blob_path(sha) do
      {:ok, path} -> {:ok, path}
      :error -> {:error, 400, "Not a SHA-256."}
    end
  end

  defp stat(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular} = st} -> {:ok, st}
      _ -> {:error, 404, "No such file in any release."}
    end
  end

  defp require_server(conn) do
    case conn.assigns[:games_auth_mode] do
      :server_api_key -> :ok
      _ -> {:error, 403, "Publishing requires the server API key."}
    end
  end

  defp fetch_game(slug) do
    case Games.get_game_by_slug(slug) do
      nil -> {:error, 404, "Unknown game: #{slug}"}
      game -> {:ok, game}
    end
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{success: false, message: message})
  end
end
