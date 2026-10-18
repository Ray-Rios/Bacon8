defmodule WebLobbyWeb.Routes do
  @moduledoc "Web Lobby's routes. Pages mount at /games/web_lobby (BACON8.md §9)."
  use Bacon8.Plugin.Routes

  browser do
    live "/", PlayLive, :index
  end
end
