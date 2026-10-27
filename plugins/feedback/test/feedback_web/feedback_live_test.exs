defmodule FeedbackWeb.FeedbackLiveTest do
  # The Suggestions & Bugs pages and the start menu icon.
  use Bacon8.DataCase, async: false

  import Feedback.Fixtures
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, _} = Bacon8.Plugins.activate("feedback")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  defp signed_in(user), do: build_conn() |> Plug.Test.init_test_session(%{"user_id" => user.id})

  test "guests and the signed-out are sent away; screenshots are 404 to them" do
    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in(guest()), "/feedback")
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), "/feedback")

    i = item(member(), %{}, [{tmp_upload(png()), "a.png"}])
    [shot] = Repo.preload(i, :shots).shots
    assert signed_in(guest()) |> get("/feedback/shots/#{shot.id}") |> response(404)
    assert build_conn() |> get("/feedback/shots/#{shot.id}") |> response(404)
    conn = signed_in(member()) |> get("/feedback/shots/#{shot.id}")
    assert conn.status == 200 and conn.resp_body == png()
    assert ["nosniff"] = Plug.Conn.get_resp_header(conn, "x-content-type-options")
  end

  test "the start menu shows the icon to members, not to guests" do
    html =
      render_component(&Bacon8Web.Components.Taskbar.taskbar/1,
        current_user: member(),
        show_start_menu: true
      )

    assert html =~ "Suggestions &amp; Bugs"
    assert html =~ ~s(href="/feedback")

    html =
      render_component(&Bacon8Web.Components.Taskbar.taskbar/1,
        current_user: guest(),
        show_start_menu: true
      )

    refute html =~ "Suggestions &amp; Bugs"
  end

  test "a member posts a bug with a screenshot, sees it, and votes" do
    me = member()
    {:ok, view, html} = live(signed_in(me), "/feedback")
    assert html =~ "Suggestions &amp; Bugs"

    view |> element("#new-bug") |> render_click()
    assert_patch(view, "/feedback/new?kind=bug")

    shot =
      file_input(view, "#feedback-form", :shots, [
        %{name: "kraken.png", content: png(), type: "image/png"}
      ])

    render_upload(shot, "kraken.png")

    view
    |> form("#feedback-form",
      item: %{
        kind: "bug",
        area: "site",
        title: "Chat scrolls up by itself",
        body: "Every new message jumps the list to the top."
      }
    )
    |> render_submit()

    {path, _} = assert_redirect(view)
    i = Repo.get_by!(Feedback.Item, title: "Chat scrolls up by itself")
    assert path == "/feedback/#{i.id}"
    assert [%{filename: "kraken.png"}] = Repo.preload(i, :shots).shots

    other = member()
    {:ok, list, html} = live(signed_in(other), "/feedback")
    assert html =~ "Chat scrolls up by itself"
    list |> element("#item-#{i.id} button[aria-label='Vote up']") |> render_click()
    assert Repo.get!(Feedback.Item, i.id).score == 2
  end

  test "an admin approves and submits to Claude from the item page; members don't see those buttons" do
    boss = admin()
    i = item(member())

    {:ok, mview, _} = live(signed_in(member()), "/feedback/#{i.id}")
    refute has_element?(mview, "#admin-panel")

    {:ok, view, _} = live(signed_in(boss), "/feedback/#{i.id}")
    view |> element("#action-approve") |> render_click()
    assert Repo.get!(Feedback.Item, i.id).status == "approved"
    view |> element("#action-submit") |> render_click()
    assert Repo.get!(Feedback.Item, i.id).status == "queued"
    assert render(view) =~ "Queued for Claude"
    # the member's open page updates too
    assert render(mview) =~ "Queued for Claude"
  end

  test "the runner page: make a token (shown once), auto-deploy and pause switches" do
    boss = admin()
    assert {:error, {_redirect, %{to: "/"}}} = live(signed_in(member()), "/admin/feedback/agent")
    {:ok, view, _} = live(signed_in(boss), "/admin/feedback/agent")
    html = view |> element("#make-token") |> render_click()
    [token] = Regex.run(~r/b8fb_[A-Za-z0-9_-]+/, html)
    assert Feedback.agent_token_valid?(token)
    view |> element("#toggle-auto-deploy") |> render_click()
    assert Feedback.agent().auto_deploy
    view |> element("#toggle-paused") |> render_click()
    assert Feedback.agent().paused
  end
end
