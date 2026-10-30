defmodule BaconStoreWeb.StoreOrderLive do
  @moduledoc """
  /store/orders and /store/orders/:id - the buyer's purchase history and one
  order's status. Coming back from checkout lands here; the page shows
  "processing" until the provider's event arrives and then updates live.

  Since 2026-10-29 both show receipts (`StoreComponents.receipt/1`): a purchase of several items
  (the cart) is one receipt with one number, and `/store/orders/:id` shows the receipt of the
  basket that order belongs to.

  Unfinished checkouts (2026-10-29c): Purchases lists only what was paid for; a checkout still
  waiting is shown above it with "Continue to payment" and "Cancel". The provider's cancel link
  (`?checkout=cancelled`) closes the checkout; coming back from paying (`?checkout=done`), or
  opening a waiting order, asks the provider where it stands (`Store.reconcile/1`) so the page
  doesn't depend on the webhook's timing.
  """
  use Bacon8Web, :live_view

  import BaconStoreWeb.StoreComponents, only: [timezone: 1, receipt: 1, store_styles: 1]
  alias BaconStore.{Store, Wallet}

  on_mount {Bacon8Web.UserAuth, :require_authenticated_user}

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    socket = assign(socket, tz: timezone(socket))

    case params["id"] do
      nil ->
        if connected?(socket), do: Enum.each(Store.open_checkouts(user), &Store.reconcile(&1.orders))
        {:ok, socket |> assign(page_title: "Purchases", order: nil, notice: nil) |> load_list()}

      id ->
        case Store.get_user_order(user, id) do
          nil ->
            {:ok, socket |> put_flash(:error, "Order not found.") |> push_navigate(to: ~p"/store")}

          order ->
            orders = Store.basket(order)
            if connected?(socket), do: Enum.each(orders, &Phoenix.PubSub.subscribe(Bacon8.PubSub, Store.topic(&1)))
            notice = if connected?(socket), do: arrive(user, order, orders, params["checkout"])

            {:ok,
             socket
             |> assign(page_title: "Order ##{order.number}", order: order, receipts: [], open: [], notice: notice)
             |> load_order()}
        end
    end
  end

  # Back from the provider: through its cancel link (close the checkout), or after paying (or
  # just opening a waiting order): ask the provider rather than wait for its webhook.
  defp arrive(user, order, _orders, "cancelled") do
    case Store.cancel_checkout(user, order.id) do
      {:ok, _} -> "Checkout cancelled. Nothing was charged."
      {:error, :already_paid} -> nil
      {:error, _} -> "We couldn't close that checkout just now. It closes by itself within half an hour."
    end
  end

  defp arrive(_user, %{status: "awaiting_payment"}, orders, _) do
    Store.reconcile(orders)
    nil
  end

  defp arrive(_user, _order, _orders, _), do: nil

  defp load_order(socket) do
    user = socket.assigns.current_user
    orders = Store.basket(Store.get_user_order(user, socket.assigns.order.id))
    assign(socket, order: hd(orders), basket: Store.receipt(orders), balance: Wallet.balance(user))
  end

  defp load_list(socket) do
    user = socket.assigns.current_user
    assign(socket, receipts: Store.list_user_receipts(user), open: Store.open_checkouts(user), balance: Wallet.balance(user))
  end

  @impl true
  def handle_info({:order_updated, _order}, %{assigns: %{order: %{}}} = socket), do: {:noreply, load_order(socket)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel_checkout", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    socket =
      case Store.cancel_checkout(user, id) do
        {:ok, _} -> put_flash(socket, :info, "Checkout cancelled. Nothing was charged.")
        {:error, reason} -> put_flash(socket, :error, Store.reason_text(reason))
      end

    {:noreply, if(socket.assigns.order, do: load_order(socket), else: load_list(socket))}
  end

  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  attr :receipt, :map, required: true

  defp checkout_actions(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-3 pt-1">
      <a :if={Store.resumable?(@receipt)} href={@receipt.lead.checkout_url} class="rounded-lg bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-500">
        Continue to payment
      </a>
      <button type="button" phx-click="cancel_checkout" phx-value-id={@receipt.lead.id} class="rounded-lg bg-gray-800 px-4 py-2 text-sm text-gray-200 hover:bg-gray-700">
        Cancel checkout
      </button>
    </div>
    """
  end

  defp gems(%{orders: orders}), do: Enum.sum(Enum.map(orders, &(&1.gems || 0)))

  defp status_text("awaiting_payment"), do: "Not paid yet: the checkout is open"
  defp status_text("paid"), do: "Paid, being delivered"
  defp status_text("fulfilled"), do: "Complete"
  defp status_text("failed"), do: "Checkout closed: nothing was charged"
  defp status_text("cancelled"), do: "Checkout cancelled: nothing was charged"
  defp status_text("disputed"), do: "Disputed with your bank"
  defp status_text("charged_back"), do: "Charged back"
  defp status_text(other), do: other

  @impl true
  def render(assigns) do
    ~H"""
    <.store_styles />
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black">
      <div class="max-w-3xl mx-auto px-4 sm:px-6 py-12 sm:py-16">
        <.link navigate={~p"/store"} class="text-sm text-gray-400 hover:text-white">← Store</.link>

        <%= if @order do %>
          <h1 class="text-3xl font-bold text-white mt-6 mb-6">Order #{@order.number}</h1>
          <p :if={@notice} id="checkout-notice" class="mb-6 rounded-lg border border-gray-700 bg-gray-900 px-4 py-3 text-gray-200">{@notice}</p>
          <.receipt receipt={@basket} tz={@tz} id="order-receipt" />
          <div class="mt-6 glass-dark rounded-lg p-6 border border-gray-700 space-y-2 text-gray-300">
            <div><span class="text-gray-500">Status:</span> <span class="text-white">{status_text(@order.status)}</span></div>
            <div :if={gems(@basket) > 0 and @order.paid_at}><span class="text-gray-500">Gems:</span> <Bacon8Web.Components.Gem.gems amount={gems(@basket)} /></div>
            <div :if={@order.status == "awaiting_payment"} class="pt-2 space-y-3">
              <p class="text-sm text-gray-400">
                If you've paid, this page updates by itself in a moment. If not, finish paying or cancel:
                an unfinished checkout closes by itself after half an hour.
              </p>
              <.checkout_actions receipt={@basket} />
            </div>
            <p :if={@order.status == "paid"} class="text-sm text-gray-400 pt-2">
              Your payment went through. We're finishing your delivery and will have it in your library shortly.
            </p>
            <p :if={@order.status == "fulfilled" and gems(@basket) > 0} class="text-sm text-green-300 pt-2">
              Your Gems have been added. Balance: <Bacon8Web.Components.Gem.gems amount={@balance} />
            </p>
            <p :if={@order.status == "fulfilled" and gems(@basket) == 0} class="text-sm text-green-300 pt-2">
              Delivered. <.link navigate={~p"/store/library"} class="text-blue-400 hover:underline">Open your library</.link>
            </p>
          </div>
        <% else %>
          <h1 class="text-3xl font-bold text-white mt-6 mb-2">Purchases</h1>
          <p class="text-gray-400 mb-6">
            Balance: <Bacon8Web.Components.Gem.gems amount={@balance} /> ·
            <.link navigate={~p"/store/library"} class="text-blue-400 hover:underline">Library</.link>
          </p>
          <section :if={@open != []} id="open-checkouts" class="mb-8">
            <h2 class="text-lg font-semibold text-white mb-1">Unfinished checkout</h2>
            <p class="text-sm text-gray-400 mb-3">Not paid. Finish paying, or cancel it: nothing has been charged.</p>
            <div class="rc-grid">
              <.receipt :for={r <- @open} receipt={r} tz={@tz} id={"open-#{r.lead.id}"}>
                <.checkout_actions receipt={r} />
              </.receipt>
            </div>
          </section>
          <div :if={@receipts == []} class="text-gray-500">No purchases yet.</div>
          <div class="rc-grid">
            <.receipt :for={r <- @receipts} receipt={r} tz={@tz} href={~p"/store/orders/#{r.lead.id}"} id={"receipt-#{r.lead.id}"} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
