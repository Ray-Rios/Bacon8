defmodule Bacon8Web.UploadController do
  use Bacon8Web, :controller
  require Logger

  def signed_download(conn, %{"token" => token}) when is_binary(token) do
    # No max_age passed: Phoenix.Token uses the lifetime signed into the token by
    # Uploads.signed_url_for/2. The old `expires_in` query param is ignored - it
    # was client-controlled. Tokens minted before this change carry the 1-day
    # default, so old links simply expire.
    case Phoenix.Token.verify(Bacon8Web.Endpoint, "uploads", token) do
      {:ok, url_path} when is_binary(url_path) ->
        fs_path = Bacon8.Uploads.url_to_path(url_path)

        if fs_path && File.regular?(fs_path) do
          conn
          |> put_resp_header("cache-control", "private, max-age=300")
          |> put_resp_header("x-content-type-options", "nosniff")
          |> maybe_force_download(fs_path)
          |> send_file(200, fs_path)
        else
          send_resp(conn, 404, "Not found")
        end

      {:error, _reason} ->
        Logger.warning("Invalid or expired upload token requested")
        send_resp(conn, 403, "Invalid or expired token")
    end
  end

  def signed_download(conn, _params), do: send_resp(conn, 400, "Missing token")

  defp maybe_force_download(conn, fs_path) do
    if Bacon8.SafePath.active_content?(fs_path) do
      conn
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> put_resp_header("content-disposition", "attachment")
    else
      conn
    end
  end
end
