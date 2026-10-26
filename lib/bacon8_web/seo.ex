defmodule Bacon8Web.Seo do
  @moduledoc """
  What search engines and link previews read about a page or post: its description, its one
  canonical address, its preview picture and whether to index it at all.

  `for_page/1` and `for_post/1` return assigns for the LiveView to set; the root layout
  (`layouts/root.html.heex`) turns them into `<meta>`, `<link rel="canonical">`, Open Graph and
  Twitter tags. A draft is marked `noindex` (staff can open one; search engines must not keep it).

  The description is, in order: the meta description the editor wrote, the excerpt, then the first
  words of the body (`plain_text/1`), cut at a word to 160 characters.
  """
  alias Bacon8Web.Endpoint

  @max_description 160

  def for_page(page) do
    common(page, "/pages/#{page.slug}", "website")
  end

  def for_post(post) do
    common(post, "/blog/#{post.slug}", "article")
    |> Keyword.put(:published_time, post.published_at && DateTime.to_iso8601(post.published_at))
  end

  defp common(record, path, og_type) do
    [
      meta_description: description(record),
      canonical_url: absolute(path),
      og_type: og_type,
      og_image: image(record),
      noindex: not record.is_published
    ]
  end

  @doc "An absolute address on this site for `path`."
  def absolute("/" <> _ = path), do: Endpoint.url() <> path
  def absolute(url) when is_binary(url), do: url

  @doc "The record's description for search results and link previews (at most 160 characters)."
  def description(record) do
    first = Enum.find([record.meta_description, record.excerpt], &present?/1)
    text = if first, do: first, else: plain_text(record.content)
    cut(text, @max_description)
  end

  @doc "The record's preview picture as an absolute address: featured image, else the first picture in the body, else nil (the site's default is used)."
  def image(record) do
    url = Enum.find([Map.get(record, :featured_image), first_image(record.content)], &present?/1)
    url && absolute(url)
  end

  @doc "The words of a body (block JSON or HTML) with the markup removed and spaces squeezed."
  def plain_text(nil), do: ""

  def plain_text(content) when is_binary(content) do
    html =
      case Jason.decode(content) do
        {:ok, %{"rows" => rows}} when is_list(rows) ->
          rows |> blocks() |> Enum.map_join(" ", &block_html/1)

        _ ->
          content
      end

    html |> String.replace(~r/<(script|style)\b.*?<\/\1>/is, " ") |> String.replace(~r/<[^>]*>/, " ") |> decode_entities() |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  def plain_text(_), do: ""

  defp blocks(rows) do
    for %{"columns" => cols} <- rows, is_list(cols), %{"blocks" => bs} <- cols, is_list(bs), b <- bs, is_map(b), do: b
  end

  defp block_html(%{"type" => type, "content" => content}) when type in ["text", "heading", "quote", "callout"] and is_binary(content), do: content
  defp block_html(_), do: ""

  defp first_image(nil), do: nil

  defp first_image(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"rows" => rows}} when is_list(rows) ->
        Enum.find_value(blocks(rows), fn
          %{"type" => "image", "content" => url} when is_binary(url) and url != "" -> url
          _ -> nil
        end)

      _ ->
        case Regex.run(~r/<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']/i, content) do
          [_, url] -> url
          _ -> nil
        end
    end
  end

  defp first_image(_), do: nil

  defp cut(text, max) do
    if String.length(text) <= max do
      text
    else
      cut = String.slice(text, 0, max - 1)
      # back to the last whole word, if there is one in the second half
      case Regex.run(~r/^(.{#{div(max, 2)},}?)\s+\S*$/su, cut) do
        [_, words] -> words <> "…"
        _ -> cut <> "…"
      end
    end
  end

  defp decode_entities(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
