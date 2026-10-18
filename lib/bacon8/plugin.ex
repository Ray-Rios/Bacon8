defmodule Bacon8.Plugin do
  @moduledoc """
  The behaviour every plugin's main module implements (BACON8.md §9).

  A plugin is a folder under `plugins/`. The folder name is the plugin's slug,
  and the main module is `<Camelized slug>.Plugin`:

      plugins/web_lobby/lib/web_lobby/plugin.ex

      defmodule WebLobby.Plugin do
        use Bacon8.Plugin,
          slug: "web_lobby",
          name: "Web Lobby",
          version: "0.1.0",
          description: "A small multiplayer 3D arcade that runs in the browser."

        @impl true
        def game, do: %{name: "Web Lobby", description: "...", path: "/games/web_lobby"}

        @impl true
        def routes, do: WebLobbyWeb.Routes
      end

  `use Bacon8.Plugin` defines the required callbacks from its options and gives
  every optional callback a harmless default, so a plugin only overrides what it
  uses.
  """

  @type game :: %{
          required(:name) => String.t(),
          required(:path) => String.t(),
          optional(:description) => String.t(),
          optional(:icon) => String.t(),
          optional(:slug) => String.t()
        }

  @type nav_item :: %{label: String.t(), path: String.t(), icon: String.t()}

  @doc "Folder name; lowercase letters, digits and underscores."
  @callback slug() :: String.t()
  @callback name() :: String.t()
  @callback version() :: String.t()
  @callback description() :: String.t()

  @doc """
  The game this plugin provides, or nil. `:slug` is the game slug (used in
  `/api/games/<slug>` and the `games` table) and defaults to the plugin slug.
  """
  @callback game() :: game() | nil

  @doc "A module using `Bacon8.Plugin.Routes`, or nil."
  @callback routes() :: module() | nil

  @doc "Processes supervised while the plugin is active."
  @callback children() :: [Supervisor.child_spec() | {module(), term()} | module()]

  @doc "Links added to the admin sidebar while active."
  @callback admin_nav() :: [nav_item()]

  @doc "Start-menu apps added while active (wired up in milestone 5)."
  @callback desktop_apps() :: [map()]

  @doc "Entitlement kinds this plugin grants or checks (BACON8.md §8)."
  @callback entitlement_kinds() :: [String.t()]

  @doc "Runs once, on the node where an admin activates the plugin."
  @callback on_activate() :: :ok | {:error, term()}

  @doc "Runs once, on the node where an admin deactivates the plugin."
  @callback on_deactivate() :: :ok

  @doc """
  Something happened in the hub that this plugin's data may depend on.
  Called synchronously, in the caller's process, for every *installed* plugin
  (active or not: a plugin's data has to stay consistent either way), via
  `Bacon8.Plugins.notify/1`. Return `:ok`; a crash is logged and ignored.

  Events:

    * `{:channel_updated, %Bacon8.Forum.Channel{} = new, %Bacon8.Forum.Channel{} = old}`
    * `{:channel_deleted, channel_id}` - before the channel's rows go
    * `{:channel_member_removed, channel_id, user_id}` - kicked, banned or left
    * `{:entitlement_granted, %Bacon8.Entitlements.Entitlement{} = e}` - a
      store purchase granted something (a game item of a kind this plugin
      declares in `entitlement_kinds/0`, a download, a pass); after commit
    * `{:entitlement_revoked, %Bacon8.Entitlements.Entitlement{} = e}` - a
      timed grant ran out (`revoked_reason` "expired") or a chargeback took it
      back ("chargeback"). Games should still check
      `Bacon8.Entitlements.active?/3` when an item is used; events are a
      convenience, not the source of truth

  Unknown events must be ignored, so the hub can add more.
  """
  @callback hub_event(event :: tuple()) :: :ok

  @slug_format ~r/\A[a-z][a-z0-9_]*\z/

  @doc false
  def slug_format, do: @slug_format

  defmacro __using__(opts) do
    slug = Keyword.fetch!(opts, :slug)
    name = Keyword.fetch!(opts, :name)
    version = Keyword.get(opts, :version, "0.0.0")
    description = Keyword.get(opts, :description, "")

    unless is_binary(slug) and Regex.match?(@slug_format, slug) do
      raise ArgumentError,
            "plugin slug must be lowercase letters, digits and underscores, starting with a letter; got #{inspect(slug)}"
    end

    quote do
      @behaviour Bacon8.Plugin

      @impl true
      def slug, do: unquote(slug)
      @impl true
      def name, do: unquote(name)
      @impl true
      def version, do: unquote(version)
      @impl true
      def description, do: unquote(description)

      @impl true
      def game, do: nil
      @impl true
      def routes, do: nil
      @impl true
      def children, do: []
      @impl true
      def admin_nav, do: []
      @impl true
      def desktop_apps, do: []
      @impl true
      def entitlement_kinds, do: []
      @impl true
      def on_activate, do: :ok
      @impl true
      def on_deactivate, do: :ok
      @impl true
      def hub_event(_event), do: :ok

      defoverridable game: 0, routes: 0, children: 0, admin_nav: 0, desktop_apps: 0,
                     entitlement_kinds: 0, on_activate: 0, on_deactivate: 0, hub_event: 1
    end
  end
end
