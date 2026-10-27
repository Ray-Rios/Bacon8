defmodule Bacon8Web.ContentEditingTest do
  # The pieces every editing screen is built from: a new page or post is a draft from the first
  # click, so uploads and autosave always have a record to belong to. (The editor itself is tested
  # in in_place_editing_test.exs.)
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Content.Page
  alias Bacon8Web.ContentEditing

  @endpoint Bacon8Web.Endpoint

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
