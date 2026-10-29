defmodule Bacon8Web.PageBuilderTest do
  # The page builder (2026-10-28): the full-screen editing screen, New page / New post from the
  # start menu, and what the public page makes of the new things a page can hold (row looks,
  # buttons, picture sizes). Pages saved before then must render exactly as they did.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Uploads
  alias Bacon8Web.Components.BlockEditor

  @endpoint Bacon8Web.Endpoint

  defp page!(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    {:ok, page} =
      Content.create_page(Map.merge(%{title: "Page #{n}", slug: "pb-#{n}", content: "<p>Words #{n}</p>", is_published: true}, Map.new(attrs)))

    on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "pages/#{page.id}")) end)
    page
  end

  defp doc(rows), do: Jason.encode!(%{"rows" => rows, "version" => 1})
  defp row(blocks, settings \\ nil), do: %{"id" => "r", "columns" => [%{"id" => "c", "width" => "full", "blocks" => blocks}]} |> then(&if(settings, do: Map.put(&1, "settings", settings), else: &1))
  defp html(content), do: content |> BlockEditor.render_blocks() |> Phoenix.HTML.safe_to_string()

  describe "the editing screen" do
    test "staff get the full-screen editor: top bar, title in place, the builder, settings in a drawer" do
      page = page!(%{is_published: false})
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}?edit=1")
      html = render(view)

      assert html =~ ~s(id="pb-shell")
      assert html =~ ~s(id="pb-title")
      assert html =~ ~s(phx-hook="BlockEditor")
      assert html =~ ~s(data-kind="page")
      assert html =~ ~s(id="pb-publish")
      assert html =~ ~s(id="pb-settings")
      assert html =~ ~s(id="settings-form")
      # the reading view is not drawn underneath
      refute html =~ "Edit Page"
    end

    test "a published page offers Save, not Publish, and says when typing isn't saved yet" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}?edit=1")
      refute render(view) =~ ~s(id="pb-publish")
      render_click(view, "editor-change", %{"content" => "<p>Changed</p>"})
      assert render(view) =~ "Not saved yet"
    end

    test "a new draft's title box is empty, not \"Untitled\"" do
      page = page!(%{is_published: false, title: "Untitled"})
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}?edit=1")
      assert render(view) =~ ~r{<textarea[^>]*id="pb-title"[^>]*>\s*</textarea>}
    end

    test "posts get the same screen" do
      admin = person("admin")
      {:ok, post} = Content.create_draft(:post, admin)
      {:ok, view, _} = live(signed_in(admin), "/blog/#{post.slug}?edit=1")
      html = render(view)
      assert html =~ ~s(id="pb-shell")
      assert html =~ ~s(data-kind="post")
    end
  end

  describe "New page and New post in the start menu" do
    test "staff start a draft in one tap and land in its editor" do
      editor = person("editor")
      {:ok, view, _} = live(signed_in(editor), "/blog")
      view |> element("[aria-label='Start']") |> render_click()
      assert has_element?(view, "#start-new")

      assert {:error, {:live_redirect, %{to: to}}} = view |> element("#start-new button[phx-value-kind='page']") |> render_click()
      assert to =~ ~r{^/pages/untitled(-\d+)?\?edit=1$}
      slug = to |> String.trim_leading("/pages/") |> String.replace("?edit=1", "")
      assert %{is_published: false} = Content.get_page_by_slug(slug)
    end

    test "members don't get the buttons" do
      {:ok, view, _} = live(signed_in(person("member")), "/blog")
      view |> element("[aria-label='Start']") |> render_click()
      refute has_element?(view, "#start-new")
    end
  end

  describe "the public page" do
    test "a row saved before the builder renders exactly as before (no wrapper)" do
      out = html(doc([row([%{"id" => "b", "type" => "text", "content" => "<p>Old</p>"}])]))
      assert out == ~s(<div class="content-column"><p>Old</p></div>)
    end

    test "a row's look becomes known classes only" do
      out = html(doc([row([%{"id" => "b", "type" => "text", "content" => "<p>Hi</p>"}], %{"width" => "wide", "space" => "l", "background" => "glass", "align" => "center"})]))
      assert out =~ ~s(<section class="content-section al-center bg-glass sp-l w-wide cols-1">)

      sneaky = html(doc([row([], %{"width" => "wide\" onmouseover=\"x", "background" => "<b>"})]))
      refute sneaky =~ "onmouseover"
      refute sneaky =~ "<b>"
    end

    test "a button links only to safe places" do
      button = fn url -> html(doc([row([%{"id" => "b", "type" => "button", "content" => "Go <now>", "settings" => %{"url" => url, "style" => "ghost", "align" => "left"}}])])) end

      assert button.("https://bacon8.net/store") =~ ~s(<a class="content-button content-button-ghost" href="https://bacon8.net/store">Go &lt;now&gt;</a>)
      assert button.("https://bacon8.net/store") =~ ~s(content-button-wrap align-left)
      assert button.("/games") =~ ~s(href="/games")
      assert button.("mailto:hi@example.com") =~ ~s(href="mailto:hi@example.com")
      for bad <- ["javascript:alert(1)", "//evil.example", "data:text/html,x", " JavaScript:alert(1)"] do
        assert button.(bad) =~ ~s(href="#"), bad
      end
    end

    test "picture sizes, decorative pictures and heading levels" do
      img = fn s -> html(doc([row([%{"id" => "b", "type" => "image", "content" => "/uploads/public/pages/x/a.png", "settings" => s}])])) end
      assert img.(%{"size" => "medium", "alt" => "A cat"}) =~ ~s(<figure class="img-medium"><img src="/uploads/public/pages/x/a.png" alt="A cat")
      assert img.(%{"size" => "full", "alt" => "A cat"}) =~ ~s(<figure><img)
      assert img.(%{"size" => "huge\" x=\"", "alt" => "A cat"}) =~ ~s(<figure><img)
      assert img.(%{"alt" => "Ignored", "decorative" => true}) =~ ~s(alt="")

      h = fn level -> html(doc([row([%{"id" => "b", "type" => "heading", "content" => "T", "settings" => %{"level" => level}}])])) end
      assert h.(1) =~ "<h1>T</h1>"
      assert h.("3") =~ "<h3>T</h3>"
      assert h.("2><script>") =~ "<h2>T</h2>"
      assert h.(9) =~ "<h2>T</h2>"
    end
  end
end
