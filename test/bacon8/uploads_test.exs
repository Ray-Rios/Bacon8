defmodule Bacon8.UploadsTest do
  # Bacon8.Uploads beyond its path functions (uploads_paths_test.exs has those): where an upload
  # lands, that a file removed as illegal can't come back, signed links and their lifetime, and
  # deleting (2026-11-15; BACON8.md §13 listed the module as untested).
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]
  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  defp entry(name, type \\ "text/plain"), do: %{client_name: name, client_type: type, client_size: 5}

  setup do
    user = user_fixture()
    on_exit(fn -> File.rm_rf(Uploads.user_dir(user.id)) end)
    %{user: user}
  end

  describe "upload_file/4" do
    test "a user's file lands in their own folder under a name of ours, never the client's", %{user: user} do
      assert {:ok, url} = Uploads.upload_file(user, tmp_upload("hello"), entry("../../evil.txt"), context: "blog")
      assert String.starts_with?(url, "/uploads/#{user.id}/blog/")
      assert Path.extname(url) == ".txt"
      refute url =~ "evil" or url =~ ".."
      assert File.read!(Uploads.url_to_path(url)) == "hello"
      assert Uploads.file_exists?(url)
      assert [%{url: ^url, size: 5}] = Uploads.list_user_uploads(user.id, "blog")
      assert Uploads.list_user_uploads(user.id, "avatar") == []
    end

    test "two uploads of the same file get two names", %{user: user} do
      assert {:ok, a} = Uploads.upload_file(user, tmp_upload("same"), entry("a.txt"), context: "blog")
      assert {:ok, b} = Uploads.upload_file(user, tmp_upload("same"), entry("a.txt"), context: "blog")
      assert a != b
    end

    test "a public upload lands under public/", %{user: _user} do
      context = "uploads-test-#{System.unique_integer([:positive])}"
      on_exit(fn -> File.rm_rf(Uploads.user_dir(nil, public: true, context: context)) end)
      assert {:ok, url} = Uploads.upload_file(nil, tmp_upload("logo"), entry("logo.txt"), context: context, public: true)
      assert String.starts_with?(url, "/uploads/public/#{context}/")
      assert File.read!(Uploads.url_to_path(url)) == "logo"
    end

    test "a file whose hash was blocked is refused, whoever sends it and whatever it is called", %{user: user} do
      body = "blocked-#{System.unique_integer([:positive])}"
      sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      admin = user_fixture(%{role: "admin", is_admin: true})
      assert :ok = Bacon8.Moderation.block_hash(sha, "test", admin)

      assert {:error, "This file can't be uploaded."} = Uploads.upload_file(user, tmp_upload(body), entry("holiday.jpg", "image/jpeg"), context: "blog")
      assert {:error, _} = Uploads.upload_file(admin, tmp_upload(body), entry("renamed.png", "image/png"), context: "chat")
      assert Uploads.list_user_uploads(user.id, "blog") == []
      # one byte different is another file
      assert {:ok, _} = Uploads.upload_file(user, tmp_upload(body <> "!"), entry("ok.txt"), context: "blog")
    end
  end

  describe "signed links" do
    setup %{user: user} do
      {:ok, url} = Uploads.upload_file(user, tmp_upload("secret"), entry("s.txt"), context: "private")
      %{url: url}
    end

    test "a signed link serves the file, as a file and not a page", %{url: url} do
      conn = get(build_conn(), Uploads.signed_url_for(url))
      assert conn.status == 200
      assert conn.resp_body == "secret"
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "the lifetime is inside the token: it can't be stretched from the URL, and is never more than a day", %{url: url} do
      "/uploads/signed?token=" <> token = Uploads.signed_url_for(url, expires_in: -1)
      # already over, and an expires_in in the query string changes nothing
      assert get(build_conn(), "/uploads/signed?token=#{token}&expires_in=999999").status == 403

      "/uploads/signed?token=" <> long = Uploads.signed_url_for(url, expires_in: 10 * 86_400)
      long = URI.decode_www_form(long)
      assert {:ok, ^url} = Phoenix.Token.verify(@endpoint, "uploads", long)
      # ten days were asked for: the token itself says one
      assert lifetime(long) == 86_400
      "/uploads/signed?token=" <> short = Uploads.signed_url_for(url, expires_in: 90)
      assert lifetime(URI.decode_www_form(short)) == 90
    end

    test "a tampered or missing token is refused; a token for a path outside uploads serves nothing", %{url: url} do
      "/uploads/signed?token=" <> token = Uploads.signed_url_for(url)
      assert get(build_conn(), "/uploads/signed?token=" <> token <> "x").status == 403
      assert get(build_conn(), "/uploads/signed").status == 400

      outside = Phoenix.Token.sign(@endpoint, "uploads", "/uploads/../mix.exs", max_age: 60)
      assert get(build_conn(), "/uploads/signed?token=" <> URI.encode_www_form(outside)).status == 404
      # and a token signed for something else is not an uploads token
      other = Phoenix.Token.sign(@endpoint, "login handoff", url)
      assert get(build_conn(), "/uploads/signed?token=" <> URI.encode_www_form(other)).status == 403
    end

    test "active content is sent as a download in a sandbox, never shown", %{user: user} do
      {:ok, url} = Uploads.upload_file(user, tmp_upload("<script>alert(1)</script>"), entry("page.html", "text/html"), context: "private")
      conn = get(build_conn(), Uploads.signed_url_for(url))
      assert conn.status == 200
      assert get_resp_header(conn, "content-disposition") == ["attachment"]
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "sandbox"
    end
  end

  describe "deleting" do
    test "deletes the file and its folder once empty, and nothing outside uploads", %{user: user} do
      {:ok, url} = Uploads.upload_file(user, tmp_upload("bye"), entry("b.txt"), context: "once")
      path = Uploads.url_to_path(url)
      assert :ok = Uploads.delete_file(url)
      refute File.exists?(path)
      refute File.exists?(Path.dirname(path))
      assert {:error, _} = Uploads.delete_file(url)
      assert {:error, :invalid_path} = Uploads.delete_file("/uploads/../mix.exs")
      assert {:error, :invalid_path} = Uploads.delete_file(nil)
      assert File.exists?("mix.exs")
    end
  end

  test "file kinds and sizes read the way the pages show them" do
    assert Uploads.get_file_type("image/png") == "image"
    assert Uploads.get_file_type("video/mp4") == "video"
    assert Uploads.get_file_type(nil) == "other"
    assert Uploads.format_bytes(0) == "0 B"
    assert Uploads.format_bytes(-1) == "0 B"
    assert Uploads.format_bytes(1024) =~ "KB"
  end

  # The lifetime a token carries (Plug.Crypto signs {data, signed at, max age} into it).
  defp lifetime(token) do
    [_, payload, _] = String.split(token, ".")

    case payload |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term([:safe]) do
      {_data, _signed_at, max_age} -> max_age
      %{max_age: max_age} -> max_age
    end
  end
end
