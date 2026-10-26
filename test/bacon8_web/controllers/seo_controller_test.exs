defmodule Bacon8Web.SeoControllerTest do
  # /blog/feed.xml and /sitemap.xml: built from what is published, nothing else.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias Bacon8.Content

  @endpoint Bacon8Web.Endpoint

  setup do
    %{author: user_fixture(%{role: "admin", is_admin: true, name: "Ada <Admin>", email: "ada-secret@example.com"})}
  end

  defp post!(author, attrs) do
    {:ok, post} = Content.create_post(author, Map.merge(%{title: "Post #{System.unique_integer([:positive])}", content: "<p>body</p>"}, attrs))
    post
  end

  describe "the blog feed" do
    test "lists published posts only, newest first, as RSS", %{author: author} do
      older = post!(author, %{title: "Older one", is_published: true, published_at: ~U[2026-01-01 10:00:00Z]})
      newer = post!(author, %{title: "Newer one", is_published: true, published_at: ~U[2026-02-01 10:00:00Z]})
      draft = post!(author, %{title: "Secret draft"})

      conn = get(build_conn(), "/blog/feed.xml")
      body = response(conn, 200)

      assert [type] = get_resp_header(conn, "content-type")
      assert type =~ "application/rss+xml"
      assert body =~ ~s(<rss version="2.0")
      assert body =~ "/blog/#{older.slug}"
      assert body =~ "/blog/#{newer.slug}"
      refute body =~ draft.slug
      refute body =~ "Secret draft"
      assert :binary.match(body, "Newer one") < :binary.match(body, "Older one")
    end

    test "escapes titles, shares the author's name and never their email", %{author: author} do
      post!(author, %{title: "Fish & <Chips>", is_published: true, published_at: ~U[2026-03-01 10:00:00Z]})
      body = get(build_conn(), "/blog/feed.xml") |> response(200)

      assert body =~ "Fish &amp; &lt;Chips&gt;"
      assert body =~ "Ada &lt;Admin&gt;"
      refute body =~ "ada-secret"
    end

    test "carries the post's body, and a ]]> in it can't break out", %{author: author} do
      post!(author, %{title: "Tricky", content: "<p>a ]]> b</p>", is_published: true, published_at: ~U[2026-03-02 10:00:00Z]})
      body = get(build_conn(), "/blog/feed.xml") |> response(200)

      assert body =~ "<content:encoded><![CDATA["
      assert body =~ "a ]]]]><![CDATA[> b"
    end

    test "is valid and empty with no posts, and needs no sign-in" do
      body = get(build_conn(), "/blog/feed.xml") |> response(200)
      assert body =~ "<channel>"
      refute body =~ "<item>"
    end

    test "is advertised in the head of the site's pages" do
      html = get(build_conn(), "/blog") |> html_response(200)
      assert html =~ ~s(rel="alternate" type="application/rss+xml")
      assert html =~ "/blog/feed.xml"
    end
  end

  describe "the sitemap" do
    test "lists the public pages, published pages and published posts - and not drafts", %{author: author} do
      {:ok, _} = Content.create_page(%{title: "Live", slug: "live-page", content: "x", is_published: true})
      {:ok, _} = Content.create_page(%{title: "Hidden", slug: "hidden-page", content: "x"})
      post!(author, %{title: "Live post", slug: "live-post", is_published: true, published_at: ~U[2026-03-01 10:00:00Z]})
      post!(author, %{title: "Hidden post", slug: "hidden-post"})

      conn = get(build_conn(), "/sitemap.xml")
      body = response(conn, 200)

      assert hd(get_resp_header(conn, "content-type")) =~ "application/xml"
      assert body =~ "<urlset"
      assert body =~ "/pages/live-page"
      assert body =~ "/blog/live-post"
      refute body =~ "hidden-page"
      refute body =~ "hidden-post"
      for path <- ["/store", "/games", "/blog", "/register"], do: assert(body =~ "#{path}</loc>")
      refute body =~ "/forum"
      assert body =~ ~r/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/
    end
  end
end
