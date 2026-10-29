defmodule BaconStore.Store.Cart do
  @moduledoc """
  The buyer's cart (2026-10-29): products waiting to be bought together, one of each (every
  product the store sells is one-per-purchase: a download, a key, a pass, a pack). Kept in
  `store_cart_items`, so it follows the buyer between devices. Paying for it is
  `BaconStore.Store.start_basket_checkout/3` (card) or `buy_basket_with_gems/2`; a paid basket
  empties the cart of what it bought.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Bacon8.Repo
  alias Bacon8.Accounts.User
  alias BaconStore.Store.Product

  @max_items 20

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "store_cart_items" do
    belongs_to :user, User
    belongs_to :product, Product
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "The most a cart holds."
  def max_items, do: @max_items

  @doc "The products in `user`'s cart, oldest first (only ones still on sale)."
  def products(%User{id: user_id}) do
    from(c in __MODULE__,
      join: p in assoc(c, :product),
      where: c.user_id == ^user_id and p.active == true,
      order_by: [asc: c.inserted_at],
      select: p
    )
    |> Repo.all()
    |> Repo.preload([:category, :files])
  end

  def products(_), do: []

  @doc "How many products are in the cart."
  def count(%User{id: user_id}), do: Repo.aggregate(from(c in __MODULE__, where: c.user_id == ^user_id), :count)
  def count(_), do: 0

  @doc "Product ids in the cart, as a set."
  def ids(%User{id: user_id}), do: from(c in __MODULE__, where: c.user_id == ^user_id, select: c.product_id) |> Repo.all() |> MapSet.new()
  def ids(_), do: MapSet.new()

  @doc "Puts `product` in the cart (once). `:ok`, or `{:error, :cart_full}`."
  def add(%User{id: user_id} = user, %Product{id: product_id}) do
    if count(user) >= @max_items do
      {:error, :cart_full}
    else
      Repo.insert(%__MODULE__{user_id: user_id, product_id: product_id}, on_conflict: :nothing, conflict_target: [:user_id, :product_id])
      :ok
    end
  end

  @doc "Takes `product_id` out of the cart."
  def remove(%User{id: user_id}, product_id) do
    Repo.delete_all(from c in __MODULE__, where: c.user_id == ^user_id and c.product_id == ^product_id)
    :ok
  end

  @doc "Takes these products out of the cart (after they were bought)."
  def remove_all(%User{id: user_id}, product_ids) when is_list(product_ids) do
    Repo.delete_all(from c in __MODULE__, where: c.user_id == ^user_id and c.product_id in ^product_ids)
    :ok
  end

  def remove_all(user_id, product_ids) when is_binary(user_id), do: remove_all(%User{id: user_id}, product_ids)
end
