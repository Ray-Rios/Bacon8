defmodule Bacon8Web.GamesLive do
  @moduledoc """
  /games - the games list: one card per active plugin game
  (`Bacon8.Plugins.active_games/0`). Each is a card with a front and a back
  (`Bacon8Web.Components.GameCard`, `Bacon8.GameCards`): the plugin supplies it from its
  `priv/static/card/` folder and an admin can change it on the plugin's admin page.
  """
  use Bacon8Web, :live_view

  alias Bacon8Web.Components.GameCard

  on_mount {Bacon8Web.UserAuth, :require_authenticated_user}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, Bacon8.Plugins.topic())
      Phoenix.PubSub.subscribe(Bacon8.PubSub, Bacon8.GameCards.topic())
    end

    {:ok, socket |> assign(page_title: "Games") |> load()}
  end

  # The games (and their cards' plugin slugs, which aren't always the game slug).
  defp load(socket) do
    games =
      for mod <- Bacon8.Plugins.active(), game = Bacon8.Plugins.game_info(mod), game != nil do
        Map.put(game, :plugin, mod.slug())
      end

    cards = Bacon8.GameCards.for_plugins(Enum.map(games, & &1.plugin))
    assign(socket, games: games, cards: cards)
  end

  # An admin activated or deactivated a plugin, or changed a card.
  @impl true
  def handle_info(:plugins_changed, socket), do: {:noreply, load(socket)}
  def handle_info({:game_card_changed, _slug}, socket), do: {:noreply, load(socket)}
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

        <%!-- Play links into plugin pages, which are in their own live_session: a full page load. --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-8 max-w-sm sm:max-w-none mx-auto">
          <GameCard.game_card
            :for={game <- @games}
            id={"game-card-#{game.plugin}"}
            game={game}
            card={@cards[game.plugin]}
          />
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
