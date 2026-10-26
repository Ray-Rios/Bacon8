defmodule Bacon8.Content.CommentNotices do
  @moduledoc """
  Notifications about comments: staff are told when comments are waiting for them (one unread
  notice at a time, however many arrive), and the author of a comment is told when someone
  replies to it. They appear in the desktop's notification area like any other
  (`Bacon8.Notifications`).
  """
  import Ecto.Query, warn: false

  alias Bacon8.{Notifications, Repo}
  alias Bacon8.Accounts.User
  alias Bacon8.Notifications.UserNotification

  @source_kind "blog_comments"

  @doc "Tells every admin, GM and editor that a comment is waiting (unless they already have an unread notice)."
  def pending(comment) do
    comment = Repo.preload(comment, [:post])

    for staff <- staff(), staff.id != comment.user_id do
      already? =
        Repo.exists?(from n in UserNotification, where: n.user_id == ^staff.id and n.source_kind == ^@source_kind and n.read == false)

      unless already? do
        Notifications.create_notification(%{
          type: "system",
          title: "A comment is waiting for approval",
          content: truncate(comment.content, 100),
          user_id: staff.id,
          actor_id: comment.user_id,
          resource_type: "comment",
          resource_id: comment.id,
          source_kind: @source_kind,
          source_id: comment.post_id,
          metadata: %{source_name: comment.post && comment.post.title, path: "/admin/comments"}
        })
      end
    end

    :ok
  end

  @doc "Tells the author of the comment `reply` answers that it was answered (once the reply is shown)."
  def reply(%{parent_id: nil}), do: :ok

  def reply(reply) do
    reply = Repo.preload(reply, [:user, :post, :parent])
    parent = reply.parent

    if parent && parent.user_id && parent.user_id != reply.user_id do
      Notifications.create_notification(%{
        type: "reply",
        title: "#{name(reply.user)} replied to your comment",
        content: truncate(reply.content, 100),
        user_id: parent.user_id,
        actor_id: reply.user_id,
        resource_type: "comment",
        resource_id: reply.id,
        source_kind: @source_kind,
        source_id: reply.post_id,
        metadata: %{source_name: reply.post && reply.post.title, path: "/blog/#{reply.post.slug}#comment-#{reply.id}"}
      })
    end

    :ok
  end

  defp staff do
    Repo.all(from u in User, where: u.is_admin == true or u.role in ["gm", "editor"])
  end

  defp name(%{name: n}) when is_binary(n) and n != "", do: n
  defp name(_), do: "Someone"

  defp truncate(nil, _), do: ""
  defp truncate(text, max), do: if(String.length(text) > max, do: String.slice(text, 0, max) <> "...", else: text)
end
