defmodule BaconStore.Plugin do
  @moduledoc """
  Bacon Store: products, checkout, the Gems ledger, payment providers and
  their webhooks, the buyer's library, the sweeper and the store admin
  (BACON8.md §8). The reference *site* plugin (ADR 0001, phase 3): it mounts at
  `/store` rather than under `/games`, and reaches the hub only through
  public contexts and plugin hooks.

  Its tables keep their names (`store_*`, `wallet_*`, `payment_events`), a
  documented exception to the `<slug>_` prefix: they hold money, and renaming
  a ledger buys nothing.
  """
  use Bacon8.Plugin,
    slug: "bacon_store",
    name: "Bacon Store",
    version: "1.0.0",
    description: "Products, checkout, Gems, payments, the buyer's library."

  import Ecto.Query, only: [from: 2]

  alias Bacon8.Repo
  alias BaconStore.Store
  alias BaconStore.Store.{LicenseKey, Order, ProductFile}
  alias BaconStore.Store.Fulfilment
  alias BaconStore.Wallet.Account

  @impl true
  def mount, do: "store"

  @impl true
  def routes, do: BaconStoreWeb.Routes

  @impl true
  def children, do: [BaconStore.Store.Sweeper]

  @impl true
  def admin_nav do
    [
      %{label: "Products", path: "/admin/bacon_store/products", icon: "gem"},
      %{label: "Orders", path: "/admin/bacon_store/orders", icon: "📦"}
    ]
  end

  @impl true
  def entitlement_kinds, do: [Fulfilment.download_kind(), Fulfilment.channel_access_kind(), "channel_slots"]

  # Orders, the Gem ledger and license keys sold are sales records: an account
  # that has any is anonymised, not deleted (BACON8.md §8).
  @impl true
  def retains_user_data?(user_id) do
    Repo.exists?(from o in Order, where: o.user_id == ^user_id) or
      Repo.exists?(from a in Account, where: a.user_id == ^user_id) or
      Repo.exists?(from k in LicenseKey, where: k.user_id == ^user_id)
  end

  # Product images and downloads live in the drive's blob store.
  @impl true
  def storage_refs, do: Repo.all(from f in ProductFile, distinct: true, select: f.sha256)

  @impl true
  # "gem": the site's Gem (Bacon8Web.Components.Gem), turning and floating in the navbar.
  def nav_links(_user), do: [%{label: "Store", path: "/store", icon: "gem"}]

  @impl true
  def profile_tabs(_user) do
    [
      %{label: "Orders", path: "/store/orders", icon: "🧾"},
      %{label: "Library", path: "/store/library", icon: "📚"}
    ]
  end

  # Payment providers sign the exact bytes they send.
  @impl true
  def raw_body_paths, do: ["/api/store/webhooks/"]

  @impl true
  def admin_tools do
    [
      %{
        id: "list_orders",
        name: "List Orders",
        category: "commerce",
        category_label: "Store",
        method: "GET",
        path: "/api/admin/orders",
        description: "Retrieve up to 50 most recent store orders with status and amounts.",
        fields: [],
        run: &__MODULE__.list_orders_tool/2
      }
    ]
  end

  @doc false
  def list_orders_tool(_params, _admin) do
    orders = Store.list_orders(limit: 50)

    {:ok,
     %{
       message: "Fetched #{length(orders)} orders (limited to 50)",
       data:
         Enum.map(orders, fn order ->
           %{
             id: order.id,
             status: order.status,
             product: order.product_name,
             total: Store.order_price(order),
             provider: order.provider,
             user_email: order.user && order.user.email,
             inserted_at: order.inserted_at
           }
         end),
       count: length(orders)
     }}
  end

  @impl true
  def admin_dashboard do
    stats = Store.stats()

    %{
      stats: [
        %{label: "Products on sale", value: stats.products, icon: "💎"},
        %{label: "Revenue today", value: Store.format_price(stats.revenue_today_cents, "usd"), icon: "💵"},
        %{label: "Revenue this month", value: Store.format_price(stats.revenue_month_cents, "usd"), icon: "📈"}
      ],
      panels: [
        %{
          title: "Recent Orders",
          empty: "No orders yet",
          items:
            for order <- Store.list_orders(limit: 5) do
              %{
                title: order.product_name,
                path: "/admin/bacon_store/orders/#{order.id}",
                subtitle: order.user && order.user.email,
                value: Store.order_price(order),
                badge: order.status |> String.replace("_", " ") |> String.capitalize()
              }
            end
        }
      ]
    }
  end
end
