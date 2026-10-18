defmodule Bacon8Web.AdminLive.Channels do
  use Bacon8Web, :live_view

  def mount(_params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      {:ok, assign(socket, page_title: "Admin - Channels")}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-3xl font-bold text-white mb-8">Chat Channel Management</h1>
      <p class="text-gray-300">Channel management interface coming soon...</p>
    </div>
    """
  end
end