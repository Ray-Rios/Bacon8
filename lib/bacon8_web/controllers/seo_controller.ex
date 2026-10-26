defmodule Bacon8Web.SeoController do
  @moduledoc """
  The two machine-readable views of the site's content: the blog's RSS feed (`/blog/feed.xml`)
  and the sitemap (`/sitemap.xml`), both built from what is published right now, so a post or
  page appears when it is published and is gone when it is unpublished or deleted.
  """
  use Bacon8Web, :controller

  import Ecto.Query, only: [from: 2]

  alias Bacon8.Repo
  alias Bacon8.Content.{Page, Post}
  alias Bacon8Web.Seo
  alias Bacon8Web.Components.BlockEditor

  @feed_limit 20

  # Pages every visitor can open. Chat and the admin are for signed-in people and stay out.
  @static_paths ["/", "/store", "/games", "/blog", "/register"]

  def feed(conn, _params) do
    posts =
      Repo.all(
        from p in Post,
          where: p.is_published == true,
          order_by: [desc: coalesce(p.published_at, p.inserted_at)],
          limit: ^@feed_limit,
          preload: [:user]
      )

    conn
    |> put_resp_content_type("application/rss+xml")
    |> put_resp_header("cache-control", "public, max-age=600")
    |> send_resp(200, feed_xml(posts))
  end

  def sitemap(conn, _params) do
    pages = Repo.all(from p in Page, where: p.is_published == true, order_by: p.slug, select: {p.slug, p.updated_at})
    posts = Repo.all(from p in Post, where: p.is_published == true, order_by: p.slug, select: {p.slug, p.updated_at})

    entries =
      Enum.map(@static_paths, &{&1, nil}) ++
        Enum.map(pages, fn {slug, at} -> {"/pages/#{slug}", at} end) ++
        Enum.map(posts, fn {slug, at} -> {"/blog/#{slug}", at} end)

    urls =
      Enum.map_join(entries, "", fn {path, at} ->
        lastmod = if at, do: "<lastmod>#{Date.to_iso8601(DateTime.to_date(at))}</lastmod>", else: ""
        "<url><loc>#{xml(Seo.absolute(path))}</loc>#{lastmod}</url>\n"
      end)

    xml = ~s(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n#{urls}</urlset>\n)

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, xml)
  end

  defp feed_xml(posts) do
    site = Seo.absolute("/blog")
    built = posts |> Enum.map(&date/1) |> Enum.max(DateTime, fn -> DateTime.utc_now() end)

    items = Enum.map_join(posts, "", &item/1)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
    <title>Bacon8 blog</title>
    <link>#{xml(site)}</link>
    <description>News and posts from Bacon8</description>
    <language>en</language>
    <lastBuildDate>#{rfc822(built)}</lastBuildDate>
    <atom:link href="#{xml(Seo.absolute("/blog/feed.xml"))}" rel="self" type="application/rss+xml" />
    #{items}</channel>
    </rss>
    """
  end

  defp item(post) do
    link = Seo.absolute("/blog/#{post.slug}")
    body = post.content |> BlockEditor.render_blocks() |> Phoenix.HTML.safe_to_string()

    """
    <item>
    <title>#{xml(post.title)}</title>
    <link>#{xml(link)}</link>
    <guid isPermaLink="true">#{xml(link)}</guid>
    <pubDate>#{rfc822(date(post))}</pubDate>
    <dc:creator>#{xml(author(post))}</dc:creator>
    <description>#{xml(Seo.description(post))}</description>
    <content:encoded>#{cdata(body)}</content:encoded>
    </item>
    """
  end

  # (an email address is not shared in a public feed: the display name only)
  defp author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp author(_), do: "Bacon8"

  defp date(%{published_at: %DateTime{} = at}), do: at
  defp date(%{inserted_at: at}), do: at

  defp rfc822(at), do: Calendar.strftime(at, "%a, %d %b %Y %H:%M:%S +0000")

  defp xml(text), do: text |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # "]]>" would end the section early; split it across two.
  defp cdata(text), do: "<![CDATA[" <> String.replace(text, "]]>", "]]]]><![CDATA[>") <> "]]>"

end
