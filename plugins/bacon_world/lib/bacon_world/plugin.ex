defmodule BaconWorld.Plugin do
  @moduledoc """
  Bacon World: a small multiplayer 3D arcade that runs in the browser.

  It is also the reference plugin (BACON8.md §9): copy this folder to start
  your own. Everything it needs from the hub goes through public contexts
  (`Bacon8.Games` for characters, `Bacon8.Plugins` for its game row,
  `Bacon8Web.Presence` and `Bacon8.PubSub` for multiplayer).

  Called Web Lobby (slug `web_lobby`) until 2026-10-21; old links redirect
  (`previous_slugs/0`), and the plugin's migrations renamed its tables, its game
  row and its `plugin_states` row (ADR 0001, phase 1).
  """
  use Bacon8.Plugin,
    slug: "bacon_world",
    name: "Bacon World",
    version: "0.1.0",
    description: "A small multiplayer 3D arcade that runs in the browser. The reference plugin."

  @impl true
  def game do
    %{
      name: "Bacon World",
      icon: "🕹️",
      description: "Multiplayer 3D arcade lobby. Create or select a character to jump in.",
      path: "/games/bacon_world"
    }
  end

  @impl true
  def routes, do: BaconWorldWeb.Routes

  @impl true
  def previous_slugs, do: ["web_lobby"]

  # The creatures: one zone process in the cluster (BaconWorld.Mobs.Zone), kept
  # alive by a keeper on every node.
  @impl true
  def children, do: BaconWorld.Mobs.children()
end
