defmodule Bacon8.Payments do
  @moduledoc """
  Payment providers and the event inbox (BACON8.md §8).

  Webhooks are the source of truth, never the buyer's redirect back: an order
  is paid when the provider says so. Every event is stored in
  `payment_events` first (`unique(provider, provider_event_id)`), then handed
  to `Bacon8.Store`; a re-delivered event finds its row and does nothing.

  Config:

      config :bacon8, Bacon8.Payments,
        default_provider: "fake",
        providers: %{"fake" => Bacon8.Payments.Fake, "stripe" => Bacon8.Payments.Stripe},
        fake_enabled: true          # dev and test only

  runtime.exs makes "stripe" the default when `STRIPE_SECRET_KEY` is set.

  The fake provider is refused unless `fake_enabled` is true, so it can't
  take "payments" in production even if someone points the config at it.
  """

  require Logger
  import Ecto.Query
  alias Bacon8.Repo
  alias Bacon8.Payments.{Event, PaymentEvent}

  defp config, do: Application.get_env(:bacon8, __MODULE__, [])

  @doc "The provider module for a name, if it's configured (and, for the fake, enabled)."
  def provider(name) when is_binary(name) do
    providers = Keyword.get(config(), :providers, %{})

    case Map.fetch(providers, name) do
      {:ok, Bacon8.Payments.Fake} ->
        if fake_enabled?(), do: {:ok, Bacon8.Payments.Fake}, else: {:error, :unknown_provider}

      {:ok, mod} ->
        Code.ensure_loaded(mod)
        if function_exported?(mod, :available?, 0) and not mod.available?(), do: {:error, :not_configured}, else: {:ok, mod}

      :error ->
        {:error, :unknown_provider}
    end
  end

  def default_provider, do: Keyword.get(config(), :default_provider, "fake")

  def fake_enabled?, do: Keyword.get(config(), :fake_enabled, false) == true

  @doc """
  A webhook from `provider_name`: verify it, store it, process it. Returns
  `:ok` for anything the provider shouldn't retry (including duplicates and
  ignored types) and `{:error, reason}` when it should.
  """
  def handle_webhook(provider_name, raw_body, headers) do
    with {:ok, mod} <- provider(provider_name) do
      case mod.parse_webhook(raw_body, headers) do
        {:ok, %Event{} = event} -> ingest(event)
        :ignore -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Stores a normalised event and applies it. Idempotent per (provider, event id)."
  def ingest(%Event{} = event) do
    row = %{
      id: Ecto.UUID.generate(),
      provider: event.provider,
      provider_event_id: event.provider_event_id,
      event_type: to_string(event.type),
      payload: event.raw || %{},
      inserted_at: DateTime.utc_now()
    }

    case Repo.insert_all(PaymentEvent, [row], on_conflict: :nothing, conflict_target: [:provider, :provider_event_id]) do
      {1, _} ->
        process(row, event)

      # Seen before. Done if it was processed; if processing failed last time,
      # this re-delivery is the provider's retry, so try again (applying an
      # event is idempotent).
      {0, _} ->
        case Repo.get_by(PaymentEvent, provider: event.provider, provider_event_id: event.provider_event_id) do
          %PaymentEvent{processed_at: nil} = existing -> process(existing, event)
          _ -> :ok
        end
    end
  end

  defp process(stored, event) do
    result =
      try do
        Bacon8.Store.apply_event(event)
      rescue
        e -> {:error, Exception.message(e)}
      end

    case result do
      :ok ->
        mark(stored, processed_at: DateTime.utc_now(), error: nil)
        :ok

      {:error, reason} ->
        Logger.error("Payments: #{event.provider} event #{event.provider_event_id} (#{event.type}) failed: #{inspect(reason)}")
        mark(stored, error: inspect(reason))
        {:error, reason}
    end
  end

  defp mark(stored, fields) do
    Repo.update_all(from(p in PaymentEvent, where: p.id == ^stored.id), set: fields)
  end

  @doc """
  Re-applies stored dispute events for a payment that failed because they
  arrived before the checkout completion that tells us the payment's id
  (Stripe can send `charge.dispute.created` first). Called by
  `Bacon8.Store` once an order has its `provider_payment_ref`.
  """
  def replay_waiting(provider_name, payment_ref) when is_binary(payment_ref) do
    with {:ok, mod} <- provider(provider_name),
         true <- Code.ensure_loaded?(mod) and function_exported?(mod, :event_from_payload, 1) do
      from(p in PaymentEvent,
        where: p.provider == ^provider_name and is_nil(p.processed_at),
        where: p.event_type in ["dispute_opened", "dispute_won", "dispute_lost"],
        where: fragment("?->'data'->'object'->>'payment_intent' = ?", p.payload, ^payment_ref),
        order_by: [asc: p.inserted_at]
      )
      |> Repo.all()
      |> Enum.each(fn stored ->
        case mod.event_from_payload(stored.payload) do
          {:ok, event} -> process(stored, event)
          _ -> :ok
        end
      end)
    end

    :ok
  end

  def replay_waiting(_provider_name, _payment_ref), do: :ok

  @doc "Recent events, newest first (admin)."
  def recent_events(limit \\ 50) do
    Repo.all(from p in PaymentEvent, order_by: [desc: p.inserted_at], limit: ^limit)
  end
end
