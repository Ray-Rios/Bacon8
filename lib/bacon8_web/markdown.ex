defmodule Bacon8Web.Markdown do
  @moduledoc """
  Simple Markdown rendering for blog posts.
  """

  @doc """
  Renders Markdown text to HTML.
  """
  def render(nil), do: ""
  def render(""), do: ""
  
  def render(markdown) when is_binary(markdown) do
    markdown
    |> String.trim()
    |> convert_headers()
    |> convert_bold()
    |> convert_italic()
    |> convert_code()
    |> convert_images()
    |> convert_links()
    |> convert_lists()
    |> convert_newlines()
    |> Phoenix.HTML.raw()
  end

  defp convert_headers(text) do
    text
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
  end

  defp convert_bold(text) do
    String.replace(text, ~r/\*\*(.+?)\*\*/s, "<strong>\\1</strong>")
  end

  defp convert_italic(text) do
    String.replace(text, ~r/\*(.+?)\*/s, "<em>\\1</em>")
  end

  defp convert_code(text) do
    text
    |> String.replace(~r/```(.+?)```/s, "<pre><code>\\1</code></pre>")
    |> String.replace(~r/`(.+?)`/s, "<code>\\1</code>")
  end

  defp convert_images(text) do
    String.replace(text, ~r/!\[([^\]]*)\]\(([^)]+)\)/, "<img src=\"\\2\" alt=\"\\1\" class=\"max-w-full h-auto rounded-lg my-4\" />")
  end

  defp convert_links(text) do
    String.replace(text, ~r/\[(.+?)\]\((.+?)\)/, "<a href=\"\\2\" class=\"text-blue-400 underline\">\\1</a>")
  end

  defp convert_lists(text) do
    text
    |> String.replace(~r/^- (.+)$/m, "<li>\\1</li>")
    |> String.replace(~r/(<li>.*<\/li>)/s, "<ul>\\1</ul>")
  end

  defp convert_newlines(text) do
    String.replace(text, ~r/\n\n/, "<br><br>")
  end
end