defmodule BaconStoreWeb.StoreLive do
  @moduledoc """
  /store - the storefront (BACON8.md §8; glass cards 2026-10-28). Everything on sale is a glass
  card like the games' cards (`BaconStoreWeb.StoreComponents.store_card/1`): the item in 3D on
  the front with its name and price, the details on the back. Clicking a card slides its sheet up
  from the bottom (`?item=<slug>`, so a link opens it and Back closes it): the full details and the
  pay buttons, by card and/or with Gems. There is no separate product page any more:
  `/store/p/<slug>` comes here (`StoreProductLive`).

  `?category=<slug>` picks a tab; `?category=gems` shows only Gem packs.

  **The cart** (2026-10-29): "Add to cart" on a sheet, the Cart button (`?cart=1`) opens the cart's
  sheet, which pays for everything at once by card (one checkout) or with Gems
  (`BaconStore.Store.start_basket_checkout/3`, `buy_basket_with_gems/2`): one order number, one
  receipt.
  """
  use Bacon8Web, :live_view

  import BaconStoreWeb.StoreComponents
  alias Bacon8.Entitlements
  alias BaconStore.{Store, Wallet}
  alias BaconStore.Store.{Cart, Catalog, Fulfilment}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    {:ok,
     assign(socket,
       page_title: "Store",
       balance: user && Wallet.balance(user),
       owned: owned_ids(user),
       categories: Catalog.storefront_categories(),
       packs: Catalog.gem_packs(),
       card_open?: Store.checkout_available?(),
       item: nil,
       images: [],
       shown: nil,
       check: nil,
       confirming: false,
       cart_open: false,
       cart: [],
       cart_ids: Cart.ids(user),
       cart_confirming: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["category"] do
        "gems" -> "gems"
        slug when is_binary(slug) -> if Enum.any?(socket.assigns.categories, &(&1.slug == slug)), do: slug, else: "all"
        _ -> "all"
      end

    products =
      case tab do
        "all" -> Catalog.storefront()
        "gems" -> []
        slug -> Catalog.storefront(slug)
      end

    {:noreply,
     socket
     |> assign(tab: tab, products: products, query: Map.take(params, ["category"]))
     |> show_item(params["item"])
     |> show_cart(params["cart"] == "1")}
  end

  defp show_cart(socket, true) do
    user = socket.assigns[:current_user]
    assign(socket, cart_open: true, cart: Cart.products(user), cart_ids: Cart.ids(user), cart_confirming: false, balance: user && Wallet.balance(user))
  end

  defp show_cart(socket, false), do: assign(socket, cart_open: false, cart_confirming: false)

  # The sheet: the item named in the URL, or none.
  defp show_item(socket, slug) when is_binary(slug) do
    case Catalog.get_active_product_by_slug(slug) do
      nil ->
        socket |> put_flash(:error, "That item isn't available.") |> assign(item: nil)

      product ->
        images = if product.kind == "gem_pack", do: [], else: Catalog.images(product)

        socket
        |> assign(page_title: product.name, item: product, images: images, shown: nil, confirming: false)
        |> refresh()
    end
  end

  defp show_item(socket, _), do: assign(socket, item: nil, page_title: "Store", confirming: false)

  defp refresh(socket) do
    user = socket.assigns[:current_user]
    item = socket.assigns.item

    assign(socket,
      balance: user && Wallet.balance(user),
      check: item && Store.purchase_check(user, item),
      card_open?: Store.checkout_available?()
    )
  end

  # Products the user can't buy again because they own them.
  defp owned_ids(nil), do: MapSet.new()

  defp owned_ids(user) do
    user |> Entitlements.active(Fulfilment.download_kind()) |> Enum.map(& &1.key) |> MapSet.new()
  end

  defp here(socket, extra), do: "/store?" <> URI.encode_query(Map.merge(socket.assigns.query, extra))

  @impl true
  def handle_event("open_item", %{"slug" => slug}, socket) when is_binary(slug),
    do: {:noreply, push_patch(socket, to: here(socket, %{"item" => slug}))}

  def handle_event("open_cart", _params, socket), do: {:noreply, push_patch(socket, to: here(socket, %{"cart" => "1"}))}

  def handle_event("add_to_cart", _params, %{assigns: %{item: %{} = item, current_user: %{} = user}} = socket) do
    case Cart.add(user, item) do
      :ok ->
        {:noreply, socket |> assign(cart_ids: Cart.ids(user)) |> put_flash(:info, "#{item.name} is in your cart.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Store.reason_text(reason))}
    end
  end

  def handle_event("add_to_cart", _params, socket), do: {:noreply, push_navigate(socket, to: ~p"/login")}

  def handle_event("remove_from_cart", %{"id" => id}, %{assigns: %{current_user: %{} = user}} = socket) do
    Cart.remove(user, id)
    {:noreply, assign(socket, cart: Cart.products(user), cart_ids: Cart.ids(user), cart_confirming: false)}
  end

  def handle_event("pay_cart_card", _params, %{assigns: %{current_user: %{} = user}} = socket) do
    case Store.start_basket_checkout(user, Cart.products(user)) do
      {:ok, _orders, url} -> {:noreply, go(socket, url)}
      {:error, reason} -> {:noreply, socket |> put_flash(:error, Store.reason_text(reason)) |> show_cart(true)}
    end
  end

  def handle_event("confirm_cart_gems", _params, socket), do: {:noreply, assign(socket, cart_confirming: true)}
  def handle_event("cancel_cart_gems", _params, socket), do: {:noreply, assign(socket, cart_confirming: false)}

  def handle_event("pay_cart_gems", _params, %{assigns: %{current_user: %{} = user}} = socket) do
    case Store.buy_basket_with_gems(user, Cart.products(user)) do
      {:ok, [order | _]} ->
        {:noreply, socket |> put_flash(:info, "Bought. It's all in your library.") |> push_navigate(to: ~p"/store/orders/#{order.id}")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Store.reason_text(reason)) |> show_cart(true)}
    end
  end

  def handle_event("close_item", _params, socket) do
    to = if socket.assigns.query == %{}, do: ~p"/store", else: here(socket, %{})
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("show", %{"id" => id}, socket) do
    {:noreply, assign(socket, shown: Enum.find(socket.assigns.images, socket.assigns.shown, &(&1.id == id)))}
  end

  def handle_event("show_art", _params, socket), do: {:noreply, assign(socket, shown: nil)}

  # A Gem pack straight from its card's sheet (card only).
  def handle_event("buy_pack", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with %{kind: "gem_pack"} = pack <- Store.get_product(id),
         {:ok, _order, url} <- Store.start_checkout(user, pack) do
      {:noreply, go(socket, url)}
    else
      {:error, :not_signed_in} -> {:noreply, push_navigate(socket, to: ~p"/login")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Store.reason_text(reason))}
      _ -> {:noreply, put_flash(socket, :error, Store.reason_text(:not_for_sale))}
    end
  end

  def handle_event("buy_card", _params, %{assigns: %{item: %{} = item}} = socket) do
    case Store.start_checkout(socket.assigns.current_user, item) do
      {:ok, _order, url} -> {:noreply, go(socket, url)}
      {:error, :not_signed_in} -> {:noreply, push_navigate(socket, to: ~p"/login")}
      {:error, reason} -> {:noreply, socket |> put_flash(:error, Store.reason_text(reason)) |> refresh()}
    end
  end

  def handle_event("confirm_gems", _params, socket), do: {:noreply, assign(socket, confirming: true)}
  def handle_event("cancel_gems", _params, socket), do: {:noreply, assign(socket, confirming: false)}

  def handle_event("buy_gems", _params, %{assigns: %{item: %{} = item}} = socket) do
    case Store.buy_with_gems(socket.assigns.current_user, item) do
      {:ok, _order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bought #{item.name}. It's in your library.")
         |> push_navigate(to: ~p"/store/library")}

      {:error, reason} ->
        {:noreply, socket |> assign(confirming: false) |> put_flash(:error, Store.reason_text(reason)) |> refresh()}
    end
  end

  # Sent by the desktop taskbar in the app layout; nothing to do here.
  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @doc false
  # A provider's hosted checkout is another site; the fake one is a page here.
  def go(socket, "http" <> _ = url), do: redirect(socket, external: url)
  def go(socket, path), do: push_navigate(socket, to: path)

  @doc "Kept for older callers; see BaconStore.Store.format_number/1."
  def format_number(n), do: Store.format_number(n)

  @impl true
  def render(assigns) do
    ~H"""
    <.store_styles />
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black" data-store-scroll>
      <div class="mx-auto max-w-6xl px-6 py-12">
        <div class="mb-8 flex flex-wrap items-end justify-between gap-6">
          <div>
            <h1 class="text-4xl font-bold tracking-tight text-white">Store</h1>
            <p class="mt-2 text-gray-400">Downloads, game items, passes and Gems. Pay by card or with Gems.</p>
          </div>
          <div :if={@balance} class="flex items-center gap-5 rounded-xl border border-gray-800 bg-gray-950/80 px-5 py-3">
            <div>
              <div class="text-xs uppercase tracking-wider text-gray-500">Your Gems</div>
              <div class="text-2xl font-semibold text-white"><Bacon8Web.Components.Gem.gems amount={@balance} /></div>
            </div>
            <div class="flex flex-col gap-1 border-l border-gray-800 pl-5 text-sm">
              <.link navigate={~p"/store/library"} class="text-blue-400 hover:underline">Library</.link>
              <.link navigate={~p"/store/orders"} class="text-blue-400 hover:underline">Purchases</.link>
            </div>
            <button type="button" phx-click="open_cart" class="cart-btn" id="cart-button" aria-label="Your cart">
              🛒 Cart <b :if={MapSet.size(@cart_ids) > 0}>{MapSet.size(@cart_ids)}</b>
            </button>
          </div>
        </div>

        <nav class="mb-8 flex flex-wrap gap-2 border-b border-gray-800 pb-4">
          <.tab label="All" active={@tab == "all"} to={~p"/store"} />
          <.tab :for={c <- @categories} label={c.name} active={@tab == c.slug} to={~p"/store?category=#{c.slug}"} />
          <.tab :if={@packs != []} label="Gems" gem active={@tab == "gems"} to={~p"/store?category=gems"} />
        </nav>

        <div :if={@tab != "gems"}>
          <div :if={@products != []} class="sc-grid">
            <.store_card :for={p <- @products} product={p} owned={MapSet.member?(@owned, p.id)} />
          </div>
          <p :if={@products == [] and @tab != "all"} class="py-12 text-center text-gray-500">Nothing in this category yet.</p>
        </div>

        <section :if={@tab in ["all", "gems"] and @packs != []} class={[@tab == "all" && @products != [] && "mt-14"]}>
          <div class="mb-5 flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="flex items-center gap-3 text-2xl font-semibold text-white" data-gem-host>
              <Bacon8Web.Components.Gem.gem size={44} /> Gems
            </h2>
            <p class="text-sm text-gray-500">100 Gems = $1. Spend them on anything here, and in every game on the hub.</p>
          </div>
          <p :if={not @card_open?} class="mb-4 text-sm text-yellow-300">Card purchases open soon.</p>
          <div class="sc-grid packs">
            <.store_card :for={pack <- @packs} product={pack} />
          </div>
        </section>

        <p :if={@products == [] and @packs == []} class="py-16 text-center text-gray-500">Nothing is for sale yet.</p>

        <div class="mt-14 border-t border-gray-900 pt-6">
          <.small_print />
          <p class="mt-1 text-xs text-gray-600">Card payments are taken on our payment provider's secure page; we never see your card.</p>
        </div>
      </div>
    </div>

    <.cart_sheet
      :if={@cart_open && !@item}
      cart={@cart}
      balance={@balance}
      confirming={@cart_confirming}
      card_open?={@card_open?}
      signed_in={!!@current_user}
    />

    <.item_sheet
      :if={@item}
      in_cart={MapSet.member?(@cart_ids, @item.id)}
      item={@item}
      images={@images}
      shown={@shown}
      check={@check}
      balance={@balance}
      confirming={@confirming}
      card_open?={@card_open?}
    />
    """
  end

  # The sheet that slides up: the item large (its 3D turn, or its pictures), what you get, the
  # description, and the pay buttons.
  attr :item, :map, required: true
  attr :images, :list, default: []
  attr :shown, :map, default: nil
  attr :check, :any, default: nil
  attr :balance, :integer, default: nil
  attr :confirming, :boolean, default: false
  attr :card_open?, :boolean, default: false
  attr :in_cart, :boolean, default: false

  defp item_sheet(assigns) do
    art = Catalog.art(assigns.item)
    assigns = assign(assigns, art: art, style: "--sc-tint:#{tint(art, 0.24)}")

    ~H"""
    <div id={"sheet-#{@item.id}"} class="ss" phx-hook="StoreSheet" role="dialog" aria-modal="true" aria-label={@item.name} style={@style}>
      <div class="ss-backdrop" data-sheet-close></div>
      <div class="ss-panel" tabindex="-1">
        <div class="ss-grab" data-sheet-close><i></i></div>
        <button type="button" class="ss-x" data-sheet-close aria-label="Close">✕</button>
        <div class="ss-body">
          <div>
            <div class="ss-stage" data-spin-host data-gem-host>
              <%= if @shown do %>
                <img src={media_url(@shown)} alt={@item.name} class="sc-img" />
              <% else %>
                <.art art={@art} alt={@item.name} />
              <% end %>
            </div>
            <div :if={@images != [] and @art.type != :image} class="ss-thumbs">
              <button type="button" phx-click="show_art" class={[!@shown && "on"]} aria-label="The item in 3D">
                <span class="flex h-full w-full items-center justify-center text-xl text-gray-300">⟳</span>
              </button>
              <button :for={img <- @images} type="button" phx-click="show" phx-value-id={img.id} class={[@shown && @shown.id == img.id && "on"]}>
                <img src={media_url(img)} alt="" />
              </button>
            </div>
            <div :if={@images != [] and @art.type == :image and length(@images) > 1} class="ss-thumbs">
              <button :for={img <- @images} type="button" phx-click="show" phx-value-id={img.id} class={[thumb_on?(@shown, img, @images) && "on"]}>
                <img src={media_url(img)} alt="" />
              </button>
            </div>
            <div :if={@item.description} class="ss-about">{description_html(@item.description)}</div>
          </div>

          <aside class="ss-buy">
            <div class="flex items-center gap-2 text-xs font-medium uppercase tracking-wider text-gray-400">
              <span>{Catalog.kind_label(@item.kind)}</span>
              <span :if={@item.category} class="text-gray-600">· {@item.category.name}</span>
              <span :if={@item.badge} class="ml-auto rounded-full bg-blue-600 px-2.5 py-0.5 normal-case tracking-normal text-white">{@item.badge}</span>
            </div>
            <h2 class="mt-3 text-3xl font-bold leading-tight text-white">{@item.name}</h2>
            <p :if={@item.summary} class="mt-2 text-gray-400">{@item.summary}</p>

            <div class="mt-5 rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-sm text-gray-300">
              <span class="text-gray-500">You get:</span> {Catalog.describe(@item)}
              <span :if={@item.kind == "gem_pack" and Store.promo_active?(@item)} class="text-green-300">
                (incl. {Store.format_number(@item.bonus_gems)} bonus)
              </span>
            </div>

            <div class="mt-6"><.price_tags product={@item} size="lg" /></div>

            <div class="mt-5 space-y-3">
              <%= if @item.kind == "gem_pack" do %>
                <button
                  type="button"
                  phx-click="buy_pack"
                  phx-value-id={@item.id}
                  disabled={not @card_open?}
                  class="w-full rounded-xl bg-blue-600 px-4 py-3 font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Pay {Store.format_price(@item.price_cents, @item.currency)}
                </button>
                <p :if={not @card_open?} class="text-xs text-yellow-300">Card purchases open soon.</p>
                <.cart_add in_cart={@in_cart} />
              <% else %>
                <%= case @check do %>
                  <% :ok -> %>
                    <button
                      :if={@item.price_cents}
                      type="button"
                      phx-click="buy_card"
                      disabled={not @card_open?}
                      class="w-full rounded-xl bg-blue-600 px-4 py-3 font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Pay with card · {Store.format_price(@item.price_cents, @item.currency)}
                    </button>
                    <p :if={@item.price_cents && not @card_open?} class="text-xs text-yellow-300">Card purchases open soon.</p>

                    <%= if @item.price_gems do %>
                      <%= cond do %>
                        <% (@balance || 0) < @item.price_gems -> %>
                          <button type="button" disabled class="w-full cursor-not-allowed rounded-xl border border-sky-800 px-4 py-3 font-semibold text-sky-300 opacity-50">
                            Pay with Gems · <Bacon8Web.Components.Gem.gems amount={@item.price_gems} />
                          </button>
                          <p class="text-xs text-gray-400">
                            You have <Bacon8Web.Components.Gem.gems amount={@balance || 0} />.
                            <.link patch={~p"/store?category=gems"} class="text-blue-400 hover:underline">Get more Gems</.link>
                          </p>
                        <% @confirming -> %>
                          <div class="rounded-xl border border-sky-700 bg-sky-950/40 p-4">
                            <p class="text-sm text-gray-200">
                              Spend <Bacon8Web.Components.Gem.gems amount={@item.price_gems} /> of your <Bacon8Web.Components.Gem.gems amount={@balance} />?
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
                            Pay with Gems · <Bacon8Web.Components.Gem.gems amount={@item.price_gems} />
                          </button>
                      <% end %>
                    <% end %>
                    <.cart_add in_cart={@in_cart} />
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
                  <% _ -> %>
                <% end %>
              <% end %>
            </div>

            <div class="mt-5"><.small_print /></div>
          </aside>
        </div>
      </div>
    </div>
    """
  end

  # "Add to cart" under the pay buttons, or where the cart is when it's already in it.
  attr :in_cart, :boolean, default: false

  defp cart_add(assigns) do
    ~H"""
    <button :if={!@in_cart} type="button" phx-click="add_to_cart" class="w-full rounded-xl border border-white/15 px-4 py-3 font-semibold text-gray-100 transition hover:bg-white/10">
      🛒 Add to cart
    </button>
    <button :if={@in_cart} type="button" phx-click="open_cart" class="w-full rounded-xl border border-green-800 bg-green-950/30 px-4 py-3 font-semibold text-green-200 transition hover:bg-green-950/60">
      ✓ In your cart · view cart
    </button>
    """
  end

  # The cart's sheet: what's in it, the totals, pay for it all by card or with Gems.
  attr :cart, :list, required: true
  attr :balance, :integer, default: nil
  attr :confirming, :boolean, default: false
  attr :card_open?, :boolean, default: false
  attr :signed_in, :boolean, default: false

  defp cart_sheet(assigns) do
    assigns =
      assign(assigns,
        card: Store.basket_price(assigns.cart, :card),
        gems: Store.basket_price(assigns.cart, :gems)
      )

    ~H"""
    <div id="cart-sheet" class="ss" phx-hook="StoreSheet" role="dialog" aria-modal="true" aria-label="Your cart" style="--sc-tint:rgba(255,138,76,.18)">
      <div class="ss-backdrop" data-sheet-close></div>
      <div class="ss-panel" tabindex="-1">
        <div class="ss-grab" data-sheet-close><i></i></div>
        <button type="button" class="ss-x" data-sheet-close aria-label="Close">✕</button>
        <div class="mx-auto w-full max-w-xl px-5 pb-8 pt-2 sm:px-8">
          <h2 class="text-2xl font-bold text-white">Your cart</h2>
          <p :if={!@signed_in} class="mt-4 text-gray-400"><.link navigate={~p"/login"} class="text-blue-400 hover:underline">Sign in</.link> to fill a cart.</p>
          <p :if={@signed_in && @cart == []} class="mt-4 text-gray-400">Nothing here yet. Open an item and press Add to cart.</p>

          <div :if={@cart != []} class="mt-4">
            <div :for={p <- @cart} class="cart-row" id={"cart-#{p.id}"}>
              <div class="cart-thumb">
                <img :if={Catalog.cover(p)} src={media_url(Catalog.cover(p))} alt="" />
                <span :if={!Catalog.cover(p)}><.kind_glyph kind={p.kind} size={26} /></span>
              </div>
              <div class="min-w-0 flex-1">
                <div class="truncate font-semibold text-white">{p.name}</div>
                <div class="text-xs text-gray-500">{Catalog.kind_label(p.kind)}</div>
              </div>
              <div class="text-right text-sm text-gray-200">
                <div :if={p.price_cents}>{Store.format_price(p.price_cents, p.currency)}</div>
                <div :if={p.price_gems && p.kind != "gem_pack"} class="text-xs text-sky-300"><Bacon8Web.Components.Gem.gems amount={p.price_gems} /></div>
              </div>
              <button type="button" class="cart-x" phx-click="remove_from_cart" phx-value-id={p.id} aria-label={"Remove #{p.name}"}>✕</button>
            </div>

            <div class="mt-5 space-y-3">
              <button
                :if={@card}
                type="button"
                phx-click="pay_cart_card"
                phx-disable-with="Opening checkout…"
                disabled={not @card_open?}
                class="w-full rounded-xl bg-blue-600 px-4 py-3 font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Pay with card · {Store.format_price(@card.cents, @card.currency)}
              </button>
              <p :if={@card && not @card_open?} class="text-xs text-yellow-300">Card purchases open soon.</p>
              <p :if={!@card} class="text-xs text-gray-400">Something here can only be bought with Gems.</p>

              <%= cond do %>
                <% is_nil(@gems) -> %>
                  <p :if={@card} class="text-xs text-gray-500">Gem packs, and items without a Gem price, are paid by card.</p>
                <% (@balance || 0) < @gems.gems -> %>
                  <button type="button" disabled class="w-full cursor-not-allowed rounded-xl border border-sky-800 px-4 py-3 font-semibold text-sky-300 opacity-50">
                    Pay with Gems · <Bacon8Web.Components.Gem.gems amount={@gems.gems} />
                  </button>
                  <p class="text-xs text-gray-400">You have <Bacon8Web.Components.Gem.gems amount={@balance || 0} />.</p>
                <% @confirming -> %>
                  <div class="rounded-xl border border-sky-700 bg-sky-950/40 p-4">
                    <p class="text-sm text-gray-200">Spend <Bacon8Web.Components.Gem.gems amount={@gems.gems} /> of your <Bacon8Web.Components.Gem.gems amount={@balance} />?</p>
                    <div class="mt-3 flex gap-2">
                      <button type="button" phx-click="pay_cart_gems" phx-disable-with="Buying…" class="flex-1 rounded-lg bg-sky-600 px-3 py-2 font-semibold text-white hover:bg-sky-500">Confirm</button>
                      <button type="button" phx-click="cancel_cart_gems" class="rounded-lg bg-gray-800 px-3 py-2 text-gray-200 hover:bg-gray-700">Cancel</button>
                    </div>
                  </div>
                <% true -> %>
                  <button type="button" phx-click="confirm_cart_gems" class="w-full rounded-xl border border-sky-600 px-4 py-3 font-semibold text-sky-300 transition hover:bg-sky-950/60">
                    Pay with Gems · <Bacon8Web.Components.Gem.gems amount={@gems.gems} />
                  </button>
              <% end %>
            </div>
            <div class="mt-5"><.small_print /></div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp thumb_on?(nil, img, [first | _]), do: img.id == first.id
  defp thumb_on?(%{id: id}, img, _images), do: img.id == id
  defp thumb_on?(_shown, _img, _images), do: false

  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :to, :string, required: true
  attr :gem, :boolean, default: false

  defp tab(assigns) do
    ~H"""
    <.link
      patch={@to}
      class={[
        "rounded-full px-4 py-1.5 text-sm font-medium transition",
        @active && "bg-white text-black",
        !@active && "bg-gray-900 text-gray-300 hover:bg-gray-800 hover:text-white"
      ]}
    >
      <Bacon8Web.Components.Gem.gem :if={@gem} size={18} class="mr-1" />{@label}
    </.link>
    """
  end
end
