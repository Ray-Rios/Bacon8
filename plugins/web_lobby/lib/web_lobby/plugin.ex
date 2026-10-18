defmodule WebLobby.Plugin do
  @moduledoc """
  Web Lobby: a small multiplayer 3D arcade that runs in the browser.

  It is also the reference plugin (BACON8.md §9): copy this folder to start
  your own. Everything it needs from the hub goes through public contexts
  (`Bacon8.Games` for characters, `Bacon8.Plugins` for its game row,
  `Bacon8Web.Presence` and `Bacon8.PubSub` for multiplayer).
  """
  use Bacon8.Plugin,
    slug: "web_lobby",
    name: "Web Lobby",
    version: "0.1.0",
    description: "A small multiplayer 3D arcade that runs in the browser. The reference plugin."

  @impl true
  def game do
    %{
      name: "Web Lobby",
      icon: "🕹️",
      description: "Multiplayer 3D arcade lobby. Create or select a character to jump in.",
      path: "/games/web_lobby"
    }
  end

  @impl true
  def routes, do: WebLobbyWeb.Routes
end
