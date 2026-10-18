defmodule Bacon8.Store.Library do
  @moduledoc """
  What a user owns from the store, for /store/library: downloads (with their
  current files), license keys, and items and passes with their end dates.
  """

  import Ecto.Query
  alias Bacon8.{Entitlements, Repo}
  alias Bacon8.Accounts.User
  alias Bacon8.Entitlements.Entitlement
  alias Bacon8.Store.{Catalog, Fulfilment, LicenseKey, Order, Product, ProductFile}

  def for_user(%User{id: user_id} = user, now \\ DateTime.utc_now()) do
    %{
      downloads: downloads(user),
      keys:
        Repo.all(
          from k in LicenseKey,
            where: k.user_id == ^user_id and not is_nil(k.sold_at),
            order_by: [desc: k.sold_at],
            preload: [:product, :order]
        ),
      grants: grants(user_id, now)
    }
  end

  @doc "Products the user may download, with their files."
  def downloads(user) do
    ids =
      user
      |> Entitlements.active(Fulfilment.download_kind())
      |> Enum.map(& &1.key)
      |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))
      |> Enum.uniq()

    files = from(f in ProductFile, order_by: [asc: f.role, asc: f.position, asc: f.inserted_at])
    Repo.all(from p in Product, where: p.id in ^ids, order_by: [asc: p.name], preload: [files: ^files])
  end

  @doc "May `user` download this product file?"
  def can_download?(nil, _file), do: false

  def can_download?(%User{} = user, %ProductFile{role: "download", product_id: product_id}) do
    staff?(user) or Entitlements.active?(user, Fulfilment.download_kind(), product_id)
  end

  def can_download?(_user, _file), do: false

  defp staff?(user), do: Map.get(user, :is_admin) == true or Map.get(user, :role) == "admin"

  defp grants(user_id, now) do
    entitlements =
      Repo.all(
        from e in Entitlement,
          where: e.user_id == ^user_id and e.source_type == "store_order" and e.kind != ^Fulfilment.download_kind(),
          order_by: [desc: e.inserted_at],
          limit: 200
      )

    order_ids = entitlements |> Enum.map(& &1.source_id) |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1))) |> Enum.uniq()
    products = Repo.all(from o in Order, join: p in assoc(o, :product), where: o.id in ^order_ids, select: {o.id, p}) |> Map.new()

    Enum.map(entitlements, fn e ->
      product = Map.get(products, e.source_id)
      %{entitlement: e, product: product, label: label(e, product), state: state(e, now)}
    end)
  end

  defp label(%Entitlement{kind: "channel_access", key: channel_id}, _p), do: "##{Catalog.channel_name(channel_id) || "deleted channel"}"
  defp label(%Entitlement{kind: "channel_slots", quantity: q}, _p), do: "+#{q || 1} channel slot#{if (q || 1) == 1, do: "", else: "s"}"
  defp label(%Entitlement{quantity: q}, %Product{name: name}) when is_integer(q) and q > 1, do: "#{name} ×#{q}"
  defp label(_e, %Product{name: name}), do: name
  defp label(%Entitlement{key: key}, _), do: key

  defp state(%Entitlement{revoked_at: r, revoked_reason: "expired", ends_at: ends}, _now) when not is_nil(r), do: {:expired, ends}
  defp state(%Entitlement{revoked_at: r, revoked_reason: "disputed"}, _now) when not is_nil(r), do: :on_hold
  defp state(%Entitlement{revoked_at: r}, _now) when not is_nil(r), do: :revoked
  defp state(%Entitlement{ends_at: nil}, _now), do: :forever

  defp state(%Entitlement{ends_at: ends}, now) do
    if DateTime.compare(ends, now) == :gt, do: {:until, ends}, else: {:expired, ends}
  end
end
