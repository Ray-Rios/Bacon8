defmodule Bacon8Web.ContentEditingTest do
  # One builder behind every editing screen: the admin pages and the in-place editors share the
  # editor's events, and a new page or post is a draft from the first click, so uploads and
  # autosave always have a record to belong to.
  use Bacon8.DataCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.{Content, Uploads}
  alias Bacon8.Content.{Page, Post}
  alias Bacon8Web.ContentEditing

  @endpoint Bacon8Web.Endpoint

  defp drop(view, name \\ "notes.txt") do
    render_hook(view, "block-media-upload", %{
      "blockId" => "b1", "mediaType" => "file", "data" => Base.encode64("hi there"), "filename" => name, "mimeType" => "text/plain"
    })
  end

  describe "new drafts" do
    test "a page starts as an untitled, unpublished draft with a free slug" do
      author = person("admin")
      {:ok, one} = Content.create_draft(:page, author)
      {:ok, two} = Content.create_draft(:page, author)

      assert {one.title, one.slug, one.is_published} == {"Untitled", "untitled", false}
      assert two.slug == "untitled-2"
      assert Content.untouched_draft?(one)
    end

    test "a post starts the same way, and belongs to its author" do
      author = person("admin")
      {:ok, post} = Content.create_draft(:post, author)
      post = Repo.preload(post, :user)
      assert {post.title, post.slug, post.user.id} == {"Untitled", "untitled", author.id}
      assert Content.untouched_draft?(post)
    end

    test "a draft with words, a new title or a publication is no longer untouched" do
      {:ok, page} = Content.create_draft(:page, person("admin"))
      {:ok, written} = Content.update_page(page, %{content: "<p>x</p>"})
      {:ok, renamed} = Content.update_page(page, %{title: "Real"})
      refute Content.untouched_draft?(written)
      refute Content.untouched_draft?(renamed)
      refute Content.untouched_draft?(%Page{title: "Untitled", content: "", is_published: true})
    end

    test "the slug follows the first real title, and only then" do
      {:ok, page} = Content.create_draft(:page, person("admin"))
      assert %{"slug" => "my-title"} = Content.slug_for_save(:page, page, %{"title" => "My Title", "slug" => "untitled"})
      assert %{"slug" => "mine"} = Content.slug_for_save(:page, page, %{"title" => "My Title", "slug" => "mine"})
      assert %{"slug" => "untitled"} = Content.slug_for_save(:page, page, %{"title" => "  ", "slug" => "untitled"})

      {:ok, named} = Content.update_page(page, %{slug: "kept"})
      assert %{"slug" => "kept"} = Content.slug_for_save(:page, named, %{"title" => "Other", "slug" => "kept"})
    end
  end

  describe "ContentEditing.context/2" do
    test "names a record's own uploads folder, and nothing without a record" do
      assert ContentEditing.context(:page, %{id: "abc"}) == "pages/abc"
      assert ContentEditing.context(:post, %{id: "abc"}) == "blog/abc"
      assert ContentEditing.context(:page, nil) == nil
      assert ContentEditing.context(:page, %Page{}) == nil
    end
  end

  describe "the admin pages editor" do
    setup do
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      render_click(view, "new_page")
      [page] = Repo.all(from p in Page, where: p.title == "Untitled")
      %{view: view, page: page}
    end

    test "a new page is a saved draft at once", %{page: page} do
      refute page.is_published
      assert page.slug =~ "untitled"
    end

    test "files dropped into the editor go to the page's own folder", %{view: view, page: page} do
      drop(view)

      assert_push_event(view, "block-media-uploaded", %{blockId: "b1", url: url, filename: "notes.txt"})
      assert String.starts_with?(url, "/uploads/public/pages/#{page.id}/")
      assert File.read!(Uploads.url_to_path(url)) == "hi there"
    end

    test "removing deletes only that page's file", %{view: view, page: page} do
      drop(view)
      assert_push_event(view, "block-media-uploaded", %{url: url})
      path = Uploads.url_to_path(url)

      other = Path.join(Uploads.public_dir(), "pages/not-#{page.id}/keep.txt")
      File.mkdir_p!(Path.dirname(other))
      File.write!(other, "keep")

      render_hook(view, "block-media-remove", %{"blockId" => "b1", "url" => "/uploads/public/pages/not-#{page.id}/keep.txt"})
      assert File.exists?(other)

      render_hook(view, "block-media-remove", %{"blockId" => "b1", "url" => url})
      refute File.exists?(path)
      File.rm_rf!(Path.dirname(other))
    end

    test "naming it gives it a matching address", %{view: view} do
      render_submit(view, "save", %{"page" => %{"title" => "Fresh Start", "content" => "<p>x</p>", "slug" => "untitled"}, "action_type" => "draft"})
      assert %Page{slug: "fresh-start"} = Repo.get_by!(Page, title: "Fresh Start")
    end

    test "cancelling an untouched draft leaves nothing behind", %{view: view, page: page} do
      render_click(view, "cancel_form")
      refute Repo.get(Page, page.id)
    end

    test "cancelling a draft that has words in it keeps it", %{view: view, page: page} do
      {:ok, _} = Content.update_page(page, %{content: "<p>keep me</p>"})
      render_click(view, "cancel_form")
      assert Repo.get(Page, page.id)
    end

    test "cancelling while editing an existing page never deletes it, even one that looks untouched" do
      {:ok, existing} = Content.create_page(%{title: "Untitled", slug: "kept-#{System.unique_integer([:positive])}", content: ""})
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      render_click(view, "edit_page", %{"id" => existing.id})
      render_click(view, "cancel_form")
      assert Repo.get(Page, existing.id)
    end

    test "a GM or editor can use the editor too" do
      for role <- ~w(gm editor) do
        {:ok, view, _} = live(signed_in(person(role)), "/admin/pages")
        render_click(view, "new_page")
        drop(view, "#{role}.txt")
        assert_push_event(view, "block-media-uploaded", %{filename: _})
      end
    end

    test "an event before any page is open is answered, not stored", %{} do
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      drop(view)
      assert_push_event(view, "block-media-error", %{blockId: "b1", error: "Save a draft first"})
    end
  end

  describe "the admin blog editor" do
    setup do
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/blog-management")
      render_click(view, "new_post")
      [post] = Repo.all(from p in Post, where: p.title == "Untitled")
      %{view: view, post: post}
    end

    test "a new post is a saved draft, and uploads go to its own folder", %{view: view, post: post} do
      refute post.is_published
      drop(view)
      assert_push_event(view, "block-media-uploaded", %{url: url})
      assert String.starts_with?(url, "/uploads/public/blog/#{post.id}/")
    end

    test "cancelling an untouched draft leaves nothing behind", %{view: view, post: post} do
      render_click(view, "cancel_form")
      refute Repo.get(Post, post.id)
    end

    test "naming it gives it a matching address", %{view: view} do
      render_submit(view, "save", %{"post" => %{"title" => "Big News", "content" => "<p>x</p>", "slug" => "untitled"}, "action_type" => "draft"})
      assert %Post{slug: "big-news"} = Repo.get_by!(Post, title: "Big News")
    end
  end

  describe "the editor's own events on the admin screens" do
    @blocks ~s({"rows":[{"columns":[{"blocks":[{"type":"text","content":"<p>typed</p>"}]}]}]})

    test "a change is acknowledged and a draft's autosave is stored (pages)" do
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      render_click(view, "new_page")
      [page] = Repo.all(from p in Page, where: p.title == "Untitled")

      render_hook(view, "editor-change", %{"content" => @blocks, "html" => "<p>typed</p>"})
      render_hook(view, "editor-autosave", %{"content" => @blocks, "html" => "<p>typed</p>"})

      assert Repo.get!(Page, page.id).content == @blocks
      assert_push_event(view, "content-saved", %{})
    end

    test "a draft's autosave is stored (posts)" do
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/blog-management")
      render_click(view, "new_post")
      [post] = Repo.all(from p in Post, where: p.title == "Untitled")

      render_hook(view, "editor-autosave", %{"content" => @blocks})
      assert Repo.get!(Post, post.id).content == @blocks
    end

    test "a published page is not rewritten behind its editor's back" do
      {:ok, page} = Content.create_page(%{title: "Live one", slug: "live-#{System.unique_integer([:positive])}", content: "<p>live</p>", is_published: true})
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      render_click(view, "edit_page", %{"id" => page.id})

      render_hook(view, "editor-autosave", %{"content" => @blocks})
      assert Repo.get!(Page, page.id).content == "<p>live</p>"
    end

    test "events with no page open do nothing and don't crash" do
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      render_hook(view, "editor-change", %{"content" => @blocks})
      render_hook(view, "editor-autosave", %{"content" => @blocks})
      assert Process.alive?(view.pid)
    end
  end

  describe "alt text" do
    @img ~s({"rows":[{"columns":[{"blocks":[{"type":"image","content":"/a.png"},{"type":"image","content":"/b.png","settings":{"alt":"A ship"}}]}]}]})

    test "the page list flags pictures without alt text, and a clean page isn't flagged" do
      {:ok, _} = Content.create_page(%{title: "Needs alt", slug: "needs-alt-#{System.unique_integer([:positive])}", content: @img})
      {:ok, _} = Content.create_page(%{title: "Has alt", slug: "has-alt-#{System.unique_integer([:positive])}", content: "<p>text only</p>"})

      {:ok, _view, html} = live(signed_in(person("admin")), "/admin/pages")
      assert html =~ "1 image without alt text"
      assert length(Regex.scan(~r/alt-warning/, html)) == 1
    end

    test "the post list flags them too" do
      {:ok, _} = Content.create_post(person("admin"), %{title: "Pic post", content: @img})
      {:ok, _view, html} = live(signed_in(person("admin")), "/admin/blog-management")
      assert html =~ "1 image without alt text"
    end

    test "a published page renders the alt text it was given" do
      {:ok, page} = Content.create_page(%{title: "Shown", slug: "shown-#{System.unique_integer([:positive])}", content: @img, is_published: true})
      {:ok, _view, html} = live(build_conn(), "/pages/#{page.slug}")
      assert html =~ ~s(alt="A ship")
    end
  end
end
