defmodule Bacon8.Entitlements do
  @moduledoc """
  What a user has been granted: storage tiers today, VIP channel access and game
  items later (BACON8.md §8). Anything purchasable becomes access through here,
  and `active/2` / `active?/3` are the only checks other code should make.

  An entitlement is *active* when it is not revoked, has started, and has not
  ended (`ends_at` nil = no end).
  """

  import Ecto.Query
  alias Bacon8.Repo
  alias Bacon8.Accounts.User
  alias Bacon8.Entitlements.Entitlement

  @storage_tier "storage_tier"

  def storage_tier_kind, do: @storage_tier

  @doc "Active entitlements of `kind` for a user."
  def active(user_or_id, kind) do
    user_id = user_id(user_or_id)
    now = DateTime.utc_now()

    from(e in Entitlement,
      where: e.user_id == ^user_id and e.kind == ^kind,
      where: is_nil(e.revoked_at) and e.starts_at <= ^now,
      where: is_nil(e.ends_at) or e.ends_at > ^now,
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  A game's active entitlements for a user (2026-10-29: what the game API's `/entitlements` lists):
  every active entitlement whose kind is one of `kinds` or starts with one of `prefixes`
  (`Bacon8.Plugins.game_entitlement_kinds/1`).
  """
  def active_for_game(user_or_id, {kinds, prefixes}) do
    user_id = user_id(user_or_id)
    now = DateTime.utc_now()

    from(e in Entitlement,
      where: e.user_id == ^user_id,
      where: is_nil(e.revoked_at) and e.starts_at <= ^now,
      where: is_nil(e.ends_at) or e.ends_at > ^now,
      order_by: [asc: e.kind, asc: e.inserted_at]
    )
    |> Repo.all()
    |> Enum.filter(fn e -> e.kind in kinds or Enum.any?(prefixes, &String.starts_with?(e.kind, &1)) end)
  end

  def active?(user_or_id, kind, key) do
    Enum.any?(active(user_or_id, kind), &(&1.key == key or &1.key == "*"))
  end

  @doc """
  Grants an entitlement. Storage tiers are refused for users who may not hold
  storage (Guest/Banned or inactive) - the same rule the store applies before
  checkout, enforced here so no other path can bypass it.
  """
  def grant(%User{} = user, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    if attrs["kind"] == @storage_tier and not Bacon8.Drive.Policy.can_purchase_storage?(user) do
      {:error, :not_eligible}
    else
      %Entitlement{}
      |> Entitlement.changeset(
        attrs
        |> Map.put("user_id", user.id)
        |> Map.put_new("starts_at", DateTime.utc_now())
      )
      |> Repo.insert()
    end
  end

  @doc "Moves `ends_at` (subscription renewals)."
  def extend(%Entitlement{} = e, %DateTime{} = ends_at) do
    e |> Ecto.Changeset.change(ends_at: ends_at) |> Repo.update()
  end

  def revoke(%Entitlement{} = e, reason) do
    e
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(), revoked_reason: to_string(reason))
    |> Repo.update()
  end

  @doc "Revokes every active entitlement of `kind`. Returns the number revoked."
  def revoke_all(user_or_id, kind, reason) do
    user_id = user_id(user_or_id)

    {count, _} =
      from(e in Entitlement,
        where: e.user_id == ^user_id and e.kind == ^kind and is_nil(e.revoked_at)
      )
      |> Repo.update_all(set: [revoked_at: DateTime.utc_now(), revoked_reason: to_string(reason),
                               updated_at: DateTime.utc_now()])

    count
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id) when is_binary(id), do: id
end
