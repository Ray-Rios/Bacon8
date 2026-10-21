defmodule BaconStoreWeb.FakeCheckoutLive do
  @moduledoc """
  /store/fake-checkout/:ref - the fake payment provider's "hosted checkout",
  for development and tests (`BaconStore.Payments.Fake`). Pay and Cancel send
  the same events a real provider's webhook would. Sends you back to the
  store unless the fake provider is enabled and the order is yours.
  """
  use Bacon8Web, :live_view

  alias BaconStore.Payments.Fake
  alias BaconStore.Store

  on_mount {Bacon8Web.UserAuth, :require_authenticated_user}

  @impl true
  def mount(%{"ref" => ref}, _session, socket) do
    user = socket.assigns.current_user

    with true <- BaconStore.Payments.fake_enabled?(),
         %Store.Order{} = order <- Store.get_order_by_ref("fake", ref),
         true <- order.user_id == user.id do
      {:ok, assign(socket, page_title: "Test checkout", order: order)}
    else
      _ -> {:ok, socket |> put_flash(:error, "That checkout isn't available.") |> push_navigate(to: ~p"/store")}
    end
  end

  @impl true
  def handle_event("pay", _params, socket) do
    order = socket.assigns.order
    Fake.complete(order.provider_ref, order.amount_cents, order.currency)
    {:noreply, push_navigate(socket, to: ~p"/store/orders/#{order.id}")}
  end

  def handle_event("decline", _params, socket) do
    order = socket.assigns.order
    Fake.fail(order.provider_ref)
    {:noreply, push_navigate(socket, to: ~p"/store/orders/#{order.id}")}
  end

  def handle_event("cancel", _params, socket) do
    {:ok, order} = Store.cancel_unpaid(socket.assigns.order)
    {:noreply, push_navigate(socket, to: ~p"/store/orders/#{order.id}")}
  end

  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black">
      <div class="max-w-md mx-auto px-6 py-16">
        <div class="glass-dark rounded-lg p-6 border border-yellow-600">
          <div class="text-xs uppercase tracking-wide text-yellow-400 mb-2">Test checkout - no real money</div>
          <h1 class="text-2xl font-bold text-white mb-1">{@order.product_name}</h1>
          <p class="text-gray-300 mb-6">{Store.format_price(@order.amount_cents, @order.currency)}</p>
          <div class="flex flex-col gap-3">
            <button phx-click="pay" class="px-4 py-2 rounded bg-green-600 hover:bg-green-700 text-white font-semibold">Pay</button>
            <button phx-click="decline" class="px-4 py-2 rounded bg-red-700 hover:bg-red-800 text-white">Card declined</button>
            <button phx-click="cancel" class="px-4 py-2 rounded bg-gray-600 hover:bg-gray-500 text-white">Cancel</button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
