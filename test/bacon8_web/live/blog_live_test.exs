defmodule Bacon8Web.BlogLiveTest do
  # /blog and /blog/:slug: what a visitor can read, and what staff can do to a post in place.
  # A draft used to be readable by anyone who knew its slug, and a slug nobody had crashed.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  setup do
    %{author: person("admin")}
  end

  defp post!(author, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    {:ok, post} =
      Content.create_post(
        author,
        Map.merge(%{title: "Post #{n}", slug: "post-#{n}", content: "<p>Post words #{n}</p>", is_published: true}, Map.new(attrs))
      )

    on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "blog/#{post.id}")) end)
    post
  end

  defp redirected_to!(result, path) do
    assert {:error, {kind, %{to: ^path}}} = result
    assert kind in [:redirect, :live_redirect]
  end

  describe "the list" do
    test "shows published posts, and not drafts", %{author: author} do
      published = post!(author)
      draft = post!(author, %{is_published: false})

      {:ok, _view, html} = live(build_conn(), "/blog")

      assert html =~ published.title
      refute html =~ draft.title
    end
  end

  describe "a post" do
    test "a published post is open to anyone", %{author: author} do
      post = post!(author)

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, _view, html} = live(conn, "/blog/#{post.slug}")
        assert html =~ post.title
        assert html =~ "Post words"
      end
    end

    test "a draft is not: visitors and members are sent to the blog", %{author: author} do
      draft = post!(author, %{is_published: false})

      redirected_to!(live(build_conn(), "/blog/#{draft.slug}"), "/blog")
      redirected_to!(live(signed_in(person("member")), "/blog/#{draft.slug}"), "/blog")
    end

    test "a draft is open to staff, the roles that may edit it", %{author: author} do
      draft = post!(author, %{is_published: false})

      for role <- staff_roles() do
        assert {:ok, _view, html} = live(signed_in(person(role)), "/blog/#{draft.slug}")
        assert html =~ draft.title, "#{role} could not open the draft"
      end
    end

    test "staff see that a draft is a draft (it has no publish date to show)", %{author: author} do
      draft = post!(author, %{is_published: false})
      {:ok, _view, html} = live(signed_in(person("editor")), "/blog/#{draft.slug}")

      assert html =~ "Draft, not published"
      assert draft.published_at == nil
    end

    test "a published post shows its date", %{author: author} do
      post = post!(author, %{published_at: ~U[2026-03-04 05:06:07Z]})
      {:ok, _view, html} = live(build_conn(), "/blog/#{post.slug}")

      assert html =~ "March 04, 2026"
      refute html =~ "Draft, not published"
    end

    test "a slug nobody has sends the visitor to the blog instead of crashing" do
      redirected_to!(live(build_conn(), "/blog/no-such-post"), "/blog")
    end
  end

  describe "editing in place" do
    test "staff see the edit control, members and visitors don't", %{author: author} do
      post = post!(author)

      for role <- staff_roles() do
        {:ok, view, _} = live(signed_in(person(role)), "/blog/#{post.slug}")
        refute assigns(view).editing
        render_click(view, "toggle_edit")
        assert assigns(view).editing, "#{role} could not start editing"
      end

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, view, _} = live(conn, "/blog/#{post.slug}")
        assert render_click(view, "toggle_edit") =~ "permission"
        refute assigns(view).editing
      end
    end

    test "renaming a post keeps its address", %{author: author} do
      post = post!(author, %{slug: "stays-put-#{System.unique_integer([:positive])}"})
      {:ok, view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")

      render_click(view, "toggle_edit")
      render_click(view, "update_title", %{"value" => "A Brand New Title"})
      assert Content.get_post!(post.id).title == post.title
      render_click(view, "save_content")

      reloaded = Content.get_post!(post.id)
      assert reloaded.title == "A Brand New Title"
      assert reloaded.slug == post.slug
      assert {:ok, _view, html} = live(build_conn(), "/blog/#{post.slug}")
      assert html =~ "A Brand New Title"
    end

    test "a member's or visitor's title edit and autosave change nothing", %{author: author} do
      post = post!(author)

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, view, _} = live(conn, "/blog/#{post.slug}")
        render_click(view, "update_title", %{"value" => "Hijacked"})
        render_click(view, "editor-autosave", %{"content" => "<p>Defaced</p>"})

        reloaded = Content.get_post!(post.id)
        assert reloaded.title == post.title
        assert reloaded.content == post.content
      end
    end

    test "a published post is only changed when Save is pressed, not by autosave", %{author: author} do
      post = post!(author)
      {:ok, view, _} = live(signed_in(person("gm")), "/blog/#{post.slug}")
      render_click(view, "toggle_edit")

      render_click(view, "editor-autosave", %{"content" => "<p>Typed, not saved</p>"})
      assert Content.get_post!(post.id).content == post.content

      render_click(view, "save_content")
      assert Content.get_post!(post.id).content == "<p>Typed, not saved</p>"
    end

    test "a draft's autosave stores the content, but only while editing", %{author: author} do
      post = post!(author, %{is_published: false})
      {:ok, view, _} = live(signed_in(person("gm")), "/blog/#{post.slug}")

      render_click(view, "editor-autosave", %{"content" => "<p>Too early</p>"})
      assert Content.get_post!(post.id).content == post.content

      render_click(view, "toggle_edit")
      render_click(view, "editor-autosave", %{"content" => "<p>Saved while editing</p>"})

      assert Content.get_post!(post.id).content == "<p>Saved while editing</p>"
      assert_push_event(view, "content-saved", %{})
    end

    test "save & exit and cancel both leave editing", %{author: author} do
      post = post!(author)
      {:ok, view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")

      render_click(view, "toggle_edit")
      assert render_click(view, "save_content") =~ "Saved"
      refute assigns(view).editing

      render_click(view, "toggle_edit")
      assert render_click(view, "cancel_edit") =~ "discarded"
      refute assigns(view).editing
    end
  end

  describe "media dropped into the editor" do
    defp drop(view, name, extra \\ %{}) do
      render_click(
        view,
        "block-media-upload",
        Map.merge(%{"blockId" => "b1", "mediaType" => "file", "data" => Base.encode64("hi there"), "filename" => name, "mimeType" => "text/plain"}, extra)
      )
    end

    test "goes in the post's own folder", %{author: author} do
      post = post!(author)
      {:ok, view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")

      drop(view, "../../../../tmp/evil.txt")

      assert_push_event(view, "block-media-uploaded", %{blockId: "b1", url: url, filename: "evil.txt"})
      assert String.starts_with?(url, "/uploads/public/blog/#{post.id}/")
      assert File.read!(Uploads.url_to_path(url)) == "hi there"
      refute File.exists?("/tmp/evil.txt")
    end

    test "a broken upload is reported, not a crash", %{author: author} do
      post = post!(author)
      {:ok, view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")

      drop(view, "a.txt", %{"data" => "%%not base64%%"})
      assert_push_event(view, "block-media-error", %{error: "Invalid file data"})

      render_click(view, "block-media-upload", %{"blockId" => "b1", "mediaType" => "file"})
      assert Process.alive?(view.pid)
    end

    test "members and visitors can't upload or remove", %{author: author} do
      post = post!(author)
      {:ok, editor_view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")
      drop(editor_view, "mine.txt")
      assert_push_event(editor_view, "block-media-uploaded", %{url: url})

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, view, _} = live(conn, "/blog/#{post.slug}")
        drop(view, "sneaky.txt")
        render_click(view, "block-media-remove", %{"blockId" => "b1", "url" => url})
      end

      folder = Path.join(Uploads.public_dir(), "blog/#{post.id}")
      assert File.exists?(Uploads.url_to_path(url))
      assert length(File.ls!(folder)) == 1
    end

    test "removing deletes the post's own file, and nothing outside it", %{author: author} do
      post = post!(author)
      {:ok, view, _} = live(signed_in(person("admin")), "/blog/#{post.slug}")
      drop(view, "mine.txt")
      assert_push_event(view, "block-media-uploaded", %{url: url})
      mine = Uploads.url_to_path(url)

      File.mkdir_p!(Uploads.base_dir())
      canary = Path.join(Uploads.base_dir(), "canary-#{System.unique_integer([:positive])}.txt")
      File.write!(canary, "keep")
      on_exit(fn -> File.rm(canary) end)

      render_click(view, "block-media-remove", %{"blockId" => "b1", "url" => "/uploads/public/../#{Path.basename(canary)}"})
      assert File.exists?(canary)
      assert File.exists?(mine)

      render_click(view, "block-media-remove", %{"blockId" => "b1", "url" => url})
      refute File.exists?(mine)
    end
  end
end
