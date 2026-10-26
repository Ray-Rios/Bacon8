defmodule Bacon8.SafePathTest do
  # SafePath is what stands between a client-supplied path or file name and the filesystem
  # (uploads, the drive, downloads, now the inline editors too). It had no tests.
  use ExUnit.Case, async: true

  alias Bacon8.SafePath

  describe "resolve/2" do
    test "joins a path inside the root" do
      assert SafePath.resolve("/srv/up", "a/b.png") == {:ok, "/srv/up/a/b.png"}
      assert SafePath.resolve("/srv/up", "a/../b.png") == {:ok, "/srv/up/b.png"}
    end

    test "the root itself is allowed" do
      assert SafePath.resolve("/srv/up") == {:ok, "/srv/up"}
      assert SafePath.resolve("/srv/up", "") == {:ok, "/srv/up"}
      assert SafePath.resolve("/srv/up", "a/..") == {:ok, "/srv/up"}
    end

    test "climbing out is refused, however it is spelled" do
      assert SafePath.resolve("/srv/up", "../etc/passwd") == :error
      assert SafePath.resolve("/srv/up", "a/../../etc/passwd") == :error
      assert SafePath.resolve("/srv/up", "a/b/../../../x") == :error
      assert SafePath.resolve("/srv/up", "..") == :error
    end

    test "a sibling whose name starts with the root's is not inside it" do
      assert SafePath.resolve("/srv/up", "../up-evil/x") == :error
      refute SafePath.inside?("/srv/up-evil/x", "/srv/up")
    end

    test "an absolute subpath is taken as relative to the root, not as an escape" do
      assert SafePath.resolve("/srv/up", "/etc/passwd") == {:ok, "/srv/up/etc/passwd"}
      assert SafePath.resolve("/srv/up", "///a") == {:ok, "/srv/up/a"}
    end

    test "NUL bytes and things that aren't strings are refused" do
      assert SafePath.resolve("/srv/up", "a\0b") == :error
      assert SafePath.resolve("/srv/up", nil) == :error
      assert SafePath.resolve(nil, "a") == :error
      assert SafePath.resolve("/srv/up", 42) == :error
    end

    test "resolve!/2 gives the path, or nil" do
      assert SafePath.resolve!("/srv/up", "a") == "/srv/up/a"
      assert SafePath.resolve!("/srv/up", "../a") == nil
    end
  end

  describe "inside?/2" do
    test "is true for the root and what is under it, and false otherwise" do
      assert SafePath.inside?("/srv/up", "/srv/up")
      assert SafePath.inside?("/srv/up/a/b", "/srv/up")
      assert SafePath.inside?("/srv/up/a/../b", "/srv/up")
      refute SafePath.inside?("/srv", "/srv/up")
      refute SafePath.inside?("/srv/up/../other", "/srv/up")
      refute SafePath.inside?(nil, "/srv/up")
    end

    test "a trailing slash on the root changes nothing" do
      assert SafePath.inside?("/srv/up/a", "/srv/up/")
    end
  end

  describe "filename/1" do
    test "keeps an ordinary name" do
      assert SafePath.filename("photo.png") == "photo.png"
      assert SafePath.filename("my file (1).jpg") == "my file (1).jpg"
    end

    test "drops any directory part, with either slash" do
      assert SafePath.filename("a/b/c.png") == "c.png"
      assert SafePath.filename("../../etc/passwd") == "passwd"
      assert SafePath.filename("C:\\Users\\me\\x.png") == "x.png"
      assert SafePath.filename("..\\..\\x.png") == "x.png"
      assert SafePath.filename("/abs/x.png") == "x.png"
    end

    test "drops control characters and trims" do
      assert SafePath.filename("  a\0b\n.png  ") == "ab.png"
    end

    test "has nothing to give for an empty name, a dot or two, a bare directory, or a non-string" do
      for bad <- ["", " ", ".", "..", "a/", "../", "../..", nil, 7] do
        assert SafePath.filename(bad) == nil, "expected nil for #{inspect(bad)}"
      end
    end

    test "is at most 255 characters" do
      assert String.length(SafePath.filename(String.duplicate("a", 400) <> ".png")) == 255
    end
  end

  describe "active_content?/1" do
    test "is true for what a browser runs, whatever the case" do
      for name <- ~w(a.html a.HTM b.svg c.JS d.php e.xml f.xhtml g.mjs h.swf i.rss j.ATOM k.rdf l.xht) do
        assert SafePath.active_content?(name), name
      end
    end

    test "is false for pictures, documents and the like" do
      for name <- ~w(a.png b.jpg c.pdf d.txt e.zip f.mp3 noextension) do
        refute SafePath.active_content?(name), name
      end

      refute SafePath.active_content?(nil)
    end
  end
end
