defmodule BaconStoreWeb.StoreProductLive do
  @moduledoc """
  /store/p/:slug - one product (BACON8.md §8): gallery, what you get, and
  Buy buttons for its card and/or Gem price. A Gem purchase is confirmed
  inline, then spends and delivers at once; a card purchase goes to the
  payment provider's page.
  """
  use Bacon8Web, :live_view

  import BaconStoreWeb.StoreComponents
  alias BaconStore.{Store, Wallet}
  alias BaconStore.Store.Catalog

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Catalog.get_active_product_by_slug(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "That product isn't available.") |> push_navigate(to: ~p"/store")}

      %{kind: "gem_pack"} ->
        {:ok, push_navigate(socket, to: ~p"/store?category=gems")}

      product ->
        images = Catalog.images(product)

        {:ok,
         socket
         |> assign(
           page_title: product.name,
           product: product,
           images: images,
           shown: List.first(images),
           confirming: false
         )
         |> refresh()}
    end
  end

  defp refresh(socket) do
    user = socket.assigns[:current_user]

    assign(socket,
      balance: user && Wallet.balance(user),
      check: Store.purchase_check(user, socket.assigns.product),
      card_open?: Store.checkout_available?()
    )
  end

  @impl true
  def handle_event("show", %{"id" => id}, socket) do
    {:noreply, assign(socket, shown: Enum.find(socket.assigns.images, socket.assigns.shown, &(&1.id == id)))}
  end

  def handle_event("buy_card", _params, socket) do
    case Store.start_checkout(socket.assigns.current_user, socket.assigns.product) do
      {:ok, _order, url} -> {:noreply, BaconStoreWeb.StoreLive.go(socket, url)}
      {:error, :not_signed_in} -> {:noreply, push_navigate(socket, to: ~p"/login")}
      {:error, reason} -> {:noreply, socket |> put_flash(:error, Store.reason_text(reason)) |> refresh()}
    end
  end

  def handle_event("confirm_gems", _params, socket), do: {:noreply, assign(socket, confirming: true)}
  def handle_event("cancel_gems", _params, socket), do: {:noreply, assign(socket, confirming: false)}

  def handle_event("buy_gems", _params, socket) do
    case Store.buy_with_gems(socket.assigns.current_user, socket.assigns.product) do
      {:ok, _order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bought #{socket.assigns.product.name}. It's in your library.")
         |> push_navigate(to: ~p"/store/library")}

      {:error, reason} ->
        {:noreply, socket |> assign(confirming: false) |> put_flash(:error, Store.reason_text(reason)) |> refresh()}
    end
  end

  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black">
      <div class="mx-auto max-w-6xl px-6 py-10">
        <div class="mb-6 flex items-center gap-2 text-sm text-gray-500">
          <.link navigate={~p"/store"} class="hover:text-white">Store</.link>
          <span :if={@product.category}>/</span>
          <.link :if={@product.category} navigate={~p"/store?category=#{@product.category.slug}"} class="hover:text-white">
            {@product.category.name}
          </.link>
        </div>

        <div class="grid grid-cols-1 gap-10 lg:grid-cols-5">
          <div class="lg:col-span-3">
            <div class="aspect-[16/10] overflow-hidden rounded-2xl border border-gray-800 bg-gradient-to-br from-gray-900 to-gray-800">
              <img :if={@shown} src={media_url(@shown)} alt={@product.name} class="h-full w-full object-contain" />
              <div :if={!@shown} class="flex h-full w-full items-center justify-center text-7xl opacity-80">
                {kind_icon(@product.kind)}
              </div>
            </div>
            <div :if={length(@images) > 1} class="mt-3 grid grid-cols-5 gap-3 sm:grid-cols-6">
              <button
                :for={img <- @images}
                type="button"
                phx-click="show"
                phx-value-id={img.id}
                class={[
                  "aspect-square overflow-hidden rounded-lg border-2 bg-gray-900 transition",
                  @shown && @shown.id == img.id && "border-blue-500",
                  !(@shown && @shown.id == img.id) && "border-transparent opacity-70 hover:opacity-100"
                ]}
              >
                <img src={media_url(img)} alt="" class="h-full w-full object-cover" />
              </button>
            </div>

            <div :if={@product.description} class="mt-10 space-y-4 text-[15px] leading-relaxed text-gray-300">
              <h2 class="text-lg font-semibold text-white">About</h2>
              {description_html(@product.description)}
            </div>
          </div>

          <aside class="lg:col-span-2">
            <div class="sticky top-6 rounded-2xl border border-gray-800 bg-gray-950/90 p-6">
              <div class="flex items-center gap-2 text-xs font-medium uppercase tracking-wider text-gray-500">
                <span>{kind_icon(@product.kind)}</span>
                <span>{Catalog.kind_label(@product.kind)}</span>
                <span :if={@product.badge} class="ml-auto rounded-full bg-blue-600 px-2.5 py-0.5 normal-case tracking-normal text-white">
                  {@product.badge}
                </span>
              </div>
              <h1 class="mt-3 text-3xl font-bold leading-tight text-white">{@product.name}</h1>
              <p :if={@product.summary} class="mt-2 text-gray-400">{@product.summary}</p>

              <div class="mt-5 rounded-lg bg-gray-900/70 px-4 py-3 text-sm text-gray-300">
                <span class="text-gray-500">You get:</span> {Catalog.describe(@product)}
              </div>

              <div class="mt-6"><.price_tags product={@product} size="lg" /></div>

              <div class="mt-5 space-y-3">
                <%= case @check do %>
                  <% :ok -> %>
                    <button
                      :if={@product.price_cents}
                      type="button"
                      phx-click="buy_card"
                      disabled={not @card_open?}
                      class="w-full rounded-xl bg-blue-600 px-4 py-3 font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Buy with card · {Store.format_price(@product.price_cents, @product.currency)}
                    </button>
                    <p :if={@product.price_cents && not @card_open?} class="text-xs text-yellow-300">Card purchases open soon.</p>

                    <%= if @product.price_gems do %>
                      <%= cond do %>
                        <% (@balance || 0) < @product.price_gems -> %>
                          <button type="button" disabled class="w-full cursor-not-allowed rounded-xl border border-sky-800 px-4 py-3 font-semibold text-sky-300 opacity-50">
                            Buy with Gems · {Store.format_gems(@product.price_gems)}
                          </button>
                          <p class="text-xs text-gray-400">
                            You have {Store.format_gems(@balance || 0)}.
                            <.link navigate={~p"/store?category=gems"} class="text-blue-400 hover:underline">Get more Gems</.link>
                          </p>
                        <% @confirming -> %>
                          <div class="rounded-xl border border-sky-700 bg-sky-950/40 p-4">
                            <p class="text-sm text-gray-200">
                              Spend {Store.format_gems(@product.price_gems)} of your {Store.format_gems(@balance)}?
                            </p>
                            <div class="mt-3 flex gap-2">
                              <button type="button" phx-click="buy_gems" phx-disable-with="Buying…" class="flex-1 rounded-lg bg-sky-600 px-3 py-2 font-semibold text-white hover:bg-sky-500">
                                Confirm
                              </button>
                              <button type="button" phx-click="cancel_gems" class="rounded-lg bg-gray-800 px-3 py-2 text-gray-200 hover:bg-gray-700">Cancel</button>
                            </div>
                          </div>
                        <% true -> %>
                          <button type="button" phx-click="confirm_gems" class="w-full rounded-xl border border-sky-600 px-4 py-3 font-semibold text-sky-300 transition hover:bg-sky-950/60">
                            Buy with Gems · {Store.format_gems(@product.price_gems)}
                          </button>
                      <% end %>
                    <% end %>
                  <% {:error, :already_owned} -> %>
                    <div class="rounded-xl border border-green-800 bg-green-950/40 px-4 py-3 text-green-200">✓ You own this.</div>
                    <.link navigate={~p"/store/library"} class="block w-full rounded-xl bg-gray-800 px-4 py-3 text-center font-semibold text-white hover:bg-gray-700">
                      Open your library
                    </.link>
                  <% {:error, :not_signed_in} -> %>
                    <.link navigate={~p"/login"} class="block w-full rounded-xl bg-blue-600 px-4 py-3 text-center font-semibold text-white hover:bg-blue-500">
                      Sign in to buy
                    </.link>
                  <% {:error, reason} -> %>
                    <div class="rounded-xl border border-gray-700 bg-gray-900 px-4 py-3 text-gray-300">{Store.reason_text(reason)}</div>
                <% end %>
              </div>

              <div class="mt-5"><.small_print /></div>
            </div>
          </aside>
        </div>
      </div>
    </div>
    """
  end
end
