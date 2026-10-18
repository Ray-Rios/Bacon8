defmodule Bacon8Web.AdminLive.Products do
  @moduledoc """
  /admin/products - everything the store sells (BACON8.md §8), and the
  storefront's categories. Each product is edited on its own page
  (`AdminLive.ProductEditor`). Products are never deleted, since orders point
  at them: take one off sale instead.
  """
  use Bacon8Web, :live_view

  import Bacon8Web.StoreComponents, only: [media_url: 1, kind_icon: 1]
  alias Bacon8.Store
  alias Bacon8.Store.{Catalog, Product}
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @new_kinds [
    {"download", "Download", "Files buyers download: software, music, ebooks, assets"},
    {"item", "Game item", "Something a game unlocks for the buyer"},
    {"access", "Access pass", "A private chat channel, or extra channel slots"},
    {"license_key", "License key", "One code from a pool you upload"},
    {"gem_pack", "Gem pack", "Gems for a card price, at 100 Gems per dollar"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Admin - Products", new_kinds: @new_kinds, kind: nil, new_category: "", editing_category: nil)
     |> load()}
  end

  defp load(socket) do
    products = Catalog.list_admin_products(kind: socket.assigns.kind)
    keys = for p <- products, p.kind == "license_key", into: %{}, do: {p.id, Catalog.key_counts(p)}
    assign(socket, products: products, keys: keys, categories: Catalog.list_categories())
  end

  @impl true
  def handle_params(params, _uri, socket) do
    kind = if params["kind"] in Product.kinds(), do: params["kind"], else: nil
    {:noreply, socket |> assign(kind: kind) |> load()}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    with %Product{} = product <- Store.get_product(id),
         {:ok, product} <- Store.update_product(product, %{active: !product.active}) do
      {:noreply,
       socket
       |> load()
       |> put_flash(:info, "#{product.name} is #{if product.active, do: "on sale", else: "off sale"}.")}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, "Can't put it on sale yet: #{first_error(cs)}. Open it to fix that.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't change that product.")}
    end
  end

  def handle_event("add_category", %{"name" => name}, socket) do
    case Catalog.create_category(%{name: name}) do
      {:ok, c} -> {:noreply, socket |> assign(new_category: "") |> load() |> put_flash(:info, "Added #{c.name}.")}
      {:error, cs} -> {:noreply, put_flash(socket, :error, "Couldn't add it: #{first_error(cs)}.")}
    end
  end

  def handle_event("edit_category", %{"id" => id}, socket), do: {:noreply, assign(socket, editing_category: id)}
  def handle_event("cancel_category", _params, socket), do: {:noreply, assign(socket, editing_category: nil)}

  def handle_event("rename_category", %{"category_id" => id, "name" => name}, socket) do
    with %{} = c <- Catalog.get_category(id),
         {:ok, _} <- Catalog.update_category(c, %{name: name}) do
      {:noreply, socket |> assign(editing_category: nil) |> load()}
    else
      {:error, cs} -> {:noreply, put_flash(socket, :error, "Couldn't rename it: #{first_error(cs)}.")}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move_category", %{"id" => id, "dir" => dir}, socket) do
    cats = socket.assigns.categories
    i = Enum.find_index(cats, &(&1.id == id))
    j = i && if(dir == "up", do: i - 1, else: i + 1)

    if i && j >= 0 && j < length(cats) do
      cats
      |> List.delete_at(i)
      |> List.insert_at(j, Enum.at(cats, i))
      |> Enum.with_index()
      |> Enum.each(fn {c, n} -> Catalog.update_category(c, %{sort_order: n * 10}) end)
    end

    {:noreply, load(socket)}
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    case Catalog.get_category(id) do
      nil -> {:noreply, socket}
      c -> {:ok, _} = Catalog.delete_category(c); {:noreply, socket |> load() |> put_flash(:info, "Deleted #{c.name}. Its products are now uncategorised.")}
    end
  end

  defp first_error(%Ecto.Changeset{errors: [{field, {msg, _}} | _]}), do: "#{Phoenix.Naming.humanize(field)} #{msg}"
  defp first_error(_), do: "invalid"

  defp detail(%Product{kind: "license_key"} = p, keys) do
    case keys[p.id] do
      %{available: a, sold: s} -> "#{a} keys left · #{s} sold"
      _ -> ""
    end
  end

  defp detail(p, _keys), do: Catalog.describe(p)

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/products">
      <div class="max-w-6xl mx-auto space-y-8">
        <div class="dark-glass p-8 rounded-xl">
          <div class="mb-6">
            <h1 class="text-3xl font-bold text-white">Products</h1>
            <p class="text-gray-400 mt-1">Everything the store sells. New products start off sale, so you can finish them first.</p>
          </div>

          <div class="mb-8 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <.link
              :for={{kind, label, hint} <- @new_kinds}
              navigate={~p"/admin/products/new?kind=#{kind}"}
              class="group rounded-xl border border-gray-700 bg-gray-900/60 p-4 transition hover:border-blue-500 hover:bg-gray-900"
            >
              <div class="flex items-center gap-2 font-semibold text-white">
                <span class="text-xl">{kind_icon(kind)}</span> New {String.downcase(label)}
              </div>
              <p class="mt-1 text-xs leading-snug text-gray-400">{hint}</p>
            </.link>
          </div>

          <div class="mb-4 flex flex-wrap gap-2">
            <.link patch={~p"/admin/products"} class={chip(@kind == nil)}>All</.link>
            <.link :for={{kind, label, _} <- @new_kinds} patch={~p"/admin/products?kind=#{kind}"} class={chip(@kind == kind)}>{label}s</.link>
          </div>

          <div class="overflow-x-auto rounded-lg border border-gray-700">
            <table class="min-w-full text-sm">
              <thead class="bg-gray-900/80 text-gray-300">
                <tr>
                  <th class="px-4 py-3 text-left font-semibold">Product</th>
                  <th class="px-4 py-3 text-left font-semibold">Kind</th>
                  <th class="px-4 py-3 text-left font-semibold">Price</th>
                  <th class="px-4 py-3 text-left font-semibold">Status</th>
                  <th class="px-4 py-3 text-right font-semibold">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-800">
                <tr :for={p <- @products} class="text-gray-200 hover:bg-gray-800/30">
                  <td class="px-4 py-3">
                    <div class="flex items-center gap-3">
                      <div class="h-10 w-16 flex-shrink-0 overflow-hidden rounded bg-gray-800">
                        <img :if={Catalog.cover(p)} src={media_url(Catalog.cover(p))} alt="" class="h-full w-full object-cover" />
                        <div :if={!Catalog.cover(p)} class="flex h-full items-center justify-center">{kind_icon(p.kind)}</div>
                      </div>
                      <div class="min-w-0">
                        <.link navigate={~p"/admin/products/#{p.id}"} class="font-medium text-white hover:underline">{p.name}</.link>
                        <div class="truncate text-xs text-gray-500">
                          {p.category && p.category.name}<span :if={p.category}> · </span>{detail(p, @keys)}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-gray-400">{Catalog.kind_label(p.kind)}</td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <div :if={p.price_cents}>{Store.format_price(p.price_cents, p.currency)}</div>
                    <div :if={p.price_gems} class="text-sky-300">{Store.format_gems(p.price_gems)}</div>
                  </td>
                  <td class="px-4 py-3">
                    <span class={[
                      "px-2 py-0.5 rounded-full text-xs font-medium",
                      if(p.active, do: "bg-green-900 text-green-200", else: "bg-gray-700 text-gray-300")
                    ]}>
                      {if p.active, do: "On sale", else: "Off sale"}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right whitespace-nowrap">
                    <.link navigate={~p"/admin/products/#{p.id}"} class="text-blue-400 hover:underline">Edit</.link>
                    <button phx-click="toggle_active" phx-value-id={p.id} class="ml-3 text-gray-400 hover:text-white hover:underline">
                      {if p.active, do: "Take off sale", else: "Put on sale"}
                    </button>
                    <.link :if={p.active and p.kind != "gem_pack"} navigate={~p"/store/p/#{p.slug}"} class="ml-3 text-gray-400 hover:text-white hover:underline">
                      View
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@products == []} class="px-4 py-8 text-center text-gray-500">No products here yet. Start one above.</p>
          </div>
        </div>

        <div class="dark-glass p-8 rounded-xl">
          <h2 class="text-xl font-semibold text-white">Categories</h2>
          <p class="text-gray-400 text-sm mt-1 mb-5">The tabs on the storefront, in this order. A tab shows only when something in it is on sale.</p>

          <div class="divide-y divide-gray-800 rounded-lg border border-gray-700">
            <div :for={c <- @categories} class="flex items-center justify-between gap-3 px-4 py-2.5">
              <%= if @editing_category == c.id do %>
                <form phx-submit="rename_category" class="flex flex-1 gap-2">
                  <input type="hidden" name="category_id" value={c.id} />
                  <input type="text" name="name" value={c.name} class="flex-1 rounded-lg border-gray-600 bg-gray-800 text-white text-sm" autofocus />
                  <button class="rounded-lg bg-blue-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-blue-500">Save</button>
                  <button type="button" phx-click="cancel_category" class="rounded-lg bg-gray-700 px-3 py-1.5 text-sm text-white">Cancel</button>
                </form>
              <% else %>
                <span class="text-gray-200">{c.name} <span class="text-xs text-gray-600">/store?category={c.slug}</span></span>
                <span class="flex gap-3 text-sm">
                  <button phx-click="move_category" phx-value-id={c.id} phx-value-dir="up" class="text-gray-400 hover:text-white" title="Move up">↑</button>
                  <button phx-click="move_category" phx-value-id={c.id} phx-value-dir="down" class="text-gray-400 hover:text-white" title="Move down">↓</button>
                  <button phx-click="edit_category" phx-value-id={c.id} class="text-blue-400 hover:underline">Rename</button>
                  <button phx-click="delete_category" phx-value-id={c.id} data-confirm={"Delete #{c.name}? Its products stay, uncategorised."} class="text-red-400 hover:underline">
                    Delete
                  </button>
                </span>
              <% end %>
            </div>
            <p :if={@categories == []} class="px-4 py-4 text-sm text-gray-500">No categories yet. Products without one still show under "All".</p>
          </div>

          <form phx-submit="add_category" class="mt-4 flex gap-2">
            <input type="text" name="name" value={@new_category} placeholder="New category, e.g. Software" class="flex-1 rounded-lg border-gray-600 bg-gray-800 text-white placeholder-gray-500 text-sm" />
            <button class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-500">Add category</button>
          </form>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end

  defp chip(true), do: "rounded-full bg-white px-3 py-1 text-sm font-medium text-black"
  defp chip(false), do: "rounded-full bg-gray-800 px-3 py-1 text-sm font-medium text-gray-300 hover:bg-gray-700 hover:text-white"
end
