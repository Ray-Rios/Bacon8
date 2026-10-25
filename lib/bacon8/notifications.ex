defmodule Bacon8.Notifications do
  @moduledoc """
  The Notifications context for managing user notifications.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Notifications.UserNotification

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
      preload: [:actor]

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
      |> Repo.update_all(set: [read: true, read_at: DateTime.truncate(DateTime.utc_now(), :second)])
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
    # (whole seconds: the column is :utc_datetime, which refuses microseconds)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second) |> DateTime.truncate(:second)
    
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
  Create a notification. Whatever made it (chat, a game, the store) describes it
  with `source_kind`/`source_id` (what it came from) and a `path` in `metadata`
  (where clicking it goes); the hub renders those and knows nothing else about it.
  """
  def create_notification(attrs) do
    %UserNotification{}
    |> UserNotification.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, notification} ->
        # The desktop listens on the user's notification topic (badge and sound)
        Phoenix.PubSub.broadcast(
          Bacon8.PubSub,
          "user:#{notification.user_id}:notifications",
          {:new_notification, notification}
        )

        {:ok, notification}

      error ->
        error
    end
  end
end
