defmodule BaconStore.Store do
  @moduledoc """
  The store (BACON8.md §8): Gem packs and digital products (downloads, game
  items, access passes, license keys). Buy one item from its sheet, or several at once from the
  cart (`BaconStore.Store.Cart`, 2026-10-29): a basket of orders with one receipt number.
  What's for sale lives in `BaconStore.Store.Catalog`; what a purchase delivers
  in `BaconStore.Store.Fulfilment`.

  Buying with a card: `start_checkout/3` creates an order and a hosted
  checkout and returns where to send the buyer. The order is paid only when
  the provider's event says so (`apply_event/1`, called by
  `BaconStore.Payments`), never because the buyer came back to the success page.
  Delivery happens in the same transaction that marks the order paid.

  Buying with Gems: `buy_with_gems/2` spends the Gems and delivers in one
  transaction; nothing is left half done.

  **Unfinished checkouts** (2026-10-29c): a buyer has at most one open card checkout. Starting
  another closes the old one at the provider first (`settle_open_checkouts/1`); so do the buyer's
  Cancel (`cancel_checkout/2`), the provider's cancel link, and the sweeper once a checkout's 31
  minutes are up (`settle_stale_checkouts/1`). Before anything is closed or shown as waiting, the
  provider is asked where the checkout stands (`reconcile/1`), so a payment whose webhook is late
  is delivered rather than cancelled. A closed, unpaid checkout was never a purchase: Purchases
  leaves it out; admins see it under "Abandoned checkouts".

  Sales are final: there's no refund path. While the buyer's bank disputes a
  payment, what the order delivered is taken away; it comes back if the hub
  wins and is gone for good if it loses (`Fulfilment.revoke/3`,
  `Fulfilment.reinstate/2`).
  """

  import Ecto.Query
  require Logger

  alias Bacon8.Repo
  alias BaconStore.Wallet
  alias Bacon8.Accounts.User
  alias BaconStore.Payments.Event
  alias BaconStore.Store.{Catalog, Fulfilment, Order, Product}

  @gems_per_dollar 100

  @doc "The house rate: 100 Gems = US$1."
  def gems_per_dollar, do: @gems_per_dollar

  def topic(%Order{id: id}), do: "store:order:#{id}"
  def topic(id) when is_binary(id), do: "store:order:#{id}"

  # ---------------------------------------------------------------------------
  # Products (see BaconStore.Store.Catalog for the rest)
  # ---------------------------------------------------------------------------

  defdelegate gem_packs(), to: Catalog
  defdelegate get_product(id), to: Catalog
  defdelegate create_product(attrs), to: Catalog
  defdelegate update_product(product, attrs), to: Catalog

  def list_products, do: Catalog.list_admin_products()

  @doc "Gems a pack gives if bought at `now`: its Gems, plus its bonus while a promotion runs."
  def gems_for(%Product{gems: gems} = p, now \\ DateTime.utc_now()) do
    (gems || 0) + if(promo_active?(p, now), do: p.bonus_gems || 0, else: 0)
  end

  def promo_active?(%Product{bonus_gems: bonus} = p, now \\ DateTime.utc_now()) do
    is_integer(bonus) and bonus > 0 and not is_nil(p.promo_starts_at) and not is_nil(p.promo_ends_at) and
      DateTime.compare(now, p.promo_starts_at) != :lt and DateTime.compare(now, p.promo_ends_at) == :lt
  end

  @doc "The Gem price that matches a card price at the house rate."
  def gems_for_cents(cents) when is_integer(cents), do: div(cents * @gems_per_dollar, 100)

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  @doc "US$ for display: 500 -> \"$5.00\"."
  def format_price(nil, _currency), do: "—"
  def format_price(cents, "usd"), do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)
  def format_price(cents, currency), do: "#{:erlang.float_to_binary(cents / 100, decimals: 2)} #{String.upcase(currency)}"

  @doc "1500 -> \"💎 1,500\"."
  def format_gems(n), do: "💎 " <> format_number(n)

  @doc "1500 -> \"1,500\"."
  def format_number(n) when is_integer(n) do
    sign = if n < 0, do: "-", else: ""
    digits = n |> abs() |> Integer.to_string() |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
    sign <> digits
  end

  def format_number(_), do: "0"

  @doc "What an order cost, card or Gems."
  def order_price(%Order{provider: "gems", amount_gems: gems}), do: format_gems(gems || 0)
  def order_price(%Order{amount_cents: cents, currency: currency}), do: format_price(cents, currency)

  # ---------------------------------------------------------------------------
  # Who can buy
  # ---------------------------------------------------------------------------

  @doc "Is a card payment provider configured? (False in production until Stripe is set up.)"
  def checkout_available?, do: match?({:ok, _}, BaconStore.Payments.provider(BaconStore.Payments.default_provider()))

  @doc """
  `:ok`, or why this user can't buy: `:not_signed_in`, `:not_eligible`
  (Guest or Banned, or the account isn't active) or `:email_unverified`.
  Members and up may buy, the same rule as storage tiers.
  """
  def can_buy(nil), do: {:error, :not_signed_in}

  def can_buy(%User{} = user) do
    cond do
      not Bacon8.Drive.Policy.can_purchase_storage?(user) -> {:error, :not_eligible}
      not User.email_verified?(user) -> {:error, :email_unverified}
      true -> :ok
    end
  end

  @doc """
  Can this user buy this product right now? `:ok`, or one of `can_buy/1`'s
  reasons, `:not_for_sale`, or one of `Fulfilment.check/2`'s
  (`:already_owned`, `:already_member`, `:banned_from_channel`, `:sold_out`).
  """
  def purchase_check(user, %Product{} = product) do
    with :ok <- can_buy(user),
         :ok <- check_product(product) do
      Fulfilment.check(user, product)
    end
  end

  defp check_product(%Product{active: false}), do: {:error, :not_for_sale}
  defp check_product(%Product{kind: kind}), do: if(kind in Product.kinds(), do: :ok, else: {:error, :not_for_sale})

  @doc "A sentence for each reason a purchase can't go ahead."
  def reason_text(:not_signed_in), do: "Sign in to buy."
  def reason_text(:email_unverified), do: "Verify your email address to buy."
  def reason_text(:not_eligible), do: "Your account can't make purchases."
  def reason_text(:not_for_sale), do: "This isn't for sale right now."
  def reason_text(:already_owned), do: "You already own this."
  def reason_text(:already_member), do: "You're already in this channel."
  def reason_text(:banned_from_channel), do: "You've been banned from this channel."
  def reason_text(:sold_out), do: "Sold out."
  def reason_text(:insufficient_gems), do: "You don't have enough Gems."
  def reason_text(:not_for_card), do: "This can only be bought with Gems."
  def reason_text(:not_for_gems), do: "This can't be bought with Gems."
  def reason_text(:unknown_provider), do: "Card payments aren't available yet."
  def reason_text(:empty_basket), do: "Your cart is empty."
  def reason_text(:duplicate_item), do: "Each item can be in the cart once."
  def reason_text(:mixed_currency), do: "These items are priced in different currencies: buy them separately."
  def reason_text(:checkout_open), do: "Your last checkout couldn't be closed, so a new one wasn't started. Try again in a minute."
  def reason_text(:already_paid), do: "That checkout was already paid. It's in your purchases."
  def reason_text(:cart_full), do: "Your cart is full (#{BaconStore.Store.Cart.max_items()} items)."
  def reason_text({%Product{name: name}, reason}), do: "#{name}: #{reason_text(reason)}"
  def reason_text(_), do: "Something went wrong. Please try again."

  # ---------------------------------------------------------------------------
  # Baskets: one or more items in one purchase (2026-10-29)
  # ---------------------------------------------------------------------------
  #
  # Each item is its own order (delivery, keys and disputes stay per item); the orders of one
  # purchase share a basket_id and a number, and a card basket is one provider checkout.

  @doc """
  Can `user` buy all of `products` together, by `:card` or with `:gems`? `:ok`, `{:error, reason}`
  for the whole basket (`can_buy/1`'s reasons, `:empty_basket`, `:duplicate_item`,
  `:mixed_currency`), or `{:error, {product, reason}}` for the first item that can't be bought
  (`purchase_check/2`'s reasons, `:not_for_card`, `:not_for_gems`).
  """
  def basket_check(user, products, how) when how in [:card, :gems] do
    with :ok <- can_buy(user),
         :ok <- if(products == [], do: {:error, :empty_basket}, else: :ok),
         :ok <- if(Enum.uniq_by(products, & &1.id) == products, do: :ok, else: {:error, :duplicate_item}),
         :ok <- each_item(user, products, how) do
      if how == :card and length(Enum.uniq_by(products, & &1.currency)) > 1, do: {:error, :mixed_currency}, else: :ok
    end
  end

  defp each_item(user, products, how) do
    Enum.reduce_while(products, :ok, fn p, :ok ->
      case item_check(user, p, how) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {p, reason}}}
      end
    end)
  end

  defp item_check(user, product, :card) do
    with :ok <- purchase_check(user, product) do
      if is_integer(product.price_cents), do: :ok, else: {:error, :not_for_card}
    end
  end

  defp item_check(user, product, :gems) do
    with :ok <- purchase_check(user, product) do
      if is_integer(product.price_gems) and product.kind != "gem_pack", do: :ok, else: {:error, :not_for_gems}
    end
  end

  @doc "What a basket costs: `%{cents: n, currency: c}` by card, `%{gems: n}` in Gems (nil when an item has no such price)."
  def basket_price(products, :card) do
    if Enum.all?(products, &is_integer(&1.price_cents)),
      do: %{cents: Enum.sum(Enum.map(products, & &1.price_cents)), currency: (List.first(products) || %{currency: "usd"}).currency},
      else: nil
  end

  def basket_price(products, :gems) do
    if products != [] and Enum.all?(products, &(is_integer(&1.price_gems) and &1.kind != "gem_pack")),
      do: %{gems: Enum.sum(Enum.map(products, & &1.price_gems))},
      else: nil
  end

  # The next receipt number, shared by every order of one basket.
  defp next_number do
    %{rows: [[n]]} = Repo.query!("SELECT nextval('store_order_number_seq')")
    n
  end

  # ---------------------------------------------------------------------------
  # Buying with a card
  # ---------------------------------------------------------------------------

  @doc """
  Creates an order and a hosted checkout. `opts`: `:provider` (default
  `BaconStore.Payments.default_provider/0`); `:success_url` and `:cancel_url`
  (built from the order id when not given). A license key is reserved for
  the order until it's paid, fails or is cancelled.

  Returns `{:ok, order, redirect_url}`. One product is a basket of one: see
  `start_basket_checkout/3`.
  """
  def start_checkout(user, %Product{} = product, opts \\ []) do
    case start_basket_checkout(user, [product], opts) do
      {:ok, [order], url} -> {:ok, order, url}
      {:error, {%Product{}, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  One hosted checkout for several products (the cart): an order per product, sharing a basket and
  a number, every key reserved at once. `{:ok, orders, redirect_url}` or one of `basket_check/3`'s
  errors (`:unknown_provider` when card payments aren't set up).
  """
  def start_basket_checkout(user, products, opts \\ []) when is_list(products) do
    provider_name = Keyword.get(opts, :provider, BaconStore.Payments.default_provider())

    # One open checkout per buyer: close (or, if it was paid, deliver) the last one first, then
    # check the basket, so nothing paid a moment ago is bought twice.
    with :ok <- can_buy(user),
         {:ok, provider} <- BaconStore.Payments.provider(provider_name),
         :ok <- settle_open_checkouts(user),
         :ok <- basket_check(user, products, :card),
         {:ok, orders} <- create_card_basket(user, products, provider.name()) do
      [lead | _] = orders

      urls = [
        success_url: Keyword.get(opts, :success_url, "/store/orders/#{lead.id}?checkout=done"),
        cancel_url: Keyword.get(opts, :cancel_url, "/store/orders/#{lead.id}?checkout=cancelled"),
        lines: Enum.map(orders, &%{name: &1.product_name, amount_cents: &1.amount_cents}),
        basket_id: lead.basket_id,
        number: lead.number,
        email: user.email
      ]

      case provider.create_checkout(lead, urls) do
        {:ok, %{redirect_url: url, provider_ref: ref} = created} ->
          expires = created[:expires_at]

          Repo.update_all(from(o in Order, where: o.basket_id == ^lead.basket_id),
            set: [provider_ref: ref, checkout_url: url, checkout_expires_at: expires, updated_at: DateTime.utc_now()]
          )

          {:ok, Enum.map(orders, &%{&1 | provider_ref: ref, checkout_url: url, checkout_expires_at: expires}), url}

        {:error, reason} ->
          for o <- orders do
            Fulfilment.release(o)
            o |> Ecto.Changeset.change(status: "failed", failure_reason: "checkout: #{inspect(reason)}") |> Repo.update!()
          end

          {:error, {:checkout_failed, reason}}
      end
    end
  end

  defp create_card_basket(user, products, provider_name) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      basket_id = Ecto.UUID.generate()
      number = next_number()

      for product <- products do
        order =
          Repo.insert!(%Order{
            user_id: user.id,
            product_id: product.id,
            basket_id: basket_id,
            number: number,
            status: "awaiting_payment",
            provider: provider_name,
            product_name: product.name,
            amount_cents: product.price_cents,
            currency: product.currency,
            gems: if(product.kind == "gem_pack", do: gems_for(product, now), else: 0),
            terms_accepted_at: now
          })

        case Fulfilment.reserve(order, product) do
          :ok -> order
          {:error, reason} -> Repo.rollback({product, reason})
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Buying with Gems
  # ---------------------------------------------------------------------------

  @doc """
  Buys `product` with Gems: spends them and delivers, all or nothing.
  `{:ok, order}` or `{:error, reason}` (see `purchase_check/2`, plus
  `:not_for_gems` and `:insufficient_gems`).
  """
  def buy_with_gems(user, %Product{} = product) do
    case buy_basket_with_gems(user, [product]) do
      {:ok, [order]} -> {:ok, order}
      {:error, {%Product{}, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Buys several products with Gems at once: every item is paid and delivered, or none is (one
  transaction). `{:ok, orders}`, `{:error, :insufficient_gems}`, or one of `basket_check/3`'s errors.
  """
  def buy_basket_with_gems(user, products) when is_list(products) do
    with :ok <- basket_check(user, products, :gems) do
      Repo.transaction(fn ->
        now = DateTime.utc_now()
        basket_id = Ecto.UUID.generate()
        number = next_number()

        Enum.map_reduce(products, [], fn product, events ->
          order =
            Repo.insert!(%Order{
              user_id: user.id,
              product_id: product.id,
              basket_id: basket_id,
              number: number,
              status: "paid",
              provider: "gems",
              product_name: product.name,
              amount_gems: product.price_gems,
              currency: "gems",
              gems: 0,
              terms_accepted_at: now,
              paid_at: now
            })

          spend =
            Wallet.spend(user, product.price_gems,
              idempotency_key: "order:#{order.id}:spend",
              reference_type: "store_order",
              reference_id: order.id,
              memo: product.name
            )

          case spend do
            {:ok, _} -> :ok
            {:ok, _, :duplicate} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end

          case Fulfilment.deliver(order, product) do
            {:ok, new} -> {mark_fulfilled!(order), events ++ new}
            {:error, reason} -> Repo.rollback({product, reason})
          end
        end)
      end)
      |> case do
        {:ok, {orders, events}} ->
          Enum.each(orders, &after_commit(&1, []))
          Enum.each(events, &Bacon8.Plugins.notify/1)
          BaconStore.Store.Cart.remove_all(user.id, Enum.map(orders, & &1.product_id))
          {:ok, orders}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Orders
  # ---------------------------------------------------------------------------

  @doc "An order, if it belongs to this user."
  def get_user_order(%User{id: user_id}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Order{user_id: ^user_id} = order <- Repo.get(Order, uuid) do
      Repo.preload(order, :product)
    else
      _ -> nil
    end
  end

  @doc "The first order of the checkout `ref` (a basket's orders share it)."
  def get_order_by_ref(provider, ref),
    do: Repo.one(from o in Order, where: o.provider == ^provider and o.provider_ref == ^ref, order_by: [asc: o.inserted_at], limit: 1)

  @doc "Every order of `order`'s basket, in the order they were added (an order from before baskets is a basket of one)."
  def basket(%Order{basket_id: nil} = order), do: [Repo.preload(order, :product)]

  def basket(%Order{basket_id: basket_id}),
    do: Repo.all(from o in Order, where: o.basket_id == ^basket_id, order_by: [asc: o.inserted_at, asc: o.id], preload: [:product])

  @doc "The basket that order `id` belongs to, if it is this user's: its orders, or nil."
  def get_user_basket(%User{} = user, id) do
    case get_user_order(user, id) do
      nil -> nil
      order -> basket(order)
    end
  end

  @doc """
  A basket's receipt: `%{number, lead (its first order), orders, total, status, inserted_at}`. `total` is
  what was paid (`Store.order_price/1` for one order, else the sum). `status` is the orders' status
  when they agree (they move together), else the first's.
  """
  def receipt([%Order{} = lead | _] = orders) do
    %{
      number: lead.number,
      lead: lead,
      orders: orders,
      total: receipt_total(orders),
      status: lead.status,
      inserted_at: lead.inserted_at,
      user: Map.get(lead, :user)
    }
  end

  defp receipt_total([%Order{provider: "gems"} | _] = orders), do: format_gems(Enum.sum(Enum.map(orders, &(&1.amount_gems || 0))))

  defp receipt_total([%Order{currency: currency} | _] = orders),
    do: format_price(Enum.sum(Enum.map(orders, &(&1.amount_cents || 0))), currency)

  @doc "The user's purchases as receipts (`receipt/1`), newest first."
  # Only what was paid for (paid_at is set when money is taken, and stays through disputes):
  # unfinished checkouts are `open_checkouts/1`, abandoned ones were never purchases.
  def list_user_receipts(%User{id: user_id}, limit \\ 50) do
    Repo.all(
      from o in Order,
        where: o.user_id == ^user_id and not is_nil(o.paid_at),
        order_by: [desc: o.inserted_at, desc: o.id],
        limit: ^(limit * 4),
        preload: [:product]
    )
    |> group_receipts()
    |> Enum.take(limit)
  end

  @doc "The user's card checkouts still waiting for payment, as receipts, newest first (normally one)."
  def open_checkouts(%User{id: user_id}) do
    Repo.all(
      from o in Order,
        where: o.user_id == ^user_id and o.status == "awaiting_payment",
        order_by: [desc: o.inserted_at, desc: o.id],
        preload: [:product]
    )
    |> group_receipts()
  end

  def open_checkouts(_), do: []

  @doc "Can the buyer still go back and pay for this open checkout?"
  def resumable?(%{lead: %Order{status: "awaiting_payment", checkout_url: url} = o}, now \\ DateTime.utc_now()),
    do: is_binary(url) and (is_nil(o.checkout_expires_at) or DateTime.compare(o.checkout_expires_at, now) == :gt)

  @doc """
  Every purchase as receipts, newest first, for admins. `:view`: `"purchases"` (paid for, the
  default), `"open"` (checkouts waiting for payment), `"abandoned"` (closed unpaid), `"all"`; or
  `:status` and `:limit` as `list_orders/1`.
  """
  def list_receipts(opts \\ []), do: opts |> list_orders() |> group_receipts()

  @admin_views ~w(purchases open abandoned all)
  def admin_views, do: @admin_views

  # Orders newest first -> receipts newest first, each receipt's orders in the order they were added.
  defp group_receipts(orders) do
    orders
    |> Enum.chunk_by(&(&1.basket_id || &1.id))
    |> Enum.map(fn chunk -> chunk |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id}) |> receipt() end)
  end

  def list_user_orders(%User{id: user_id}, limit \\ 50) do
    Repo.all(from o in Order, where: o.user_id == ^user_id, order_by: [desc: o.inserted_at, desc: o.id], limit: ^limit, preload: [:product])
  end

  @doc "Every order, newest first, for admins. Options: `:status`, `:limit` (100)."
  def list_orders(opts \\ []) do
    query = from o in Order, order_by: [desc: o.inserted_at, desc: o.id], limit: ^Keyword.get(opts, :limit, 100), preload: [:user, :product]

    query =
      case Keyword.get(opts, :view, "all") do
        "purchases" -> from o in query, where: not is_nil(o.paid_at)
        "open" -> from o in query, where: o.status == "awaiting_payment"
        "abandoned" -> from o in query, where: is_nil(o.paid_at) and o.status in ["cancelled", "failed"]
        _ -> query
      end

    case Keyword.get(opts, :status) do
      nil -> Repo.all(query)
      status -> Repo.all(from o in query, where: o.status == ^status)
    end
  end

  @doc "Any order by id, for admins."
  def get_order(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Order |> Repo.get(uuid) |> Repo.preload([:user, :product])
      :error -> nil
    end
  end

  # Orders whose money the hub has (a dispute may still take it back).
  @paid_statuses ~w(paid fulfilled disputed)

  @doc "Order counts and card revenue (in cents, USD) for the admin dashboard."
  def stats(now \\ DateTime.utc_now()) do
    day = DateTime.new!(DateTime.to_date(now), ~T[00:00:00], "Etc/UTC")
    month = DateTime.new!(Date.beginning_of_month(DateTime.to_date(now)), ~T[00:00:00], "Etc/UTC")

    revenue = fn since ->
      Repo.one(
        from o in Order,
          where: o.status in @paid_statuses and o.currency == "usd" and o.paid_at >= ^since,
          select: coalesce(sum(o.amount_cents), 0)
      )
    end

    %{
      orders: Repo.aggregate(from(o in Order, where: o.status in ^(@paid_statuses ++ ["charged_back"])), :count),
      products: Repo.aggregate(from(p in Product, where: p.active), :count),
      revenue_today_cents: revenue.(day),
      revenue_month_cents: revenue.(month)
    }
  end

  @doc """
  Retries delivering a paid order that couldn't be delivered (a key product
  that ran out, a channel that was missing). For admins, once the cause is
  fixed.
  """
  def retry_delivery(%Order{id: id}) do
    Repo.transaction(fn ->
      order = Repo.one!(from o in Order, where: o.id == ^id, lock: "FOR UPDATE")
      if order.status != "paid", do: Repo.rollback(:not_awaiting_delivery)

      case Fulfilment.deliver(order, Repo.get!(Product, order.product_id)) do
        {:ok, events} -> {mark_fulfilled!(order), events}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {order, events}} ->
        after_commit(order, events)
        {:ok, order}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Provider events (called by BaconStore.Payments)
  # ---------------------------------------------------------------------------

  @doc """
  Applies a provider event to its order. Idempotent: an event that finds its
  order already past the step it describes does nothing. Returns `:ok` or
  `{:error, reason}` (the provider will retry).
  """
  def apply_event(%Event{} = event) do
    Repo.transaction(fn ->
      # every order of the checkout's basket (one, for a single purchase), locked
      case Repo.all(order_query(event)) do
        [] -> Repo.rollback(:unknown_order)
        orders -> transition_basket(orders, event)
      end
    end)
    |> case do
      {:ok, {:changed, [order | _] = orders, events}} ->
        Enum.each(orders, &after_commit(&1, []))
        Enum.each(events, &Bacon8.Plugins.notify/1)

        if event.type == :checkout_completed do
          # what was bought leaves the cart
          BaconStore.Store.Cart.remove_all(order.user_id, Enum.map(orders, & &1.product_id))

          # A dispute can arrive before the completion that tells us the
          # payment's id; now that we know it, apply any that are waiting.
          if order.provider_payment_ref,
            do: BaconStore.Payments.replay_waiting(order.provider, order.provider_payment_ref)
        end

        :ok

      {:ok, :unchanged} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp order_query(%Event{provider: provider, provider_ref: ref}) when is_binary(ref),
    do: from(o in Order, where: o.provider == ^provider and o.provider_ref == ^ref, order_by: [asc: o.inserted_at, asc: o.id], lock: "FOR UPDATE")

  defp order_query(%Event{provider: provider, payment_ref: ref}) when is_binary(ref),
    do: from(o in Order, where: o.provider == ^provider and o.provider_payment_ref == ^ref, order_by: [asc: o.inserted_at, asc: o.id], lock: "FOR UPDATE")

  defp order_query(_), do: from(o in Order, where: false)

  # Money taken for a basket: it must be what the whole basket costs; then each order is paid and
  # delivered as one order always was (below). Other events apply to every order of the basket.
  defp transition_basket(orders, %Event{type: :checkout_completed} = e) do
    total = Enum.sum(Enum.map(orders, &(&1.amount_cents || 0)))
    currency = hd(orders).currency

    cond do
      not Enum.any?(orders, &(&1.status in ["awaiting_payment", "cancelled", "failed"])) ->
        :unchanged

      e.amount_cents != total or String.downcase(e.currency || "") != currency ->
        Repo.rollback({:amount_mismatch, %{expected: {total, currency}, got: {e.amount_cents, e.currency}}})

      true ->
        collect(orders, &transition(&1, %{e | amount_cents: &1.amount_cents}))
    end
  end

  defp transition_basket(orders, e), do: collect(orders, &transition(&1, e))

  defp collect(orders, fun) do
    {changed, events} =
      Enum.reduce(orders, {[], []}, fn order, {changed, events} ->
        case fun.(order) do
          {:changed, o, ev} -> {[o | changed], events ++ ev}
          :unchanged -> {changed, events}
        end
      end)

    if changed == [], do: :unchanged, else: {:changed, Enum.reverse(changed), events}
  end

  # Money taken: check it's what the order says, then pay and deliver. Also
  # from cancelled/failed: the buyer may have left our page and still paid in
  # the provider's, and money taken must always be honoured. If delivery
  # can't happen (out of keys), the order stays "paid" with the reason, for an
  # admin to fix and retry; the provider isn't asked to retry.
  defp transition(%Order{status: status} = order, %Event{type: :checkout_completed} = e)
       when status in ["awaiting_payment", "cancelled", "failed"] do
    if e.amount_cents == order.amount_cents and String.downcase(e.currency || "") == order.currency do
      paid =
        order
        |> Ecto.Changeset.change(status: "paid", paid_at: DateTime.utc_now(), failure_reason: nil,
                                 provider_payment_ref: e.payment_ref || order.provider_payment_ref)
        |> Repo.update!()

      product = Repo.get!(Product, paid.product_id)

      # Paid for something the buyer already owns (two checkouts paid at once, say): say so
      # rather than deliver a second copy; the admin page shows it for a refund decision.
      case duplicate_check(paid, product) do
        {:duplicate, reason} ->
          Logger.warning("Store: order #{paid.id} paid for something the buyer already owns")
          {:changed, paid |> Ecto.Changeset.change(failure_reason: reason) |> Repo.update!(), []}

        :ok ->
          deliver_paid(paid, product)
      end
    else
      Repo.rollback({:amount_mismatch, %{expected: {order.amount_cents, order.currency}, got: {e.amount_cents, e.currency}}})
    end
  end

  defp transition(%Order{status: "awaiting_payment"} = order, %Event{type: :checkout_failed}) do
    Fulfilment.release(order)
    {:changed, order |> Ecto.Changeset.change(status: "failed", failure_reason: "checkout not completed") |> Repo.update!(), []}
  end

  # The buyer's bank is disputing the payment: no access while it's open.
  defp transition(%Order{status: "fulfilled"} = order, %Event{type: :dispute_opened}) do
    {:ok, events} = Fulfilment.revoke(order, Repo.get!(Product, order.product_id), "disputed")
    {:changed, order |> Ecto.Changeset.change(status: "disputed") |> Repo.update!(), events}
  end

  # The hub won: everything comes back.
  defp transition(%Order{status: "disputed"} = order, %Event{type: :dispute_won}) do
    {:ok, events} = Fulfilment.reinstate(order, Repo.get!(Product, order.product_id))
    {:changed, order |> Ecto.Changeset.change(status: "fulfilled") |> Repo.update!(), events}
  end

  # The bank took the money back; what it paid for goes too.
  defp transition(%Order{status: status} = order, %Event{type: :dispute_lost}) when status in ["disputed", "fulfilled", "paid"] do
    {:ok, events} = Fulfilment.revoke(order, Repo.get!(Product, order.product_id))
    Fulfilment.release(order)
    {:changed, order |> Ecto.Changeset.change(status: "charged_back") |> Repo.update!(), events}
  end

  # Anything else is a re-delivery or an event for a later state: nothing to do.
  defp transition(_order, _event), do: :unchanged

  @duplicate_note "Paid twice: the buyer already owned this. Refund this payment in Stripe (the item stays delivered once)."

  defp duplicate_check(%Order{} = order, %Product{} = product) do
    case Fulfilment.check(Repo.get!(User, order.user_id), product) do
      {:error, :already_owned} -> {:duplicate, @duplicate_note}
      _ -> :ok
    end
  end

  @doc false
  def duplicate_note, do: @duplicate_note

  defp deliver_paid(paid, product) do
    case Fulfilment.deliver(paid, product) do
      {:ok, events} ->
        {:changed, mark_fulfilled!(paid), events}

      {:error, reason} ->
        Logger.error("Store: order #{paid.id} paid but not delivered: #{inspect(reason)}")
        {:changed, paid |> Ecto.Changeset.change(failure_reason: delivery_failure(reason)) |> Repo.update!(), []}
    end
  end

  defp mark_fulfilled!(order),
    do: order |> Ecto.Changeset.change(status: "fulfilled", fulfilled_at: DateTime.utc_now(), failure_reason: nil) |> Repo.update!()

  defp delivery_failure(:sold_out), do: "Paid, but out of license keys: add keys, then retry delivery"
  defp delivery_failure(:channel_missing), do: "Paid, but the channel no longer exists: fix the product, then retry delivery"
  defp delivery_failure(reason), do: "Paid, but delivery failed: #{inspect(reason)}"

  defp after_commit(order, events) do
    Phoenix.PubSub.broadcast(Bacon8.PubSub, topic(order), {:order_updated, order})
    Enum.each(events, &Bacon8.Plugins.notify/1)
  end

  @doc "The buyer abandoned checkout on our side (back button on the fake page, or a cancel URL)."
  def cancel_unpaid(order, why \\ nil)

  def cancel_unpaid(%Order{status: "awaiting_payment"} = order, why) do
    Fulfilment.release(order)
    order = order |> Ecto.Changeset.change(status: "cancelled", failure_reason: why) |> Repo.update!()
    Phoenix.PubSub.broadcast(Bacon8.PubSub, topic(order), {:order_updated, order})
    {:ok, order}
  end

  def cancel_unpaid(order, _why), do: {:ok, order}

  # ---------------------------------------------------------------------------
  # Unfinished checkouts (2026-10-29c)
  # ---------------------------------------------------------------------------

  @doc """
  Closes every checkout of `user`'s still waiting for payment, before a new one starts. A
  checkout the provider says was paid is delivered instead (`reconcile/1`). `:ok`, or
  `{:error, :checkout_open}` when the provider couldn't be asked, so two payable checkouts never
  exist at once.
  """
  def settle_open_checkouts(%User{} = user) do
    user
    |> open_baskets()
    |> Enum.reduce_while(:ok, fn orders, :ok ->
      case close_basket(orders, "replaced by a newer checkout") do
        {:ok, _} -> {:cont, :ok}
        {:error, :already_paid} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, :checkout_open}}
      end
    end)
  end

  @doc """
  The buyer cancels an unfinished checkout (the Cancel button, or the provider's cancel link
  that brings them back). `{:ok, orders}` (cancelled, or already settled), `{:error,
  :already_paid}` (it was paid: now delivered), `{:error, :not_found}` or `{:error, reason}`.
  """
  def cancel_checkout(%User{} = user, order_id) do
    case get_user_basket(user, order_id) do
      nil -> {:error, :not_found}
      [%Order{status: "awaiting_payment"} | _] = orders -> close_basket(orders, "cancelled by the buyer")
      orders -> {:ok, orders}
    end
  end

  @doc """
  Asks the provider where a waiting basket's checkout stands and acts on it: paid -> paid and
  delivered (as its webhook would), expired -> failed, open -> nothing. Returns the state, or
  `:unknown` (a provider that can't say, or couldn't be reached).
  """
  def reconcile([%Order{provider_ref: ref, provider: provider_name} | _] = orders) when is_binary(ref) do
    with {:ok, provider} <- provider_for(provider_name),
         true <- function_exported?(provider, :checkout_status, 1),
         {:ok, %{state: state} = status} <- provider.checkout_status(ref) do
      case state do
        :paid -> ingest_status(:checkout_completed, "reconcile:" <> ref, orders, status)
        :expired -> ingest_status(:checkout_failed, "reconcile-expired:" <> ref, orders, status)
        _ -> :ok
      end

      state
    else
      _ -> :unknown
    end
  end

  def reconcile(_orders), do: :unknown

  @doc """
  For the sweeper: closes card checkouts whose time is up (their `checkout_expires_at`, or 35
  minutes for ones started before it was kept). Paid ones are delivered, the rest cancelled.
  Returns how many baskets were settled.
  """
  def settle_stale_checkouts(now \\ DateTime.utc_now()) do
    legacy = DateTime.add(now, -35 * 60, :second)

    Repo.all(
      from o in Order,
        where:
          o.status == "awaiting_payment" and
            ((not is_nil(o.checkout_expires_at) and o.checkout_expires_at < ^now) or
               (is_nil(o.checkout_expires_at) and o.inserted_at < ^legacy)),
        order_by: [asc: o.inserted_at, asc: o.id]
    )
    |> Enum.group_by(&(&1.basket_id || &1.id))
    |> Enum.count(fn {_basket, orders} ->
      case close_basket(orders, "checkout timed out") do
        {:ok, _} -> true
        {:error, :already_paid} -> true
        _ -> false
      end
    end)
  end

  # A user's waiting card baskets, each a list of orders.
  defp open_baskets(%User{id: user_id}) do
    Repo.all(from o in Order, where: o.user_id == ^user_id and o.status == "awaiting_payment", order_by: [asc: o.inserted_at, asc: o.id])
    |> Enum.group_by(&(&1.basket_id || &1.id))
    |> Map.values()
  end

  # Close a waiting basket's checkout at the provider, then cancel its orders. If the provider
  # says it was paid, deliver it instead ({:error, :already_paid}). A provider that can't be
  # reached leaves it waiting ({:error, reason}); one the hub no longer knows (the fake, switched
  # off) is cancelled here only.
  defp close_basket([lead | _] = orders, why) do
    result =
      case {lead.provider_ref, provider_for(lead.provider)} do
        {ref, {:ok, provider}} when is_binary(ref) ->
          if function_exported?(provider, :expire_checkout, 1), do: provider.expire_checkout(ref), else: :ok

        _ ->
          :ok
      end

    case result do
      :ok ->
        cancelled = Enum.map(orders, fn o -> elem(cancel_unpaid(Repo.get!(Order, o.id), why), 1) end)
        {:ok, cancelled}

      {:error, :already_paid} ->
        reconcile(orders)
        {:error, :already_paid}

      {:error, reason} ->
        Logger.warning("Store: couldn't close checkout #{lead.provider_ref}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp provider_for(name) do
    case BaconStore.Payments.provider(name) do
      {:ok, mod} ->
        Code.ensure_loaded(mod)
        {:ok, mod}

      error -> error
    end
  end

  defp ingest_status(type, event_id, [lead | _], status) do
    BaconStore.Payments.ingest(%Event{
      type: type,
      provider: lead.provider,
      provider_event_id: event_id,
      provider_ref: lead.provider_ref,
      payment_ref: status[:payment_ref],
      amount_cents: status[:amount_cents],
      currency: status[:currency],
      raw: %{"source" => "checkout_status", "state" => to_string(status[:state]), "ref" => lead.provider_ref}
    })
  end

  @doc """
  Cancels card orders left awaiting payment for more than `hours` (default
  48), returning their reserved keys. Stripe expires its sessions after 24h
  and tells us, so this only catches what that missed. Returns the count.
  """
  def cancel_stale(hours \\ 48, now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -hours * 3600, :second)

    stale = Repo.all(from o in Order, where: o.status == "awaiting_payment" and o.inserted_at < ^cutoff)
    Enum.each(stale, &cancel_unpaid/1)
    length(stale)
  end
end
