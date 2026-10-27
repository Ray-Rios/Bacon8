defmodule Bacon8.Content.LibraryTest do
  # The image library: pictures added to pages and posts, listed once, reusable elsewhere.
  use Bacon8.DataCase, async: false

  alias Bacon8.{Repo, Uploads}
  alias Bacon8.Content.{Image, InlineMedia, Library}

  defp unique, do: "lib#{System.unique_integer([:positive])}"

  defp folder(kind \\ "pages") do
    context = "#{kind}/#{Ecto.UUID.generate()}"
    on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), context)) end)
    context
  end

  defp add(context, name, bytes) do
    {:ok, %{url: url}} = InlineMedia.store(context, %{"data" => Base.encode64(bytes), "filename" => name, "mimeType" => "image/png"})
    url
  end

  defp names(search), do: Library.list(query: search).images |> Enum.map(& &1.filename)

  describe "recording" do
    test "a picture stored for a page is listed, and a text file is not" do
      ctx = folder()
      tag = unique()
      add(ctx, "#{tag}.png", "picture one")
      {:ok, _} = InlineMedia.store(ctx, %{"data" => Base.encode64("words"), "filename" => "#{tag}.txt", "mimeType" => "text/plain"})

      assert names(tag) == ["#{tag}.png"]
    end

    test "the same picture on two pages is listed once" do
      tag = unique()
      add(folder(), "#{tag}.png", "same bytes #{tag}")
      add(folder("blog"), "#{tag}.png", "same bytes #{tag}")

      assert names(tag) == ["#{tag}.png"]
      assert Repo.aggregate(Image, :count) >= 2
    end

    test "search matches part of a file name, case-insensitively, and treats % and _ as plain letters" do
      tag = unique()
      add(folder(), "Sunset-#{tag}.png", "a #{tag}")
      add(folder(), "Moon-#{tag}.png", "b #{tag}")

      assert names("sunset-#{tag}") == ["Sunset-#{tag}.png"]
      assert names("%") == []
      assert names("_____") == []
    end
  end

  describe "paging" do
    test "forty at a time, newest first, and says when there are more" do
      ctx = folder()
      tag = unique()
      for n <- 1..45, do: add(ctx, "#{tag}-#{n}.png", "bytes #{tag} #{n}")

      first = Library.list(query: tag)
      assert length(first.images) == 40
      assert first.more

      second = Library.list(query: tag, offset: 40)
      assert length(second.images) == 5
      refute second.more
    end
  end

  describe "sync_from_disk/0" do
    test "adds pictures that were there before the library, skipping thumbnails" do
      ctx = folder()
      dir = Path.join(Uploads.public_dir(), ctx)
      File.mkdir_p!(dir)
      tag = unique()
      File.write!(Path.join(dir, "#{tag}.jpg"), "old picture #{tag}")
      File.write!(Path.join(dir, "thumb_#{tag}.jpg.png"), "thumbnail")

      assert names(tag) == ["#{tag}.jpg"]
    end

    test "forgets pictures whose file is gone" do
      ctx = folder()
      tag = unique()
      url = add(ctx, "#{tag}.png", "doomed #{tag}")
      assert names(tag) == ["#{tag}.png"]

      File.rm!(Uploads.url_to_path(url))

      assert names(tag) == []
      assert Repo.get_by(Image, url: url) == nil
    end
  end

  describe "use_image/3" do
    test "copies the picture into the other page's folder" do
      tag = unique()
      source = add(folder(), "#{tag}.png", "to share #{tag}")
      target = folder("blog")

      assert {:ok, %{url: url, filename: filename}} = Library.use_image(target, source, nil)

      assert url != source
      assert String.starts_with?(url, "/uploads/public/#{target}/")
      assert filename == "#{tag}.png"
      assert File.read!(Uploads.url_to_path(url)) == "to share #{tag}"
      # (still one entry: same picture)
      assert names(tag) == ["#{tag}.png"]
    end

    test "deleting the first page's folder leaves the copy working" do
      tag = unique()
      source_ctx = folder()
      source = add(source_ctx, "#{tag}.png", "survivor #{tag}")
      {:ok, %{url: copy}} = Library.use_image(folder("blog"), source)

      File.rm_rf!(Path.join(Uploads.public_dir(), source_ctx))

      assert File.read!(Uploads.url_to_path(copy)) == "survivor #{tag}"
    end

    test "a picture already in that folder is used as it is" do
      ctx = folder()
      url = add(ctx, "#{unique()}.png", "mine #{unique()}")
      assert {:ok, %{url: ^url}} = Library.use_image(ctx, url)
    end

    test "only library pictures can be used: not other files, other places, or paths that climb" do
      target = folder()
      outside = Path.join(Uploads.base_dir(), "not-public-#{unique()}.png")
      File.mkdir_p!(Uploads.base_dir())
      File.write!(outside, "secret")
      on_exit(fn -> File.rm(outside) end)

      for url <- ["/uploads/public/../#{Path.basename(outside)}", "/etc/passwd", "../../x.png", "/uploads/public/pages/nope/x.png", nil, 42] do
        assert {:error, _} = Library.use_image(target, url)
      end
    end
  end
end
