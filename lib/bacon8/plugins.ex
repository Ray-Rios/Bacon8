defmodule Bacon8.Plugins do
  @moduledoc """
  Installed and active plugins (BACON8.md §9).

    * **Installed** - every folder under `plugins/` at compile time. Their code
      is compiled, their routes are in the router, and their migrations run.
    * **Active** - chosen by an admin on /admin/plugins and stored in the
      `plugin_states` table (`Bacon8.Plugins.State`), one row per plugin. Only
      active plugins serve requests, run processes, and appear in menus and the
      games list. Inactive plugins' routes answer 404.

  A plugin with no row yet (never toggled) is active if its slug is in
  `config :bacon8, :default_active_plugins`.

  Each node caches the active set in `:persistent_term` (see
  `Bacon8.Plugins.Runtime`); `activate/2` and `deactivate/2` update the
  database and broadcast so every node refreshes and starts or stops the
  plugin's processes.
  """

  require Logger
  import Ecto.Query, only: [from: 2]

  alias Bacon8.Repo
  alias Bacon8.Plugins.{Discovery, State}

  @topic "bacon8:plugins"
  @cache_key {__MODULE__, :active}

  # Compile-time snapshot of plugins/*; recompiled when the folders change.
  @discovered Discovery.discover()
  for %{dir: dir} <- @discovered, do: @external_resource(dir)

  @doc false
  def __mix_recompile__?, do: Discovery.slugs() != Enum.map(@discovered, & &1.slug)

  def topic, do: @topic

  # ---------------------------------------------------------------------------
  # Installed
  # ---------------------------------------------------------------------------

  @doc "Main modules of every installed plugin (compiled in), plus test fixtures from config."
  def installed do
    discovered = Enum.map(@discovered, & &1.module)
    extra = Application.get_env(:bacon8, :extra_plugins, [])

    (discovered ++ extra)
    |> Enum.uniq()
    |> Enum.filter(&plugin_module?/1)
  end

  @doc "The installed plugin with this slug, or nil."
  def get(slug) when is_binary(slug), do: Enum.find(installed(), &(&1.slug() == slug))
  def get(_), do: nil

  @doc "Admin listing: one map per installed plugin."
  def list do
    active = active_slugs()

    for mod <- installed() do
      %{
        slug: mod.slug(),
        name: mod.name(),
        version: mod.version(),
        description: mod.description(),
        module: mod,
        game: game_info(mod),
        active?: MapSet.member?(active, mod.slug())
      }
    end
  end

  defp plugin_module?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :slug, 0) and function_exported?(mod, :on_activate, 0)
  end

  # ---------------------------------------------------------------------------
  # Active
  # ---------------------------------------------------------------------------

  @doc "True when the plugin with this slug is installed and active."
  def active?(slug), do: MapSet.member?(active_slugs(), slug)

  @doc "Active plugin modules."
  def active, do: Enum.filter(installed(), &active?(&1.slug()))

  @doc "Active slugs (cached; loads on first use)."
  def active_slugs do
    case :persistent_term.get(@cache_key, :unset) do
      :unset -> refresh_cache()
      set -> set
    end
  end

  @doc "Re-reads the active set from the database into this node's cache."
  def refresh_cache do
    installed = MapSet.new(installed(), & &1.slug())
    set = load_active_slugs() |> MapSet.new() |> MapSet.intersection(installed)
    :persistent_term.put(@cache_key, set)
    set
  end

  @doc "Activates an installed plugin. `actor` is the admin, for the log."
  def activate(slug, actor \\ nil), do: set_active(slug, true, actor)

  @doc "Deactivates a plugin."
  def deactivate(slug, actor \\ nil), do: set_active(slug, false, actor)

  defp set_active(slug, on?, actor) do
    case get(slug) do
      nil ->
        {:error, :not_installed}

      mod ->
        with :ok <- check_requirements(mod, on?) do
          run_toggle(mod, slug, on?, actor)
        end
    end
  end

  # Activating needs every required plugin active; deactivating must not strand
  # an active plugin that requires this one.
  defp check_requirements(mod, true) do
    case Enum.reject(mod.requires(), &active?/1) do
      [] -> :ok
      missing -> {:error, {:requires, missing}}
    end
  end

  defp check_requirements(mod, false) do
    slug = mod.slug()

    case for(other <- active(), other.slug() != slug, slug in other.requires(), do: other.slug()) do
      [] -> :ok
      dependents -> {:error, {:required_by, dependents}}
    end
  end

  @doc "Slugs this plugin needs, and which of them are inactive now."
  def requirements(mod) do
    required = mod.requires()
    %{requires: required, missing: Enum.reject(required, &active?/1)}
  end

  @doc "Active plugins that require this one (they block deactivating it)."
  def required_by(slug) do
    for other <- active(), other.slug() != slug, slug in other.requires(), do: other.slug()
  end

  defp run_toggle(mod, slug, on?, actor) do
    hook_result = if on?, do: mod.on_activate(), else: mod.on_deactivate()

    case hook_result do
      :ok ->
        save_state!(slug, on?, actor)
        Bacon8.Audit.log(actor_id(actor), if(on?, do: "plugin.activated", else: "plugin.deactivated"), "plugin", nil, %{slug: slug})
        sync_game(mod, on?)
        refresh_cache()
        Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, :plugins_changed)

        Logger.info("Plugin #{slug} #{if on?, do: "activated", else: "deactivated"} by #{actor_label(actor)}")
        {:ok, mod}

      {:error, reason} ->
        {:error, {:hook_failed, reason}}
    end
  end

  # Saved rows win; plugins never toggled fall back to the configured defaults.
  defp load_active_slugs do
    saved = Repo.all(from s in State, select: {s.slug, s.active}) |> Map.new()
    load_from(saved)
  rescue
    # No database or table yet (first boot before migrating, test sandbox not
    # checked out): defaults only.
    e ->
      Logger.debug("Plugins: could not read plugin_states (#{Exception.message(e)}); using defaults")
      load_from(%{})
  end

  defp load_from(saved) do
    defaults = MapSet.new(Application.get_env(:bacon8, :default_active_plugins, []))

    wanted =
      for mod <- installed(),
          slug = mod.slug(),
          Map.get(saved, slug, MapSet.member?(defaults, slug)),
          do: mod

    wanted |> drop_unmet_requirements() |> Enum.map(& &1.slug())
  end

  # A plugin whose required plugins aren't active can't be active either (they
  # may have been switched on by default or by a saved row). Repeats until
  # stable, so a chain of requirements resolves.
  defp drop_unmet_requirements(mods) do
    slugs = MapSet.new(mods, & &1.slug())
    {kept, dropped} = Enum.split_with(mods, fn mod -> Enum.all?(mod.requires(), &MapSet.member?(slugs, &1)) end)

    for mod <- dropped do
      Logger.warning("Plugin #{mod.slug()} is not active: it requires #{Enum.join(mod.requires() -- MapSet.to_list(slugs), ", ")}")
    end

    if dropped == [], do: kept, else: drop_unmet_requirements(kept)
  end

  defp save_state!(slug, on?, actor) do
    now = DateTime.utc_now()
    actor_id = actor_id(actor)

    Repo.insert!(
      %State{slug: slug, active: on?, changed_by_id: actor_id, inserted_at: now, updated_at: now},
      on_conflict: [set: [active: on?, changed_by_id: actor_id, updated_at: now]],
      conflict_target: :slug
    )
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_), do: nil

  defp actor_label(%{id: id}), do: id
  defp actor_label(_), do: "system"

  # ---------------------------------------------------------------------------
  # Games
  # ---------------------------------------------------------------------------

  @doc "The plugin's game with defaults filled in (`:slug` defaults to the plugin slug), or nil."
  def game_info(mod) do
    case mod.game() do
      %{} = g -> Map.put_new(g, :slug, mod.slug()) |> Map.put_new(:description, "")
      _ -> nil
    end
  end

  @doc """
  The entitlement kinds that belong to game `game_slug` (2026-10-29, for `/api/games/:slug/entitlements`):
  what its plugin declares in `entitlement_kinds/0`. Store items for a game are granted under kinds
  named after it, so any kind starting with the game's slug (`bacon_world_mount`) is its too.
  Returns `{kinds, prefixes}`.
  """
  def game_entitlement_kinds(game_slug) when is_binary(game_slug) do
    mod = Enum.find(installed(), fn m -> match?(%{slug: ^game_slug}, game_info(m)) end)
    prefixes = Enum.uniq([game_slug, String.replace(game_slug, "-", "_")] ++ if(mod, do: [mod.slug()], else: []))
    {if(mod, do: mod.entitlement_kinds(), else: []), prefixes}
  end

  @doc "Games of active plugins, for the games list."
  def active_games, do: active() |> Enum.map(&game_info/1) |> Enum.reject(&is_nil/1)

  @doc """
  The plugin's row in the `games` table, created if it is missing.

  `activate/2` registers the row, but a plugin that is active by default
  (`:default_active_plugins`) may never have been activated; plugins call this
  to get their game id, and `Bacon8.Plugins.Runtime` calls it at boot.
  """
  def ensure_game(slug) when is_binary(slug) do
    with mod when not is_nil(mod) <- get(slug),
         %{slug: game_slug, name: name} <- game_info(mod) do
      case Bacon8.Games.get_game_by_slug(game_slug) do
        nil ->
          case Bacon8.Games.create_game(%{slug: game_slug, name: name, is_active: active?(slug)}) do
            {:ok, game} -> {:ok, game}
            # Lost a race with another node or process: the row exists now.
            {:error, _} -> found_or_error(Bacon8.Games.get_game_by_slug(game_slug))
          end

        game ->
          {:ok, game}
      end
    else
      _ -> {:error, :no_game}
    end
  end

  defp found_or_error(nil), do: {:error, :no_game}
  defp found_or_error(game), do: {:ok, game}

  # Registers / enables the plugin's game row, or disables it on deactivation.
  defp sync_game(mod, on?) do
    with %{slug: game_slug, name: name} <- game_info(mod) do
      case Bacon8.Games.get_game_by_slug(game_slug) do
        nil when on? ->
          {:ok, _} = Bacon8.Games.create_game(%{slug: game_slug, name: name, is_active: true})

        nil ->
          :ok

        game ->
          game |> Bacon8.Games.Game.changeset(%{is_active: on?}) |> Bacon8.GamesRepo.update!()
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Hub events
  # ---------------------------------------------------------------------------

  @doc """
  Tells every installed plugin about a hub event (see `c:Bacon8.Plugin.hub_event/1`).
  Synchronous: when this returns, every plugin has handled it, so a caller
  that revokes access can rely on it being done. A plugin that raises is
  logged and skipped; the others still run.
  """
  def notify(event) when is_tuple(event) do
    for mod <- installed() do
      try do
        mod.hub_event(event)
      rescue
        e ->
          Logger.error("Plugin #{mod.slug()}: hub_event #{inspect(elem(event, 0))} failed: " <> Exception.format(:error, e, __STACKTRACE__))
      catch
        kind, reason ->
          Logger.error("Plugin #{mod.slug()}: hub_event #{inspect(elem(event, 0))} failed: #{inspect({kind, reason})}")
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Menus
  # ---------------------------------------------------------------------------

  @doc "Admin sidebar links from active plugins. A plugin's admin pages live under /admin/<slug>."
  def admin_nav, do: Enum.flat_map(active(), & &1.admin_nav())

  @doc "Start-menu apps from active plugins, for this user (nil when signed out)."
  def desktop_apps(user), do: collect(active(), :desktop_apps, [user])

  @doc "Site navigation and taskbar links from active plugins."
  def nav_links(user), do: collect(active(), :nav_links, [user])

  @doc "Profile-page links from active plugins."
  def profile_tabs(user), do: collect(active(), :profile_tabs, [user])

  @doc "API-toolbox actions from active plugins (see `c:Bacon8.Plugin.admin_tools/0`)."
  def admin_tools, do: collect(active(), :admin_tools, [])

  @doc "Admin dashboard stats and panels from active plugins, merged."
  def admin_dashboard do
    for mod <- active(), reduce: %{stats: [], panels: []} do
      acc ->
        case call(mod, :admin_dashboard, []) do
          {:ok, %{} = d} ->
            %{stats: acc.stats ++ Map.get(d, :stats, []), panels: acc.panels ++ Map.get(d, :panels, [])}

          _ ->
            acc
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Data hooks: asked of every INSTALLED plugin (an inactive plugin's data still
  # exists), and a plugin that crashes gets the safe answer
  # ---------------------------------------------------------------------------

  @doc """
  True if any installed plugin keeps records about this user that must
  outlive the account (`Bacon8.Accounts.delete_user/1` anonymises instead).
  A plugin that crashes counts as yes: keeping data is the safe mistake.
  """
  def retains_user_data?(user_id) do
    Enum.any?(installed(), fn mod ->
      case call(mod, :retains_user_data?, [user_id]) do
        {:ok, answer} -> answer == true
        :error -> true
      end
    end)
  end

  @doc """
  Storage keys installed plugins still use, for `Bacon8.Drive.gc_blobs/2`.
  `{:error, slug}` if a plugin crashes: the caller must then delete nothing.
  """
  def storage_refs do
    Enum.reduce_while(installed(), {:ok, MapSet.new()}, fn mod, {:ok, acc} ->
      case call(mod, :storage_refs, []) do
        {:ok, keys} when is_list(keys) -> {:cont, {:ok, MapSet.union(acc, MapSet.new(keys))}}
        _ -> {:halt, {:error, mod.slug()}}
      end
    end)
  end

  @doc "Path prefixes whose raw request body installed plugins need kept."
  def raw_body_paths, do: collect(installed(), :raw_body_paths, [])

  defp collect(mods, fun, args) do
    Enum.flat_map(mods, fn mod ->
      case call(mod, fun, args) do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end
    end)
  end

  defp call(mod, fun, args) do
    {:ok, apply(mod, fun, args)}
  rescue
    e ->
      Logger.error("Plugin #{mod.slug()}: #{fun} failed: " <> Exception.format(:error, e, __STACKTRACE__))
      :error
  catch
    kind, reason ->
      Logger.error("Plugin #{mod.slug()}: #{fun} failed: #{inspect({kind, reason})}")
      :error
  end

  # ---------------------------------------------------------------------------
  # Migrations
  # ---------------------------------------------------------------------------

  @repo_dirs %{Bacon8.Repo => "repo", Bacon8.GamesRepo => "games_repo"}

  @doc """
  Migration folders of every installed plugin for `repo` (active or not:
  a plugin's tables exist from install, as WordPress plugins' do from upload).

  In a release they are copied to `priv/plugins/<slug>/<repo>/migrations`
  by the release step in mix.exs; in development they are read from the
  source tree.
  """
  def migration_paths(repo) do
    case Map.fetch(@repo_dirs, repo) do
      {:ok, repo_dir} ->
        for %{slug: slug, dir: dir} <- @discovered,
            path = migration_dir(slug, dir, repo_dir),
            path != nil,
            do: path

      :error ->
        []
    end
  end

  @doc """
  The plugin's `priv/` folder: `priv/plugins/<slug>` inside a release (copied
  there by the release step in mix.exs), `plugins/<slug>/priv` in development.
  For files a plugin ships with, like data it reads at runtime.
  """
  def priv_dir(slug) when is_binary(slug) do
    released = Application.app_dir(:bacon8, Path.join(["priv", "plugins", slug]))

    source =
      case Enum.find(@discovered, &(&1.slug == slug)) do
        %{dir: dir} -> Path.join(dir, "priv")
        nil -> Path.join(["plugins", slug, "priv"])
      end

    if File.dir?(released), do: released, else: source
  end

  defp migration_dir(slug, source_dir, repo_dir) do
    released = Application.app_dir(:bacon8, Path.join(["priv", "plugins", slug, repo_dir, "migrations"]))
    source = Path.join([source_dir, "priv", repo_dir, "migrations"])

    cond do
      File.dir?(released) -> released
      File.dir?(source) -> source
      true -> nil
    end
  end
end
