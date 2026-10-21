defmodule Bacon8.Release do
  @moduledoc """
  DB release tasks, for production where Mix is not installed.

  ## Why `create_db` used to do nothing on a live box

  `storage_up/1` answers `{:error, :already_up}` when the database is already
  there. That is the NORMAL answer on any server that has run before. The old
  code matched it against `:ok =`, so the very first repo raised a MatchError
  and the loop died — and because `Bacon8.Repo` is first in `:ecto_repos`,
  `Bacon8.GamesRepo` was never reached on any box that already had a main
  database.

  The result was a task that appeared to run, appeared to fail for a boring
  reason, and silently never created the games database at all:

      FATAL 3D000 (invalid_catalog_name) database "bacon8_games_prod" does not exist

  repeating once per connection-pool member, forever. Adding a repo to
  `:ecto_repos` is supposed to be all it takes; it was, everywhere except here.
  """
  @app :bacon8

  @doc """
  Create storage for every configured repo.

  Idempotent on purpose — this is run on deploy, when most repos already exist.
  """
  def create_db do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config) do
        :ok ->
          log("created storage for #{inspect(repo)}")

        {:error, :already_up} ->
          log("storage for #{inspect(repo)} already exists")

        # A real failure — bad credentials, no CREATE DATABASE grant, host
        # unreachable. Loud, because the alternative is what happened here:
        # an application that boots and then cannot answer a single query.
        {:error, reason} ->
          raise "could not create storage for #{inspect(repo)}: #{inspect(reason)}"
      end
    end

    :ok
  end

  @doc """
  Run all pending migrations for every configured repo.

  Reports per repo, because the deploy job wraps this in a retry loop whose
  `if` swallows the exit status - so a failure here prints "Migration attempt 1
  failed" and nothing about WHY. If a repo has no migration files at all it says
  so instead of succeeding quietly, which is the failure that looks most like
  everything having worked.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      path = Ecto.Migrator.migrations_path(repo)
      files = Path.wildcard(Path.join(path, "*.exs"))

      log("migrating #{inspect(repo)} from #{path} (#{length(files)} migration files)")

      if files == [] do
        log("  !! no migration files found - this repo will never gain a schema")
      end

      # Installed plugins' migrations (BACON8.md §9) run with the core ones.
      plugin_paths = Bacon8.Plugins.migration_paths(repo)
      for p <- plugin_paths, do: log("  + plugin migrations from #{p}")

      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, [path | plugin_paths], :up, all: true)) do
        {:ok, versions, _} ->
          log("  #{inspect(repo)}: applied #{length(versions)} migration(s)")

        {:error, reason} ->
          # Raised, not returned: the caller is a deploy step, and a migration
          # that failed must not look like one that had nothing to do.
          raise "migrating #{inspect(repo)} failed: #{inspect(reason)}"
      end
    end

    :ok
  end

  @doc """
  The migrations not yet run, as `[{repo, version, name}]` across every repo
  and every installed plugin's folder (the same set `migrate/0` runs), or
  `:unavailable` when a database can't be reached or doesn't exist yet.
  """
  def pending_migrations do
    load_app()

    Enum.reduce_while(repos(), [], fn repo, acc ->
      case pending_for(repo) do
        {:ok, pending} -> {:cont, acc ++ pending}
        :unavailable -> {:halt, :unavailable}
      end
    end)
  end

  defp pending_for(repo) do
    paths = [Ecto.Migrator.migrations_path(repo) | Bacon8.Plugins.migration_paths(repo)]

    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.migrations(&1, paths)) do
      {:ok, migrations, _} ->
        {:ok, for({:down, version, name} <- migrations, do: {repo, version, name})}

      {:error, _} ->
        :unavailable
    end
  rescue
    # No database yet (a fresh namespace, before db-init creates it), or not
    # accepting connections.
    _ -> :unavailable
  catch
    :exit, _ -> :unavailable
  end

  @doc """
  Block until no migration is pending, then return `:ok`.

  The web pods' init container runs this (`k3s/base/bacon8-deployment.yaml`),
  so a pod only starts the app once `db-init` has migrated both databases. Both
  start together on a deploy, and without this the new code could serve
  requests against the old schema for a few seconds, or create rows (a plugin's
  game row) that a migration renaming stored names then has to merge
  (BACON8.md §5, invariant 14). A restart with nothing new to run passes
  straight through; a new image whose migrations were never run waits here
  while the old pods keep serving.
  """
  def await_migrations(interval_ms \\ 3_000) do
    case pending_migrations() do
      [] ->
        log("no pending migrations; starting")
        :ok

      :unavailable ->
        log("database not reachable yet; waiting")
        Process.sleep(interval_ms)
        await_migrations(interval_ms)

      pending ->
        names = Enum.map_join(pending, ", ", fn {_repo, version, name} -> "#{version}_#{name}" end)
        log("waiting for db-init: #{length(pending)} pending (#{names})")
        Process.sleep(interval_ms)
        await_migrations(interval_ms)
    end
  end

  @doc """
  Print what each repo is pointed at and what it still has to run.

  A diagnostic, safe to run any time. Exists because "relation does not exist"
  in prod has at least three causes that look identical from the outside - the
  database is missing, the migrations never ran, or the migration FILES are not
  in the release - and this distinguishes them in one command.
  """
  def status do
    load_app()

    for repo <- repos() do
      config = repo.config()
      path = Ecto.Migrator.migrations_path(repo)
      files = Path.wildcard(Path.join(path, "*.exs"))

      IO.puts("")
      IO.puts("== #{inspect(repo)}")
      IO.puts("   database : #{config[:database] || "(from url)"}")
      IO.puts("   priv     : #{config[:priv] || "(default)"}")
      IO.puts("   path     : #{path}")
      IO.puts("   files    : #{length(files)}")

      if files == [] do
        IO.puts("   !! No migration files at that path. Nothing will ever be migrated,")
        IO.puts("      and `migrate` will report success because it had nothing to do.")
      end

      plugin_paths = Bacon8.Plugins.migration_paths(repo)
      for p <- plugin_paths, do: IO.puts("   plugin   : #{p}")

      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.migrations(&1, [path | plugin_paths])) do
        {:ok, migrations, _} ->
          {applied, pending} = Enum.split_with(migrations, fn {status, _, _} -> status == :up end)

          IO.puts("   applied  : #{length(applied)}")
          IO.puts("   pending  : #{length(pending)}")

          for {_, version, name} <- pending do
            IO.puts("      pending -> #{version}_#{name}")
          end

        {:error, reason} ->
          IO.puts("   !! cannot connect or inspect: #{inspect(reason)}")
      end
    end

    IO.puts("")
    :ok
  end

  @doc """
  Create anything missing, then migrate. The one command a deploy should call.

  Two separate steps invite half a deploy: `create_db` on its own leaves empty
  databases, and `migrate` on its own fails against a database nobody made.
  """
  def setup do
    create_db()
    migrate()
  end

  def rollback(repo, version) do
    load_app()
    paths = [Ecto.Migrator.migrations_path(repo) | Bacon8.Plugins.migration_paths(repo)]
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, paths, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  # IO.puts rather than Logger: this runs before the app starts, so the logger
  # backends are not necessarily configured yet and the output would vanish —
  # which is the failure mode this whole module is about.
  defp log(message), do: IO.puts("[release] " <> message)
end
