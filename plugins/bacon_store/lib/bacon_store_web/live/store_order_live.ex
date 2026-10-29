defmodule BaconStoreWeb.StoreOrderLive do
  @moduledoc """
  /store/orders and /store/orders/:id - the buyer's purchase history and one
  order's status. Coming back from checkout lands here; the page shows
  "processing" until the provider's event arrives and then updates live.

  Since 2026-10-29 both show receipts (`StoreComponents.receipt/1`): a purchase of several items
  (the cart) is one receipt with one number, and `/store/orders/:id` shows the receipt of the
  basket that order belongs to.
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
        {:ok, assign(socket, page_title: "Purchases", order: nil, receipts: Store.list_user_receipts(user), balance: Wallet.balance(user))}

      id ->
        case Store.get_user_order(user, id) do
          nil ->
            {:ok, socket |> put_flash(:error, "Order not found.") |> push_navigate(to: ~p"/store")}

          order ->
            orders = Store.basket(order)
            if connected?(socket), do: Enum.each(orders, &Phoenix.PubSub.subscribe(Bacon8.PubSub, Store.topic(&1)))
            {:ok, assign(socket, page_title: "Order ##{order.number}", order: order, basket: Store.receipt(orders), receipts: [], balance: Wallet.balance(user))}
        end
    end
  end

  @impl true
  def handle_info({:order_updated, _order}, %{assigns: %{order: %{} = lead}} = socket) do
    orders = Store.basket(Store.get_user_order(socket.assigns.current_user, lead.id))
    {:noreply, assign(socket, order: hd(orders), basket: Store.receipt(orders), balance: Wallet.balance(socket.assigns.current_user))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  defp gems(%{orders: orders}), do: Enum.sum(Enum.map(orders, &(&1.gems || 0)))

  defp status_text("awaiting_payment"), do: "Waiting for payment"
  defp status_text("paid"), do: "Paid, being delivered"
  defp status_text("fulfilled"), do: "Complete"
  defp status_text("failed"), do: "Payment didn't go through"
  defp status_text("cancelled"), do: "Cancelled"
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
          <.receipt receipt={@basket} tz={@tz} id="order-receipt" />
          <div class="mt-6 glass-dark rounded-lg p-6 border border-gray-700 space-y-2 text-gray-300">
            <div><span class="text-gray-500">Status:</span> <span class="text-white">{status_text(@order.status)}</span></div>
            <div :if={gems(@basket) > 0}><span class="text-gray-500">Gems:</span> <Bacon8Web.Components.Gem.gems amount={gems(@basket)} /></div>
            <p :if={@order.status == "awaiting_payment"} class="text-sm text-gray-400 pt-2">
              This page updates by itself once the payment is confirmed.
            </p>
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
