defmodule Bacon8.Content.Audit do
  @moduledoc """
  Checks on what a page or post says, for the editors to act on.

  `images_missing_alt/1` counts the pictures a screen reader would announce as just "image": an
  image block (or gallery picture) with no alt text that isn't marked *decorative*. Old content
  written as plain HTML is checked too, by its `<img>` tags.
  """

  @doc "How many pictures in `content` (block JSON, HTML or nil) have no alt text and aren't decorative."
  def images_missing_alt(nil), do: 0
  def images_missing_alt(""), do: 0

  def images_missing_alt(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"rows" => rows}} when is_list(rows) -> rows |> blocks() |> Enum.map(&missing/1) |> Enum.sum()
      {:ok, _} -> 0
      {:error, _} -> html_images_missing_alt(content)
    end
  end

  def images_missing_alt(_), do: 0

  defp blocks(rows) do
    for %{"columns" => cols} <- rows, is_list(cols), %{"blocks" => blocks} <- cols, is_list(blocks), block <- blocks, is_map(block), do: block
  end

  defp missing(%{"type" => "image", "content" => url} = block) when is_binary(url) and url != "" do
    settings = block["settings"] || %{}
    if decorative?(settings) or present?(settings["alt"]), do: 0, else: 1
  end

  defp missing(%{"type" => "gallery", "media" => items}) when is_list(items) do
    Enum.count(items, fn item -> is_map(item) and not present?(item["alt"]) and not decorative?(item) end)
  end

  defp missing(_), do: 0

  defp decorative?(%{"decorative" => true}), do: true
  defp decorative?(_), do: false

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp html_images_missing_alt(html) do
    ~r/<img\b[^>]*>/i
    |> Regex.scan(html)
    |> Enum.count(fn [tag] ->
      case Regex.run(~r/\balt\s*=\s*("([^"]*)"|'([^']*)')/i, tag) do
        nil -> true
        [_, _, value] -> String.trim(value) == ""
        [_, _, "", value] -> String.trim(value) == ""
        _ -> false
      end
    end)
  end
end
