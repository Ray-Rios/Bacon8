defmodule Bacon8.Store.Catalog do
  @moduledoc """
  What the store sells (BACON8.md §8): categories, products, product images
  and download files, and license key pools. Buying is `Bacon8.Store`.

  File bodies go to `Bacon8.Storage` by SHA-256, the same store as drive
  files, using the same protocol: the `drive_blobs` row is upserted (taking
  its lock) before the body is written, and `Bacon8.Drive.gc_blobs/2` keeps
  any body a `store_product_files` row still names.
  """

  import Ecto.Query
  alias Bacon8.{Repo, Storage}
  alias Bacon8.Drive.{Blob, Sniff}
  alias Bacon8.Store.{Category, LicenseKey, Product, ProductFile}

  # Images are shown inline on the product page, so only types recognised
  # from their bytes (never SVG, which can carry script).
  @image_types ~w(image/png image/jpeg image/gif image/webp)

  def image_types, do: @image_types

  # ---------------------------------------------------------------------------
  # Categories
  # ---------------------------------------------------------------------------

  def list_categories, do: Repo.all(from c in Category, order_by: [asc: c.sort_order, asc: c.name])

  def get_category(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Category, uuid)
      :error -> nil
    end
  end

  def create_category(attrs) do
    sort = (Repo.one(from c in Category, select: max(c.sort_order)) || 0) + 10
    %Category{sort_order: sort} |> Category.changeset(attrs) |> Repo.insert()
  end

  def update_category(%Category{} = c, attrs), do: c |> Category.changeset(attrs) |> Repo.update()

  @doc "Deletes a category; its products stay, uncategorised."
  def delete_category(%Category{} = c), do: Repo.delete(c)

  @doc "Categories that have something on sale, for the storefront tabs."
  def storefront_categories do
    from(c in Category,
      as: :c,
      where: exists(from p in Product, where: p.category_id == parent_as(:c).id and p.active and p.kind != "gem_pack", select: 1),
      order_by: [asc: c.sort_order, asc: c.name]
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Products
  # ---------------------------------------------------------------------------

  @doc "Active Gem packs, in display order."
  def gem_packs do
    Repo.all(from p in Product, where: p.kind == "gem_pack" and p.active, order_by: [asc: p.sort_order, asc: p.price_cents])
  end

  @doc "Products on sale other than Gem packs, optionally in one category (by slug), with images."
  def storefront(category_slug \\ nil) do
    query =
      from p in Product,
        where: p.active and p.kind != "gem_pack",
        order_by: [asc: p.sort_order, desc: p.inserted_at],
        preload: [:category, files: ^files_query("image")]

    query =
      case category_slug do
        nil -> query
        slug -> from p in query, join: c in assoc(p, :category), where: c.slug == ^slug
      end

    Repo.all(query)
  end

  @doc "A product on sale, by its URL slug, with category and files."
  def get_active_product_by_slug(slug) when is_binary(slug) do
    Repo.one(from p in Product, where: p.slug == ^slug and p.active, preload: [:category, files: ^files_query(nil)])
  end

  def get_active_product_by_slug(_), do: nil

  def get_product(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Product, uuid)
      :error -> nil
    end
  end

  @doc "A product for the admin editor, with category and files."
  def get_product_for_admin(id) do
    case get_product(id) do
      nil -> nil
      product -> Repo.preload(product, [:category, files: files_query(nil)])
    end
  end

  @doc "Everything, for /admin/products. Options: `:kind`, `:category_id`."
  def list_admin_products(opts \\ []) do
    query =
      from p in Product,
        order_by: [asc: fragment("? = 'gem_pack'", p.kind), asc: p.sort_order, desc: p.inserted_at],
        preload: [:category, files: ^files_query("image")]

    query = if kind = opts[:kind], do: from(p in query, where: p.kind == ^kind), else: query
    query = if cat = opts[:category_id], do: from(p in query, where: p.category_id == ^cat), else: query
    Repo.all(query)
  end

  defp files_query(nil), do: from(f in ProductFile, order_by: [asc: f.role, asc: f.position, asc: f.inserted_at])
  defp files_query(role), do: from(f in ProductFile, where: f.role == ^role, order_by: [asc: f.position, asc: f.inserted_at])

  @doc "A new, unsaved product of `kind`, off sale until the admin is ready."
  def new_product(kind) when kind in ["gem_pack", "download", "item", "access", "license_key"] do
    sort = (Repo.one(from p in Product, select: max(p.sort_order)) || 0) + 10
    %Product{kind: kind, active: false, currency: "usd", sort_order: sort, files: [], category: nil,
             grant_kind: if(kind == "access", do: "channel")}
  end

  def change_product(%Product{} = product, attrs \\ %{}), do: Product.changeset(product, attrs)

  @doc "Creates a product. A blank slug is made from the name."
  def create_product(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    attrs =
      if blank?(attrs["slug"]) and not blank?(attrs["name"]),
        do: Map.put(attrs, "slug", unique_slug(slugify(attrs["name"]))),
        else: attrs

    %Product{} |> Product.changeset(attrs) |> Repo.insert()
  end

  def update_product(%Product{} = p, attrs), do: p |> Product.changeset(attrs) |> Repo.update()

  @doc "\"Falcon Ship (Gold)\" -> \"falcon-ship-gold\"."
  def slugify(text) do
    text
    |> to_string()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> String.slice(0, 60)
    |> case do
      "" -> "product"
      slug -> slug
    end
  end

  defp unique_slug(base) do
    taken = Repo.all(from p in Product, where: p.slug == ^base or like(p.slug, ^"#{base}-%"), select: p.slug) |> MapSet.new()

    if MapSet.member?(taken, base),
      do: Enum.find_value(2..10_000, fn n -> candidate = "#{base}-#{n}"; unless MapSet.member?(taken, candidate), do: candidate end),
      else: base
  end

  defp blank?(v), do: v in [nil, ""] or (is_binary(v) and String.trim(v) == "")

  # ---------------------------------------------------------------------------
  # Images and downloads
  # ---------------------------------------------------------------------------

  def images(%Product{files: files}) when is_list(files), do: Enum.filter(files, &(&1.role == "image"))
  def downloads(%Product{files: files}) when is_list(files), do: Enum.filter(files, &(&1.role == "download"))

  @doc "The cover image (the first image), or nil."
  def cover(%Product{} = p), do: p |> images() |> List.first()

  def get_file(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(ProductFile, uuid) |> Repo.preload(:product)
      :error -> nil
    end
  end

  @doc """
  Stores the file at `src_path` (a LiveView upload) as an image or download
  of `product`. Images must be PNG, JPEG, GIF or WebP by their bytes.
  `opts`: `:label`. Returns `{:ok, file}` or `{:error, reason}`.
  """
  def add_file(%Product{id: product_id}, role, src_path, filename, opts \\ []) when role in ["image", "download"] do
    sniffed = Sniff.sniff_file(src_path)
    filename = clean_filename(filename)

    if role == "image" and sniffed not in @image_types do
      {:error, :not_an_image}
    else
      size = File.stat!(src_path).size
      sha = Storage.sha256_file(src_path)

      Repo.transaction(fn ->
        now = DateTime.utc_now()

        Repo.insert_all(Blob, [%{sha256: sha, size: size, content_type: sniffed, last_referenced_at: now, inserted_at: now}],
          on_conflict: [set: [last_referenced_at: now]],
          conflict_target: :sha256
        )

        case Storage.put_new(sha, src_path) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback({:storage_failed, reason})
        end

        position =
          (Repo.one(from f in ProductFile, where: f.product_id == ^product_id and f.role == ^role, select: max(f.position)) || -1) + 1

        Repo.insert!(%ProductFile{
          product_id: product_id,
          role: role,
          sha256: sha,
          filename: filename,
          content_type: if(role == "image", do: sniffed, else: Sniff.content_type(sniffed, filename)),
          byte_size: size,
          label: opts[:label],
          position: position
        })
      end)
    end
  end

  defp clean_filename(name) do
    name
    |> to_string()
    |> String.replace("\\", "/")
    |> Path.basename()
    |> String.replace(~r/[\x00-\x1F\x7F]/u, "")
    |> String.slice(0, 200)
    |> case do
      "" -> "file"
      n -> n
    end
  end

  def update_file_label(%ProductFile{} = f, label) do
    label = label |> to_string() |> String.trim() |> String.slice(0, 80)
    f |> Ecto.Changeset.change(label: if(label == "", do: nil, else: label)) |> Repo.update()
  end

  @doc "Removes a file from its product. The body is collected later by blob GC if nothing else uses it."
  def delete_file(%ProductFile{} = f) do
    now = DateTime.utc_now()
    # Restart the GC grace period, so a body still being sent isn't pulled at once.
    Repo.update_all(from(b in Blob, where: b.sha256 == ^f.sha256), set: [last_referenced_at: now])
    Repo.delete(f)
  end

  @doc "Moves a file one place earlier (`:up`) or later (`:down`) among its product's files of the same role."
  def move_file(%ProductFile{} = f, direction) when direction in [:up, :down] do
    siblings =
      Repo.all(from s in ProductFile, where: s.product_id == ^f.product_id and s.role == ^f.role, order_by: [asc: s.position, asc: s.inserted_at])

    index = Enum.find_index(siblings, &(&1.id == f.id))
    target = index && if(direction == :up, do: index - 1, else: index + 1)

    if index && target >= 0 && target < length(siblings) do
      siblings
      |> List.delete_at(index)
      |> List.insert_at(target, Enum.at(siblings, index))
      |> renumber()
    end

    :ok
  end

  @doc "Makes an image the cover (first)."
  def make_cover(%ProductFile{role: "image"} = f) do
    siblings =
      Repo.all(from s in ProductFile, where: s.product_id == ^f.product_id and s.role == "image" and s.id != ^f.id, order_by: [asc: s.position, asc: s.inserted_at])

    renumber([f | siblings])
    :ok
  end

  defp renumber(files) do
    Repo.transaction(fn ->
      files
      |> Enum.with_index()
      |> Enum.each(fn {file, i} -> Repo.update_all(from(x in ProductFile, where: x.id == ^file.id), set: [position: i]) end)
    end)
  end

  # ---------------------------------------------------------------------------
  # License keys
  # ---------------------------------------------------------------------------

  @doc """
  Adds codes (one per line; blank lines and duplicates skipped) to a license
  key product's pool. Returns `{:ok, %{added: n, skipped: m}}`.
  """
  def add_license_keys(%Product{id: product_id, kind: "license_key"}, text) when is_binary(text) do
    codes =
      text
      |> String.split(~r/\R/u)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    unique = Enum.uniq(codes)
    {too_long, ok} = Enum.split_with(unique, &(String.length(&1) > 200))
    now = DateTime.utc_now()

    {added, _} =
      Repo.insert_all(LicenseKey, Enum.map(ok, &%{id: Ecto.UUID.generate(), product_id: product_id, code: &1, inserted_at: now, updated_at: now}),
        on_conflict: :nothing,
        conflict_target: [:product_id, :code]
      )

    {:ok, %{added: added, skipped: length(codes) - added, too_long: length(too_long)}}
  end

  @doc "%{available: n, reserved: n, sold: n} for a product's key pool."
  def key_counts(%Product{id: product_id}) do
    counts =
      Repo.all(
        from k in LicenseKey,
          where: k.product_id == ^product_id,
          group_by: fragment("CASE WHEN ? IS NULL THEN 'available' WHEN ? IS NULL THEN 'reserved' ELSE 'sold' END", k.order_id, k.sold_at),
          select: {fragment("CASE WHEN ? IS NULL THEN 'available' WHEN ? IS NULL THEN 'reserved' ELSE 'sold' END", k.order_id, k.sold_at), count(k.id)}
      )
      |> Map.new()

    %{available: counts["available"] || 0, reserved: counts["reserved"] || 0, sold: counts["sold"] || 0}
  end

  def available_keys(%Product{id: product_id}),
    do: Repo.aggregate(from(k in LicenseKey, where: k.product_id == ^product_id and is_nil(k.order_id)), :count)

  @doc "A product's keys, newest first, with buyer."
  def list_license_keys(%Product{id: product_id}, limit \\ 200) do
    Repo.all(from k in LicenseKey, where: k.product_id == ^product_id, order_by: [desc: k.inserted_at], limit: ^limit, preload: [:user])
  end

  @doc "Deletes a key that hasn't been reserved or sold."
  def delete_license_key(product, key_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(key_id),
         {1, _} <- Repo.delete_all(from k in LicenseKey, where: k.id == ^uuid and k.product_id == ^product.id and is_nil(k.order_id)) do
      :ok
    else
      _ -> {:error, :not_deletable}
    end
  end

  # ---------------------------------------------------------------------------
  # What can be granted
  # ---------------------------------------------------------------------------

  @doc "Item kinds installed game plugins declare (`entitlement_kinds/0`), as `{plugin name, kind}`."
  def item_kinds do
    Bacon8.Plugins.installed()
    |> Enum.flat_map(fn mod -> Enum.map(mod.entitlement_kinds(), &{mod.name(), &1}) end)
    |> Enum.sort()
  end

  @doc "Private chat channels, the ones an access pass can sell."
  def access_channels do
    Repo.all(from c in Bacon8.Forum.Channel, where: c.is_private == true, order_by: [asc: c.name], select: %{id: c.id, name: c.name})
  end

  def channel_name(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.one(from c in Bacon8.Forum.Channel, where: c.id == ^uuid, select: c.name)
      :error -> nil
    end
  end

  @doc "One line saying what a purchase delivers, for product pages and the admin list."
  def describe(%Product{kind: "gem_pack"} = p), do: "#{Bacon8.Store.format_number(p.gems || 0)} Gems"
  def describe(%Product{kind: "download"} = p) do
    case p.files do
      files when is_list(files) ->
        case downloads(p) do
          [] -> "Download"
          d -> "Download · #{length(d)} file#{if length(d) == 1, do: "", else: "s"} · #{format_bytes(Enum.sum(Enum.map(d, & &1.byte_size)))}"
        end

      _ ->
        "Download"
    end
  end

  def describe(%Product{kind: "item"} = p) do
    qty = if (p.grant_quantity || 1) > 1, do: " ×#{p.grant_quantity}", else: ""
    "In-game item#{qty}#{for_days(p)}"
  end

  def describe(%Product{kind: "access", grant_kind: "channel"} = p),
    do: "Access to ##{channel_name(p.grant_key) || "channel"}#{for_days(p) |> then(&if(&1 == "", do: ", forever", else: &1))}"

  def describe(%Product{kind: "access", grant_kind: "channel_slots"} = p),
    do: "#{p.grant_quantity || 1} more channel#{if (p.grant_quantity || 1) == 1, do: "", else: "s"} you can create"

  def describe(%Product{kind: "license_key"}), do: "License key"
  def describe(_), do: ""

  defp for_days(%Product{duration_days: nil}), do: ""
  defp for_days(%Product{duration_days: d}), do: " for #{d} day#{if d == 1, do: "", else: "s"}"

  @doc "Short label for a kind."
  def kind_label("gem_pack"), do: "Gems"
  def kind_label("download"), do: "Download"
  def kind_label("item"), do: "Game item"
  def kind_label("access"), do: "Access pass"
  def kind_label("license_key"), do: "License key"
  def kind_label(other), do: other

  def format_bytes(n) when is_integer(n) and n >= 1_073_741_824, do: "#{Float.round(n / 1_073_741_824, 1)} GB"
  def format_bytes(n) when is_integer(n) and n >= 1_048_576, do: "#{Float.round(n / 1_048_576, 1)} MB"
  def format_bytes(n) when is_integer(n) and n >= 1024, do: "#{div(n, 1024)} KB"
  def format_bytes(n) when is_integer(n), do: "#{n} B"
  def format_bytes(_), do: ""
end
