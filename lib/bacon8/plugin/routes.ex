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
      import Bacon8.Plugin.Routes, only: [api: 1, browser: 1, admin: 1]
      @before_compile Bacon8.Plugin.Routes
      Module.register_attribute(__MODULE__, :bacon8_api_routes, accumulate: false)
      Module.register_attribute(__MODULE__, :bacon8_browser_routes, accumulate: false)
      Module.register_attribute(__MODULE__, :bacon8_admin_routes, accumulate: false)

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

  defmacro __before_compile__(env) do
    api = Module.get_attribute(env.module, :bacon8_api_routes)
    browser = Module.get_attribute(env.module, :bacon8_browser_routes)
    admin = Module.get_attribute(env.module, :bacon8_admin_routes)

    quote do
      @doc false
      def __api_routes__, do: unquote(Macro.escape(api))
      @doc false
      def __browser_routes__, do: unquote(Macro.escape(browser))
      @doc false
      def __admin_routes__, do: unquote(Macro.escape(admin))
    end
  end
end
