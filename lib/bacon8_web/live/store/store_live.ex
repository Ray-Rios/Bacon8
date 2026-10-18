defmodule Bacon8Web.StoreLive do
  @moduledoc """
  /store - the storefront (BACON8.md §8): products in category tabs, each
  linking to its page (`StoreProductLive`), and Gem packs, bought straight
  from their card. `?category=<slug>` picks a tab; `?category=gems` shows
  only Gem packs.
  """
  use Bacon8Web, :live_view

  import Bacon8Web.StoreComponents
  alias Bacon8.{Entitlements, Store, Wallet}
  alias Bacon8.Store.{Catalog, Fulfilment}

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
       card_open?: Store.checkout_available?()
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

    {:noreply, assign(socket, tab: tab, products: products)}
  end

  # Products the user can't buy again because they own them.
  defp owned_ids(nil), do: MapSet.new()

  defp owned_ids(user) do
    user |> Entitlements.active(Fulfilment.download_kind()) |> Enum.map(& &1.key) |> MapSet.new()
  end

  @impl true
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

  # Sent by the desktop taskbar in the app layout; nothing to do here.
  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  @doc false
  # A provider's hosted checkout is another site; the fake one is a page here.
  def go(socket, "http" <> _ = url), do: redirect(socket, external: url)
  def go(socket, path), do: push_navigate(socket, to: path)

  @doc "Kept for older callers; see Bacon8.Store.format_number/1."
  def format_number(n), do: Store.format_number(n)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black">
      <div class="mx-auto max-w-6xl px-6 py-12">
        <div class="mb-8 flex flex-wrap items-end justify-between gap-6">
          <div>
            <h1 class="text-4xl font-bold tracking-tight text-white">Store</h1>
            <p class="mt-2 text-gray-400">Downloads, game items, passes and Gems. Pay by card or with Gems.</p>
          </div>
          <div :if={@balance} class="flex items-center gap-5 rounded-xl border border-gray-800 bg-gray-950/80 px-5 py-3">
            <div>
              <div class="text-xs uppercase tracking-wider text-gray-500">Your Gems</div>
              <div class="text-2xl font-semibold text-white">{Store.format_gems(@balance)}</div>
            </div>
            <div class="flex flex-col gap-1 border-l border-gray-800 pl-5 text-sm">
              <.link navigate={~p"/store/library"} class="text-blue-400 hover:underline">Library</.link>
              <.link navigate={~p"/store/orders"} class="text-blue-400 hover:underline">Purchases</.link>
            </div>
          </div>
        </div>

        <nav class="mb-8 flex flex-wrap gap-2 border-b border-gray-800 pb-4">
          <.tab label="All" active={@tab == "all"} to={~p"/store"} />
          <.tab :for={c <- @categories} label={c.name} active={@tab == c.slug} to={~p"/store?category=#{c.slug}"} />
          <.tab :if={@packs != []} label="💎 Gems" active={@tab == "gems"} to={~p"/store?category=gems"} />
        </nav>

        <div :if={@tab != "gems"}>
          <div :if={@products != []} class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <.product_card :for={p <- @products} product={p} owned={MapSet.member?(@owned, p.id)} />
          </div>
          <p :if={@products == [] and @tab != "all"} class="py-12 text-center text-gray-500">Nothing in this category yet.</p>
        </div>

        <section :if={@tab in ["all", "gems"] and @packs != []} class={[@tab == "all" && @products != [] && "mt-14"]}>
          <div class="mb-5 flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-2xl font-semibold text-white">Gems</h2>
            <p class="text-sm text-gray-500">100 Gems = $1. Spend them on anything here, and in every game on the hub.</p>
          </div>
          <p :if={not @card_open?} class="mb-4 text-sm text-yellow-300">Card purchases open soon.</p>
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
            <div :for={pack <- @packs} class="flex flex-col rounded-xl border border-gray-800 bg-gray-950/80 p-4">
              <div class="flex items-start justify-between">
                <span class="text-3xl">💎</span>
                <span :if={pack.badge} class="rounded bg-blue-600/30 px-2 py-0.5 text-xs text-blue-200">{pack.badge}</span>
              </div>
              <div class="mt-3 text-lg font-semibold text-white">{Store.format_number(Store.gems_for(pack))}</div>
              <div :if={Store.promo_active?(pack)} class="text-xs text-green-300">incl. {Store.format_number(pack.bonus_gems)} bonus</div>
              <button
                type="button"
                phx-click="buy_pack"
                phx-value-id={pack.id}
                disabled={not @card_open?}
                class="mt-4 w-full rounded-lg bg-blue-600 px-3 py-2 text-sm font-semibold text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {Store.format_price(pack.price_cents, pack.currency)}
              </button>
            </div>
          </div>
        </section>

        <p :if={@products == [] and @packs == []} class="py-16 text-center text-gray-500">Nothing is for sale yet.</p>

        <div class="mt-14 border-t border-gray-900 pt-6">
          <.small_print />
          <p class="mt-1 text-xs text-gray-600">Card payments are taken on our payment provider's secure page; we never see your card.</p>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :to, :string, required: true

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
      {@label}
    </.link>
    """
  end
end
