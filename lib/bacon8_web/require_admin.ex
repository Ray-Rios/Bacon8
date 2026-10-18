defmodule Bacon8Web.RequireAdmin do
  import Phoenix.LiveView

  # LiveView mount hook
  def on_mount(:ensure_admin, _params, _session, socket) do
    user = socket.assigns[:current_user]

    if user && Map.get(user, :is_admin, false) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end
end
