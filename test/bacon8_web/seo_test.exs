defmodule Bacon8Web.SeoTest do
  # What a page or post tells search engines and link previews.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest

  alias Bacon8.Content
  alias Bacon8Web.Seo

  @endpoint Bacon8Web.Endpoint

  defp blocks(list), do: Jason.encode!(%{"rows" => [%{"columns" => [%{"blocks" => list}]}]})
  defp text(html), do: %{"type" => "text", "content" => html}

  describe "description/1" do
    test "prefers the meta description, then the excerpt, then the body" do
      body = blocks([text("<p>The body says this.</p>")])
      assert Seo.description(%{meta_description: "Meta", excerpt: "Excerpt", content: body}) == "Meta"
      assert Seo.description(%{meta_description: " ", excerpt: "Excerpt", content: body}) == "Excerpt"
      assert Seo.description(%{meta_description: nil, excerpt: nil, content: body}) == "The body says this."
    end

    test "is cut at a word, at most 160 characters" do
      long = String.duplicate("word ", 80)
      d = Seo.description(%{meta_description: nil, excerpt: nil, content: "<p>#{long}</p>"})
      assert String.length(d) <= 160
      assert String.ends_with?(d, "…")
      refute d =~ ~r/wor…$/
    end

    test "has no markup, scripts or entities in it" do
      d = Seo.description(%{meta_description: nil, excerpt: nil, content: "<h1>Hi</h1><script>alert(1)</script><p>a&nbsp;&amp;&nbsp;b</p>"})
      assert d == "Hi a & b"
    end

    test "is empty for an empty body" do
      assert Seo.description(%{meta_description: nil, excerpt: nil, content: nil}) == ""
      assert Seo.description(%{meta_description: nil, excerpt: nil, content: ""}) == ""
    end
  end

  describe "image/1" do
    test "is the featured image, else the first picture, as an absolute address" do
      body = blocks([text("<p>x</p>"), %{"type" => "image", "content" => "/uploads/public/pages/1/a.png"}])
      assert Seo.image(%{featured_image: "/uploads/f.png", content: body}) =~ ~r{^https?://.+/uploads/f\.png$}
      assert Seo.image(%{featured_image: nil, content: body}) =~ "/uploads/public/pages/1/a.png"
      assert Seo.image(%{featured_image: nil, content: "<p>none</p>"}) == nil
      assert Seo.image(%{featured_image: nil, content: ~s(<img src="/x.png" alt="">)}) =~ "/x.png"
    end
  end

  describe "in the page head" do
    test "a published page has its own description, canonical address and preview" do
      {:ok, page} =
        Content.create_page(%{title: "About us", slug: "about-seo", content: blocks([text("<p>We make things.</p>")]), meta_description: "Who we are", is_published: true})

      html = get(build_conn(), "/pages/#{page.slug}") |> html_response(200)

      assert html =~ ~s(<meta name="description" content="Who we are")
      assert html =~ ~s(rel="canonical" href="#{Seo.absolute("/pages/about-seo")}")
      assert html =~ ~s(property="og:url" content="#{Seo.absolute("/pages/about-seo")}")
      assert html =~ ~s(property="og:description" content="Who we are")
      assert html =~ ~s(name="twitter:description" content="Who we are")
      refute html =~ ~s(name="robots" content="noindex)
    end

    test "a published post is an article with its date, and falls back to its words for a description" do
      {:ok, post} =
        Content.create_post(user_fixture(%{is_admin: true}), %{
          title: "News", slug: "news-seo", content: blocks([text("<p>Big news today.</p>")]), is_published: true, published_at: ~U[2026-03-01 10:00:00Z]
        })

      html = get(build_conn(), "/blog/#{post.slug}") |> html_response(200)

      assert html =~ ~s(property="og:type" content="article")
      assert html =~ ~s(property="article:published_time" content="2026-03-01T10:00:00Z")
      assert html =~ ~s(<meta name="description" content="Big news today.")
    end

    test "other pages keep the site's description and are indexable" do
      html = get(build_conn(), "/blog") |> html_response(200)
      assert html =~ ~s(<meta name="description" content="The kitchen sink.")
      refute html =~ ~s(rel="canonical")
      refute html =~ "noindex"
    end
  end

  test "a draft is marked noindex for the staff who can open it" do
    {:ok, page} = Content.create_page(%{title: "Draft", slug: "draft-seo", content: "x"})
    admin = user_fixture(%{role: "admin", is_admin: true, email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    conn = build_conn() |> Plug.Test.init_test_session(%{"user_id" => admin.id})

    html = get(conn, "/pages/#{page.slug}") |> html_response(200)
    assert html =~ ~s(name="robots" content="noindex, nofollow")
  end
end
