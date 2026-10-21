defmodule BaconStoreWeb.StoreOrderLive do
  @moduledoc """
  /store/orders and /store/orders/:id - the buyer's purchase history and one
  order's status. Coming back from checkout lands here; the page shows
  "processing" until the provider's event arrives and then updates live.
  """
  use Bacon8Web, :live_view

  import BaconStoreWeb.StoreComponents, only: [timezone: 1, local_datetime: 2]
  alias BaconStore.{Store, Wallet}

  on_mount {Bacon8Web.UserAuth, :require_authenticated_user}

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    socket = assign(socket, tz: timezone(socket))

    case params["id"] do
      nil ->
        {:ok, assign(socket, page_title: "Purchases", order: nil, orders: Store.list_user_orders(user), balance: Wallet.balance(user))}

      id ->
        case Store.get_user_order(user, id) do
          nil ->
            {:ok, socket |> put_flash(:error, "Order not found.") |> push_navigate(to: ~p"/store")}

          order ->
            if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, Store.topic(order))
            {:ok, assign(socket, page_title: "Order", order: order, orders: [], balance: Wallet.balance(user))}
        end
    end
  end

  @impl true
  def handle_info({:order_updated, order}, socket) do
    {:noreply, assign(socket, order: order, balance: Wallet.balance(socket.assigns.current_user))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

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
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black">
      <div class="max-w-3xl mx-auto px-6 py-16">
        <.link navigate={~p"/store"} class="text-sm text-gray-400 hover:text-white">← Store</.link>

        <%= if @order do %>
          <h1 class="text-3xl font-bold text-white mt-6 mb-6">{@order.product_name}</h1>
          <div class="glass-dark rounded-lg p-6 border border-gray-700 space-y-2 text-gray-300">
            <div><span class="text-gray-500">Ordered:</span> {local_datetime(@order.inserted_at, @tz)}</div>
            <div><span class="text-gray-500">Status:</span> <span class="text-white">{status_text(@order.status)}</span></div>
            <div><span class="text-gray-500">Price:</span> {Store.order_price(@order)}</div>
            <div :if={@order.gems > 0}><span class="text-gray-500">Gems:</span> {Store.format_gems(@order.gems)}</div>
            <p :if={@order.status == "awaiting_payment"} class="text-sm text-gray-400 pt-2">
              This page updates by itself once the payment is confirmed.
            </p>
            <p :if={@order.status == "paid"} class="text-sm text-gray-400 pt-2">
              Your payment went through. We're finishing your delivery and will have it in your library shortly.
            </p>
            <p :if={@order.status == "fulfilled" and @order.gems > 0} class="text-sm text-green-300 pt-2">
              Your Gems have been added. Balance: {Store.format_gems(@balance)}
            </p>
            <p :if={@order.status == "fulfilled" and @order.gems == 0} class="text-sm text-green-300 pt-2">
              Delivered. <.link navigate={~p"/store/library"} class="text-blue-400 hover:underline">Open your library</.link>
            </p>
          </div>
        <% else %>
          <h1 class="text-3xl font-bold text-white mt-6 mb-2">Purchases</h1>
          <p class="text-gray-400 mb-6">
            Balance: {Store.format_gems(@balance)} ·
            <.link navigate={~p"/store/library"} class="text-blue-400 hover:underline">Library</.link>
          </p>
          <div :if={@orders == []} class="text-gray-500">No purchases yet.</div>
          <div class="space-y-2">
            <.link
              :for={o <- @orders}
              navigate={~p"/store/orders/#{o.id}"}
              class="flex items-center justify-between gap-4 glass-dark rounded p-4 border border-gray-700 hover:border-blue-400"
            >
              <span class="min-w-0">
                <span class="block text-white">{o.product_name}</span>
                <span class="block text-xs text-gray-500">{local_datetime(o.inserted_at, @tz)}</span>
              </span>
              <span class="text-right text-gray-400">{Store.order_price(o)} · {status_text(o.status)}</span>
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
