defmodule Bacon8Web.EditorMediaControllerTest do
  # POST /editor/media (2026-10-29): the page builder's pictures and files go by HTTP, not as
  # base64 inside a LiveView event (a phone photo made one frame big enough to drop the connection).
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content

  @endpoint Bacon8Web.Endpoint

  defp upload(name, bytes) do
    path = Path.join(System.tmp_dir!(), "b8_editor_media_test_#{System.unique_integer([:positive])}_#{name}")
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: name, content_type: "image/png"}
  end

  defp post_media(conn, params), do: conn |> Plug.Conn.put_private(:plug_skip_csrf_protection, true) |> post("/editor/media", params)

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "picture bytes">>

  test "staff add a picture to their draft; it lands in the page's own folder" do
    editor = person("editor")
    {:ok, page} = Content.create_draft(:page, editor)

    conn = post_media(signed_in(editor), %{"kind" => "page", "id" => page.id, "file" => upload("cat.png", @png)})
    assert %{"url" => "/uploads/public/pages/" <> rest, "filename" => "cat.png"} = json_response(conn, 200)
    assert String.starts_with?(rest, page.id <> "/")
  end

  test "members, guests and strangers can't upload; a missing page or file says so" do
    {:ok, page} = Content.create_draft(:page, person("admin"))
    params = %{"kind" => "page", "id" => page.id, "file" => upload("x.png", @png)}

    assert json_response(post_media(signed_in(person("member")), params), 403)
    assert json_response(post_media(build_conn(), params), 403)
    assert json_response(post_media(signed_in(person("admin")), %{params | "id" => Ecto.UUID.generate()}), 404)
    assert json_response(post_media(signed_in(person("admin")), Map.delete(params, "file")), 400)
  end

  test "files a browser would run are refused" do
    admin = person("admin")
    {:ok, post} = Content.create_draft(:post, admin)
    up = %{upload("evil.svg", "<svg onload=alert(1)>") | content_type: "image/svg+xml"}

    assert %{"error" => message} = json_response(post_media(signed_in(admin), %{"kind" => "post", "id" => post.id, "file" => up}), 422)
    assert message =~ "can't be added"
  end
end
