defmodule BaconWorldWeb.Admin.HomeLive do
  @moduledoc """
  /admin/bacon_world - Bacon World's admin page: its card on /games (the hub's
  `Bacon8Web.GameCardAdmin` section; the card's own files are in
  `priv/static/card/`) and links to the game's other admin pages.
  """
  use Bacon8Web, :live_view

  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Admin - Bacon World")}

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/bacon_world">
      <div class="max-w-6xl mx-auto space-y-6">
        <div class="dark-glass p-6 rounded-xl flex flex-wrap items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-white">Bacon World</h1>
            <p class="mt-1 text-sm text-gray-400">The game's card on /games, and its other admin pages.</p>
          </div>
          <div class="flex gap-2">
            <.link
              navigate="/admin/bacon_world/skills"
              class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium"
            >
              🌳 Skill tree
            </.link>
            <a href="/games/bacon_world" class="bg-blue-600 hover:bg-blue-500 text-white px-4 py-2 rounded-md text-sm font-medium">
              ▶ Play
            </a>
          </div>
        </div>

        <.live_component module={Bacon8Web.GameCardAdmin} id="game-card" plugin="bacon_world" current_user={@current_user} />
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
