defmodule BaconStoreWeb.PaymentWebhookController do
  @moduledoc """
  POST /api/store/webhooks/:provider - provider webhooks (BACON8.md §8).

  Answers 200 once the event is safely handled (or is a duplicate, or a type
  we ignore), 400 when the signature or body is bad (the provider shouldn't
  retry those), and 500 when processing failed, so the provider retries.
  """
  use Bacon8Web, :controller
  require Logger

  def create(conn, %{"provider" => provider}) do
    raw = conn.private[:raw_body] || ""

    case BaconStore.Payments.handle_webhook(provider, raw, conn.req_headers) do
      :ok ->
        json(conn, %{received: true})

      {:error, reason} when reason in [:unknown_provider, :not_configured] ->
        conn |> put_status(404) |> json(%{error: "unknown provider"})

      {:error, reason}
      when reason in [:missing_signature, :bad_signature, :stale_signature, :no_webhook_secret, :malformed_event, :no_webhooks] ->
        Logger.warning("Payment webhook from #{provider} refused: #{inspect(reason)}")
        conn |> put_status(400) |> json(%{error: to_string(reason)})

      {:error, %Jason.DecodeError{}} ->
        conn |> put_status(400) |> json(%{error: "malformed_event"})

      {:error, _reason} ->
        # Already logged by BaconStore.Payments; the provider will retry.
        conn |> put_status(500) |> json(%{error: "processing failed"})
    end
  end
end
