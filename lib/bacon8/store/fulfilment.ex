defmodule Bacon8.Store.Fulfilment do
  @moduledoc """
  What a purchase delivers, and takes back after a lost chargeback
  (BACON8.md §8). Called by `Bacon8.Store` inside the order's transaction,
  with the order row locked; every step is safe to repeat.

  Grants are entitlements (`Bacon8.Entitlements`) with `source_type`
  "store_order" and `source_id` the order id:

    * download - `store_download` / product id, no end
    * game item - the product's `grant_kind` / `grant_key` / `grant_quantity`,
      ending after `duration_days` if set. Games check
      `Entitlements.active?(user, kind, key)`.
    * channel access - `channel_access` / channel id, plus membership of the
      channel. Buying again while a pass runs extends it. When the last pass
      ends (`expire/1`, run by `Bacon8.Store.Sweeper`) or is charged back,
      the membership goes too, unless the buyer was promoted meanwhile.
    * channel slots - `channel_slots` / "slots", and the user's
      `channel_allowance` goes up (permanently).

  Gem packs credit the wallet; license keys move from the pool to the buyer.

  A bank dispute takes all of it away at once (`revoke(order, product,
  "disputed")`, Gems included, even into a negative balance); a won dispute
  gives it back (`reinstate/2`); a lost one makes it permanent.

  `deliver/2` and `revoke/2` return hub events for the caller to send to
  plugins (`Bacon8.Plugins.notify/1`) once the transaction has committed:
  `{:entitlement_granted, entitlement}` and `{:entitlement_revoked, entitlement}`.
  """

  import Ecto.Query

  alias Bacon8.{Entitlements, Forum, Repo, Wallet}
  alias Bacon8.Accounts.User
  alias Bacon8.Entitlements.Entitlement
  alias Bacon8.Store.{Catalog, LicenseKey, Order, Product}

  @download "store_download"
  @channel_access "channel_access"
  @channel_slots "channel_slots"
  @source "store_order"

  def download_kind, do: @download
  def channel_access_kind, do: @channel_access

  # ---------------------------------------------------------------------------
  # Before payment
  # ---------------------------------------------------------------------------

  @doc """
  Can `user` buy (one more of) `product`? `:ok`, or `{:error, reason}`:
  `:already_owned`, `:already_member`, `:banned_from_channel`, `:sold_out`,
  `:not_for_sale` (the channel it sells is gone).
  """
  def check(%User{} = user, %Product{kind: "download"} = p) do
    if Entitlements.active?(user, @download, p.id), do: {:error, :already_owned}, else: :ok
  end

  def check(%User{} = user, %Product{kind: "item", one_per_user: true} = p) do
    if Entitlements.active?(user, p.grant_kind, p.grant_key), do: {:error, :already_owned}, else: :ok
  end

  def check(%User{} = user, %Product{kind: "access", grant_kind: "channel", grant_key: channel_id}) do
    passes = active_passes(user.id, channel_id)

    cond do
      is_nil(Catalog.channel_name(channel_id)) -> {:error, :not_for_sale}
      Enum.any?(passes, &is_nil(&1.ends_at)) -> {:error, :already_owned}
      match?(%{is_banned: true}, Forum.get_channel_member(channel_id, user.id)) -> {:error, :banned_from_channel}
      passes == [] and Forum.is_channel_member?(channel_id, user.id) -> {:error, :already_member}
      true -> :ok
    end
  end

  def check(_user, %Product{kind: "license_key"} = p) do
    if Catalog.available_keys(p) > 0, do: :ok, else: {:error, :sold_out}
  end

  def check(_user, _product), do: :ok

  @doc "Sets a key aside for a card order, so nobody else can pay for it. `{:error, :sold_out}` if none is left."
  def reserve(%Order{} = order, %Product{kind: "license_key"} = p) do
    case take_key(p) do
      nil ->
        {:error, :sold_out}

      key ->
        key |> Ecto.Changeset.change(order_id: order.id, reserved_at: DateTime.utc_now()) |> Repo.update!()
        :ok
    end
  end

  def reserve(_order, _product), do: :ok

  @doc "Puts an unpaid order's reserved key back in the pool."
  def release(%Order{id: order_id}) do
    Repo.update_all(from(k in LicenseKey, where: k.order_id == ^order_id and is_nil(k.sold_at)),
      set: [order_id: nil, reserved_at: nil, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  defp take_key(%Product{id: product_id}) do
    Repo.one(
      from k in LicenseKey,
        where: k.product_id == ^product_id and is_nil(k.order_id),
        order_by: [asc: k.inserted_at],
        limit: 1,
        lock: "FOR UPDATE SKIP LOCKED"
    )
  end

  # ---------------------------------------------------------------------------
  # Delivery
  # ---------------------------------------------------------------------------

  @doc "Delivers a paid order. `{:ok, hub_events}` or `{:error, reason}`; nothing is delivered twice."
  def deliver(%Order{} = order, %Product{kind: "gem_pack"}) do
    if order.gems > 0 do
      case Wallet.credit_purchase(order.user_id, order.gems, order, memo: order.product_name) do
        {:ok, _} -> {:ok, []}
        {:ok, _, :duplicate} -> {:ok, []}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, []}
    end
  end

  def deliver(%Order{} = order, %Product{kind: "license_key"} = p) do
    key = Repo.one(from(k in LicenseKey, where: k.order_id == ^order.id, lock: "FOR UPDATE")) || take_key(p)

    cond do
      is_nil(key) ->
        {:error, :sold_out}

      key.sold_at ->
        {:ok, []}

      true ->
        now = DateTime.utc_now()
        key |> Ecto.Changeset.change(order_id: order.id, user_id: order.user_id, sold_at: now, reserved_at: key.reserved_at || now) |> Repo.update!()
        {:ok, []}
    end
  end

  def deliver(%Order{} = order, %Product{} = p) do
    if delivered?(order) do
      {:ok, []}
    else
      user = Repo.get!(User, order.user_id)
      grant(user, order, p)
    end
  end

  defp delivered?(%Order{id: id}),
    do: Repo.exists?(from e in Entitlement, where: e.source_type == @source and e.source_id == ^id)

  defp grant(user, order, %Product{kind: "download"} = p),
    do: entitlement(user, order, %{kind: @download, key: p.id})

  defp grant(user, order, %Product{kind: "item"} = p) do
    entitlement(user, order, %{kind: p.grant_kind, key: p.grant_key, quantity: p.grant_quantity || 1, ends_at: ends_at(DateTime.utc_now(), p.duration_days)})
  end

  defp grant(user, order, %Product{kind: "access", grant_kind: "channel", grant_key: channel_id} = p) do
    if is_nil(Catalog.channel_name(channel_id)) do
      {:error, :channel_missing}
    else
      now = DateTime.utc_now()

      # A new pass starts when the current one ends, so buying early loses nothing.
      start =
        user.id
        |> active_passes(channel_id)
        |> Enum.map(& &1.ends_at)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> now end)
        |> then(&if(DateTime.compare(&1, now) == :gt, do: &1, else: now))

      with {:ok, events} <- entitlement(user, order, %{kind: @channel_access, key: channel_id, ends_at: ends_at(start, p.duration_days)}),
           :ok <- ensure_member(channel_id, user.id) do
        {:ok, events}
      end
    end
  end

  defp grant(user, order, %Product{kind: "access", grant_kind: "channel_slots"} = p) do
    n = p.grant_quantity || 1

    with {:ok, events} <- entitlement(user, order, %{kind: @channel_slots, key: "slots", quantity: n}) do
      Repo.update_all(from(u in User, where: u.id == ^user.id), inc: [channel_allowance: n])
      {:ok, events}
    end
  end

  defp grant(_user, _order, %Product{kind: kind}), do: {:error, {:unknown_kind, kind}}

  defp entitlement(user, order, attrs) do
    case Entitlements.grant(user, Map.merge(attrs, %{source_type: @source, source_id: order.id})) do
      {:ok, e} -> {:ok, [{:entitlement_granted, e}]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ends_at(_from, nil), do: nil
  defp ends_at(from, days), do: DateTime.add(from, days * 86_400, :second)

  defp ensure_member(channel_id, user_id) do
    if Forum.is_channel_member?(channel_id, user_id) do
      :ok
    else
      case Forum.create_channel_member(%{channel_id: channel_id, user_id: user_id, role: "member"}) do
        {:ok, _} -> :ok
        {:error, changeset} -> {:error, {:membership, changeset.errors}}
      end
    end
  end

  defp active_passes(user_id, channel_id) do
    user_id |> Entitlements.active(@channel_access) |> Enum.filter(&(&1.key == channel_id))
  end

  # ---------------------------------------------------------------------------
  # Disputes, chargebacks and expiry
  # ---------------------------------------------------------------------------

  @doc """
  Takes away what an order delivered: `reason` "disputed" when the buyer's
  bank opens a dispute (undone by `reinstate/2` if the hub wins), or
  "chargeback" when it's lost. Gems are held the same way. Returns
  `{:ok, hub_events}`.
  """
  def revoke(%Order{} = order, %Product{} = p, reason \\ "chargeback") do
    if p.kind == "gem_pack" and order.gems > 0, do: hold_gems(order)

    now = DateTime.utc_now()

    Repo.update_all(from(k in LicenseKey, where: k.order_id == ^order.id and not is_nil(k.sold_at) and is_nil(k.revoked_at)),
      set: [revoked_at: now, updated_at: now]
    )

    events =
      from(e in Entitlement, where: e.source_type == @source and e.source_id == ^order.id and is_nil(e.revoked_at))
      |> Repo.all()
      |> Enum.map(&end_entitlement(&1, reason))

    # A lost dispute makes the hold permanent.
    if reason == "chargeback" do
      Repo.update_all(
        from(e in Entitlement, where: e.source_type == @source and e.source_id == ^order.id and e.revoked_reason == "disputed"),
        set: [revoked_reason: "chargeback", updated_at: now]
      )
    end

    {:ok, events}
  end

  @doc "Gives back what `revoke(order, product, \"disputed\")` took, after a won dispute. Returns `{:ok, hub_events}`."
  def reinstate(%Order{} = order, %Product{} = p) do
    if p.kind == "gem_pack" and order.gems > 0, do: release_gems(order)

    now = DateTime.utc_now()

    Repo.update_all(from(k in LicenseKey, where: k.order_id == ^order.id and not is_nil(k.revoked_at)),
      set: [revoked_at: nil, updated_at: now]
    )

    events =
      from(e in Entitlement, where: e.source_type == @source and e.source_id == ^order.id and e.revoked_reason == "disputed")
      |> Repo.all()
      |> Enum.map(&restore_entitlement(&1, now))

    {:ok, events}
  end

  # Gems are held once per dispute: only when they aren't already held.
  defp hold_gems(order) do
    %{clawbacks: c, restores: r} = Wallet.dispute_counts(order.id)

    if c == r do
      case Wallet.clawback(order.user_id, order.gems, order, c + 1) do
        {:error, reason} -> Repo.rollback({:clawback_failed, reason})
        _ -> :ok
      end
    end
  end

  defp release_gems(order) do
    %{clawbacks: c, restores: r} = Wallet.dispute_counts(order.id)

    if c > r do
      case Wallet.restore_clawback(order.user_id, order.gems, order, r + 1) do
        {:error, reason} -> Repo.rollback({:restore_failed, reason})
        _ -> :ok
      end
    end
  end

  # A pass whose time ran out during the dispute comes back already ended;
  # the sweeper marks it expired.
  defp restore_entitlement(%Entitlement{} = e, now) do
    {:ok, e} = e |> Ecto.Changeset.change(revoked_at: nil, revoked_reason: nil) |> Repo.update()
    running? = is_nil(e.ends_at) or DateTime.compare(e.ends_at, now) == :gt

    case e.kind do
      @channel_access ->
        # The channel may have been deleted meanwhile; nothing to rejoin then.
        if running? and Catalog.channel_name(e.key), do: ensure_member(e.key, e.user_id)

      @channel_slots ->
        Repo.update_all(from(u in User, where: u.id == ^e.user_id), inc: [channel_allowance: e.quantity || 1])

      _ ->
        :ok
    end

    {:entitlement_granted, e}
  end

  @doc """
  Ends store-granted entitlements whose time is up (channel passes lose
  their membership). Returns how many ended. Run by `Bacon8.Store.Sweeper`.
  """
  def expire(now \\ DateTime.utc_now()) do
    from(e in Entitlement,
      where: e.source_type == @source and is_nil(e.revoked_at) and not is_nil(e.ends_at) and e.ends_at <= ^now
    )
    |> Repo.all()
    |> Enum.map(fn e ->
      {:ok, event} = Repo.transaction(fn -> end_entitlement(e, "expired") end)
      Bacon8.Plugins.notify(event)
    end)
    |> length()
  end

  defp end_entitlement(%Entitlement{} = e, reason) do
    {:ok, e} = Entitlements.revoke(e, reason)

    case e.kind do
      @channel_access ->
        maybe_remove_member(e.user_id, e.key)

      @channel_slots ->
        n = e.quantity || 1

        from(u in User,
          where: u.id == ^e.user_id,
          update: [set: [channel_allowance: fragment("GREATEST(? - ?, 0)", u.channel_allowance, ^n)]]
        )
        |> Repo.update_all([])

      _ ->
        :ok
    end

    {:entitlement_revoked, e}
  end

  # The pass was the reason for the membership. Keep it if another pass still
  # runs, or if the buyer has been promoted (moderator, owner) since.
  defp maybe_remove_member(user_id, channel_id) do
    if active_passes(user_id, channel_id) == [] do
      case Forum.get_channel_member(channel_id, user_id) do
        %{role: "member", is_banned: false} -> Forum.remove_channel_member(channel_id, user_id)
        _ -> :ok
      end
    end

    :ok
  end
end
