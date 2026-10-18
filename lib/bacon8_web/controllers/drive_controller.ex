defmodule Bacon8Web.DriveController do
  @moduledoc """
  Serves drive file bodies after an access check (BACON8.md §7).

    * `GET /files/:id`    - owner, staff, or anyone if the file is public
    * `GET /s/:token`     - anyone holding the share link ("link" visibility)

  Add `?download=1` to force a download. Single-range `Range:` requests are
  honoured so audio and video can seek.

  Refusals are always 404, never 403: a stranger must not learn that a private
  file exists.
  """
  use Bacon8Web, :controller

  alias Bacon8.Drive
  alias Bacon8.Drive.Sniff

  def show(conn, %{"id" => id} = params) do
    with %{} = file <- Drive.get_file(id),
         true <- Drive.can_read?(conn.assigns[:current_user], file, :id) do
      serve(conn, file, params, :id)
    else
      _ -> not_found(conn)
    end
  end

  def shared(conn, %{"token" => token} = params) do
    with %{} = file <- Drive.get_file_by_share_token(token),
         true <- Drive.can_read?(conn.assigns[:current_user], file, :share) do
      serve(conn, file, params, :share)
    else
      _ -> not_found(conn)
    end
  end

  defp serve(conn, file, params, via) do
    case Drive.body_path(file) do
      {:ok, path} ->
        inline? = Sniff.inline?(file.content_type) and params["download"] != "1"

        conn
        |> put_resp_content_type(file.content_type, nil)
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-disposition", disposition(inline?, file.name))
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("cache-control", cache_control(file))
        |> put_resp_header("referrer-policy", "no-referrer")
        |> put_csp(file.content_type)
        |> maybe_noindex(via)
        |> send_body(path, file.size)

      :error ->
        # Row exists but the body is gone - an operator problem, not the viewer's.
        require Logger
        Logger.error("Drive file #{file.id} has no body for blob #{file.blob_sha256}")
        not_found(conn)
    end
  end

  # PDFs are exempt from the sandbox: Chrome's PDF viewer refuses to run in a
  # sandboxed document. They are still nosniff'd and only served inline when
  # the bytes were recognised as a PDF.
  defp put_csp(conn, "application/pdf"), do: conn

  defp put_csp(conn, _type),
    do: put_resp_header(conn, "content-security-policy", "default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'; sandbox")

  defp maybe_noindex(conn, :share), do: put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
  defp maybe_noindex(conn, _), do: conn

  defp cache_control(%{visibility: "public"}), do: "public, max-age=3600"
  defp cache_control(_), do: "private, max-age=300"

  defp disposition(inline?, name) do
    kind = if inline?, do: "inline", else: "attachment"
    ascii = name |> String.replace(~r/[^\x20-\x7E]|["\\]/u, "_")
    ~s(#{kind}; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(name, &URI.char_unreserved?/1)})
  end

  defp send_body(conn, path, size) do
    case get_req_header(conn, "range") do
      [range] ->
        case parse_range(range, size) do
          {:ok, first, last} ->
            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
            |> send_file(206, path, first, last - first + 1)

          :error ->
            conn
            |> put_resp_header("content-range", "bytes */#{size}")
            |> send_resp(416, "")
        end

      _ ->
        send_file(conn, 200, path)
    end
  end

  @doc false
  # "bytes=0-99", "bytes=100-", "bytes=-500". Multi-range is not supported.
  def parse_range("bytes=" <> spec, size) when size > 0 do
    case String.split(spec, "-", parts: 2) do
      ["", suffix] ->
        with {n, ""} when n > 0 <- Integer.parse(suffix), do: {:ok, max(size - n, 0), size - 1}, else: (_ -> :error)

      [first, ""] ->
        with {f, ""} when f < size <- Integer.parse(first), do: {:ok, f, size - 1}, else: (_ -> :error)

      [first, last] ->
        with {f, ""} <- Integer.parse(first),
             {l, ""} <- Integer.parse(last),
             true <- f <= l and f < size do
          {:ok, f, min(l, size - 1)}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def parse_range(_, _), do: :error

  defp not_found(conn), do: conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not found")
end
