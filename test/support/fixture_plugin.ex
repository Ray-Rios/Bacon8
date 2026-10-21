defmodule Bacon8.Test.FixturePlugin do
  @moduledoc "A plugin used only by the test suite (registered via config :extra_plugins)."
  use Bacon8.Plugin,
    slug: "fixture_plugin",
    name: "Fixture",
    version: "1.2.3",
    description: "Exercises the plugin API in tests."

  @impl true
  def game, do: %{name: "Fixture Game", path: "/games/fixture_plugin", description: "A test game"}

  @impl true
  def admin_nav, do: [%{label: "Fixture", path: "/admin/fixture", icon: "🧪"}]

  # Hooks run in the caller's process, so tests can observe them.
  @impl true
  def on_activate do
    send(self(), {:fixture_hook, :activated})
    :ok
  end

  @impl true
  def on_deactivate do
    send(self(), {:fixture_hook, :deactivated})
    :ok
  end

  @impl true
  def hub_event(event) do
    send(self(), {:fixture_hub_event, event})
    :ok
  end

  # Phase 2 hooks (ADR 0001). The data hooks answer from app config, so tests
  # can set them: :fixture_retains (user ids) and :fixture_storage_refs.
  @impl true
  def retains_user_data?(user_id), do: user_id in Application.get_env(:bacon8, :fixture_retains, [])

  @impl true
  def storage_refs, do: Application.get_env(:bacon8, :fixture_storage_refs, [])

  @impl true
  def nav_links(_user), do: [%{label: "Fixture Shop", path: "/fixture", icon: "🧪"}]

  @impl true
  def profile_tabs(_user), do: [%{label: "Fixture Orders", path: "/fixture/orders", icon: "🧾"}]

  @impl true
  def raw_body_paths, do: ["/api/fixture/hooks/"]

  @impl true
  def admin_tools do
    [%{id: "fixture_tool", name: "Fixture Tool", category: "fixture", category_label: "Fixture",
       method: "GET", path: "/api/fixture", description: "Says hello.", fields: [],
       run: fn _params, _admin -> {:ok, %{message: "hello"}} end}]
  end

  @impl true
  def admin_dashboard do
    %{stats: [%{label: "Fixture things", value: 7, icon: "🧪"}],
      panels: [%{title: "Fixture panel", empty: "None", items: [%{title: "One"}]}]}
  end
end

defmodule Bacon8.Test.RequiringPlugin do
  @moduledoc "A plugin that needs the fixture plugin active (`requires/0`)."
  use Bacon8.Plugin, slug: "requiring_plugin", name: "Requirer"

  @impl true
  def requires, do: ["fixture_plugin"]
end

defmodule Bacon8.Test.CrashingPlugin do
  @moduledoc "A plugin whose hub_event raises, to prove one plugin can't break the others."
  use Bacon8.Plugin, slug: "crashing_plugin", name: "Crasher"

  @impl true
  def hub_event(_event), do: raise("boom")

  @impl true
  def retains_user_data?(_user_id), do: raise("boom")
  @impl true
  def storage_refs, do: raise("boom")
  @impl true
  def nav_links(_user), do: raise("boom")
  @impl true
  def admin_dashboard, do: raise("boom")
end

defmodule Bacon8.Test.RefusingPlugin do
  @moduledoc "A plugin whose activation hook refuses."
  use Bacon8.Plugin, slug: "refusing_plugin", name: "Refuser"

  @impl true
  def on_activate, do: {:error, :missing_configuration}
end

defmodule Bacon8.Test.FixtureWeb.Routes do
  use Bacon8.Plugin.Routes

  api do
    get "/ping", PingController, :show
  end

  browser do
    live "/", PlayLive, :index
  end

  admin do
    live "/", AdminLive, :index
  end
end
