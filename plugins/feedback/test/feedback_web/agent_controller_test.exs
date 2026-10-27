defmodule FeedbackWeb.AgentControllerTest do
  # The API Claude's runner calls: token required, one item at a time, screenshots, reports.
  use Bacon8.DataCase, async: false

  import Feedback.Fixtures
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, _} = Bacon8.Plugins.activate("feedback")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    boss = admin()
    {:ok, token} = Feedback.new_agent_token(boss)
    %{boss: boss, token: token}
  end

  defp api(token),
    do:
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)

  test "no token, a wrong one, or a session cookie: 401" do
    assert build_conn() |> get("/api/feedback/agent/next") |> json_response(401)

    assert api("b8fb_wrongwrongwrongwrongwrongwrong")
           |> get("/api/feedback/agent/next")
           |> json_response(401)

    boss = admin()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"user_id" => boss.id})
      |> put_req_header("accept", "application/json")

    assert conn |> get("/api/feedback/agent/next") |> json_response(401)
  end

  test "guessing is slowed down, but the right token always gets through", %{token: token} do
    on_exit(fn -> :ets.delete(:rate_limit_table, {:feedback_agent_fail, "127.0.0.1"}) end)

    for _ <- 1..10, do: build_conn() |> get("/api/feedback/agent/next")
    assert build_conn() |> get("/api/feedback/agent/next") |> json_response(429)

    # strangers sharing the runner's address must not lock the runner out
    assert api(token) |> get("/api/feedback/agent/next") |> json_response(200)
  end

  test "the loop: nothing, then work with a screenshot, a report, wait, deploy, live", %{
    boss: boss,
    token: token
  } do
    assert %{"action" => "none", "auto_deploy" => false} =
             api(token) |> get("/api/feedback/agent/next") |> json_response(200)

    me = member()
    i = item(me, %{"kind" => "bug"}, [{tmp_upload(png()), "shot.png"}])
    {:ok, i} = Feedback.moderate(i, boss, "approve")
    {:ok, _} = Feedback.moderate(i, boss, "submit")

    assert %{"action" => "queued", "waiting" => 1} =
             api(token) |> get("/api/feedback/agent/next", peek: "1") |> json_response(200)

    body = api(token) |> get("/api/feedback/agent/next", note: "checking") |> json_response(200)

    assert %{
             "action" => "work",
             "item" => %{"id" => id, "kind" => "bug", "shots" => [%{"url" => url}]}
           } = body

    assert Feedback.agent().last_seen_note == "checking"

    shot = api(token) |> get(url)
    assert shot.status == 200
    assert shot.resp_body == png()
    assert ["image/png"] = Plug.Conn.get_resp_header(shot, "content-type")

    # a run that stopped part way is offered again
    assert %{"action" => "resume", "item" => %{"id" => ^id}} =
             api(token) |> get("/api/feedback/agent/next") |> json_response(200)

    assert %{"ok" => true, "status" => "ready"} =
             api(token)
             |> post("/api/feedback/agent/items/#{id}/report", %{
               status: "ready",
               summary: "Fixed it.",
               commit: "deadbeef"
             })
             |> json_response(200)

    assert %{"action" => "wait"} =
             api(token) |> get("/api/feedback/agent/next") |> json_response(200)

    {:ok, _} = Feedback.moderate(Feedback.get_item(id, boss), boss, "deploy")

    assert %{"action" => "deploy", "item" => %{"commit" => "deadbeef"}} =
             api(token) |> get("/api/feedback/agent/next") |> json_response(200)

    assert %{"status" => "deployed"} =
             api(token)
             |> post("/api/feedback/agent/items/#{id}/report", %{status: "deployed"})
             |> json_response(200)

    # done: it can't see the item or its screenshot any more
    assert api(token) |> get("/api/feedback/agent/items/#{id}") |> json_response(404)
    assert api(token) |> get(url) |> json_response(404)
  end

  test "a report it isn't allowed to make is 422; an unknown item 404", %{
    boss: boss,
    token: token
  } do
    i = item_at("queued", member(), boss)

    %{"item" => %{"id" => id}} =
      api(token) |> get("/api/feedback/agent/next") |> json_response(200)

    assert id == i.id

    assert api(token)
           |> post("/api/feedback/agent/items/#{id}/report", %{status: "open"})
           |> json_response(422)

    assert api(token)
           |> post("/api/feedback/agent/items/#{Ecto.UUID.generate()}/report", %{status: "ready"})
           |> json_response(404)
  end
end
