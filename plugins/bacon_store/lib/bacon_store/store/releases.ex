defmodule BaconStore.Store.Release do
  @moduledoc "A release of a plugin sold as a download (`BaconStore.Store.Releases`)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "store_product_releases" do
    belongs_to :product, BaconStore.Store.Product
    belongs_to :product_file, BaconStore.Store.ProductFile
    field :plugin, :string
    field :version, :string
    field :branch, :string
    field :commit, :string
    field :notes, :string
    field :built_at, :utc_datetime
    field :yanked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

defmodule BaconStore.Store.Releases do
  @moduledoc """
  Plugins sold in the store (2026-11-03): Bacon World, RaysSpaceSim or any other plugin, as a
  `download` product whose files are **releases cut from git release branches**.

  The branch is `release/<plugin>/<version>` (`branch_for/2`), in the hub's repository for a plugin
  the hub ships (`plugins/bacon_world`) or in the plugin's own repository for a private one
  (`plugins/rays_space_sim/.git`). `scripts/release/package_plugin.py` checks the branch out of git
  (`git archive`, so only committed, tracked files go in, never the working tree), refuses anything
  that looks like a secret, and adds `RELEASE.json`:

      {"plugin": "bacon_world", "version": "1.0.0", "branch": "release/bacon_world/1.0.0",
       "commit": "<40 hex>", "built_at": "2026-11-03T22:10:00Z", "notes": "..."}

  Uploading that zip on the product's admin page (Download files) recognises it (`read_manifest/1`)
  and records the release (`add_release/4`): the file is labelled with its version, and the
  release row keeps the branch and commit, so every sale can be traced to the exact source.
  Withdrawing a release (`yank/1`) takes its file away from buyers and keeps the record.

  The hub runs no git in production: releases are packaged where the repository is (the
  development PC) and uploaded.
  """

  import Ecto.Query
  alias Bacon8.Repo
  alias BaconStore.Store.{Catalog, Product, ProductFile, Release}

  @version ~r/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?\z/
  @slug ~r/\A[a-z][a-z0-9_]*\z/

  @doc "The git branch a release is cut on."
  def branch_for(plugin, version), do: "release/#{plugin}/#{version}"

  @doc """
  The release manifest inside a zip at `path`: `{:ok, map}`, `:none` (not a zip, or no
  RELEASE.json: an ordinary download) or `{:error, message}` (a manifest that doesn't add up).
  """
  def read_manifest(path) do
    with {:ok, files} <- :zip.unzip(String.to_charlist(path), [:memory, {:file_list, [~c"RELEASE.json"]}]),
         [{_, json}] <- files do
      case Jason.decode(json) do
        {:ok, %{} = m} -> validate(m)
        _ -> {:error, "RELEASE.json isn't valid JSON."}
      end
    else
      _ -> :none
    end
  rescue
    _ -> :none
  end

  defp validate(m) do
    plugin = m["plugin"]
    version = m["version"]

    cond do
      not (is_binary(plugin) and Regex.match?(@slug, plugin)) -> {:error, "RELEASE.json: \"plugin\" must be a plugin slug."}
      not (is_binary(version) and Regex.match?(@version, version)) -> {:error, "RELEASE.json: \"version\" must look like 1.2.3."}
      m["branch"] != branch_for(plugin, version) -> {:error, "RELEASE.json: the branch must be #{branch_for(plugin, version)}."}
      not (is_binary(m["commit"]) and Regex.match?(~r/\A[0-9a-f]{40}\z/, m["commit"])) -> {:error, "RELEASE.json: \"commit\" must be a full git commit id."}
      true -> {:ok, m}
    end
  end

  @doc """
  Records a release: stores the zip as one of `product`'s download files, labelled with the
  version, and the release row. A product sells one plugin: every release must name the same one.
  `{:ok, release}` or `{:error, message}`.
  """
  def add_release(%Product{kind: "download"} = product, path, filename, %{} = m) do
    existing = list(product)

    cond do
      Enum.any?(existing, &(&1.version == m["version"])) ->
        {:error, "Version #{m["version"]} is already released here."}

      Enum.any?(existing, &(&1.plugin != m["plugin"])) ->
        {:error, "This product sells #{hd(existing).plugin}, not #{m["plugin"]}."}

      true ->
        Repo.transaction(fn ->
          case Catalog.add_file(product, "download", path, filename, label: "v#{m["version"]}") do
            {:ok, file} ->
              %Release{
                product_id: product.id,
                product_file_id: file.id,
                plugin: m["plugin"],
                version: m["version"],
                branch: m["branch"],
                commit: m["commit"],
                notes: m["notes"] && String.slice(to_string(m["notes"]), 0, 4_000),
                built_at: parse_time(m["built_at"])
              }
              |> Repo.insert!()

            {:error, reason} ->
              Repo.rollback("Couldn't store the zip: #{inspect(reason)}")
          end
        end)
    end
  end

  def add_release(_product, _path, _filename, _m), do: {:error, "Releases belong to a download product."}

  @doc "A product's releases, newest version first."
  def list(%Product{id: id}) do
    Repo.all(from r in Release, where: r.product_id == ^id)
    |> Enum.sort(fn a, b -> Version.compare(a.version, b.version) != :lt end)
  end

  @doc "The newest release buyers can download, or nil."
  def latest(%Product{} = p), do: Enum.find(list(p), &is_nil(&1.yanked_at))

  @doc "Withdraws a release: its file leaves the product (buyers no longer see it); the record stays."
  def yank(%Release{} = r) do
    Repo.transaction(fn ->
      if r.product_file_id do
        case Repo.get(ProductFile, r.product_file_id) do
          nil -> :ok
          f -> Catalog.delete_file(f)
        end
      end

      r |> Ecto.Changeset.change(yanked_at: DateTime.utc_now() |> DateTime.truncate(:second), product_file_id: nil) |> Repo.update!()
    end)
  end

  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Release, uuid)
      :error -> nil
    end
  end

  @doc """
  A draft (off sale) download product for an installed plugin, at the card price given, or the
  existing one (`plugin-<slug>`). `{:ok, product}` or `{:error, changeset}`.
  """
  def ensure_plugin_product(slug, name, price_cents) when is_binary(slug) do
    product_slug = "plugin-" <> String.replace(slug, "_", "-")

    case Repo.get_by(Product, slug: product_slug) do
      %Product{} = p ->
        {:ok, p}

      nil ->
        Catalog.create_product(%{
          "kind" => "download",
          "slug" => product_slug,
          "name" => "#{name} (Bacon8 plugin)",
          "summary" => "The #{name} plugin for your own Bacon8 hub, with every update.",
          "description" =>
            "Drop the folder into your hub's plugins/ directory, deploy, and switch it on at /admin/plugins. " <>
              "Each version is cut from its release branch; your library always has the newest.",
          "price_cents" => price_cents,
          "currency" => "usd",
          "active" => false
        })
    end
  end

  defp parse_time(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, d, _} -> DateTime.truncate(d, :second)
      _ -> nil
    end
  end

  defp parse_time(_), do: nil
end
