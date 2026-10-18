defmodule Bacon8Web.LauncherDownloadController do
  @moduledoc """
  GET /games/:game_slug/launcher - the launcher installer for signed-in users.

  The launcher is the ONLY thing downloaded from the website. Everything else
  (the game itself, and later versions of the launcher) the launcher fetches
  for itself from `/api/games/:slug/releases`.
  """

  use Bacon8Web, :controller

  alias Bacon8.{Accounts, Games}
  alias Bacon8.Games.Releases

  def show(conn, %{"game_slug" => slug}) do
    user = get_session(conn, "user_id") && Accounts.get_user(get_session(conn, "user_id"))

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:info, "Sign in to download the launcher.")
        |> redirect(to: "/login")

      true ->
        with %{} = game <- Games.get_game_by_slug(slug),
             %{} = release <- Releases.live_release(game.id),
             %{"sha256" => sha} <- release.manifest["launcher"],
             {:ok, path} <- Releases.blob_path(sha),
             {:ok, %File.Stat{size: size}} <- File.stat(path) do
          Bacon8Web.Api.ReleasesController.send_blob(conn, path, size, launcher_filename(game, release))
        else
          _ ->
            conn
            |> put_flash(:error, "The launcher is not available yet - check back soon.")
            |> redirect(to: "/games")
        end
    end
  end

  # The manifest may name the file ("launcher": {"filename": ...}); otherwise
  # it is the game's name, letters and digits only: "My Game" ->
  # "MyGameLauncher.exe".
  defp launcher_filename(game, release) do
    case release.manifest["launcher"]["filename"] do
      name when is_binary(name) and name != "" -> Path.basename(name)
      _ -> String.replace(game.name, ~r/[^A-Za-z0-9]/, "") <> "Launcher.exe"
    end
  end
end
