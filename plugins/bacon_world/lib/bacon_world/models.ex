defmodule BaconWorld.Models do
  @moduledoc """
  Character models players can pick from.

  Models are the hub's static files under `priv/static/models` (served at
  `/models/...`, mounted from a volume in production), not part of this
  plugin. A `supported_models.txt` manifest there, one relative path per
  line, limits the list; without it, hashed duplicates are hidden.

  Environment:

    * `MAX_CHARACTER_MODELS` - cap on the list (default 48)
    * `ENABLE_BUILTIN_MODELS` - `true` to offer three procedural models when
      no model files are installed

  The folders searched can be overridden (tests point this at a fixture):

      config :bacon8, BaconWorld.Models, roots: ["/path/to/models"]
  """

  @valid_extensions [".glb", ".gltf", ".fbx"]
  @preferred_extensions [".glb", ".gltf"]
  @default_max 48
  @manifest "supported_models.txt"
  @builtin [
    %{label: "Builtin/Explorer", model_path: "builtin://explorer"},
    %{label: "Builtin/Sentinel", model_path: "builtin://sentinel"},
    %{label: "Builtin/Runner", model_path: "builtin://runner"}
  ]

  @doc "Models as `%{label, model_path}`, preferred formats first."
  def list do
    models =
      roots()
      |> Enum.flat_map(fn root ->
        root
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&(File.regular?(&1) and valid_file?(&1)))
        |> Enum.map(fn abs ->
          rel = abs |> Path.relative_to(root) |> String.replace("\\", "/")
          %{label: rel, relative_path: rel, model_path: "/models/" <> rel, extension: rel |> Path.extname() |> String.downcase()}
        end)
      end)
      |> Enum.uniq_by(& &1.model_path)

    curated =
      models
      |> filter_supported()
      |> prioritize()
      |> Enum.sort_by(& &1.label)
      |> Enum.take(max_models())
      |> Enum.map(&Map.take(&1, [:label, :model_path]))

    if curated == [] and builtin_enabled?(), do: @builtin, else: curated
  end

  @doc """
  `{:ok, path}` when `path` is a model a player may pick: an installed model
  file allowed by the manifest (or a built-in one, when enabled).

  Checks the one requested file rather than rebuilding `list/0`, which walks
  every model folder; it ignores `MAX_CHARACTER_MODELS`, which only limits how
  many the picker shows.
  """
  def validate("builtin://" <> _ = path) do
    if builtin_enabled?() and Enum.any?(@builtin, &(&1.model_path == path)),
      do: {:ok, path},
      else: {:error, :invalid_model_path}
  end

  def validate("/models/" <> rel = path) do
    segments = String.split(rel, "/")

    allowed? =
      rel != "" and not String.contains?(rel, ["\\", "\0"]) and
        Enum.all?(segments, &(&1 not in ["", ".", ".."])) and
        valid_file?(rel) and supported?(rel) and
        Enum.any?(roots(), &File.regular?(Path.join(&1, rel)))

    if allowed?, do: {:ok, path}, else: {:error, :invalid_model_path}
  end

  def validate(_), do: {:error, :invalid_model_path}

  @doc """
  What the 3D client needs to dress the Bacon8 humans, read from the models folder:

    * `"bodies"` - `Humans/Male.json` and `Humans/Female.json` (which body regions
      each garment hides, material roles, morph names)
    * `"hair"` - the `"styles"` of `Humans/Hair/hair_manifest.json` (hair and facial
      hair per body, with thumbnails)
    * `"versions"` - `asset_versions/0`, for the model URLs

  The client can't fetch these itself: `/models` serves only runtime formats
  (invariant 17), not `.json`. Missing or unreadable files are left out.
  """
  def human_assets do
    bodies =
      Enum.reduce([{"Male", "Humans/Male.json"}, {"Female", "Humans/Female.json"}], %{}, fn {key, rel}, acc ->
        case read_json(rel) do
          %{} = manifest -> Map.put(acc, key, Map.take(manifest, ~w(regions hides slots colors morphs materials)))
          _ -> acc
        end
      end)

    hair =
      case read_json("Humans/Hair/hair_manifest.json") do
        %{"styles" => styles} when is_map(styles) -> styles
        _ -> %{}
      end

    %{"bodies" => bodies, "hair" => hair, "versions" => asset_versions()}
  end

  @versioned_dirs ~w(Humans World Weapons Mobs)
  @versioned_exts ~w(.glb .gltf .png .jpg .jpeg .webp .ktx2)

  @doc """
  A short version for every model, texture and thumbnail the 3D client loads
  (`%{"Humans/Male.glb" => "5f1c09a2", ...}`), from each file's size and
  modification time. The client adds it to the URL (`?vsn=5f1c09a2`, which Plug.Static
  caches as immutable), so an
  updated model is fetched again even though `/models` lets browsers cache files
  for a day; an unchanged one stays cached.
  """
  def asset_versions do
    # The first root that has a file wins, as when the file is served.
    roots()
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn root, acc -> Map.merge(acc, versions_in(root)) end)
  end

  defp versions_in(root) do
    for dir <- @versioned_dirs,
        abs <- Path.wildcard(Path.join([root, dir, "**", "*"])),
        (abs |> Path.extname() |> String.downcase()) in @versioned_exts,
        {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} <- [File.stat(abs, time: :posix)],
        into: %{} do
      rel = abs |> Path.relative_to(root) |> String.replace("\\", "/")
      hash = :crypto.hash(:sha256, "#{rel}:#{size}:#{mtime}") |> Base.encode16(case: :lower) |> binary_part(0, 8)
      {rel, hash}
    end
  end

  @doc "Hair and facial hair style ids per body type (`male`/`female`), from the hair manifest."
  def human_style_ids(assets \\ nil) do
    hair = (assets || human_assets())["hair"] || %{}

    for {key, body} <- [{"Male", "male"}, {"Female", "female"}], into: %{} do
      entry = hair[key] || %{}
      ids = fn kind -> for(%{"id" => id} <- List.wrap(entry[kind]), is_binary(id), do: id) end
      {body, %{"hair" => ids.("hair"), "facial" => ids.("facial")}}
    end
  end

  @max_manifest_bytes 512_000

  # A JSON file under a models root, or nil. Relative paths here are fixed strings,
  # never from a client.
  defp read_json(rel) do
    with path when is_binary(path) <- Enum.find_value(roots(), &existing(Path.join(&1, rel))),
         {:ok, %File.Stat{size: size}} when size <= @max_manifest_bytes <- File.stat(path),
         {:ok, body} <- File.read(path),
         {:ok, data} <- Jason.decode(body) do
      data
    else
      _ -> nil
    end
  end

  defp existing(path), do: if(File.regular?(path), do: path)

  defp supported?(rel) do
    supported = manifest()
    if MapSet.size(supported) == 0, do: not hashed_variant?(%{relative_path: rel}), else: MapSet.member?(supported, rel)
  end

  defp roots do
    case Application.get_env(:bacon8, __MODULE__, [])[:roots] do
      nil -> default_roots()
      roots -> roots
    end
    |> Enum.filter(&File.dir?/1)
    # The same folder is often reachable by several of these paths (the build's
    # priv is a symlink to the source priv in development); scan it once.
    |> Enum.uniq_by(&folder_identity/1)
  end

  defp default_roots do
    [
      Application.app_dir(:bacon8, "priv/static/models"),
      Path.expand("priv/static/models", File.cwd!()),
      "/app/priv/static/models"
      | Path.wildcard("/app/lib/bacon8-*/priv/static/models")
    ]
  end

  # {device, inode} where the filesystem reports one; some (Windows mounts) report 0.
  defp folder_identity(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode, major_device: dev}} when inode > 0 -> {dev, inode}
      _ -> Path.expand(path)
    end
  end

  defp valid_file?(path), do: (path |> Path.extname() |> String.downcase()) in @valid_extensions

  defp max_models do
    with value when is_binary(value) <- System.get_env("MAX_CHARACTER_MODELS"),
         {n, _} when n > 0 <- Integer.parse(value) do
      n
    else
      _ -> @default_max
    end
  end

  defp filter_supported(models) do
    supported = manifest()

    if MapSet.size(supported) == 0,
      do: Enum.reject(models, &hashed_variant?/1),
      else: Enum.filter(models, &MapSet.member?(supported, &1.relative_path))
  end

  defp prioritize(models) do
    {preferred, rest} = Enum.split_with(models, &(&1.extension in @preferred_extensions))
    preferred ++ rest
  end

  defp builtin_enabled?, do: System.get_env("ENABLE_BUILTIN_MODELS") in ["1", "true", "TRUE", "yes", "YES"]

  defp hashed_variant?(model), do: String.match?(model.relative_path, ~r/-[0-9a-f]{12,}\.(fbx|gltf|glb)$/i)

  defp manifest do
    case roots() |> Enum.map(&Path.join(&1, @manifest)) |> Enum.find(&File.exists?/1) do
      nil ->
        MapSet.new()

      path ->
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
        |> MapSet.new()
    end
  end
end
