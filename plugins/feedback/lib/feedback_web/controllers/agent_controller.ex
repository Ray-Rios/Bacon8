defmodule FeedbackWeb.AgentController do
  @moduledoc """
  The API Claude's runner calls (README.md, "Claude's runner"). Every request carries
  `Authorization: Bearer <token>`, the token an admin made on /admin/feedback/agent; anything
  else is 401, and failures are rate limited per address. The runner can only read what was
  submitted to Claude and report on it: it cannot see other items, users or anything else.

    * `GET /api/feedback/agent/next` - `{"action": "work", "item": ...}` (it now has the oldest
      submitted item), `{"action": "deploy", "item": ...}` (an admin pressed Deploy on a held
      change), `{"action": "wait", "item": ...}` (a change is in progress or waiting for
      Deploy), `{"action": "resume", "item": ...}` (an item is still "in progress": the last run
      stopped part way), `{"action": "paused"}` or `{"action": "none"}`. With `?peek=1` nothing is claimed:
      `{"action": "queued", "waiting": n}` instead of "work". Every answer also has
      `"auto_deploy"`.
    * `GET /api/feedback/agent/items/:id` - one item it may see.
    * `POST /api/feedback/agent/items/:id/report` - `status`, `summary`, `commit`,
      `hold_reason`, `note` (see `Feedback.agent_report/2`).
    * `GET /api/feedback/agent/shots/:id` - a screenshot's bytes.
  """
  use Bacon8Web, :controller

  alias Bacon8.Storage

  plug(:authenticate)

  def next(conn, params) do
    Feedback.touch_agent(params["note"])
    agent = Feedback.agent()

    body =
      case Feedback.agent_next(peek: params["peek"] in ["1", "true"]) do
        {:paused, _} -> %{action: "paused"}
        {:queued, n} -> %{action: "queued", waiting: n}
        :empty -> %{action: "none"}
        {:ok, item} -> %{action: "work", item: view(conn, item)}
        {:busy, %{status: "deploying"} = item} -> %{action: "deploy", item: view(conn, item)}
        {:busy, %{status: "in_progress"} = item} -> %{action: "resume", item: view(conn, item)}
        {:busy, item} -> %{action: "wait", item: view(conn, item)}
      end

    json(conn, Map.put(body, :auto_deploy, agent.auto_deploy))
  end

  def show(conn, %{"id" => id}) do
    case Feedback.agent_item(id) do
      nil -> not_found(conn)
      item -> json(conn, %{item: view(conn, item), auto_deploy: Feedback.agent().auto_deploy})
    end
  end

  def report(conn, %{"id" => id} = params) do
    case Feedback.agent_report(id, params) do
      {:ok, item} -> json(conn, %{ok: true, status: item.status})
      {:error, :not_found} -> not_found(conn)
      {:error, reason} -> conn |> put_status(422) |> json(%{ok: false, error: inspect(reason)})
    end
  end

  def shot(conn, %{"id" => id}) do
    with %Feedback.Shot{} = shot <- Feedback.agent_shot(id),
         {:ok, path} <- Storage.local_path(shot.sha256) do
      conn
      |> put_resp_content_type(shot.content_type, nil)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> send_file(200, path)
    else
      _ -> not_found(conn)
    end
  end

  # Screenshot URLs are paths: the runner puts its own base URL in front.
  defp view(_conn, item),
    do: Feedback.agent_view(item, fn s -> "/api/feedback/agent/shots/" <> s.id end)

  defp not_found(conn),
    do: conn |> put_status(404) |> json(%{ok: false, error: "not found"}) |> halt()

  # The token, compared in constant time. A right token always gets through: the limit (ten
  # failures a minute per address, then 429 for the rest of the minute) only slows guessing, and it
  # must never lock the real runner out when strangers share its address behind the proxy.
  defp authenticate(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> t] -> String.trim(t)
        _ -> nil
      end

    cond do
      Feedback.agent_token_valid?(token) ->
        conn

      limited?(ip, false) ->
        conn |> put_status(429) |> json(%{ok: false, error: "too many attempts"}) |> halt()

      true ->
        limited?(ip, true)
        conn |> put_status(401) |> json(%{ok: false, error: "unauthorized"}) |> halt()
    end
  end

  defp limited?(ip, record?) do
    key = {:feedback_agent_fail, ip}

    if record? do
      Bacon8.RateLimiter.check_and_increment_rate(key, 10, 60_000)
      true
    else
      case :ets.lookup(:rate_limit_table, key) do
        [{^key, stamps}] ->
          Enum.count(stamps, &(&1 > System.system_time(:millisecond) - 60_000)) >= 10

        _ ->
          false
      end
    end
  rescue
    ArgumentError -> false
  end
end
