defmodule Bacon8.Plugins.Discovery do
  @moduledoc """
  Finds installed plugins by scanning `plugins/*/` in the source tree. Used at
  COMPILE time only (by `Bacon8.Plugins` and the router): a release does not
  ship the source tree, so nothing may call this at runtime in production.

  Each folder whose name is a valid slug and that has `lib/<slug>/plugin.ex` is
  a plugin, and its main module is `<Camelized slug>.Plugin`
  (`plugins/web_lobby` -> `WebLobby.Plugin`).

  Other folders are ignored: names that aren't slugs (`_template`,
  `README.md`), and folders without a `plugin.ex`, such as an empty or
  half-finished clone of a private plugin. Those print a warning on stderr
  (not a compiler warning, so `--warnings-as-errors` builds still pass) rather
  than breaking the whole hub's build.
  """

  # lib/bacon8/plugins/discovery.ex -> project root
  @root Path.expand("../../..", __DIR__)

  def root, do: @root
  def plugins_dir, do: Path.join(@root, "plugins")

  @doc "[%{slug, dir, module}] for every plugin folder, sorted by slug."
  def discover(dir \\ plugins_dir()) do
    dir
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(fn path -> {Path.basename(path), path} end)
    |> Enum.filter(fn {slug, _} -> Regex.match?(Bacon8.Plugin.slug_format(), slug) end)
    |> Enum.filter(fn {slug, path} -> complete?(slug, path) end)
    |> Enum.sort()
    |> Enum.map(fn {slug, path} ->
      %{slug: slug, dir: path, module: Module.concat([Macro.camelize(slug), "Plugin"])}
    end)
  end

  def slugs(dir \\ plugins_dir()), do: Enum.map(discover(dir), & &1.slug)

  defp complete?(slug, path) do
    main = Path.join([path, "lib", slug, "plugin.ex"])

    if File.regular?(main) do
      true
    else
      warn_once(path, "warning: plugins/#{slug} has no lib/#{slug}/plugin.ex; skipping it (an empty or unfinished clone?)")
      false
    end
  end

  # Discovery runs several times per compile (Bacon8.Plugins and each router
  # macro); say it once per VM.
  defp warn_once(path, message) do
    key = {__MODULE__, :warned, path}

    unless :persistent_term.get(key, false) do
      :persistent_term.put(key, true)
      IO.puts(:stderr, message)
    end
  end
end
