defmodule Bacon8.Content.Moderation do
  @moduledoc """
  The rules for who may comment and which comments wait for a person to approve them.

  Only signed-in members with a verified email may comment (no anonymous comments, which is most
  of what spam is). Then, in order:

    1. A staff member (admin, GM, editor) is approved at once.
    2. More than `@max_links` links holds the comment for approval, whoever wrote it. Spam is mostly links.
    3. Someone who already has an approved comment is approved at once (they are known).
    4. Everyone else's first comment waits for a moderator.

  Independently of those, `Content.submit_comment/3` refuses more than `@rate_limit` comments from
  one person in an hour and the same text twice in a row.

  `decide/3` is pure (it is given what it needs to know), so the rules can be tested without a database.
  """

  @max_links 2
  @rate_limit 5
  @staff_roles ~w(admin gm editor)

  def max_links, do: @max_links
  def rate_limit, do: @rate_limit

  @doc """
  `:approved` or `:pending` for a comment with this text from `user`. `approved_before` is how many
  of that user's comments a moderator has already approved.
  """
  def decide(user, text, approved_before) do
    cond do
      staff?(user) -> :approved
      link_count(text) > @max_links -> :pending
      approved_before > 0 -> :approved
      true -> :pending
    end
  end

  @doc "True for an admin, GM or editor."
  def staff?(%{is_admin: true}), do: true
  def staff?(%{role: role}) when role in @staff_roles, do: true
  def staff?(_), do: false

  @doc "How many web addresses `text` contains."
  def link_count(text) when is_binary(text) do
    ~r{(?:https?://|www\.)\S+}i |> Regex.scan(text) |> length()
  end

  def link_count(_), do: 0
end
