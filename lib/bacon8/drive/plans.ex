defmodule Bacon8.Drive.Plans do
  @moduledoc """
  Storage tiers and their prices. Decided 2026-10-15 (BACON8.md §2):

    * Every role except Guest and Banned gets the **Free** tier (1 GB).
    * Paid tiers **replace** the free tier and are priced on their full size.
    * Price is **$0.50 per GB per month**.
    * Tiers: Free 1, Small 10, Medium 25, Large 50, XL 100, and Custom
      (any whole number of GB up to 1000).
    * Admins have no quota. Guest and Banned have zero and cannot buy a tier.

  All of it is overridable for a fork:

      config :bacon8, Bacon8.Drive.Plans,
        cents_per_gb_month: 50,
        free_gb: 1,
        tiers: [small: 10, medium: 25, large: 50, xl: 100],
        custom_min_gb: 1,
        custom_max_gb: 1000
  """

  @gib 1_073_741_824

  @defaults [
    cents_per_gb_month: 50,
    free_gb: 1,
    tiers: [small: 10, medium: 25, large: 50, xl: 100],
    custom_min_gb: 1,
    custom_max_gb: 1000
  ]

  @labels %{free: "Free", small: "Small", medium: "Medium", large: "Large", xl: "XL", custom: "Custom"}

  defp conf(key), do: Keyword.get(Application.get_env(:bacon8, __MODULE__, []), key, @defaults[key])

  def gib, do: @gib
  def cents_per_gb_month, do: conf(:cents_per_gb_month)
  def free_gb, do: conf(:free_gb)
  def free_bytes, do: free_gb() * @gib
  def custom_range, do: conf(:custom_min_gb)..conf(:custom_max_gb)

  @doc "GB -> bytes."
  def bytes(gb) when is_integer(gb) and gb >= 0, do: gb * @gib

  @doc "Monthly price in cents for `gb` gigabytes."
  def monthly_cents(gb) when is_integer(gb) and gb >= 0, do: gb * cents_per_gb_month()

  @doc """
  The purchasable tiers, cheapest first, followed by Custom. Free is listed
  separately by `free_tier/0` because it is never bought.
  """
  def tiers do
    fixed =
      for {key, gb} <- conf(:tiers) do
        %{key: Atom.to_string(key), label: label(key), gb: gb, monthly_cents: monthly_cents(gb)}
      end

    fixed ++
      [%{key: "custom", label: label(:custom), gb: nil, monthly_cents: nil,
         min_gb: conf(:custom_min_gb), max_gb: conf(:custom_max_gb)}]
  end

  def free_tier, do: %{key: "free", label: label(:free), gb: free_gb(), monthly_cents: 0}

  @doc """
  Validates a purchase request. `gb` is required for "custom" and ignored for
  fixed tiers. Returns the canonical `%{key, gb, monthly_cents}` to charge and
  to record on the entitlement.
  """
  def resolve("custom", gb) when is_integer(gb) do
    if gb in custom_range(),
      do: {:ok, %{key: "custom", gb: gb, monthly_cents: monthly_cents(gb)}},
      else: {:error, :custom_size_out_of_range}
  end

  def resolve("custom", _), do: {:error, :custom_size_required}

  def resolve(key, _gb) when is_binary(key) do
    case Enum.find(conf(:tiers), fn {k, _} -> Atom.to_string(k) == key end) do
      {_, gb} -> {:ok, %{key: key, gb: gb, monthly_cents: monthly_cents(gb)}}
      nil -> {:error, :unknown_tier}
    end
  end

  def resolve(_, _), do: {:error, :unknown_tier}

  @doc "Formats cents as dollars, e.g. 1250 -> \"$12.50\"."
  def format_cents(cents) when is_integer(cents) do
    "$#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp label(key), do: Map.get(@labels, key, key |> Atom.to_string() |> String.capitalize())
end
