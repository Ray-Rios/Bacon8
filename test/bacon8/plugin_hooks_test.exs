defmodule Bacon8.PluginHooksTest do
  # The plugin hooks from ADR 0001 phase 2, through the fixture plugins.
  # Not async: the active set and the fixtures' answers are global.
  use Bacon8.DataCase, async: false

  alias Bacon8.{Accounts, Drive, Plugins, Storage}
  alias Bacon8.Test.{CrashingPlugin, FixturePlugin, RequiringPlugin}

  setup do
    Application.put_env(:bacon8, :extra_plugins, [FixturePlugin, RequiringPlugin])

    on_exit(fn ->
      Application.put_env(:bacon8, :extra_plugins, [FixturePlugin])
      Application.delete_env(:bacon8, :fixture_retains)
      Application.delete_env(:bacon8, :fixture_storage_refs)
      :persistent_term.erase({Bacon8.Plugins, :active})
    end)

    Plugins.refresh_cache()
    :ok
  end

  describe "requires/0" do
    test "a plugin can't be activated while a plugin it requires is inactive" do
      assert {:error, {:requires, ["fixture_plugin"]}} = Plugins.activate("requiring_plugin")
      refute Plugins.active?("requiring_plugin")
      assert %{missing: ["fixture_plugin"]} = Plugins.requirements(RequiringPlugin)
    end

    test "once the requirement is active it can, and the requirement can't then be switched off" do
      {:ok, _} = Plugins.activate("fixture_plugin")
      assert {:ok, _} = Plugins.activate("requiring_plugin")
      assert Plugins.required_by("fixture_plugin") == ["requiring_plugin"]

      assert {:error, {:required_by, ["requiring_plugin"]}} = Plugins.deactivate("fixture_plugin")
      assert Plugins.active?("fixture_plugin")

      {:ok, _} = Plugins.deactivate("requiring_plugin")
      assert {:ok, _} = Plugins.deactivate("fixture_plugin")
    end

    test "a plugin active by default with its requirement off is not active" do
      Application.put_env(:bacon8, :default_active_plugins, ["requiring_plugin"])
      on_exit(fn -> Application.put_env(:bacon8, :default_active_plugins, []) end)

      Plugins.refresh_cache()
      refute Plugins.active?("requiring_plugin")

      Application.put_env(:bacon8, :default_active_plugins, ["requiring_plugin", "fixture_plugin"])
      Plugins.refresh_cache()
      assert Plugins.active?("requiring_plugin")
    end
  end

  describe "data hooks ask every installed plugin, and fail safe" do
    test "retains_user_data? decides between deleting and anonymising an account" do
      keep = user_fixture()
      gone = user_fixture()
      Application.put_env(:bacon8, :fixture_retains, [keep.id])

      # Inactive, still asked: its data exists either way.
      refute Plugins.active?("fixture_plugin")
      assert Plugins.retains_user_data?(keep.id)
      refute Plugins.retains_user_data?(gone.id)

      {:ok, _} = Accounts.delete_user(keep)
      {:ok, _} = Accounts.delete_user(gone)
      assert %{} = Repo.get(Accounts.User, keep.id)
      assert Repo.get(Accounts.User, gone.id) == nil
    end

    test "a plugin that crashes counts as keeping the user's data" do
      Application.put_env(:bacon8, :extra_plugins, [CrashingPlugin, FixturePlugin])
      user = user_fixture()
      assert Plugins.retains_user_data?(user.id)
    end

    test "blob GC keeps bodies a plugin still uses" do
      user = user_fixture()
      {:ok, used} = Drive.add_file(user, nil, tmp_upload("a product image"), "p.png")
      {:ok, orphan} = Drive.add_file(user, nil, tmp_upload("nobody wants me"), "o.txt")
      {:ok, _} = Drive.delete_file(user, used.id)
      {:ok, _} = Drive.delete_file(user, orphan.id)

      Application.put_env(:bacon8, :fixture_storage_refs, [used.blob_sha256])
      assert {:ok, refs} = Plugins.storage_refs()
      assert MapSet.member?(refs, used.blob_sha256)

      assert Drive.gc_blobs(-1) == 1
      assert Storage.exists?(used.blob_sha256)
      refute Storage.exists?(orphan.blob_sha256)
    end

    test "if a plugin can't list its blobs, GC deletes nothing" do
      user = user_fixture()
      {:ok, orphan} = Drive.add_file(user, nil, tmp_upload("orphan"), "o.txt")
      {:ok, _} = Drive.delete_file(user, orphan.id)

      Application.put_env(:bacon8, :extra_plugins, [CrashingPlugin, FixturePlugin])
      assert {:error, "crashing_plugin"} = Plugins.storage_refs()
      assert Drive.gc_blobs(-1) == 0
      assert Storage.exists?(orphan.blob_sha256)
    end

    test "raw-body paths come from installed plugins, active or not" do
      refute Plugins.active?("fixture_plugin")
      assert "/api/fixture/hooks/" in Plugins.raw_body_paths()
    end
  end

  describe "display hooks come from active plugins only" do
    test "nav links, profile tabs, admin tools and dashboard" do
      refute Enum.any?(Plugins.nav_links(nil), &(&1.label == "Fixture Shop"))
      assert Plugins.admin_dashboard() |> Map.get(:stats) |> Enum.all?(&(&1.label != "Fixture things"))

      {:ok, _} = Plugins.activate("fixture_plugin")

      assert %{path: "/fixture"} = Enum.find(Plugins.nav_links(nil), &(&1.label == "Fixture Shop"))
      assert %{path: "/fixture/orders"} = Enum.find(Plugins.profile_tabs(user_fixture()), &(&1.label == "Fixture Orders"))
      assert %{run: run} = Enum.find(Plugins.admin_tools(), &(&1.id == "fixture_tool"))
      assert {:ok, %{message: "hello"}} = run.(%{}, nil)

      %{stats: stats, panels: panels} = Plugins.admin_dashboard()
      assert %{value: 7} = Enum.find(stats, &(&1.label == "Fixture things"))
      assert %{items: [%{title: "One"}]} = Enum.find(panels, &(&1.title == "Fixture panel"))
    end

    test "a display hook that crashes is skipped, not fatal" do
      Application.put_env(:bacon8, :extra_plugins, [CrashingPlugin, FixturePlugin])
      Application.put_env(:bacon8, :default_active_plugins, ["crashing_plugin"])
      on_exit(fn -> Application.put_env(:bacon8, :default_active_plugins, []) end)
      Plugins.refresh_cache()

      assert Plugins.active?("crashing_plugin")
      assert is_list(Plugins.nav_links(nil))
      assert %{stats: _, panels: _} = Plugins.admin_dashboard()
    end
  end

  describe "routes DSL" do
    test "site, site_api and fixed blocks are stored with their options, in order" do
      [{routes, _}] =
        Code.compile_string("""
        defmodule Bacon8.PluginHooksTest.SiteWeb.Routes do
          use Bacon8.Plugin.Routes

          site do
            live "/", ShopLive, :index
          end

          site pipe_through: :drive_files do
            get "/media/:id", FileController, :media
          end

          site_api pipe_through: :webhooks do
            post "/hooks/:provider", HookController, :create
          end

          fixed reason: "an outside service still calls the old URL", pipe_through: :webhooks do
            post "/api/old/hooks/:provider", HookController, :create
          end
        end
        """)

      assert [{[], _}, {[pipe_through: :drive_files], _}] = routes.__site_routes__()
      assert [{[pipe_through: :webhooks], _}] = routes.__site_api_routes__()
      assert [{opts, _}] = routes.__fixed_routes__()
      assert opts[:reason] =~ "outside service"
      assert routes.__namespace__() == Bacon8.PluginHooksTest.SiteWeb
    end

    test "a fixed block without a reason is a compile error" do
      code = """
      defmodule Bacon8.PluginHooksTest.NoReason do
        use Bacon8.Plugin.Routes
        fixed pipe_through: :api do
          get "/x", X, :x
        end
      end
      """

      assert_raise ArgumentError, ~r/reason/, fn -> Code.compile_string(code) end
    end
  end
end
