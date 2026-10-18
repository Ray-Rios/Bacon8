defmodule Bacon8.Drive.Policy do
  @moduledoc """
  Who gets how much storage, and who may do what. Pure functions over a user
  and (for quota) their active storage entitlements - no Repo calls here, so
  the rules are unit-testable. `Bacon8.Drive.quota_bytes/1` loads the
  entitlements and calls `quota_bytes/2`.
  """

  alias Bacon8.Drive.Plans

  @no_storage_roles ~w(guest banned)
  @staff_readers ~w(admin gm)

  @doc "Roles with zero storage that may not buy any."
  def no_storage_roles, do: @no_storage_roles

  def no_storage_role?(role), do: role in @no_storage_roles

  @doc """
  Quota in bytes, or `:unlimited`.

    * Guest / Banned -> 0
    * Admin          -> :unlimited
    * Everyone else  -> the largest active storage_tier entitlement, or the
                        free tier if they have none (paid tiers replace free).
  """
  def quota_bytes(%{role: role}, _tier_entitlements) when role in @no_storage_roles, do: 0
  def quota_bytes(%{role: "admin"}, _tier_entitlements), do: :unlimited

  def quota_bytes(_user, tier_entitlements) do
    tier_entitlements
    |> Enum.map(fn %{quantity: gb} when is_integer(gb) -> Plans.bytes(gb) end)
    |> Enum.max(fn -> Plans.free_bytes() end)
  end

  @mib 1_048_576
  @gib 1_073_741_824

  @doc """
  Largest single upload, by role (decided 2026-10-15): members 25 MB,
  moderators 50 MB, editors and GMs 1 GB, admins unlimited, guest/banned 0.
  Separate from quota: a file must fit both.
  """
  def max_upload_bytes(%{role: "admin"}), do: :unlimited
  def max_upload_bytes(%{role: role}) when role in ~w(gm editor), do: @gib
  def max_upload_bytes(%{role: "moderator"}), do: 50 * @mib
  def max_upload_bytes(%{role: "member"}), do: 25 * @mib
  def max_upload_bytes(_), do: 0

  @doc """
  `max_upload_bytes/1` as a positive integer for `allow_upload(max_file_size:)`,
  which accepts neither `:unlimited` nor 0. "Unlimited" becomes 1 TB (the largest
  storage tier); 0 becomes 1 byte, and the drive refuses the upload anyway.
  """
  def upload_limit_for_live_view(user) do
    case max_upload_bytes(user) do
      :unlimited -> 1024 * @gib
      0 -> 1
      n -> n
    end
  end

  @doc "May this user buy (or be granted) a storage tier?"
  def can_purchase_storage?(%{role: role, status: status}),
    do: not no_storage_role?(role) and status == "active"

  def can_purchase_storage?(_), do: false

  @doc "Staff who may open any user's files (moderation)."
  def staff_reader?(%{role: role, status: "active"}), do: role in @staff_readers
  def staff_reader?(_), do: false

  @doc "True when adding `size` bytes keeps the user within quota."
  def fits?(:unlimited, _used, _size), do: true
  def fits?(quota, used, size), do: used + size <= quota
end
