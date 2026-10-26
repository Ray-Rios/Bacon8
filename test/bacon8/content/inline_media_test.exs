defmodule Bacon8.Content.InlineMediaTest do
  # What a staff member drops into a page or post while editing it in place. It handles a file
  # name and a URL the browser sends, so a hostile name or URL must never reach outside the
  # page's own folder (the code it replaces wrote and deleted files wherever `../` led).
  use ExUnit.Case, async: false

  alias Bacon8.Content.InlineMedia
  alias Bacon8.Uploads

  setup do
    n = System.unique_integer([:positive])
    ctx = "pages/inline-media-test-#{n}"
    other = "pages/inline-media-other-#{n}"

    # a file that must survive everything below: in the uploads directory, outside public/
    File.mkdir_p!(Uploads.base_dir())
    canary = Path.join(Uploads.base_dir(), "canary-#{n}.txt")
    File.write!(canary, "keep me")

    on_exit(fn ->
      File.rm(canary)
      File.rm_rf(Path.join(Uploads.public_dir(), ctx))
      File.rm_rf(Path.join(Uploads.public_dir(), other))
    end)

    %{ctx: ctx, other: other, canary: canary}
  end

  defp upload(name, content \\ "hello", extra \\ %{}) do
    Map.merge(%{"data" => Base.encode64(content), "filename" => name, "mimeType" => "text/plain"}, extra)
  end

  defp stored_path(url), do: Uploads.url_to_path(url)
  defp inline_temp_files, do: Path.wildcard(Path.join(System.tmp_dir!(), "b8_inline_*"))

  describe "store/2" do
    test "puts the file in the context's folder and says where", %{ctx: ctx} do
      assert {:ok, %{url: url, filename: "note.txt"}} = InlineMedia.store(ctx, upload("note.txt", "the words"))

      assert String.starts_with?(url, "/uploads/public/#{ctx}/")
      assert String.ends_with?(url, ".txt")
      assert File.read!(stored_path(url)) == "the words"
    end

    test "leaves no temp file behind", %{ctx: ctx} do
      before = inline_temp_files()
      {:ok, _} = InlineMedia.store(ctx, upload("a.txt"))
      assert inline_temp_files() -- before == []
    end

    test "a file name that climbs out is cut down to its last part, and nothing lands outside", %{ctx: ctx} do
      for name <- ["../../../evil.txt", "..\\..\\evil.txt", "/etc/evil.txt", "a/b/../../../../evil.txt"] do
        assert {:ok, %{url: url, filename: "evil.txt"}} = InlineMedia.store(ctx, upload(name))
        assert String.starts_with?(url, "/uploads/public/#{ctx}/")
        assert Uploads.url_to_path(url) |> Bacon8.SafePath.inside?(Path.join(Uploads.public_dir(), ctx))
      end

      # nothing was written where the traversal pointed
      refute File.exists?(Path.expand("../evil.txt", System.tmp_dir!()))
      refute File.exists?(Path.expand("../../evil.txt", System.tmp_dir!()))
      refute File.exists?(Path.join(System.tmp_dir!(), "evil.txt"))
    end

    test "refuses a name with nothing usable in it", %{ctx: ctx} do
      for name <- ["..", ".", "", "../"] do
        assert {:error, "Invalid file name"} = InlineMedia.store(ctx, upload(name))
      end
    end

    test "invents a name when the browser sent none", %{ctx: ctx} do
      assert {:ok, %{filename: "upload_" <> _}} = InlineMedia.store(ctx, %{"data" => Base.encode64("x")})
    end

    test "refuses data that isn't base64, or isn't there", %{ctx: ctx} do
      assert {:error, "Invalid file data"} = InlineMedia.store(ctx, upload("a.txt", "x", %{"data" => "not base64!!"}))
      assert {:error, "Invalid file data"} = InlineMedia.store(ctx, %{"filename" => "a.txt"})
      assert {:error, "Invalid file data"} = InlineMedia.store(ctx, %{"data" => 12})
    end

    test "refuses a file over 25 MB", %{ctx: ctx} do
      big = :binary.copy("a", 25 * 1024 * 1024 + 1)
      assert {:error, "File too large"} = InlineMedia.store(ctx, upload("big.bin", big))
    end

    # Review of 2026-10-25 (a second reader, as BACON8.md section 14 asks)

    test "refuses file types a browser would run (invariant 4), and writes nothing", %{ctx: ctx} do
      for name <- ~w(page.html page.HTM pic.svg pic.SVGZ doc.xhtml feed.xml app.js ../../x.svg) do
        assert {:error, "That type of file can't be added here"} = InlineMedia.store(ctx, upload(name)), name
      end

      refute File.exists?(Path.join(Uploads.public_dir(), ctx))
    end

    test "refuses oversized data before decoding it", %{ctx: ctx} do
      # Not base64 at all: decoded first, the answer would have been "Invalid file data".
      too_long = :binary.copy("!", div(25 * 1024 * 1024 + 2, 3) * 4 + 1)
      assert {:error, "File too large"} = InlineMedia.store(ctx, upload("big.bin", "", %{"data" => too_long}))
    end

    test "a file of exactly 25 MB is still accepted (the early size check is not too strict)", %{ctx: ctx} do
      exact = :binary.copy("a", 25 * 1024 * 1024)
      assert {:ok, %{url: url}} = InlineMedia.store(ctx, upload("exact.bin", exact))
      assert File.stat!(stored_path(url)).size == 25 * 1024 * 1024
    end

    test "a missing mime type is fine", %{ctx: ctx} do
      assert {:ok, _} = InlineMedia.store(ctx, %{"data" => Base.encode64("x"), "filename" => "a.txt"})
    end
  end

  describe "remove/2" do
    test "deletes the context's own file", %{ctx: ctx} do
      {:ok, %{url: url}} = InlineMedia.store(ctx, upload("a.txt"))
      path = stored_path(url)
      assert File.exists?(path)

      assert :ok = InlineMedia.remove(ctx, url)
      refute File.exists?(path)
    end

    test "ignores another page's file", %{ctx: ctx, other: other} do
      {:ok, %{url: url}} = InlineMedia.store(other, upload("theirs.txt"))

      assert :ignored = InlineMedia.remove(ctx, url)
      assert File.exists?(stored_path(url))
    end

    test "ignores a URL that climbs out of public/", %{ctx: ctx, canary: canary} do
      name = Path.basename(canary)
      {:ok, %{url: own}} = InlineMedia.store(ctx, upload("a.txt"))

      for url <- [
            "/uploads/public/../#{name}",
            "/uploads/public/#{ctx}/../../../#{name}",
            "/uploads/public/#{ctx}/../../#{name}",
            "/uploads/public/./../#{name}"
          ] do
        assert :ignored = InlineMedia.remove(ctx, url), url
        assert File.exists?(canary), "#{url} deleted the canary"
      end

      assert File.exists?(stored_path(own))
    end

    test "ignores a URL that climbs out of this page into another's folder", %{ctx: ctx, other: other} do
      {:ok, %{url: url}} = InlineMedia.store(other, upload("theirs.txt"))
      theirs = Path.basename(url)

      assert :ignored = InlineMedia.remove(ctx, "/uploads/public/#{ctx}/../#{Path.basename(other)}/#{theirs}")
      assert File.exists?(stored_path(url))
    end

    test "ignores a directory, the context's own folder, and URLs outside public/", %{ctx: ctx, canary: canary} do
      {:ok, %{url: url}} = InlineMedia.store(ctx, upload("a.txt"))
      dir = Path.dirname(stored_path(url))

      assert :ignored = InlineMedia.remove(ctx, "/uploads/public/#{ctx}")
      assert :ignored = InlineMedia.remove(ctx, "/uploads/public/#{ctx}/")
      assert File.dir?(dir)
      assert :ignored = InlineMedia.remove(ctx, "/uploads/#{Path.basename(canary)}")
      assert :ignored = InlineMedia.remove(ctx, "/etc/passwd")
      assert :ignored = InlineMedia.remove(ctx, "https://example.com/uploads/public/#{ctx}/a.txt")
      assert :ignored = InlineMedia.remove(ctx, nil)
      assert File.exists?(canary)
    end

    # Review of 2026-10-25

    test "a page whose folder name starts another's can't reach the other", %{ctx: ctx} do
      longer = ctx <> "0"
      on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), longer)) end)
      {:ok, %{url: url}} = InlineMedia.store(longer, upload("theirs.txt"))

      assert :ignored = InlineMedia.remove(ctx, url)
      assert File.exists?(stored_path(url))
    end

    test "home-directory, encoded and doubled-slash URLs are ignored", %{ctx: ctx, canary: canary} do
      name = Path.basename(canary)

      for url <- [
            "/uploads/public/~/#{name}",
            "/uploads/public/~",
            "/uploads/public/%2e%2e/#{name}",
            "/uploads/public/#{ctx}/%2e%2e/%2e%2e/%2e%2e/#{name}",
            "/uploads/public//../#{name}",
            "/uploads/public/#{ctx}//../../../#{name}",
            "/uploads/public/#{ctx}/\\..\\..\\..\\#{name}",
            "/uploads/public/#{ctx}/x\0/../../../#{name}"
          ] do
        assert :ignored = InlineMedia.remove(ctx, url), inspect(url)
      end

      assert File.exists?(canary)
    end

    test "a link in the page's folder is removed as a link; what it points to stays", %{ctx: ctx, canary: canary} do
      dir = Path.join(Uploads.public_dir(), ctx)
      File.mkdir_p!(dir)
      link = Path.join(dir, "link.txt")

      case File.ln_s(canary, link) do
        :ok ->
          assert :ok = InlineMedia.remove(ctx, "/uploads/public/#{ctx}/link.txt")
          assert {:error, :enoent} = File.lstat(link)
          assert File.read!(canary) == "keep me"

        {:error, _} ->
          # A folder that can't hold links (a Windows folder mounted into Docker) has nothing to test.
          :ok
      end
    end

    test "a file that is already gone is not an error", %{ctx: ctx} do
      assert :ignored = InlineMedia.remove(ctx, "/uploads/public/#{ctx}/nothing.txt")
    end
  end
end
