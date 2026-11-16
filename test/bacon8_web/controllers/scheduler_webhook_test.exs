defmodule Bacon8Web.SchedulerWebhookTest do
  # POST /api/webhooks/scheduler: the webhook's secret travels in a header (2026-11-15). It used to
  # be part of the URL, which the app's and the ingress's request logs keep.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  alias Bacon8.Scheduler

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, event} = Scheduler.create_scheduled_event(%{title: "hook #{System.unique_integer([:positive])}", event_type: "webhook"})
    assert is_binary(event.webhook_secret) and event.webhook_secret != ""
    %{event: event}
  end

  defp runs(event), do: Scheduler.get_scheduled_event!(event.id).run_count || 0
  defp post_with(headers) do
    Enum.reduce(headers, build_conn(), fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end) |> post("/api/webhooks/scheduler")
  end

  test "the secret in X-Webhook-Secret runs the event", %{event: event} do
    before = runs(event)
    conn = post_with([{"x-webhook-secret", event.webhook_secret}])
    # (an event with no action answers 500 from its action; either way it was found and run)
    assert conn.status in [200, 500]
    assert runs(event) == before + 1
  end

  test "Authorization: Bearer carries it too", %{event: event} do
    before = runs(event)
    assert post_with([{"authorization", "Bearer " <> event.webhook_secret}]).status in [200, 500]
    assert runs(event) == before + 1
  end

  test "no secret is 401, a wrong one 404, and neither runs anything", %{event: event} do
    before = runs(event)
    assert json_response(post_with([]), 401)["error"] =~ "X-Webhook-Secret"
    assert post_with([{"x-webhook-secret", "  "}]).status == 401
    assert post_with([{"x-webhook-secret", "not-" <> event.webhook_secret}]).status == 404
    assert runs(event) == before
  end

  test "the old URL with the secret in it is gone and runs nothing", %{event: event} do
    before = runs(event)
    conn = post(build_conn(), "/api/webhooks/scheduler/" <> event.webhook_secret)
    assert json_response(conn, 410)["error"] =~ "X-Webhook-Secret"
    assert runs(event) == before
  end

  test "what the API and the admin page show never has the secret in a URL", %{event: event} do
    assert Scheduler.generate_webhook_url(event.id) == "/api/webhooks/scheduler"
    assert Scheduler.trigger_webhook(nil) == {:error, :not_found}
    assert Scheduler.trigger_webhook("") == {:error, :not_found}
  end
end
