defmodule Bacon8.Plugin do
  @moduledoc """
  The behaviour every plugin's main module implements (BACON8.md §9).

  A plugin is a folder under `plugins/`. The folder name is the plugin's slug,
  and the main module is `<Camelized slug>.Plugin`:

      plugins/bacon_world/lib/bacon_world/plugin.ex

      defmodule BaconWorld.Plugin do
        use Bacon8.Plugin,
          slug: "bacon_world",
          name: "Bacon World",
          version: "0.1.0",
          description: "A small multiplayer 3D arcade that runs in the browser."

        @impl true
        def game, do: %{name: "Bacon World", description: "...", path: "/games/bacon_world"}

        @impl true
        def routes, do: BaconWorldWeb.Routes
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

  @type nav_item :: %{required(:label) => String.t(), required(:path) => String.t(), required(:icon) => String.t(), optional(:badge) => pos_integer()}

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

  @doc """
  Slugs this plugin was installed under before a rename. Old links keep working:
  `/games/<old>/...` and `/admin/<old>/...` answer 301 to the same path under
  the current slug (`Bacon8Web.PluginRouter`). Stored names (tables, the game
  row, `plugin_states`) are the plugin's own migrations' job (BACON8.md §5).
  """
  @callback previous_slugs() :: [String.t()]

  @doc """
  Where a plugin's `site` and `site_api` routes mount: `/<mount>/...` and
  `/api/<mount>/...` (e.g. "store"). nil (the default) for a plugin without
  site routes. Lowercase letters, digits, `-` and `_`; must not clash with
  another plugin or a core path (`Bacon8Web.PluginRouter`).
  """
  @callback mount() :: String.t() | nil

  @doc """
  Slugs of plugins this one needs. `Bacon8.Plugins.activate/2` refuses while
  one of them is inactive, and `deactivate/2` refuses to turn off a plugin an
  active plugin requires.
  """
  @callback requires() :: [String.t()]

  @doc "Processes supervised while the plugin is active."
  @callback children() :: [Supervisor.child_spec() | {module(), term()} | module()]

  @doc """
  True when this plugin keeps records about the user that must outlive the
  account (orders, a ledger): `Bacon8.Accounts.delete_user/1` then anonymises
  instead of deleting. Asked of every *installed* plugin, active or not.
  """
  @callback retains_user_data?(user_id :: Ecto.UUID.t()) :: boolean()

  @doc """
  Storage keys (SHA-256 of the body, as `Bacon8.Storage` names blobs) this
  plugin still uses outside the drive, so `Bacon8.Drive.gc_blobs/2` keeps them.
  Asked of every *installed* plugin, active or not.
  """
  @callback storage_refs() :: [String.t()]

  @doc """
  Links this plugin adds to the site navigation and taskbar while active. A link may carry
  a `:badge`, a count shown beside it (chat uses it for pending invites); leave it out when
  there is nothing to show.
  """
  @callback nav_links(user :: struct() | nil) :: [nav_item()]

  @doc "Links this plugin adds to the profile page while active (e.g. purchase history)."
  @callback profile_tabs(user :: struct()) :: [nav_item()]

  @doc """
  Request path prefixes whose raw body must be kept (`conn.private[:raw_body]`),
  e.g. payment webhooks whose signature covers the exact bytes. Asked of every
  installed plugin, so a request is read the same way whether or not it ends
  up refused by the plugin's gate.
  """
  @callback raw_body_paths() :: [String.t()]

  @doc """
  Actions for /admin/api-toolbox while active: maps with `:id`, `:name`,
  `:category`, `:category_label`, `:method`, `:path`, `:description`, `:fields`
  and `:run`, a 2-arity function `(params, admin) -> {:ok, map} | {:error,
  message, detail}`.
  """
  @callback admin_tools() :: [map()]

  @doc """
  What this plugin shows on the admin dashboard while active:
  `%{stats: [%{label, value, icon}], panels: [%{title, empty, items}]}`, where
  each item is `%{title, path, subtitle, value, badge}` (all but `:title`
  optional).
  """
  @callback admin_dashboard() :: %{optional(:stats) => [map()], optional(:panels) => [map()]}

  @doc "Links added to the admin sidebar while active."
  @callback admin_nav() :: [nav_item()]

  @doc """
  Apps this plugin adds to the start menu's grid while active, for this user (nil when signed
  out): `%{label, path, icon}`, opened by navigating to `path`. Leave out what the user may not
  open (Suggestions & Bugs gives guests nothing).
  """
  @callback desktop_apps(user :: struct() | nil) :: [nav_item()]

  @doc "Entitlement kinds this plugin grants or checks (BACON8.md §8)."
  @callback entitlement_kinds() :: [String.t()]

  @doc """
  Live numbers for the game's status on the front page (2026-10-29, `Bacon8.GameStatus`), or nil
  for the hub's own: its world servers' heartbeats (`game_servers`) and its characters. A plugin
  whose game runs inside the hub (Bacon World: zones and Presence) returns
  `%{online: boolean, zones: [%{name: String.t(), online: boolean, players: integer}],
  current_players: integer}`, optionally `total_players` (else the hub counts the accounts with a
  character in the game). Called at most every few seconds; keep it cheap and don't crash.
  """
  @callback game_stats() :: map() | nil

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

    * `{:channel_updated, %ChatChannels.Channel{} = new, %ChatChannels.Channel{} = old}`
    * `{:channel_deleted, channel_id}` - before the channel's rows go
    * `{:channel_member_removed, channel_id, user_id}` - kicked, banned or left
    * `{:user_content_removed, user_id}` - the user was banned or deleted: remove what they
      wrote. Sent inside the account's transaction, so what a plugin does here rolls back with it
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
      def previous_slugs, do: []
      @impl true
      def mount, do: nil
      @impl true
      def requires, do: []
      @impl true
      def children, do: []
      @impl true
      def retains_user_data?(_user_id), do: false
      @impl true
      def storage_refs, do: []
      @impl true
      def nav_links(_user), do: []
      @impl true
      def profile_tabs(_user), do: []
      @impl true
      def raw_body_paths, do: []
      @impl true
      def admin_tools, do: []
      @impl true
      def admin_dashboard, do: %{}
      @impl true
      def admin_nav, do: []
      @impl true
      def desktop_apps(_user), do: []
      @impl true
      def entitlement_kinds, do: []
      @impl true
      def game_stats, do: nil
      @impl true
      def on_activate, do: :ok
      @impl true
      def on_deactivate, do: :ok
      @impl true
      def hub_event(_event), do: :ok

      defoverridable game: 0, routes: 0, previous_slugs: 0, mount: 0, requires: 0, children: 0,
                     retains_user_data?: 1, storage_refs: 0, nav_links: 1, profile_tabs: 1,
                     raw_body_paths: 0, admin_tools: 0, admin_dashboard: 0, admin_nav: 0, desktop_apps: 1,
                     entitlement_kinds: 0, game_stats: 0, on_activate: 0, on_deactivate: 0, hub_event: 1
    end
  end
end
