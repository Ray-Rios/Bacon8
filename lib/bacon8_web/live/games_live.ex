defmodule Bacon8Web.GamesLive do
  @moduledoc """
  /games - the games list: one card per active plugin game
  (`Bacon8.Plugins.active_games/0`), each linking to the plugin's page.
  """
  use Bacon8Web, :live_view

  on_mount {Bacon8Web.UserAuth, :require_authenticated_user}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, Bacon8.Plugins.topic())

    {:ok, assign(socket, page_title: "Games", games: Bacon8.Plugins.active_games())}
  end

  # An admin activated or deactivated a plugin.
  @impl true
  def handle_info(:plugins_changed, socket), do: {:noreply, assign(socket, games: Bacon8.Plugins.active_games())}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Sent by the desktop taskbar in the app layout; nothing to do here.
  @impl true
  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black">
      <div class="max-w-5xl mx-auto px-6 py-16">
        <h1 class="text-3xl font-bold text-white mb-2">Games</h1>
        <p class="text-gray-400 mb-10">Pick a game to play.</p>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <%!-- Plugin pages are in their own live_session, so this is a full page load. --%>
          <.link
            :for={game <- @games}
            navigate={game.path}
            class="block text-left glass-dark rounded-lg p-6 border border-gray-700 hover:border-blue-400 transition-colors duration-300"
          >
            <div class="text-4xl mb-3">{Map.get(game, :icon, "🎮")}</div>
            <div class="text-xl font-semibold text-white">{game.name}</div>
            <p class="text-sm text-gray-400 mt-2">{game.description}</p>
          </.link>
        </div>

        <p :if={@games == []} class="text-gray-500">
          No games are available yet.
          <%= if @current_user.role == "admin" do %>
            Activate one on <.link navigate={~p"/admin/plugins"} class="text-blue-400 hover:underline">Plugins</.link>.
          <% end %>
        </p>
      </div>
    </div>
    """
  end
end
