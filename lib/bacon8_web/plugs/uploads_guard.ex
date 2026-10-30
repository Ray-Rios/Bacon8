defmodule Bacon8Web.Plugs.UploadsGuard do
  @moduledoc """
  Sits in the endpoint immediately before the `/uploads` `Plug.Static`.

  1. **Every** `/uploads` response gets `X-Content-Type-Options: nosniff`, and files
     whose type a browser would execute (HTML, SVG, XML, JS...) additionally get a
     sandboxing CSP and `Content-Disposition: attachment`. Uploads are served from
     our own origin, so without this an uploaded `.html`/`.svg` is stored XSS.

  2. **Private** trees are never handed to `Plug.Static` (which would serve them to
     anyone with a one-year public cache). They are authorised here against the
     session and sent with `Cache-Control: private`, or answered with 404:

       * `/uploads/users/<user_id>/...`     - desktop "My Files" drive
       * `/uploads/<user_id>/files/...`     - older per-user uploads (the legacy `user_files`
                                               table is gone; only the owner and staff read these)

  `/uploads/_drive/...` (the drive's blob store) is refused outright.

     Owner, admin and gm may read. Everything else under `/uploads` (public/,
     avatars/, posts/, products/, forum/, per-user blog images) is unchanged.

  This is a stop-gap until user storage moves behind an authorising controller
  with signed URLs; see BACON8.md.
  """

  import Plug.Conn
  require Logger

  alias Bacon8.SafePath

  @behaviour Plug

  @impl true
  def init(opts) do
    %{
      session: Plug.Session.init(Keyword.fetch!(opts, :session)),
      root: Keyword.fetch!(opts, :root)
    }
  end

  @impl true
  def call(%Plug.Conn{path_info: ["uploads" | rest]} = conn, %{root: root} = opts) do
    conn = put_safety_headers(conn, List.last(rest))

    case classify(rest) do
      :public ->
        conn

      :never ->
        conn |> send_resp(404, "Not found") |> halt()

      {:private, owner_id} ->
        serve_private(conn, opts, root, rest, owner_id)
    end
  end

  def call(conn, _opts), do: conn

  # ---------------------------------------------------------------------------

  # Drive blob store (Bacon8.Storage.Local). Bodies are only ever served by
  # Bacon8Web.DriveController after an access check - never by path.
  defp classify(["_drive" | _]), do: :never
  defp classify(["users", owner_id | _]), do: {:private, owner_id}
  defp classify([owner_id, "files", _name | _]), do: {:private, owner_id}
  defp classify([_owner_id, "files"]), do: {:private, nil}
  defp classify(_), do: :public

  defp serve_private(conn, opts, root, rest, owner_id) do
    user = current_user(conn, opts)

    allowed =
      owner_id != nil and
        (owner?(user, owner_id) or staff?(user))

    with true <- allowed,
         {:ok, fs_path} <- SafePath.resolve(root, Path.join(rest)),
         {:ok, %File.Stat{type: :regular}} <- File.stat(fs_path) do
      conn
      |> put_resp_content_type(MIME.from_path(fs_path), nil)
      |> put_resp_header("cache-control", "private, max-age=300")
      |> send_file(200, fs_path)
      |> halt()
    else
      _ ->
        # 404 rather than 403: do not confirm that someone else's file exists.
        conn |> send_resp(404, "Not found") |> halt()
    end
  end

  defp current_user(conn, %{session: session_opts}) do
    conn
    |> Plug.Session.call(session_opts)
    |> fetch_session()
    |> Bacon8Web.Auth.call([])
    |> Map.get(:assigns)
    |> Map.get(:current_user)
  rescue
    e ->
      Logger.warning("UploadsGuard could not load session: #{Exception.message(e)}")
      nil
  end

  defp owner?(%{id: id, status: "active"}, owner_id), do: to_string(id) == owner_id
  defp owner?(_, _), do: false

  defp staff?(%{role: role, status: "active"}) when role in ["admin", "gm"], do: true
  defp staff?(_), do: false

  defp put_safety_headers(conn, name) do
    conn = put_resp_header(conn, "x-content-type-options", "nosniff")

    if SafePath.active_content?(name || "") do
      conn
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> put_resp_header("content-disposition", "attachment")
    else
      conn
    end
  end
end
