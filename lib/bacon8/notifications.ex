defmodule Bacon8.Notifications do
  @moduledoc """
  The Notifications context for managing user notifications.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Notifications.UserNotification
  alias Bacon8.Accounts
  alias Bacon8.Forum.Message

  require Logger

  # ==================== NOTIFICATION QUERIES ====================

  @doc """
  List all notifications for a user, ordered by most recent first.
  """
  def list_user_notifications(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    unread_only = Keyword.get(opts, :unread_only, false)

    query = from n in UserNotification,
      where: n.user_id == ^user_id,
      order_by: [desc: n.inserted_at],
      limit: ^limit,
      preload: [:actor, :channel]

    query = if unread_only do
      from n in query, where: n.read == false
    else
      query
    end

    try do
      Repo.all(query)
    rescue
      _ -> []
    end
  end

  @doc """
  Count unread notifications for a user.
  """
  def count_unread_notifications(user_id) do
    try do
      from(n in UserNotification, where: n.user_id == ^user_id and n.read == false)
      |> Repo.aggregate(:count)
    rescue
      _ -> 0
    end
  end

  @doc """
  Get a notification by ID for a specific user.
  """
  def get_notification(user_id, notification_id) do
    try do
      Repo.get_by(UserNotification, id: notification_id, user_id: user_id)
    rescue
      _ -> nil
    end
  end

  @doc """
  Mark a notification as read.
  """
  def mark_as_read(notification) do
    notification
    |> UserNotification.mark_read_changeset()
    |> Repo.update()
  end

  @doc """
  Mark all notifications as read for a user.
  """
  def mark_all_as_read(user_id) do
    try do
      from(n in UserNotification, where: n.user_id == ^user_id and n.read == false)
      |> Repo.update_all(set: [read: true, read_at: DateTime.utc_now()])
    rescue
      _ -> {0, nil}
    end
  end

  @doc """
  Delete a notification.
  """
  def delete_notification(notification) do
    Repo.delete(notification)
  end

  @doc """
  Delete all read notifications older than X days.
  """
  def cleanup_old_notifications(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)
    
    try do
      from(n in UserNotification, 
        where: n.read == true and n.inserted_at < ^cutoff)
      |> Repo.delete_all()
    rescue
      _ -> {0, nil}
    end
  end

  # ==================== NOTIFICATION CREATION ====================

  @doc """
  Create a notification.
  """
  def create_notification(attrs) do
    %UserNotification{}
    |> UserNotification.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Create a mention notification when a user is mentioned in a message.
  """
  def create_mention_notification(mentioned_user, message, actor) do
    # Don't notify yourself
    if mentioned_user.id == actor.id do
      {:ok, nil}
    else
      channel = case message.channel do
        %Ecto.Association.NotLoaded{} -> Bacon8.Forum.get_channel(message.channel_id)
        nil -> Bacon8.Forum.get_channel(message.channel_id)
        channel -> channel
      end
      channel_name = if channel, do: channel.name, else: "a channel"
      
      attrs = %{
        type: "mention",
        title: "#{actor.username} mentioned you",
        content: truncate_content(message.content, 100),
        user_id: mentioned_user.id,
        actor_id: actor.id,
        channel_id: message.channel_id,
        resource_type: "message",
        resource_id: message.id,
        metadata: %{
          channel_name: channel_name,
          message_preview: truncate_content(message.content, 200)
        }
      }

      case create_notification(attrs) do
        {:ok, notification} ->
          # Broadcast to user's notification channel
          Phoenix.PubSub.broadcast(
            Bacon8.PubSub,
            "user:#{mentioned_user.id}:notifications",
            {:new_notification, notification}
          )
          {:ok, notification}
        error ->
          error
      end
    end
  end

  # ==================== MENTION PARSING ====================

  @doc """
  Extract @username mentions from message content.
  Returns a list of usernames (without the @ symbol).
  """
  def extract_mentions(content) when is_binary(content) do
    # Match @username patterns (alphanumeric, underscores, hyphens)
    Regex.scan(~r/@([a-zA-Z0-9_-]+)/, content)
    |> Enum.map(fn [_, username] -> username end)
    |> Enum.uniq()
  end
  def extract_mentions(_), do: []

  @doc """
  Process mentions in a message and create notifications.
  Returns {:ok, notifications_created} or {:error, reason}
  """
  def process_message_mentions(%Message{} = message, actor) do
    content = message.content || ""
    usernames = extract_mentions(content)
    
    if usernames == [] do
      {:ok, []}
    else
      # Look up users by username
      users = Accounts.get_users_by_usernames(usernames)
      
      # Create notifications for each mentioned user
      notifications = Enum.map(users, fn user ->
        case create_mention_notification(user, message, actor) do
          {:ok, notification} -> notification
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      
      {:ok, notifications}
    end
  end

  # ==================== HELPERS ====================

  defp truncate_content(nil, _), do: ""
  defp truncate_content(content, max_length) when byte_size(content) <= max_length, do: content
  defp truncate_content(content, max_length) do
    String.slice(content, 0, max_length) <> "..."
  end
end
