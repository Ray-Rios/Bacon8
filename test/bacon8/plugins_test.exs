defmodule Bacon8.PluginsTest do
  # Not async: the active set is cached in :persistent_term, shared by all tests.
  use Bacon8.DataCase, async: false

  alias Bacon8.Plugins

  setup do
    Application.put_env(:bacon8, :extra_plugins, [Bacon8.Test.FixturePlugin, Bacon8.Test.RefusingPlugin])
    on_exit(fn -> Application.put_env(:bacon8, :extra_plugins, [Bacon8.Test.FixturePlugin]) end)
    Plugins.refresh_cache()
    :ok
  end

  test "installed plugins are listed, inactive by default" do
    assert Bacon8.Test.FixturePlugin in Plugins.installed()

    assert %{name: "Fixture", version: "1.2.3", active?: false, game: %{slug: "fixture_plugin"}} =
             Enum.find(Plugins.list(), &(&1.slug == "fixture_plugin"))

    refute Plugins.active?("fixture_plugin")
    assert Plugins.admin_nav() == []
    assert Plugins.active_games() == []
  end

  test "activate turns everything on, runs the hook, and registers the game" do
    assert {:ok, Bacon8.Test.FixturePlugin} = Plugins.activate("fixture_plugin")
    assert_received {:fixture_hook, :activated}

    assert Plugins.active?("fixture_plugin")
    assert [%{label: "Fixture"}] = Plugins.admin_nav()
    assert [%{slug: "fixture_plugin", name: "Fixture Game"}] = Plugins.active_games()
    assert %{is_active: true, name: "Fixture Game"} = Bacon8.Games.get_game_by_slug("fixture_plugin")

    # Persisted, not just cached.
    :persistent_term.erase({Bacon8.Plugins, :active})
    assert Plugins.active?("fixture_plugin")
  end

  test "deactivate turns it off and disables the game; data is kept" do
    {:ok, _} = Plugins.activate("fixture_plugin")
    assert {:ok, _} = Plugins.deactivate("fixture_plugin")
    assert_received {:fixture_hook, :deactivated}

    refute Plugins.active?("fixture_plugin")
    assert Plugins.admin_nav() == []
    assert %{is_active: false} = Bacon8.Games.get_game_by_slug("fixture_plugin")
  end

  test "a refusing hook leaves the plugin inactive" do
    assert {:error, {:hook_failed, :missing_configuration}} = Plugins.activate("refusing_plugin")
    refute Plugins.active?("refusing_plugin")
  end

  test "unknown plugins can't be activated, and rows for uninstalled plugins are ignored" do
    assert {:error, :not_installed} = Plugins.activate("nope")

    now = DateTime.utc_now()
    for slug <- ["fixture_plugin", "uninstalled"] do
      Repo.insert!(%Bacon8.Plugins.State{slug: slug, active: true, inserted_at: now, updated_at: now})
    end

    assert Plugins.refresh_cache() == MapSet.new(["fixture_plugin"])
  end

  test "defaults apply until an admin toggles; a saved choice then wins" do
    Application.put_env(:bacon8, :default_active_plugins, ["fixture_plugin"])
    on_exit(fn -> Application.put_env(:bacon8, :default_active_plugins, []) end)

    Plugins.refresh_cache()
    assert Plugins.active?("fixture_plugin")

    admin = user_fixture(role: "admin")
    {:ok, _} = Plugins.deactivate("fixture_plugin", admin)
    refute Plugins.active?("fixture_plugin")
    assert %{active: false, changed_by_id: id} = Repo.get(Bacon8.Plugins.State, "fixture_plugin")
    assert id == admin.id

    # Still off after the cache is rebuilt, despite the default.
    :persistent_term.erase({Bacon8.Plugins, :active})
    refute Plugins.active?("fixture_plugin")
  end

  test "the gate plug 404s inactive plugins and passes active ones" do
    conn = Plug.Test.conn(:get, "/api/games/fixture_plugin/ping")
    opts = Bacon8Web.Plugs.PluginActive.init(slug: "fixture_plugin")

    assert %{status: 404, halted: true} = Bacon8Web.Plugs.PluginActive.call(conn, opts)

    {:ok, _} = Plugins.activate("fixture_plugin")
    assert %{halted: false, assigns: assigns} = Bacon8Web.Plugs.PluginActive.call(conn, opts)
    refute Map.has_key?(assigns, :bacon8_plugin)

    page_opts = Bacon8Web.Plugs.PluginActive.init(slug: "fixture_plugin", page: true)
    assert %{assigns: %{bacon8_plugin: "fixture_plugin"}} = Bacon8Web.Plugs.PluginActive.call(conn, page_opts)
  end

  test "the API gate hands controllers the game slug, as the core routes do" do
    {:ok, _} = Plugins.activate("fixture_plugin")

    conn =
      Plug.Test.conn(:get, "/api/games/my-game/ping")
      |> Plug.Conn.fetch_query_params()

    opts = Bacon8Web.Plugs.PluginActive.init(slug: "fixture_plugin", game_slug: "my-game")
    conn = Bacon8Web.Plugs.PluginActive.call(conn, opts)

    assert conn.params["game_slug"] == "my-game"
    assert conn.path_params["game_slug"] == "my-game"
  end

  test "hub events reach every installed plugin, active or not, and a crash is contained" do
    Application.put_env(:bacon8, :extra_plugins, [Bacon8.Test.CrashingPlugin, Bacon8.Test.FixturePlugin])

    refute Plugins.active?("fixture_plugin")
    channel_id = Ecto.UUID.generate()
    assert :ok = Plugins.notify({:channel_deleted, channel_id})

    # The crashing plugin came first; the fixture still got the event.
    assert_received {:fixture_hub_event, {:channel_deleted, ^channel_id}}
  end

  test "admin pages bounce to /admin/plugins when the plugin is inactive" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}

    assert {:halt, _} = Bacon8Web.PluginGate.on_mount({"fixture_plugin", "/admin/plugins"}, %{}, %{}, socket)

    {:ok, _} = Plugins.activate("fixture_plugin")
    assert {:cont, _} = Bacon8Web.PluginGate.on_mount({"fixture_plugin", "/admin/plugins"}, %{}, %{}, socket)
  end

  test "discovery skips folders that aren't finished plugins" do
    dir = Path.join(System.tmp_dir!(), "bacon8_plugins_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    File.mkdir_p!(Path.join(dir, "empty_clone"))
    File.mkdir_p!(Path.join([dir, "half_done", "lib"]))
    File.mkdir_p!(Path.join([dir, "_template", "lib", "_template"]))
    File.mkdir_p!(Path.join([dir, "real_one", "lib", "real_one"]))
    File.write!(Path.join([dir, "real_one", "lib", "real_one", "plugin.ex"]), "# a plugin")

    {result, stderr} =
      ExUnit.CaptureIO.with_io(:stderr, fn -> Bacon8.Plugins.Discovery.discover(dir) end)

    assert [%{slug: "real_one", module: RealOne.Plugin}] = result
    assert stderr =~ "plugins/empty_clone has no lib/empty_clone/plugin.ex"
    assert stderr =~ "plugins/half_done"
  end

  test "priv_dir points at a plugin's priv folder" do
    assert Plugins.priv_dir("bacon_world") |> String.ends_with?(Path.join(["bacon_world", "priv"]))
  end
end

defmodule Bacon8.PluginDefinitionTest do
  use ExUnit.Case, async: true

  test "use Bacon8.Plugin fills in defaults" do
    mod = Bacon8.Test.RefusingPlugin
    assert mod.slug() == "refusing_plugin"
    assert mod.version() == "0.0.0"
    assert mod.routes() == nil
    assert mod.children() == []
    assert mod.game() == nil
  end

  test "invalid slugs are a compile error" do
    for bad <- ["Web-Lobby", "9lives", "bacon world", ""] do
      assert_raise ArgumentError, ~r/plugin slug/, fn ->
        Code.eval_string("""
        defmodule Bacon8.Test.BadSlug#{System.unique_integer([:positive])} do
          use Bacon8.Plugin, slug: #{inspect(bad)}, name: "Bad"
        end
        """)
      end
    end
  end

  test "routes DSL stores the blocks and the namespace" do
    routes = Bacon8.Test.FixtureWeb.Routes
    assert routes.__namespace__() == Bacon8.Test.FixtureWeb
    assert {:get, _, ["/ping", _, :show]} = routes.__api_routes__()
    assert {:live, _, ["/", _, :index]} = routes.__browser_routes__()
    assert {:live, _, ["/", _, :index]} = routes.__admin_routes__()
  end

  test "hub_event defaults to :ok" do
    assert Bacon8.Test.RefusingPlugin.hub_event({:anything, 1}) == :ok
  end
end
