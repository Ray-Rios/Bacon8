defmodule Bacon8.Plugin.Routes do
  @moduledoc """
  How a plugin declares its routes:

      defmodule BaconWorldWeb.Routes do
        use Bacon8.Plugin.Routes

        # Mounted at /api/games/<game slug>, `:games_api` pipeline
        # (player bearer token or game-server key).
        api do
          get "/zones", ZoneController, :index
        end

        # Mounted at /games/<plugin slug>, signed-in browser session.
        browser do
          live "/", PlayLive, :index
        end

        # Mounted at /admin/<plugin slug>, admins only.
        admin do
          live "/", AdminLive, :index
        end
      end

  A plugin that is a site feature rather than a game (it returns a `mount/0`,
  e.g. "store") mounts pages and APIs at the top level instead:

        # Mounted at /<mount>. `:browser` (the default) puts them in a
        # live_session of the plugin's own; any other core pipeline gives a
        # plain scope (e.g. `pipe_through: :drive_files` for file downloads).
        site do
          live "/", StoreLive, :index
        end

        site pipe_through: :drive_files do
          get "/media/:id", FileController, :media
        end

        # Mounted at /api/<mount>; `:api` by default.
        site_api pipe_through: :webhooks do
          post "/webhooks/:provider", WebhookController, :create
        end

        # Absolute paths, for a URL an outside party already uses. Needs a
        # reason, so it's clear when it can go.
        fixed reason: "Stripe still posts here until the dashboard is changed",
              pipe_through: :webhooks do
          post "/api/webhooks/payments/:provider", WebhookController, :create
        end

  In `api` routes `conn.params["game_slug"]` is set to the plugin's game slug,
  as it is for the hub's own `/api/games/:game_slug/...` routes, so controllers
  written for either work unchanged.

  Module names inside the blocks are relative to the routes module's parent
  namespace (`BaconWorldWeb` here). The blocks are stored as quoted code and
  expanded by `Bacon8Web.PluginRouter` inside the core router at compile time,
  so they can use anything a Phoenix router scope can.
  """

  defmacro __using__(_opts) do
    namespace =
      __CALLER__.module
      |> Module.split()
      |> Enum.drop(-1)
      |> Module.concat()

    quote do
      import Bacon8.Plugin.Routes,
        only: [api: 1, browser: 1, admin: 1, site: 1, site: 2, site_api: 1, site_api: 2, fixed: 2]

      @before_compile Bacon8.Plugin.Routes
      Module.register_attribute(__MODULE__, :bacon8_api_routes, accumulate: false)
      Module.register_attribute(__MODULE__, :bacon8_browser_routes, accumulate: false)
      Module.register_attribute(__MODULE__, :bacon8_admin_routes, accumulate: false)
      Module.register_attribute(__MODULE__, :bacon8_site_routes, accumulate: true)
      Module.register_attribute(__MODULE__, :bacon8_site_api_routes, accumulate: true)
      Module.register_attribute(__MODULE__, :bacon8_fixed_routes, accumulate: true)

      @doc false
      def __namespace__, do: unquote(namespace)
    end
  end

  @doc "Declares API routes, mounted under /api/games/<game slug>."
  defmacro api(do: block) do
    quote do: @bacon8_api_routes unquote(Macro.escape(block))
  end

  @doc "Declares browser routes, mounted under /games/<plugin slug>."
  defmacro browser(do: block) do
    quote do: @bacon8_browser_routes unquote(Macro.escape(block))
  end

  @doc "Declares admin pages, mounted under /admin/<plugin slug>, admins only."
  defmacro admin(do: block) do
    quote do: @bacon8_admin_routes unquote(Macro.escape(block))
  end

  @doc "Declares site pages, mounted under /<mount>. Option: `pipe_through:` (default `:browser`)."
  defmacro site(opts \\ [], do: block) do
    quote do: @bacon8_site_routes {unquote(opts), unquote(Macro.escape(block))}
  end

  @doc "Declares site API routes, mounted under /api/<mount>. Option: `pipe_through:` (default `:api`)."
  defmacro site_api(opts \\ [], do: block) do
    quote do: @bacon8_site_api_routes {unquote(opts), unquote(Macro.escape(block))}
  end

  @doc """
  Declares routes at absolute paths, for URLs an outside party already uses.
  Options: `reason:` (required, non-empty), `pipe_through:` (default `:api`).
  """
  defmacro fixed(opts, do: block) do
    case Keyword.get(opts, :reason) do
      reason when is_binary(reason) and reason != "" -> :ok
      _ -> raise ArgumentError, "a `fixed` routes block needs `reason: \"...\"` saying why the path can't move"
    end

    quote do: @bacon8_fixed_routes {unquote(opts), unquote(Macro.escape(block))}
  end

  defmacro __before_compile__(env) do
    api = Module.get_attribute(env.module, :bacon8_api_routes)
    browser = Module.get_attribute(env.module, :bacon8_browser_routes)
    admin = Module.get_attribute(env.module, :bacon8_admin_routes)
    # Accumulated attributes are newest-first.
    site = env.module |> Module.get_attribute(:bacon8_site_routes) |> Enum.reverse()
    site_api = env.module |> Module.get_attribute(:bacon8_site_api_routes) |> Enum.reverse()
    fixed = env.module |> Module.get_attribute(:bacon8_fixed_routes) |> Enum.reverse()

    quote do
      @doc false
      def __api_routes__, do: unquote(Macro.escape(api))
      @doc false
      def __browser_routes__, do: unquote(Macro.escape(browser))
      @doc false
      def __admin_routes__, do: unquote(Macro.escape(admin))
      @doc false
      def __site_routes__, do: unquote(Macro.escape(site))
      @doc false
      def __site_api_routes__, do: unquote(Macro.escape(site_api))
      @doc false
      def __fixed_routes__, do: unquote(Macro.escape(fixed))
    end
  end
end
