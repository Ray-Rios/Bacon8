defmodule BaconStore.Payments.Fake do
  @moduledoc """
  A pretend provider for development and tests. Checkout sends the buyer to
  /store/fake-checkout/<ref>, where "Pay" and "Cancel" produce the same
  events a real provider's webhook would. Only usable while
  `config :bacon8, BaconStore.Payments, fake_enabled: true`.
  """
  @behaviour BaconStore.Payments.Provider

  alias BaconStore.Payments.Event

  @impl true
  def name, do: "fake"

  @impl true
  def create_checkout(_order, _opts) do
    ref = "fake_cs_" <> random()
    {:ok, %{redirect_url: "/store/fake-checkout/#{ref}", provider_ref: ref, expires_at: DateTime.add(DateTime.utc_now(), 31 * 60, :second)}}
  end

  # Unfinished checkouts (2026-10-29c). The fake keeps no state of its own: a checkout is paid
  # once an order of it is, open while it awaits payment, otherwise closed. Tests can pretend
  # the provider knows better (a payment whose event never arrived):
  # `config :bacon8, BaconStore.Payments.Fake, status: %{ref => %{state: :paid, ...}}`.
  @impl true
  def expire_checkout(ref) do
    case checkout_status(ref) do
      {:ok, %{state: :paid}} -> {:error, :already_paid}
      _ -> :ok
    end
  end

  @impl true
  def checkout_status(ref) do
    import Ecto.Query
    override = Application.get_env(:bacon8, __MODULE__, []) |> Keyword.get(:status, %{}) |> Map.get(ref)

    orders = Bacon8.Repo.all(from o in BaconStore.Store.Order, where: o.provider == "fake" and o.provider_ref == ^ref)
    total = Enum.sum(Enum.map(orders, &(&1.amount_cents || 0)))

    state =
      cond do
        orders == [] -> :expired
        Enum.any?(orders, &(&1.paid_at != nil)) -> :paid
        Enum.all?(orders, &(&1.status == "awaiting_payment")) -> :open
        true -> :expired
      end

    {:ok, Map.merge(%{state: state, amount_cents: total, currency: "usd", payment_ref: nil}, override || %{})}
  end

  # The fake has no webhooks; its checkout page calls complete/2 and fail/1.
  @impl true
  def parse_webhook(_raw_body, _headers), do: {:error, :no_webhooks}

  @doc "The buyer clicked Pay: the provider took `amount_cents` for checkout `ref`."
  def complete(ref, amount_cents, currency \\ "usd") do
    event(:checkout_completed, ref, %{amount_cents: amount_cents, currency: currency})
  end

  @doc "The checkout was abandoned or the card declined."
  def fail(ref), do: event(:checkout_failed, ref, %{})

  @doc "A chargeback's progress (`:dispute_opened`, `:dispute_won`, `:dispute_lost`)."
  def dispute(ref, type) when type in [:dispute_opened, :dispute_won, :dispute_lost], do: event(type, ref, %{})

  defp event(type, ref, extra) do
    BaconStore.Payments.ingest(
      struct!(Event, Map.merge(%{type: type, provider: name(), provider_event_id: "fake_evt_" <> random(), provider_ref: ref, raw: %{"type" => to_string(type), "ref" => ref}}, extra))
    )
  end

  defp random, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
