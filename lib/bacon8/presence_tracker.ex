defmodule Bacon8.PresenceTracker do
  use Phoenix.Presence,
    otp_app: :bacon8,
    pubsub_server: Bacon8.PubSub

  def track_user(user_id, socket) do
    track(socket, "users:general", user_id, %{
      online_at: inspect(System.system_time(:second)),
      user_id: user_id
    })
  end

  def untrack_user(user_id, socket) do
    untrack(socket, "users:general", user_id)
  end

  def list_online_users do
    list("users:general")
  end
end