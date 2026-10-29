defmodule BaconStoreWeb.Admin.OrdersLive do
  @moduledoc """
  /admin/bacon_store/orders - store orders and the payment provider's event inbox
  (BACON8.md §8). An order changes only when the provider says so, and sales
  are final, so there is nothing here to refund or mark paid. The one action
  is retrying delivery of an order that was paid but couldn't be delivered
  (a key product that ran out, say), once the cause is fixed.

  Since 2026-10-29 purchases show as receipts (`StoreComponents.receipt/1`): one card per purchase
  with its number, buyer, items and total, a purchase of several items (the cart) being one
  receipt; the detail shows each item's order.
  """
  use Bacon8Web, :live_view
  import BaconStoreWeb.StoreComponents, only: [receipt: 1, store_styles: 1]
  alias BaconStore.{Payments, Store}
  alias BaconStore.Store.Order
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Admin - Orders",
       statuses: Order.statuses(),
       filter_status: nil,
       receipts: Store.list_receipts(),
       events: Payments.recent_events(25),
       order: nil,
       basket: nil
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Store.get_order(id) do
      nil -> {:noreply, socket |> put_flash(:error, "No such order.") |> push_patch(to: ~p"/admin/bacon_store/orders")}
      order -> {:noreply, assign(socket, order: order, basket: Store.receipt(Store.basket(order) |> Bacon8.Repo.preload(:user)))}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, assign(socket, order: nil, basket: nil)}

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    status = if status in socket.assigns.statuses, do: status, else: nil
    {:noreply, assign(socket, filter_status: status, receipts: Store.list_receipts(status: status))}
  end

  def handle_event("retry_delivery", %{"id" => id}, socket) do
    with %Order{} = order <- Store.get_order(id),
         {:ok, order} <- Store.retry_delivery(order) do
      Bacon8.Audit.log(socket.assigns.current_user.id, "store.delivery_retried", "store_order", order.id, %{number: order.number, product: order.product_name})

      {:noreply,
       socket
       |> assign(order: Store.get_order(order.id), basket: Store.receipt(Store.basket(order) |> Bacon8.Repo.preload(:user)), receipts: Store.list_receipts(status: socket.assigns.filter_status))
       |> put_flash(:info, "Delivered.")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Still can't deliver: #{inspect(reason)}")}
      _ -> {:noreply, put_flash(socket, :error, "No such order.")}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply,
     assign(socket,
       receipts: Store.list_receipts(status: socket.assigns.filter_status),
       events: Payments.recent_events(25)
     )}
  end

  defp status_class(status) do
    case status do
      "fulfilled" -> "bg-green-900 text-green-200"
      "paid" -> "bg-green-900 text-green-200"
      "awaiting_payment" -> "bg-yellow-900 text-yellow-200"
      "disputed" -> "bg-orange-900 text-orange-200"
      "charged_back" -> "bg-red-900 text-red-200"
      "failed" -> "bg-red-900 text-red-200"
      _ -> "bg-gray-700 text-gray-300"
    end
  end

  defp status_label(status), do: status |> String.replace("_", " ") |> String.capitalize()

  defp when_(nil), do: "—"
  defp when_(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp buyer(%Order{user: %{email: email}}), do: email
  defp buyer(_), do: "—"

  @impl true
  def render(assigns) do
    ~H"""
    <.store_styles />
    <AdminSidebar.admin_layout current_path="/admin/bacon_store/orders">
      <div class="max-w-6xl mx-auto space-y-8">
        <div class="dark-glass p-4 sm:p-8 rounded-xl">
          <div class="flex flex-wrap justify-between items-center gap-4 mb-8">
            <div>
              <h1 class="text-3xl font-bold text-white">Orders</h1>
              <p class="text-gray-400 mt-1">Every purchase, as the payment provider reported it. Sales are final.</p>
            </div>
            <div class="flex items-center gap-3">
              <form phx-change="filter_status">
                <select name="status" class="bg-gray-700 border-gray-600 text-white rounded-lg px-3 py-2 text-sm">
                  <option value="">All orders</option>
                  <option :for={s <- @statuses} value={s} selected={@filter_status == s}>{status_label(s)}</option>
                </select>
              </form>
              <button phx-click="refresh" class="px-3 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-white text-sm">Refresh</button>
            </div>
          </div>

          <div :if={@order} class="mb-8 rounded-lg border border-gray-700 bg-gray-900/60 p-4 sm:p-6">
            <div class="flex justify-between items-start mb-4">
              <h2 class="text-lg font-semibold text-white">Order #{@order.number}</h2>
              <.link patch={~p"/admin/bacon_store/orders"} class="text-gray-400 hover:text-white text-sm">Close</.link>
            </div>
            <div class="grid gap-6 lg:grid-cols-[minmax(0,22rem)_1fr]">
              <.receipt receipt={@basket} show_buyer />
              <div class="space-y-4">
                <div :for={o <- @basket.orders} class="rounded-lg border border-gray-800 bg-black/30 p-4">
                  <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
                    <span class="font-semibold text-white">{o.product_name}</span>
                    <span class={["px-2 py-0.5 rounded-full text-xs font-medium", status_class(o.status)]}>{status_label(o.status)}</span>
                  </div>
                  <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 text-sm">
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Buyer</dt><dd class="text-gray-200 break-all text-right">{buyer(o)}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Amount</dt><dd class="text-gray-200">{Store.order_price(o)}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Gems</dt><dd class="text-gray-200">{o.gems}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Provider</dt><dd class="text-gray-200">{o.provider}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Checkout ref</dt><dd class="text-gray-200 font-mono text-xs break-all text-right">{o.provider_ref || "—"}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Payment ref</dt><dd class="text-gray-200 font-mono text-xs break-all text-right">{o.provider_payment_ref || "—"}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Created</dt><dd class="text-gray-200">{when_(o.inserted_at)}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Paid</dt><dd class="text-gray-200">{when_(o.paid_at)}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Fulfilled</dt><dd class="text-gray-200">{when_(o.fulfilled_at)}</dd></div>
                    <div class="flex justify-between gap-3"><dt class="text-gray-500">Terms accepted</dt><dd class="text-gray-200">{when_(o.terms_accepted_at)}</dd></div>
                    <div :if={o.failure_reason} class="sm:col-span-2 flex justify-between gap-3"><dt class="text-gray-500">Reason</dt><dd class="text-red-300 text-right">{o.failure_reason}</dd></div>
                  </dl>
                  <div :if={o.status == "paid"} class="mt-3 flex flex-wrap items-center gap-3">
                    <button phx-click="retry_delivery" phx-value-id={o.id} class="px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-white text-sm font-semibold">
                      Retry delivery
                    </button>
                    <span class="text-sm text-gray-400">Fix the cause first (add license keys, restore the channel).</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div :if={@receipts != []} class="rc-grid">
            <.receipt
              :for={r <- @receipts}
              receipt={r}
              show_buyer
              href={~p"/admin/bacon_store/orders/#{r.lead.id}"}
              patch
              id={"admin-receipt-#{r.lead.id}"}
            />
          </div>
          <p :if={@receipts == []} class="rounded-lg border border-gray-700 px-4 py-8 text-center text-gray-500">No orders yet.</p>
        </div>

        <div class="dark-glass p-4 sm:p-8 rounded-xl">
          <h2 class="text-xl font-semibold text-white mb-1">Payment events</h2>
          <p class="text-gray-400 text-sm mb-6">
            What the provider has told us, newest first. An event with an error is retried when the provider sends it again.
          </p>
          <div class="overflow-x-auto rounded-lg border border-gray-700">
            <table class="min-w-full text-sm">
              <thead class="bg-gray-900/80 text-gray-300">
                <tr>
                  <th class="px-4 py-3 text-left font-semibold">Received</th>
                  <th class="px-4 py-3 text-left font-semibold">Provider</th>
                  <th class="px-4 py-3 text-left font-semibold">Event</th>
                  <th class="px-4 py-3 text-left font-semibold">Result</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-800">
                <tr :for={e <- @events} class="text-gray-200">
                  <td class="px-4 py-3 whitespace-nowrap">{when_(e.inserted_at)}</td>
                  <td class="px-4 py-3 text-gray-400">{e.provider}</td>
                  <td class="px-4 py-3">
                    <div>{status_label(e.event_type)}</div>
                    <div class="text-xs text-gray-500 font-mono">{e.provider_event_id}</div>
                  </td>
                  <td class="px-4 py-3">
                    <%= cond do %>
                      <% e.error -> %>
                        <span class="text-red-300">{e.error}</span>
                      <% e.processed_at -> %>
                        <span class="text-green-300">Applied</span>
                      <% true -> %>
                        <span class="text-yellow-300">Pending</span>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@events == []} class="px-4 py-8 text-center text-gray-500">No events yet.</p>
          </div>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
