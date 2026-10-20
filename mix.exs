defmodule Bacon8.MixProject do
  use Mix.Project

  def project do
    [
      app: :bacon8,
      version: "0.1.0",
      elixir: "~> 1.19.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Plugins' own tests run with the core suite (BACON8.md §9).
      test_paths: ["test" | plugin_paths("test")],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      # Optimize compilation
      consolidate_protocols: Mix.env() != :dev,
      build_embedded: Mix.env() == :prod,
      compilers: Mix.compilers(),
      # Suppress warnings from dependencies (not our code)
      # Only treat warnings as errors in dev/test, not in prod builds
      elixirc_options: [
        warnings_as_errors: Mix.env() in [:dev, :test]
      ]
    ]
  end

  def application do
    [
      mod: {Bacon8.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"] ++ plugin_paths("lib") ++ plugin_paths("test/support")
  defp elixirc_paths(_), do: ["lib" | plugin_paths("lib")]

  # Installed plugins are folders under plugins/ (BACON8.md §9). Returns
  # plugins/<slug>/<sub> for each plugin that has it. Same rules as
  # Bacon8.Plugins.Discovery: the folder name must be a valid slug (so
  # "_template" is skipped) and lib/<slug>/plugin.ex must exist (so an empty
  # or half-finished clone is skipped rather than half-compiled).
  defp plugin_paths(sub) do
    "plugins/*/#{sub}"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(fn path ->
      slug = path |> Path.split() |> Enum.at(1)
      Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, slug) and File.regular?(Path.join(["plugins", slug, "lib", slug, "plugin.ex"]))
    end)
    |> Enum.sort()
  end

  # `mix bacon8.migrate`: every repo, core + plugin migration folders.
  # Use this instead of plain `mix ecto.migrate`, which only sees priv/.
  defp migrate_all(args) do
    for {repo, dir} <- [{"Bacon8.Repo", "repo"}, {"Bacon8.GamesRepo", "games_repo"}] do
      paths = ["priv/#{dir}/migrations" | plugin_paths("priv/#{dir}/migrations")]
      Mix.Task.reenable("ecto.migrate")
      Mix.Task.run("ecto.migrate", ["-r", repo] ++ Enum.flat_map(paths, &["--migrations-path", &1]) ++ args)
    end
  end

  # Release step: plugins' priv/ (migrations, assets) is not part of the OTP app,
  # so copy it into the release where Bacon8.Plugins.migration_paths/1 looks.
  defp copy_plugin_priv(%Mix.Release{} = release) do
    vsn = to_string(release.applications[:bacon8][:vsn])
    dest_root = Path.join([release.path, "lib", "bacon8-#{vsn}", "priv", "plugins"])

    for src <- plugin_paths("priv") do
      slug = src |> Path.split() |> Enum.at(1)
      File.mkdir_p!(dest_root)
      File.cp_r!(src, Path.join(dest_root, slug))
    end

    release
  end

  defp deps do
    [
      {:phoenix, "~> 1.7.18"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, "~> 0.36.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.5"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.16"},
      {:gen_smtp, "~> 1.2"},
      {:finch, "~> 0.18"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:gettext, "~> 0.26"},
  {:jason, "~> 1.4"},
      {:joken, "~> 2.6"},
      {:guardian, "~> 2.3"},
      {:plug_cowboy, "~> 2.7"},
      {:redix, "~> 1.5"},
      {:pbkdf2_elixir, "~> 2.2"},
      ## E-commerce & Payments
      #{:stripity_stripe, "~> 3.0"},
      #{:decimal, "~> 2.0"},
      # File uploads
      {:arc, "~> 0.11"},
      {:arc_ecto, "~> 0.11"},
      ## 2FA
      #{:pot, "~> 1.0"},
      #{:qr_code, "~> 3.1"},
      ## File handling
      {:mime, "~> 2.0"},
      # Caching
      {:cachex, "~> 3.4"},
      # Additional utilities
      {:uuid, "~> 1.1"},
      {:cors_plug, "~> 3.0"},
      {:tz, "~> 0.24"},
      {:httpoison, "~> 2.0"},
  {:csv, "~> 3.0"},
      {:libcluster, "~> 3.3"},

      # Linting and security tools
  {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
  {:sobelow, "~> 0.12", only: :dev, runtime: false},
  {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false}

    ]
  end

  defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
    "ecto.setup": ["ecto.create", "bacon8.migrate", "run priv/repo/seeds.exs"],
    "bacon8.migrate": &migrate_all/1,
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "bacon8.migrate --quiet", "test"],

    # Frontend asset tasks using npm instead of mix tailwind
  "assets.setup": ["cmd --cd assets ../scripts/dev-assets.sh ci"],
  "assets.build": ["cmd --cd assets ../scripts/dev-assets.sh build"],
  "assets.deploy": ["cmd --cd assets ../scripts/dev-assets.sh run deploy", "phx.digest"],
    # Lint alias for CI
  lint: ["format --check-formatted", "cmd --cd assets ../scripts/dev-assets.sh run lint", "cmd --cd assets ../scripts/dev-assets.sh run type-check", "credo --strict", "sobelow --exit", "dialyzer"]
  ]
  end

  defp releases do
    [
      bacon8: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, &copy_plugin_priv/1, :tar]
      ]
    ]
  end
end