defmodule Bacon8Web.UploadsGuardTest do
  # The guard in front of the /uploads static files (BACON8.md invariants 2, 4 and 11). It had no
  # tests until the review of 2026-10-25, which found `.rss` and `.atom` files served inline as
  # XML, a type a browser runs script in.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  setup do
    n = System.unique_integer([:positive])
    dir = Path.join(Uploads.public_dir(), "guard-test-#{n}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir, url: "/uploads/public/guard-test-#{n}"}
  end

  test "a type a browser would run is sent as a sandboxed download", %{dir: dir, url: url} do
    for name <- ~w(page.html pic.svg feed.rss feed.atom data.xml page.HTML) do
      File.write!(Path.join(dir, name), "<x/>")
      conn = get(build_conn(), "#{url}/#{name}")

      assert conn.status == 200, name
      assert get_resp_header(conn, "content-disposition") == ["attachment"], name
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "sandbox", name
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"], name
    end
  end

  test "a picture is served inline, with nosniff", %{dir: dir, url: url} do
    File.write!(Path.join(dir, "a.png"), <<0x89, "PNG", 0, 0, 0, 0>>)
    conn = get(build_conn(), "#{url}/a.png")

    assert conn.status == 200
    assert get_resp_header(conn, "content-disposition") == []
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "the drive's blob store is never served by path" do
    dir = Path.join(Uploads.base_dir(), "_drive/zz")
    File.mkdir_p!(dir)
    body = Path.join(dir, "guard-test-#{System.unique_integer([:positive])}")
    File.write!(body, "someone's file")
    on_exit(fn -> File.rm(body) end)

    assert get(build_conn(), "/uploads/_drive/zz/#{Path.basename(body)}").status == 404
  end
end
