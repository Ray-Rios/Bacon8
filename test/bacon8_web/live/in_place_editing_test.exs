defmodule Bacon8Web.InPlaceEditingTest do
  # Editing a page or post where it is shown: settings, publishing, schedule, earlier versions,
  # deleting, the featured image and the image library. (Typing and autosave are in
  # page_live_test.exs and blog_live_test.exs.)
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.{Content, Uploads}
  alias Bacon8.Content.{InlineMedia, Page, Post, Revisions}

  @endpoint Bacon8Web.Endpoint

  defp unique, do: System.unique_integer([:positive])

  defp page!(attrs \\ %{}) do
    n = unique()
    {:ok, page} = Content.create_page(Map.merge(%{title: "Page #{n}", slug: "page-#{n}", content: "<p>words #{n}</p>", is_published: true}, Map.new(attrs)))
    on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "pages/#{page.id}")) end)
    page
  end

  defp post!(attrs \\ %{}) do
    n = unique()
    {:ok, post} = Content.create_post(person("admin"), Map.merge(%{title: "Post #{n}", slug: "post-#{n}", content: "<p>words #{n}</p>", is_published: true}, Map.new(attrs)))
    on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "blog/#{post.id}")) end)
    post
  end

  defp editing_page(page, role \\ "editor") do
    {:ok, view, html} = live(signed_in(person(role)), "/pages/#{page.slug}?edit=1")
    {view, html}
  end

  defp editing_post(post, role \\ "editor") do
    {:ok, view, html} = live(signed_in(person(role)), "/blog/#{post.slug}?edit=1")
    {view, html}
  end

  describe "opening" do
    test "?edit=1 opens the editor and the settings for staff" do
      for role <- staff_roles() do
        {_view, html} = editing_page(page!(), role)
        assert html =~ ~s(id="content-settings"), "#{role} did not get the settings"
        assert html =~ ~s(id="settings-form")
      end
    end

    test "members and visitors get the page, not the editor" do
      page = page!()

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, _view, html} = live(conn, "/pages/#{page.slug}?edit=1")
        refute html =~ ~s(id="content-settings")
        refute html =~ "Edit Page"
      end
    end

    test "posts too" do
      {_view, html} = editing_post(post!())
      assert html =~ ~s(id="content-settings")
      assert html =~ "Tags"
    end
  end

  describe "saving the settings of a page" do
    test "title, summary, search description, template and category are saved" do
      page = page!()
      {view, _} = editing_page(page)

      html =
        render_submit(view, "save_settings", %{
          "settings" => %{
            "title" => "New title", "slug" => page.slug, "excerpt" => "Short", "meta_description" => "For search engines",
            "template_type" => "landing", "category" => "News"
          }
        })

      assert html =~ "Settings saved"
      saved = Content.get_page!(page.id)
      assert {saved.title, saved.excerpt, saved.meta_description, saved.template_type, saved.category} == {"New title", "Short", "For search engines", "landing", "News"}
      assert saved.slug == page.slug
    end

    test "changing the address opens the page at the new one, still editing" do
      page = page!()
      {view, _} = editing_page(page)
      new = "moved-#{unique()}"

      assert {:error, {:live_redirect, %{to: to}}} =
               render_submit(view, "save_settings", %{"settings" => %{"title" => page.title, "slug" => new}})

      assert to == "/pages/#{new}?edit=1"
      assert Content.get_page!(page.id).slug == new
    end

    test "two pages can't share an address" do
      other = page!()
      page = page!()
      {view, _} = editing_page(page)

      html = render_submit(view, "save_settings", %{"settings" => %{"title" => page.title, "slug" => other.slug}})

      assert html =~ "Not saved"
      assert Content.get_page!(page.id).slug == page.slug
    end

    test "share buttons: off, colour, and only the platforms ticked" do
      page = page!()
      {view, _} = editing_page(page)

      render_submit(view, "save_settings", %{
        "settings" => %{
          "title" => page.title, "slug" => page.slug, "show_share_buttons" => "false", "share_buttons_colored" => "true",
          "share_platforms" => ["", "twitter", "email"]
        }
      })

      saved = Content.get_page!(page.id)
      assert saved.show_share_buttons == false
      assert saved.share_buttons_colored
      assert saved.share_platforms == ["twitter", "email"]
    end

    test "typed words that were waiting go in with the settings" do
      page = page!()
      {view, _} = editing_page(page)
      render_click(view, "editor-change", %{"content" => "<p>typed first</p>"})

      render_submit(view, "save_settings", %{"settings" => %{"title" => page.title, "slug" => page.slug, "excerpt" => "x"}})

      assert Content.get_page!(page.id).content == "<p>typed first</p>"
    end

    test "a member can't save settings" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("member")), "/pages/#{page.slug}")

      render_submit(view, "save_settings", %{"settings" => %{"title" => "Hijacked", "slug" => page.slug}})

      assert Content.get_page!(page.id).title == page.title
    end
  end

  describe "saving the settings of a post" do
    test "tags typed as a comma list become a list" do
      post = post!()
      {view, _} = editing_post(post)

      render_submit(view, "save_settings", %{"settings" => %{"title" => post.title, "slug" => post.slug, "tags" => "news, patch notes,,  v2 "}})

      assert Content.get_post!(post.id).tags == ["news", "patch notes", "v2"]
    end

    test "a new draft's address follows its first real title" do
      {:ok, draft} = Content.create_draft(:post, person("admin"))
      {view, _} = editing_post(draft)

      assert {:error, {:live_redirect, %{to: "/blog/big-news?edit=1"}}} =
               render_submit(view, "save_settings", %{"settings" => %{"title" => "Big News", "slug" => draft.slug}})
    end
  end

  describe "the schedule" do
    test "a draft saved with a time is scheduled, and a published one has no schedule box" do
      draft = page!(%{is_published: false})
      {view, html} = editing_page(draft)
      assert html =~ ~s(id="scheduled-at")

      html = render_submit(view, "save_settings", %{"settings" => %{"title" => draft.title, "slug" => draft.slug, "scheduled_at" => "2031-10-27T09:30"}})

      assert html =~ "Goes live"
      assert Content.get_page!(draft.id).scheduled_at == ~U[2031-10-27 09:30:00Z]

      {_view, published_html} = editing_page(page!())
      refute published_html =~ ~s(id="scheduled-at")
    end

    test "Publish now publishes at once and clears the time" do
      draft = page!(%{is_published: false})
      {:ok, _} = Content.update_page(draft, %{scheduled_at: ~U[2031-10-27 09:30:00Z]})
      {view, _} = editing_page(draft)

      render_click(view, "set_published", %{"to" => "true"})

      published = Content.get_page!(draft.id)
      assert published.is_published
      assert published.scheduled_at == nil
    end
  end

  describe "publishing" do
    test "publish and unpublish, with typed words saved on the way" do
      draft = post!(%{is_published: false})
      {view, _} = editing_post(draft)
      render_click(view, "editor-change", %{"content" => "<p>final words</p>"})

      assert render_click(view, "set_published", %{"to" => "true"}) =~ "Published"
      live_post = Content.get_post!(draft.id)
      assert live_post.is_published
      assert live_post.content == "<p>final words</p>"

      assert render_click(view, "set_published", %{"to" => "false"}) =~ "draft again"
      refute Content.get_post!(draft.id).is_published
    end

    test "a page without a body can't be published, and says why" do
      draft = page!(%{is_published: false})
      {:ok, bare} = Content.update_page(draft, %{content: ""})
      {view, _} = editing_page(bare)

      assert render_click(view, "set_published", %{"to" => "true"}) =~ "Can't publish"
      refute Content.get_page!(draft.id).is_published
    end
  end

  describe "earlier versions" do
    setup do
      page = page!()
      {:ok, edited} = Content.update_page(page, %{content: "<p>second words</p>"})
      %{page: edited}
    end

    test "are listed, and one can be put back", %{page: page} do
      {view, html} = editing_page(page)
      assert html =~ "Earlier versions"

      [rev] = Revisions.list(:page, page.id)
      assert {:error, {:live_redirect, %{to: to}}} = view |> element("#revision-#{rev.id} button") |> render_click()

      assert to == "/pages/#{page.slug}?edit=1"
      assert Content.get_page!(page.id).content =~ "words"
      refute Content.get_page!(page.id).content == "<p>second words</p>"
    end

    test "a version that isn't this page's is refused", %{page: page} do
      {view, _} = editing_page(page)
      html = render_click(view, "restore_revision", %{"id" => Ecto.UUID.generate()})

      assert html =~ "no longer there"
      assert Content.get_page!(page.id).content == "<p>second words</p>"
    end
  end

  describe "cancelling and deleting" do
    test "cancelling a just-started draft that nothing was written in removes it" do
      {:ok, draft} = Content.create_draft(:page, person("admin"))
      {view, _} = editing_page(draft)

      assert {:error, {:live_redirect, %{to: "/admin/pages"}}} = render_click(view, "cancel_edit")
      refute Repo.get(Page, draft.id)
    end

    test "cancelling a draft that has words in it keeps it" do
      {:ok, draft} = Content.create_draft(:post, person("admin"))
      {:ok, written} = Content.update_post(draft, %{content: "<p>keep me</p>"})
      {view, _} = editing_post(written)

      assert render_click(view, "cancel_edit") =~ "discarded"
      assert Repo.get(Post, draft.id)
    end

    test "deleting removes the page and its pictures, and returns to the list" do
      page = page!()
      folder = Path.join(Uploads.public_dir(), "pages/#{page.id}")
      File.mkdir_p!(folder)
      File.write!(Path.join(folder, "pic.txt"), "x")
      {view, _} = editing_page(page)

      assert {:error, {:live_redirect, %{to: "/admin/pages"}}} = render_click(view, "delete_record")

      refute Repo.get(Page, page.id)
      refute File.exists?(folder)
      assert Revisions.list(:page, page.id) == []
    end

    test "deleting a post goes back to the post list" do
      post = post!()
      {view, _} = editing_post(post)
      assert {:error, {:live_redirect, %{to: "/admin/blog-management"}}} = render_click(view, "delete_record")
      refute Repo.get(Post, post.id)
    end

    test "a member can't delete" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("member")), "/pages/#{page.slug}")
      render_click(view, "delete_record")
      assert Repo.get(Page, page.id)
    end
  end

  describe "the image library in the editor" do
    defp shared_picture(tag) do
      ctx = "pages/#{Ecto.UUID.generate()}"
      on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), ctx)) end)
      {:ok, %{url: url}} = InlineMedia.store(ctx, %{"data" => Base.encode64("pixels #{tag}"), "filename" => "#{tag}.png", "mimeType" => "image/png"})
      url
    end

    test "library-list answers with the pictures, matching a search" do
      tag = "findme#{unique()}"
      url = shared_picture(tag)
      {view, _} = editing_page(page!())

      render_hook(view, "library-list", %{"query" => tag, "offset" => 0})

      assert_reply(view, %{images: [%{url: ^url, filename: filename}], more: false})
      assert filename == "#{tag}.png"
    end

    test "library-use copies the picture into this page and tells the editor like an upload" do
      tag = "use#{unique()}"
      source = shared_picture(tag)
      page = page!()
      {view, _} = editing_page(page)

      render_hook(view, "library-use", %{"blockId" => "b1", "url" => source, "mediaType" => "image"})

      assert_push_event(view, "block-media-uploaded", %{blockId: "b1", url: url, mediaType: "image"})
      assert String.starts_with?(url, "/uploads/public/pages/#{page.id}/")
      assert File.read!(Uploads.url_to_path(url)) == "pixels #{tag}"
    end

    test "a picture that isn't in the library is refused, and the editor is told" do
      {view, _} = editing_page(page!())

      render_hook(view, "library-use", %{"blockId" => "b1", "url" => "/uploads/public/pages/x/nothing.png", "mediaType" => "image"})

      assert_push_event(view, "block-media-error", %{blockId: "b1", error: "That picture is no longer in the library"})
    end

    test "members get an empty library and can't use it" do
      source = shared_picture("private#{unique()}")
      page = page!()
      {:ok, view, _} = live(signed_in(person("member")), "/pages/#{page.slug}")

      render_hook(view, "library-list", %{"query" => "", "offset" => 0})
      assert_reply(view, %{images: [], more: false})

      render_hook(view, "library-use", %{"blockId" => "b1", "url" => source})
      refute File.exists?(Path.join(Uploads.public_dir(), "pages/#{page.id}"))
    end
  end

  describe "the featured image" do
    test "choose one from the library: it is copied to the post and set" do
      tag = "hero#{unique()}"
      ctx = "pages/#{Ecto.UUID.generate()}"
      on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), ctx)) end)
      {:ok, %{url: source}} = InlineMedia.store(ctx, %{"data" => Base.encode64("hero #{tag}"), "filename" => "#{tag}.png", "mimeType" => "image/png"})
      post = post!()
      {view, _} = editing_post(post)

      html = render_click(view, "open_featured_library")
      assert html =~ ~s(id="featured-library")
      assert html =~ "#{tag}.png"

      html = render_click(view, "pick_featured", %{"url" => source})

      saved = Content.get_post!(post.id)
      assert String.starts_with?(saved.featured_image, "/uploads/public/blog/#{post.id}/")
      refute html =~ ~s(id="featured-library")

      render_click(view, "remove_featured")
      assert Content.get_post!(post.id).featured_image == nil
    end

    test "the picker can be closed, and shows a message when the library is empty" do
      {view, _} = editing_page(page!())
      render_click(view, "open_featured_library")
      refute render_click(view, "close_featured_library") =~ ~s(id="featured-library")
    end

    test "a picture that isn't in the library can't be set" do
      post = post!()
      {view, _} = editing_post(post)
      html = render_click(view, "pick_featured", %{"url" => "/uploads/public/blog/x/y.png"})

      assert html =~ "no longer in the library"
      assert Content.get_post!(post.id).featured_image == nil
    end
  end
end
