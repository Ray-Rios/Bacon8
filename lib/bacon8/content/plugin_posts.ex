defmodule Bacon8.Content.PluginPosts do
  @moduledoc """
  Blog posts written by a plugin or a game (patch notes, event announcements).

      Bacon8.Content.post_from_plugin("rays_space_sim", %{
        title: "Patch 0.4",
        body: [{:heading, "Fixes"}, {:list, ["Warp drive no longer stalls"]}, {:paragraph, "Thanks for playing."}]
      }, publish: true)

  The body is a list of `{:heading, text}`, `{:paragraph, text}` and `{:list, [text]}`. Text is
  always HTML-escaped, so a plugin can put player names or other untrusted strings in a post
  without being able to inject markup (page and post HTML is otherwise rendered as written).

  Posts are **drafts** unless `publish: true`. The author is `author:` (a user) or, without one,
  the oldest admin account; `{:error, :no_author}` when the site has neither. The post is tagged
  with the plugin's slug so staff can tell where it came from, and a title that is taken gets
  a numbered slug. The post is built as ordinary editor blocks, so staff can edit it afterwards
  in the block editor like any other.
  """
  import Ecto.Query, only: [from: 2]

  alias Bacon8.{Content, Repo}
  alias Bacon8.Accounts.User
  alias Bacon8.Content.Post

  def create(plugin_slug, attrs, opts \\ []) when is_binary(plugin_slug) and is_map(attrs) do
    title = attrs |> field(:title) |> to_string() |> String.trim()

    with :ok <- check_title(title),
         {:ok, body} <- blocks(field(attrs, :body)),
         {:ok, author} <- author(opts[:author]) do
      Content.create_post(author, %{
        title: title,
        slug: free_slug(field(attrs, :slug) || title),
        content: body,
        excerpt: field(attrs, :excerpt),
        tags: Enum.uniq([plugin_slug | List.wrap(field(attrs, :tags))]),
        is_published: opts[:publish] == true
      })
    end
  end

  defp field(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp check_title(""), do: {:error, :title_required}
  defp check_title(_), do: :ok

  defp author(%User{} = user), do: {:ok, user}

  defp author(nil) do
    case Repo.one(from u in User, where: u.is_admin == true, order_by: [asc: u.inserted_at], limit: 1) do
      nil -> {:error, :no_author}
      user -> {:ok, user}
    end
  end

  defp blocks(body) when is_list(body) and body != [] do
    html = body |> Enum.map(&html/1) |> Enum.reject(&is_nil/1)

    if html == [] do
      {:error, :empty_body}
    else
      content = %{
        "version" => 1,
        "rows" => [
          %{
            "id" => id("r"),
            "columns" => [
              %{
                "id" => id("c"),
                "width" => "100%",
                "blocks" => for(h <- html, do: %{"id" => id("b"), "type" => "text", "content" => h})
              }
            ]
          }
        ]
      }

      {:ok, Jason.encode!(content)}
    end
  end

  defp blocks(_), do: {:error, :empty_body}

  defp html({:heading, text}), do: "<h2>#{esc(text)}</h2>"
  defp html({:paragraph, text}), do: "<p>#{esc(text)}</p>"

  defp html({:list, items}) when is_list(items) and items != [],
    do: "<ul>" <> Enum.map_join(items, "", &"<li>#{esc(&1)}</li>") <> "</ul>"

  defp html(_), do: nil

  defp esc(text), do: text |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp id(prefix), do: prefix <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

  # The slug the title would get, with -2, -3... added while another post has it.
  defp free_slug(text) do
    base =
      text
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 90)
      |> String.trim("-")
      |> case do
        "" -> "post"
        s -> s
      end

    Enum.find_value(1..1000, fn n ->
      slug = if n == 1, do: base, else: "#{base}-#{n}"
      if Repo.exists?(from p in Post, where: p.slug == ^slug), do: nil, else: slug
    end)
  end
end
