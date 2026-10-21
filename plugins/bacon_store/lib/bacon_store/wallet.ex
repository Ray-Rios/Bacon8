defmodule BaconStore.Wallet do
  @moduledoc """
  Gems, the hub-wide currency (BACON8.md §8): an append-only, double-entry
  ledger.

  Every movement is one `Wallet.Transaction` whose entries sum to zero: a
  purchase is user +500 / `gem_sales` -500, a spend is user -50 /
  `gem_spend` +50. An account's `balance` is the sum of its entries, cached on
  the account row and updated in the same database transaction, under a row
  lock, so concurrent spends can't both pass the balance check. System
  accounts (`gem_sales`, `gem_spend`, `promotions`) are not locked and keep
  no cached balance - every purchase and spend touches one, and locking it
  would queue the whole hub behind it. Their balance is `system_balance/1`.

  Every call takes an idempotency key. Posting the same key twice returns the
  first transaction (`{:ok, txn, :duplicate}`) and moves nothing, so a retried
  request, a re-delivered webhook or a double click can't pay or charge twice.

  Spending can't take a balance below zero. A chargeback (`clawback/3`) can,
  and a negative balance blocks spending until it's settled.
  """

  import Ecto.Query
  alias Bacon8.Repo
  alias BaconStore.Wallet.{Account, Entry, Transaction}

  @currency "GEMS"

  def currency, do: @currency

  # ---------------------------------------------------------------------------
  # Reading
  # ---------------------------------------------------------------------------

  @doc "The user's Gem balance (0 if they have never had any)."
  def balance(user_or_id) do
    user_id = user_id(user_or_id)

    Repo.one(from a in Account, where: a.user_id == ^user_id and a.currency == ^@currency, select: a.balance) || 0
  end

  @doc "A system account's balance: the sum of its entries (e.g. `gem_sales` is minus all Gems ever sold)."
  def system_balance(name) do
    from(e in Entry,
      join: a in assoc(e, :account),
      where: a.owner_type == "system" and a.name == ^name and a.currency == ^@currency,
      select: coalesce(sum(e.amount), 0)
    )
    |> Repo.one()
    |> to_int()
  end

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n

  @doc "The user's most recent transactions, newest first, with this user's amount."
  def history(user_or_id, limit \\ 50) do
    user_id = user_id(user_or_id)

    from(e in Entry,
      join: a in assoc(e, :account),
      join: t in assoc(e, :transaction),
      where: a.user_id == ^user_id and a.currency == ^@currency,
      order_by: [desc: t.inserted_at],
      limit: ^limit,
      select: %{
        id: t.id,
        kind: t.kind,
        amount: e.amount,
        memo: t.memo,
        game_slug: t.game_slug,
        reference_type: t.reference_type,
        reference_id: t.reference_id,
        at: t.inserted_at
      }
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Moving Gems
  # ---------------------------------------------------------------------------

  @doc "Gems bought with money (a fulfilled store order)."
  def credit_purchase(user, gems, %{id: order_id}, opts \\ []) when is_integer(gems) and gems > 0 do
    post(:gem_purchase, [{:user, user, gems}, {:system, "gem_sales", -gems}],
      idempotency_key: "order:#{order_id}:credit",
      reference_type: "store_order",
      reference_id: order_id,
      memo: opts[:memo]
    )
  end

  @doc """
  Spends Gems on something (`opts`: `:idempotency_key` required, `:game_slug`,
  `:memo`, `:reference_type`, `:reference_id`). `{:error, :insufficient_gems}`
  if the balance can't cover it.
  """
  def spend(user, gems, opts) when is_integer(gems) and gems > 0 do
    post(:spend, [{:user, user, -gems}, {:system, "gem_spend", gems}],
      idempotency_key: Keyword.fetch!(opts, :idempotency_key),
      game_slug: opts[:game_slug],
      memo: opts[:memo],
      reference_type: opts[:reference_type],
      reference_id: opts[:reference_id]
    )
  end

  @doc "Free Gems: a promotion, a prize, an admin's goodwill (`opts`: `:idempotency_key`, `:memo`, `:actor_id`)."
  def grant(user, gems, opts) when is_integer(gems) and gems > 0 do
    post(:grant, [{:user, user, gems}, {:system, "promotions", -gems}],
      idempotency_key: Keyword.fetch!(opts, :idempotency_key),
      memo: opts[:memo],
      actor_id: opts[:actor_id]
    )
  end

  @doc """
  Takes back a Gem pack's Gems while its payment is disputed (and for good if
  the dispute is lost). May leave the balance negative, which blocks spending
  until it's settled. `n` counts disputes on the order (a won dispute can be
  followed by another), so each hold has its own idempotency key.
  """
  def clawback(user, gems, %{id: order_id}, n \\ 1) when is_integer(gems) and gems > 0 do
    post(:chargeback, [{:user, user, -gems}, {:system, "gem_sales", gems}],
      idempotency_key: "order:#{order_id}:clawback" <> if(n == 1, do: "", else: ":#{n}"),
      reference_type: "store_order",
      reference_id: order_id,
      allow_negative: true
    )
  end

  @doc "Gives back Gems held by `clawback/4` when the hub wins the dispute (the `n`th time)."
  def restore_clawback(user, gems, %{id: order_id}, n) when is_integer(gems) and gems > 0 do
    post(:chargeback_reversal, [{:user, user, gems}, {:system, "gem_sales", -gems}],
      idempotency_key: "order:#{order_id}:restore:#{n}",
      reference_type: "store_order",
      reference_id: order_id
    )
  end

  @doc "How many times an order's Gems were held and given back: %{clawbacks: n, restores: n}."
  def dispute_counts(order_id) do
    counts =
      from(t in Transaction,
        where: t.reference_type == "store_order" and t.reference_id == ^to_string(order_id),
        where: t.kind in ["chargeback", "chargeback_reversal"],
        group_by: t.kind,
        select: {t.kind, count(t.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{clawbacks: Map.get(counts, "chargeback", 0), restores: Map.get(counts, "chargeback_reversal", 0)}
  end

  # ---------------------------------------------------------------------------
  # The ledger
  # ---------------------------------------------------------------------------

  # legs: [{:user, user_or_id, amount} | {:system, name, amount}]
  defp post(kind, legs, opts) do
    key = Keyword.fetch!(opts, :idempotency_key)
    0 = legs |> Enum.map(&elem(&1, 2)) |> Enum.sum()

    Repo.transaction(fn ->
      case Repo.one(from t in Transaction, where: t.idempotency_key == ^key) do
        %Transaction{} = existing ->
          {existing, :duplicate}

        nil ->
          accounts = Enum.map(legs, fn leg -> {lock_account(leg), elem(leg, 2)} end)

          unless opts[:allow_negative] do
            for {%Account{owner_type: "user"} = acc, amount} <- accounts, acc.balance + amount < 0 do
              Repo.rollback(:insufficient_gems)
            end
          end

          now = DateTime.utc_now()

          txn =
            Repo.insert!(%Transaction{
              kind: to_string(kind),
              idempotency_key: key,
              reference_type: opts[:reference_type],
              reference_id: opts[:reference_id] && to_string(opts[:reference_id]),
              game_slug: opts[:game_slug],
              memo: opts[:memo],
              actor_id: opts[:actor_id],
              inserted_at: now
            })

          for {acc, amount} <- accounts do
            Repo.insert!(%Entry{transaction_id: txn.id, account_id: acc.id, amount: amount, inserted_at: now})

            if acc.owner_type == "user" do
              {1, _} =
                Repo.update_all(from(a in Account, where: a.id == ^acc.id),
                  inc: [balance: amount],
                  set: [updated_at: now]
                )
            end
          end

          {txn, :posted}
      end
    end)
    |> case do
      {:ok, {txn, :duplicate}} -> {:ok, txn, :duplicate}
      {:ok, {txn, :posted}} -> {:ok, txn}
      {:error, reason} -> {:error, reason}
    end
  rescue
    # Two posts with the same key raced past the lookup; the unique index
    # stopped the second. Report it as the duplicate it is.
    e in Ecto.ConstraintError ->
      if e.constraint == "wallet_transactions_idempotency_key_index" do
        key = Keyword.fetch!(opts, :idempotency_key)
        {:ok, Repo.one!(from t in Transaction, where: t.idempotency_key == ^key), :duplicate}
      else
        reraise e, __STACKTRACE__
      end
  end

  # Finds or creates the account. A user's row is locked for the rest of the
  # transaction (SELECT ... FOR UPDATE); a system account's isn't (see moduledoc).
  defp lock_account({:user, user, _}) do
    user_id = user_id(user)
    ensure_account(%{owner_type: "user", user_id: user_id, name: nil}, [:user_id, :currency], "user_id IS NOT NULL")
    Repo.one!(from a in Account, where: a.user_id == ^user_id and a.currency == ^@currency, lock: "FOR UPDATE")
  end

  defp lock_account({:system, name, _}) do
    ensure_account(%{owner_type: "system", user_id: nil, name: name}, [:name, :currency], "name IS NOT NULL")
    Repo.one!(from a in Account, where: a.name == ^name and a.currency == ^@currency)
  end

  defp ensure_account(attrs, conflict_target, where) do
    now = DateTime.utc_now()

    Repo.insert!(
      struct(Account, Map.merge(attrs, %{currency: @currency, balance: 0, inserted_at: now, updated_at: now})),
      on_conflict: :nothing,
      conflict_target: {:unsafe_fragment, "(#{Enum.join(conflict_target, ", ")}) WHERE #{where}"}
    )
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id) when is_binary(id), do: id
end
