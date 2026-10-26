defmodule Bacon8.Content.Slugs do
  @moduledoc """
  A free URL slug for a page or a post: the title cut down to letters, digits and dashes,
  with `-2`, `-3`... added while another page (or post) already has it. The changesets only
  *check* uniqueness ("has already been taken"); this is for code that must not fail on it
  (new drafts, posts written by plugins).
  """
  import Ecto.Query, only: [from: 2]

  alias Bacon8.Repo
  alias Bacon8.Content.{Page, Post}

  def free(kind, text) when kind in [:page, :post] do
    base = base(text)

    Enum.find_value(1..1000, fn n ->
      slug = if n == 1, do: base, else: "#{base}-#{n}"
      if taken?(kind, slug), do: nil, else: slug
    end)
  end

  def base(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 90)
    |> String.trim("-")
    |> case do
      "" -> "untitled"
      slug -> slug
    end
  end

  defp taken?(:page, slug), do: Repo.exists?(from p in Page, where: p.slug == ^slug)
  defp taken?(:post, slug), do: Repo.exists?(from p in Post, where: p.slug == ^slug)
end
