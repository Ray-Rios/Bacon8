defmodule BaconStoreWeb.Admin.ProductEditorLive do
  @moduledoc """
  /admin/bacon_store/products/new?kind=... and /admin/bacon_store/products/:id - one product
  (BACON8.md §8): its page text, prices, what the buyer gets, images,
  download files and license keys.

  The main form saves with "Save". Images, files and keys are separate: they
  apply as soon as they're uploaded or added, so they appear once the
  product has been saved for the first time.
  """
  use Bacon8Web, :live_view

  import BaconStoreWeb.StoreComponents, only: [media_url: 1, kind_glyph: 1]
  alias BaconStore.Store
  alias BaconStore.Store.{Catalog, Product}
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @fields ~w(name slug summary description category_id price price_gems gems bonus_gems promo_starts_at promo_ends_at
             grant_kind grant_key grant_quantity duration_days one_per_user badge active sort_order)

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(
        categories: Catalog.list_categories(),
        item_kinds: Catalog.item_kinds(),
        channels: Catalog.access_channels(),
        submitted: false,
        key_text: ""
      )
      |> allow_upload(:images,
        accept: ~w(.png .jpg .jpeg .gif .webp),
        max_entries: 10,
        max_file_size: 15_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> allow_upload(:downloads,
        accept: :any,
        max_entries: 5,
        max_file_size: max_download_bytes(),
        chunk_size: 1_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    case socket.assigns.live_action do
      :new ->
        kind = if params["kind"] in Product.kinds(), do: params["kind"], else: "download"
        {:ok, socket |> assign(page_title: "New #{String.downcase(Catalog.kind_label(kind))}") |> put_product(Catalog.new_product(kind))}

      :edit ->
        case Catalog.get_product_for_admin(params["id"]) do
          nil -> {:ok, socket |> put_flash(:error, "No such product.") |> push_navigate(to: ~p"/admin/bacon_store/products")}
          product -> {:ok, socket |> assign(page_title: "Edit #{product.name}") |> put_product(product)}
        end
    end
  end

  defp max_download_bytes do
    Keyword.get(Application.get_env(:bacon8, BaconStore.Store, []), :max_download_bytes, 2_147_483_648)
  end

  defp put_product(socket, product) do
    params = initial_params(product)

    socket
    |> assign(product: product, params: params, changeset: Product.changeset(product, normalize(params)))
    |> assign_errors()
    |> load_keys()
  end

  defp load_keys(%{assigns: %{product: %Product{id: id, kind: "license_key"} = p}} = socket) when not is_nil(id),
    do: assign(socket, key_counts: Catalog.key_counts(p), keys: Catalog.list_license_keys(p))

  defp load_keys(socket), do: assign(socket, key_counts: nil, keys: [])

  defp reload_files(socket) do
    fresh = Catalog.get_product_for_admin(socket.assigns.product.id)
    assign(socket, product: %{socket.assigns.product | files: fresh.files})
  end

  # ---------------------------------------------------------------------------
  # Form values: the admin's text as typed, normalised for the changeset.
  # ---------------------------------------------------------------------------

  defp initial_params(%Product{} = p) do
    %{
      "name" => p.name,
      "slug" => p.slug,
      "summary" => p.summary,
      "description" => p.description,
      "category_id" => p.category_id,
      "price" => p.price_cents && :erlang.float_to_binary(p.price_cents / 100, decimals: 2),
      "price_gems" => p.price_gems,
      "gems" => p.gems,
      "bonus_gems" => p.bonus_gems,
      "promo_starts_at" => local_input(p.promo_starts_at),
      "promo_ends_at" => local_input(p.promo_ends_at),
      "grant_kind" => p.grant_kind,
      "grant_key" => p.grant_key,
      "grant_quantity" => p.grant_quantity,
      "duration_days" => p.duration_days,
      "one_per_user" => p.one_per_user,
      "badge" => p.badge,
      "active" => p.active,
      "sort_order" => p.sort_order
    }
    |> Map.new(fn {k, v} -> {k, to_value(v)} end)
  end

  defp to_value(nil), do: ""
  defp to_value(v) when is_boolean(v), do: to_string(v)
  defp to_value(v), do: to_string(v)

  defp local_input(nil), do: nil
  defp local_input(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M")

  defp normalize(params) do
    params = Map.take(params, @fields)

    params
    |> Map.delete("price")
    |> Map.put("price_cents", dollars_to_cents(params["price"]))
    |> Map.update("promo_starts_at", nil, &utc_input/1)
    |> Map.update("promo_ends_at", nil, &utc_input/1)
    |> Map.update("bonus_gems", "0", &if(&1 in [nil, ""], do: "0", else: &1))
    |> Map.update("grant_quantity", "1", &if(&1 in [nil, ""], do: "1", else: &1))
  end

  defp dollars_to_cents(nil), do: nil

  defp dollars_to_cents(text) do
    case text |> String.trim() |> String.replace(["$", ","], "") do
      "" ->
        nil

      clean ->
        case Decimal.parse(clean) do
          {d, ""} -> d |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
          _ -> text
        end
    end
  end

  # <input type="datetime-local"> sends "2026-10-17T12:00", which we treat as UTC.
  defp utc_input(nil), do: nil
  defp utc_input(""), do: nil
  defp utc_input(text), do: if(Regex.match?(~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/, text), do: text <> ":00Z", else: text)

  # Field errors show once the admin has tried to save.
  defp assign_errors(socket) do
    errs =
      if socket.assigns.submitted do
        Enum.group_by(socket.assigns.changeset.errors, fn {field, _} -> field end, fn {_, error} -> translate_error(error) end)
      else
        %{}
      end

    assign(socket, errs: errs)
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)

    changeset =
      socket.assigns.product
      |> Product.changeset(normalize(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(params: params, changeset: changeset) |> assign_errors()}
  end

  def handle_event("save", %{"product" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)
    product = socket.assigns.product

    result =
      case product do
        %Product{id: nil, kind: kind} -> Catalog.create_product(Map.put(normalize(params), "kind", kind))
        %Product{} -> Catalog.update_product(product, normalize(params))
      end

    case result do
      {:ok, saved} when is_nil(product.id) ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{saved.name}. Add images#{extra_hint(saved)} below, then put it on sale.")
         |> push_navigate(to: ~p"/admin/bacon_store/products/#{saved.id}")}

      {:ok, saved} ->
        {:noreply,
         socket
         |> assign(submitted: false, page_title: "Edit #{saved.name}")
         |> put_product(Catalog.get_product_for_admin(saved.id))
         |> put_flash(:info, "Saved.")}

      {:error, changeset} ->
        {:noreply, socket |> assign(params: params, changeset: changeset, submitted: true) |> assign_errors()}
    end
  end

  def handle_event("match_gems", _params, socket) do
    case dollars_to_cents(socket.assigns.params["price"]) do
      cents when is_integer(cents) ->
        field = if socket.assigns.product.kind == "gem_pack", do: "gems", else: "price_gems"
        handle_event("validate", %{"product" => %{field => to_string(Store.gems_for_cents(cents))}}, socket)

      _ ->
        {:noreply, put_flash(socket, :error, "Enter a card price first.")}
    end
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload}, socket) when upload in ["images", "downloads"],
    do: {:noreply, cancel_upload(socket, String.to_existing_atom(upload), ref)}

  def handle_event("file_label", %{"id" => id, "value" => label}, socket) do
    with %{} = f <- own_file(socket, id), {:ok, _} <- Catalog.update_file_label(f, label), do: :ok
    {:noreply, reload_files(socket)}
  end

  def handle_event("file_move", %{"id" => id, "dir" => dir}, socket) do
    if f = own_file(socket, id), do: Catalog.move_file(f, if(dir == "up", do: :up, else: :down))
    {:noreply, reload_files(socket)}
  end

  def handle_event("make_cover", %{"id" => id}, socket) do
    if f = own_file(socket, id), do: Catalog.make_cover(f)
    {:noreply, reload_files(socket)}
  end

  def handle_event("delete_file", %{"id" => id}, socket) do
    if f = own_file(socket, id), do: Catalog.delete_file(f)
    {:noreply, reload_files(socket)}
  end

  def handle_event("add_keys", %{"codes" => text}, socket) do
    {:ok, %{added: added, skipped: skipped, too_long: too_long}} = Catalog.add_license_keys(socket.assigns.product, text)

    note =
      ["Added #{added} key#{if added == 1, do: "", else: "s"}."]
      |> then(&if(skipped > 0, do: &1 ++ ["Skipped #{skipped} already in the pool or repeated."], else: &1))
      |> then(&if(too_long > 0, do: &1 ++ ["#{too_long} longer than 200 characters weren't added."], else: &1))
      |> Enum.join(" ")

    {:noreply, socket |> assign(key_text: "") |> load_keys() |> put_flash(:info, note)}
  end

  def handle_event("delete_key", %{"id" => id}, socket) do
    case Catalog.delete_license_key(socket.assigns.product, id) do
      :ok -> {:noreply, load_keys(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Only keys that haven't been sold or reserved can be deleted.")}
    end
  end

  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  defp own_file(socket, id) do
    case Catalog.get_file(id) do
      %{product_id: pid} = f when pid == socket.assigns.product.id -> f
      _ -> nil
    end
  end

  defp extra_hint(%Product{kind: "download"}), do: " and the download files"
  defp extra_hint(%Product{kind: "license_key"}), do: " and the license keys"
  defp extra_hint(_), do: ""

  def handle_progress(upload, entry, socket) when upload in [:images, :downloads] do
    if entry.done? do
      role = if upload == :images, do: "image", else: "download"

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Catalog.add_file(socket.assigns.product, role, path, entry.client_name)}
        end)

      socket =
        case result do
          {:ok, _file} -> reload_files(socket)
          {:error, :not_an_image} -> put_flash(socket, :error, "#{entry.client_name} isn't a PNG, JPEG, GIF or WebP image.")
          {:error, reason} -> put_flash(socket, :error, "Couldn't store #{entry.client_name}: #{inspect(reason)}")
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp upload_error(:too_large), do: "That file is too large."
  defp upload_error(:not_accepted), do: "That kind of file isn't accepted here."
  defp upload_error(:too_many_files), do: "Too many files at once."
  defp upload_error(other), do: to_string(other)

  # ---------------------------------------------------------------------------
  # View
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/bacon_store/products">
      <div class="mx-auto max-w-5xl space-y-6">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div>
            <.link navigate={~p"/admin/bacon_store/products"} class="text-sm text-gray-400 hover:text-white">← Products</.link>
            <h1 class="mt-2 flex items-center gap-3 text-3xl font-bold text-white">
              <span><.kind_glyph kind={@product.kind} size={34} /></span>
              {if @product.id, do: @product.name, else: "New #{String.downcase(Catalog.kind_label(@product.kind))}"}
            </h1>
          </div>
          <div class="flex items-center gap-3">
            <span class={[
              "rounded-full px-3 py-1 text-xs font-semibold",
              @product.active && "bg-green-900 text-green-200",
              !@product.active && "bg-gray-700 text-gray-300"
            ]}>
              {if @product.active, do: "On sale", else: "Off sale"}
            </span>
            <.link
              :if={@product.id && @product.active && @product.kind != "gem_pack"}
              navigate={~p"/store/p/#{@product.slug}"}
              class="text-sm text-blue-400 hover:underline"
            >
              View in store →
            </.link>
          </div>
        </div>

        <form id="product-form" phx-change="validate" phx-submit="save" class="space-y-6">
          <.panel title="Basics">
            <div class="grid grid-cols-1 gap-5 md:grid-cols-2">
              <.field label="Name" name="name" params={@params} errors={(@errs[:name] || [])} placeholder="Falcon Ship" />
              <.field
                label="Page address"
                name="slug"
                params={@params}
                errors={(@errs[:slug] || [])}
                placeholder="made from the name"
                help={"/store/p/#{@params["slug"] |> blank_to("…")}"}
              />
              <div>
                <.label_text for="product_category_id">Category</.label_text>
                <select id="product_category_id" name="product[category_id]" class={input_class([])}>
                  <option value="">No category</option>
                  <option :for={c <- @categories} value={c.id} selected={@params["category_id"] == c.id}>{c.name}</option>
                </select>
                <p class="mt-1 text-xs text-gray-500">
                  Manage categories on <.link navigate={~p"/admin/bacon_store/products"} class="text-blue-400 hover:underline">Products</.link>.
                </p>
              </div>
              <.field label="Summary" name="summary" params={@params} errors={(@errs[:summary] || [])} placeholder="One line for the store card" />
              <div class="md:col-span-2">
                <.label_text for="product_description">Description</.label_text>
                <textarea id="product_description" name="product[description]" rows="7" class={input_class([])}>{@params["description"]}</textarea>
                <p class="mt-1 text-xs text-gray-500">
                  A blank line starts a new paragraph. Lines starting with "- " make a list. **bold** and *italic* work.
                </p>
              </div>
            </div>
          </.panel>

          <.panel title="Price">
            <%= if @product.kind == "gem_pack" do %>
              <div class="grid grid-cols-1 gap-5 md:grid-cols-2">
                <.field label="Card price (USD)" name="price" params={@params} errors={(@errs[:price_cents] || [])} placeholder="10.00" inputmode="decimal" />
                <div>
                  <.field label="Gems" name="gems" type="number" params={@params} errors={(@errs[:gems] || [])} help="Always the card price × 100." />
                  <button type="button" phx-click="match_gems" class="mt-2 text-xs text-blue-400 hover:underline">Set from the card price</button>
                </div>
                <.field label="Bonus Gems (promotion)" name="bonus_gems" type="number" params={@params} errors={(@errs[:bonus_gems] || [])} help="Extra Gems, only between the dates below." />
                <div></div>
                <.field label="Promotion starts (UTC)" name="promo_starts_at" type="datetime-local" params={@params} errors={(@errs[:promo_starts_at] || [])} />
                <.field label="Promotion ends (UTC)" name="promo_ends_at" type="datetime-local" params={@params} errors={(@errs[:promo_ends_at] || [])} />
              </div>
            <% else %>
              <div class="grid grid-cols-1 gap-5 md:grid-cols-2">
                <.field
                  label="Card price (USD)"
                  name="price"
                  params={@params}
                  errors={(@errs[:price_cents] || [])}
                  placeholder="4.99"
                  inputmode="decimal"
                  help="Leave empty to sell for Gems only. At least $0.50."
                />
                <div>
                  <.field
                    label="Gem price"
                    name="price_gems"
                    type="number"
                    params={@params}
                    errors={(@errs[:price_gems] || [])}
                    placeholder="499"
                    help="Leave empty to sell by card only."
                  />
                  <button type="button" phx-click="match_gems" class="mt-2 text-xs text-blue-400 hover:underline">
                    Match the card price (100 Gems per $1)
                  </button>
                </div>
              </div>
            <% end %>
          </.panel>

          <.panel :if={@product.kind != "gem_pack"} title="What the buyer gets">
            <%= case @product.kind do %>
              <% "download" -> %>
                <p class="text-sm text-gray-300">
                  The files under <strong>Download files</strong> below. Buyers keep access forever, and always get the files as they are now:
                  replace a file and every buyer gets the new one.
                </p>
              <% "license_key" -> %>
                <p class="text-sm text-gray-300">
                  One code from the pool under <strong>License keys</strong> below, shown in the buyer's library. The product shows
                  "Sold out" when the pool is empty.
                </p>
              <% "item" -> %>
                <div class="grid grid-cols-1 gap-5 md:grid-cols-2">
                  <div>
                    <.field
                      label="Item type"
                      name="grant_kind"
                      params={@params}
                      errors={(@errs[:grant_kind] || [])}
                      list="item-kinds"
                      placeholder="rays_space_sim.ship"
                      help={
                        if @item_kinds == [],
                          do: "No installed game declares item types yet (a plugin's entitlement_kinds/0). Type the one your game checks.",
                          else: "Pick one a game declares, or type the one your game checks."
                      }
                    />
                    <datalist id="item-kinds">
                      <option :for={{plugin, kind} <- @item_kinds} value={kind}>{plugin}</option>
                    </datalist>
                  </div>
                  <.field label="Item id" name="grant_key" params={@params} errors={(@errs[:grant_key] || [])} placeholder="falcon" help="What the game looks up, e.g. a ship or skin id." />
                  <.field label="Quantity" name="grant_quantity" type="number" params={@params} errors={(@errs[:grant_quantity] || [])} min="1" />
                  <.field label="Lasts (days)" name="duration_days" type="number" params={@params} errors={(@errs[:duration_days] || [])} placeholder="forever" help="Leave empty to keep it forever." />
                  <.checkbox label="One per player (can't be bought again while they have it)" name="one_per_user" params={@params} />
                </div>
              <% "access" -> %>
                <div class="space-y-5">
                  <div class="flex flex-wrap gap-6">
                    <label class="flex items-center gap-2 text-sm text-gray-200">
                      <input type="radio" name="product[grant_kind]" value="channel" checked={@params["grant_kind"] == "channel"} class="text-blue-600" />
                      Access to a private chat channel
                    </label>
                    <label class="flex items-center gap-2 text-sm text-gray-200">
                      <input type="radio" name="product[grant_kind]" value="channel_slots" checked={@params["grant_kind"] == "channel_slots"} class="text-blue-600" />
                      Extra channel slots
                    </label>
                  </div>
                  <p :for={e <- (@errs[:grant_kind] || [])} class="text-xs text-red-400">{e}</p>

                  <div :if={@params["grant_kind"] == "channel"} class="grid grid-cols-1 gap-5 md:grid-cols-2">
                    <div>
                      <.label_text for="product_grant_key">Channel</.label_text>
                      <select id="product_grant_key" name="product[grant_key]" class={input_class((@errs[:grant_key] || []))}>
                        <option value="">Choose a channel</option>
                        <option :for={c <- @channels} value={c.id} selected={@params["grant_key"] == c.id}>#{c.name}</option>
                      </select>
                      <p :if={@channels == []} class="mt-1 text-xs text-yellow-300">No private channels yet. Make one private in the forum first.</p>
                      <p :for={e <- (@errs[:grant_key] || [])} class="mt-1 text-xs text-red-400">{e}</p>
                    </div>
                    <.field
                      label="Lasts (days)"
                      name="duration_days"
                      type="number"
                      params={@params}
                      errors={(@errs[:duration_days] || [])}
                      placeholder="forever"
                      help="Leave empty for permanent access. Buying again while a pass runs adds the days on."
                    />
                  </div>

                  <div :if={@params["grant_kind"] == "channel_slots"} class="grid grid-cols-1 gap-5 md:grid-cols-2">
                    <.field
                      label="Extra channels"
                      name="grant_quantity"
                      type="number"
                      params={@params}
                      errors={(@errs[:grant_quantity] || [])}
                      min="1"
                      help="Added to how many channels the buyer may create, for good."
                    />
                  </div>
                </div>
            <% end %>
          </.panel>

          <.panel title="On the storefront">
            <div class="grid grid-cols-1 gap-5 md:grid-cols-3">
              <.field label="Badge" name="badge" params={@params} errors={(@errs[:badge] || [])} placeholder="New, Best value…" help="Optional. Shown on the card." />
              <.field label="Sort order" name="sort_order" type="number" params={@params} errors={(@errs[:sort_order] || [])} help="Lower numbers come first." />
              <div class="flex items-end pb-6">
                <.checkbox label="On sale" name="active" params={@params} />
              </div>
            </div>
          </.panel>

          <div class="sticky bottom-4 z-20 flex items-center justify-end gap-3 rounded-xl border border-gray-800 bg-gray-950/95 px-5 py-3 shadow-xl shadow-black/50 backdrop-blur">
            <p :if={@errs != %{}} class="mr-auto text-sm text-red-300">Fix the fields marked in red.</p>
            <.link navigate={~p"/admin/bacon_store/products"} class="rounded-lg bg-gray-800 px-4 py-2 text-sm text-gray-200 hover:bg-gray-700">Cancel</.link>
            <button type="submit" phx-disable-with="Saving…" class="rounded-lg bg-blue-600 px-6 py-2 text-sm font-semibold text-white hover:bg-blue-500">
              {if @product.id, do: "Save", else: "Create"}
            </button>
          </div>
        </form>

        <%= if @product.id do %>
          <.panel title="Images" subtitle="The first image is the cover on the store card. PNG, JPEG, GIF or WebP, up to 15 MB each. Saved as soon as they upload.">
            <form id="image-upload" phx-change="validate_upload" phx-submit="validate_upload">
              <label
                phx-drop-target={@uploads.images.ref}
                class="flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed border-gray-700 px-6 py-8 text-center hover:border-blue-500"
              >
                <span class="text-sm text-gray-300">Drop images here or <span class="text-blue-400 underline">choose files</span></span>
                <.live_file_input upload={@uploads.images} class="sr-only" />
              </label>
            </form>
            <.upload_progress upload={@uploads.images} name="images" />

            <div :if={Catalog.images(@product) != []} class="mt-5 grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
              <div :for={{img, i} <- Enum.with_index(Catalog.images(@product))} class="overflow-hidden rounded-xl border border-gray-700 bg-gray-900">
                <div class="relative aspect-[16/10]">
                  <img src={media_url(img)} alt="" class="h-full w-full object-cover" />
                  <span :if={i == 0} class="absolute left-2 top-2 rounded bg-blue-600 px-2 py-0.5 text-xs font-semibold text-white">Cover</span>
                </div>
                <div class="flex items-center justify-between gap-1 px-2 py-1.5 text-xs">
                  <button :if={i > 0} type="button" phx-click="make_cover" phx-value-id={img.id} class="text-blue-400 hover:underline">Make cover</button>
                  <span :if={i == 0}></span>
                  <span class="flex gap-2">
                    <button type="button" phx-click="file_move" phx-value-id={img.id} phx-value-dir="up" class="text-gray-400 hover:text-white" title="Earlier">←</button>
                    <button type="button" phx-click="file_move" phx-value-id={img.id} phx-value-dir="down" class="text-gray-400 hover:text-white" title="Later">→</button>
                    <button type="button" phx-click="delete_file" phx-value-id={img.id} data-confirm="Remove this image?" class="text-red-400 hover:underline">Remove</button>
                  </span>
                </div>
              </div>
            </div>
          </.panel>

          <.panel
            :if={@product.kind == "download"}
            title="Download files"
            subtitle={"What buyers download. Up to #{Catalog.format_bytes(max_download_bytes())} each. Give each a label if there's more than one (\"Windows\", \"macOS\")."}
          >
            <form id="download-upload" phx-change="validate_upload" phx-submit="validate_upload">
              <label
                phx-drop-target={@uploads.downloads.ref}
                class="flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed border-gray-700 px-6 py-8 text-center hover:border-blue-500"
              >
                <span class="text-sm text-gray-300">Drop files here or <span class="text-blue-400 underline">choose files</span></span>
                <.live_file_input upload={@uploads.downloads} class="sr-only" />
              </label>
            </form>
            <.upload_progress upload={@uploads.downloads} name="downloads" />

            <div :if={Catalog.downloads(@product) != []} class="mt-5 divide-y divide-gray-800 rounded-xl border border-gray-700">
              <div :for={f <- Catalog.downloads(@product)} class="flex flex-wrap items-center gap-3 px-4 py-3">
                <div class="min-w-0 flex-1">
                  <div class="truncate text-sm text-white">{f.filename}</div>
                  <div class="text-xs text-gray-500">{Catalog.format_bytes(f.byte_size)} · added {Calendar.strftime(f.inserted_at, "%b %-d, %Y")}</div>
                </div>
                <input
                  type="text"
                  value={f.label}
                  placeholder="Label (optional)"
                  phx-blur="file_label"
                  phx-value-id={f.id}
                  class="w-44 rounded-lg border-gray-600 bg-gray-800 text-sm text-white placeholder-gray-500"
                />
                <a href={~p"/store/download/#{f.id}"} class="text-sm text-blue-400 hover:underline">Test download</a>
                <button type="button" phx-click="file_move" phx-value-id={f.id} phx-value-dir="up" class="text-gray-400 hover:text-white" title="Up">↑</button>
                <button type="button" phx-click="file_move" phx-value-id={f.id} phx-value-dir="down" class="text-gray-400 hover:text-white" title="Down">↓</button>
                <button type="button" phx-click="delete_file" phx-value-id={f.id} data-confirm={"Remove #{f.filename}? Buyers won't see it any more."} class="text-sm text-red-400 hover:underline">
                  Remove
                </button>
              </div>
            </div>
            <p :if={Catalog.downloads(@product) == []} class="mt-4 text-sm text-yellow-300">No files yet. Buyers would get nothing.</p>
          </.panel>

          <.panel :if={@product.kind == "license_key"} title="License keys" subtitle="Paste codes, one per line. Each sale takes the oldest unused one.">
            <div :if={@key_counts} class="mb-5 grid grid-cols-3 gap-3 text-center">
              <div class="rounded-xl bg-gray-900 px-4 py-3">
                <div class="text-2xl font-semibold text-white">{@key_counts.available}</div>
                <div class="text-xs text-gray-500">available</div>
              </div>
              <div class="rounded-xl bg-gray-900 px-4 py-3">
                <div class="text-2xl font-semibold text-white">{@key_counts.reserved}</div>
                <div class="text-xs text-gray-500">in checkout</div>
              </div>
              <div class="rounded-xl bg-gray-900 px-4 py-3">
                <div class="text-2xl font-semibold text-white">{@key_counts.sold}</div>
                <div class="text-xs text-gray-500">sold</div>
              </div>
            </div>
            <form phx-submit="add_keys" class="space-y-3">
              <textarea name="codes" rows="5" placeholder={"AAAA-BBBB-CCCC\nDDDD-EEEE-FFFF"} class={[input_class([]), "font-mono"]}>{@key_text}</textarea>
              <button class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-500">Add keys</button>
            </form>

            <div :if={@keys != []} class="mt-6 max-h-96 overflow-y-auto rounded-xl border border-gray-700">
              <table class="min-w-full text-sm">
                <thead class="sticky top-0 bg-gray-900 text-gray-400">
                  <tr>
                    <th class="px-4 py-2 text-left font-medium">Code</th>
                    <th class="px-4 py-2 text-left font-medium">Status</th>
                    <th class="px-4 py-2"></th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-800">
                  <tr :for={k <- @keys}>
                    <td class="px-4 py-2 font-mono text-gray-200">{k.code}</td>
                    <td class="px-4 py-2 text-gray-400">
                      <%= cond do %>
                        <% k.revoked_at -> %>
                          Revoked
                        <% k.sold_at -> %>
                          Sold to {k.user && k.user.email} · {Calendar.strftime(k.sold_at, "%b %-d")}
                        <% k.order_id -> %>
                          In checkout
                        <% true -> %>
                          Available
                      <% end %>
                    </td>
                    <td class="px-4 py-2 text-right">
                      <button :if={is_nil(k.order_id)} type="button" phx-click="delete_key" phx-value-id={k.id} class="text-red-400 hover:underline">
                        Delete
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.panel>
        <% else %>
          <p class="rounded-xl border border-gray-800 bg-gray-950/60 px-5 py-4 text-sm text-gray-400">
            Images{extra_hint(@product)} can be added after you create the product.
          </p>
        <% end %>
      </div>
    </AdminSidebar.admin_layout>
    """
  end

  # ---------------------------------------------------------------------------
  # Form pieces (dark theme; the core inputs assume a light page)
  # ---------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <section class="rounded-2xl border border-gray-800 bg-gray-950/80 p-6">
      <h2 class="text-lg font-semibold text-white">{@title}</h2>
      <p :if={@subtitle} class="mt-1 text-sm text-gray-400">{@subtitle}</p>
      <div class="mt-5">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :for, :string, required: true
  slot :inner_block, required: true

  defp label_text(assigns) do
    ~H"""
    <label for={@for} class="mb-1.5 block text-sm font-medium text-gray-200">{render_slot(@inner_block)}</label>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :params, :map, required: true
  attr :errors, :list, default: []
  attr :help, :string, default: nil
  attr :type, :string, default: "text"
  attr :rest, :global, include: ~w(placeholder min max step list inputmode autocomplete)

  defp field(assigns) do
    ~H"""
    <div>
      <.label_text for={"product_#{@name}"}>{@label}</.label_text>
      <input type={@type} id={"product_#{@name}"} name={"product[#{@name}]"} value={@params[@name]} class={input_class(@errors)} {@rest} />
      <p :if={@help} class="mt-1 text-xs text-gray-500">{@help}</p>
      <p :for={e <- @errors} class="mt-1 text-xs text-red-400">{e}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :params, :map, required: true

  defp checkbox(assigns) do
    ~H"""
    <label class="flex items-center gap-3 text-sm text-gray-200">
      <input type="hidden" name={"product[#{@name}]"} value="false" />
      <input type="checkbox" name={"product[#{@name}]"} value="true" checked={@params[@name] == "true"} class="h-4 w-4 rounded border-gray-600 bg-gray-800 text-blue-600" />
      {@label}
    </label>
    """
  end

  attr :upload, :any, required: true
  attr :name, :string, required: true

  defp upload_progress(assigns) do
    ~H"""
    <div :for={entry <- @upload.entries} class="mt-3 flex items-center gap-3 text-sm">
      <span class="w-48 truncate text-gray-300">{entry.client_name}</span>
      <div class="h-2 flex-1 overflow-hidden rounded bg-gray-800">
        <div class="h-full bg-blue-500 transition-all" style={"width: #{entry.progress}%"}></div>
      </div>
      <span class="w-10 text-right text-gray-500">{entry.progress}%</span>
      <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} phx-value-upload={@name} class="text-gray-400 hover:text-white">✕</button>
      <span :for={err <- upload_errors(@upload, entry)} class="text-red-400">{upload_error(err)}</span>
    </div>
    <p :for={err <- upload_errors(@upload)} class="mt-2 text-sm text-red-400">{upload_error(err)}</p>
    """
  end

  defp input_class(errors) do
    [
      "block w-full rounded-lg bg-gray-900 text-white placeholder-gray-500 shadow-sm sm:text-sm focus:ring-2 focus:ring-blue-500/40",
      if(errors == [], do: "border-gray-700 focus:border-blue-500", else: "border-red-500 focus:border-red-400")
    ]
  end

  defp blank_to(v, default) when v in [nil, ""], do: default
  defp blank_to(v, _default), do: v
end
