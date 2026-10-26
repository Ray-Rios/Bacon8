defmodule Bacon8.UploadsPathsTest do
  # Uploads turns URLs into file paths, for deleting and checking files. Every one is
  # confined to the uploads directory (`delete_file/1` and `file_exists?/1` used to join
  # whatever they were given, so `/uploads/../mix.exs` was the project's own mix.exs).
  use ExUnit.Case, async: false

  alias Bacon8.Uploads

  setup do
    n = System.unique_integer([:positive])
    dir = Path.join(Uploads.base_dir(), "paths-test-#{n}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir, rel: "/uploads/paths-test-#{n}"}
  end

  describe "url_to_path/1" do
    test "maps an uploads URL to its file", %{dir: dir, rel: rel} do
      assert Uploads.url_to_path("#{rel}/a/b.png") == Path.join(dir, "a/b.png")
    end

    test "gives nil for a URL that climbs out of the uploads directory" do
      assert Uploads.url_to_path("/uploads/../mix.exs") == nil
      assert Uploads.url_to_path("/uploads/a/../../mix.exs") == nil
      assert Uploads.url_to_path(nil) == nil
    end
  end

  describe "delete_file/1" do
    test "deletes the file and an emptied folder", %{dir: dir, rel: rel} do
      File.mkdir_p!(Path.join(dir, "sub"))
      File.write!(Path.join(dir, "sub/a.txt"), "x")

      assert :ok = Uploads.delete_file("#{rel}/sub/a.txt")
      refute File.exists?(Path.join(dir, "sub/a.txt"))
      refute File.exists?(Path.join(dir, "sub")), "the empty folder is removed"
    end

    test "keeps a folder that still has something in it", %{dir: dir, rel: rel} do
      File.write!(Path.join(dir, "a.txt"), "x")
      File.write!(Path.join(dir, "b.txt"), "y")

      assert :ok = Uploads.delete_file("#{rel}/a.txt")
      assert File.exists?(Path.join(dir, "b.txt"))
    end

    test "refuses a URL that climbs out, and the file is still there", %{dir: dir, rel: rel} do
      outside = Path.join(Uploads.base_dir(), "outside-#{System.unique_integer([:positive])}.txt")
      File.write!(outside, "keep")
      on_exit(fn -> File.rm(outside) end)

      assert {:error, :invalid_path} = Uploads.delete_file("/uploads/../mix.exs")
      assert {:error, :invalid_path} = Uploads.delete_file("#{rel}/../../mix.exs")
      assert {:error, :invalid_path} = Uploads.delete_file("/uploads/#{Path.basename(dir)}/../../mix.exs")
      assert File.exists?("mix.exs")

      # a path that stays inside the uploads directory is allowed, wherever in it
      assert :ok = Uploads.delete_file("/uploads/#{Path.basename(outside)}")
      refute File.exists?(outside)
    end

    # Review of 2026-10-25: the drive's blob bodies are never deleted by URL, and only
    # /uploads/ URLs are taken at all.
    test "refuses the drive's blob store, wherever it is configured" do
      n = System.unique_integer([:positive])

      for root <- [Path.join(Uploads.base_dir(), "_drive"), Bacon8.Storage.Local.root()] do
        dir = Path.join(root, "zz-paths-test-#{n}")
        File.mkdir_p!(dir)
        on_exit(fn -> File.rm_rf(dir) end)
        body = Path.join(dir, "body")
        File.write!(body, "someone's file")

        if Bacon8.SafePath.inside?(body, Uploads.base_dir()) do
          url = "/uploads/" <> Path.relative_to(body, Path.expand(Uploads.base_dir()))
          assert {:error, :invalid_path} = Uploads.delete_file(url), url
        end

        assert File.exists?(body)
      end
    end

    test "refuses anything that isn't an /uploads/ URL", %{dir: dir} do
      File.write!(Path.join(dir, "a.txt"), "x")
      rel = "#{Path.basename(dir)}/a.txt"

      for url <- [rel, "/" <> rel, "uploads/" <> rel, "https://example.com/uploads/" <> rel] do
        assert {:error, :invalid_path} = Uploads.delete_file(url), url
      end

      assert File.exists?(Path.join(dir, "a.txt"))
    end

    test "never removes the uploads folder or public/ when they end up empty" do
      # it can't empty the real ones in a test, so check the guard by name: a file straight in
      # public/ is deleted and public/ itself is left alone
      File.mkdir_p!(Uploads.public_dir())
      name = "paths-test-#{System.unique_integer([:positive])}.txt"
      File.write!(Path.join(Uploads.public_dir(), name), "x")

      assert :ok = Uploads.delete_file("/uploads/public/#{name}")
      assert File.dir?(Uploads.public_dir())
    end

    test "says so when there is nothing to delete, or no path", %{rel: rel} do
      assert {:error, :enoent} = Uploads.delete_file("#{rel}/missing.txt")
      assert {:error, :invalid_path} = Uploads.delete_file(nil)
    end
  end

  describe "file_exists?/1" do
    test "is true for a file under the uploads directory", %{dir: dir, rel: rel} do
      File.write!(Path.join(dir, "a.txt"), "x")
      assert Uploads.file_exists?("#{rel}/a.txt")
      refute Uploads.file_exists?("#{rel}/b.txt")
    end

    test "is false for a path that climbs out, even to a file that exists" do
      assert File.exists?("mix.exs")
      refute Uploads.file_exists?("/uploads/../mix.exs")
      refute Uploads.file_exists?(nil)
    end
  end
end
