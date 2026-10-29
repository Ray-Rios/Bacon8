defmodule Bacon8Web.AuthRegisterTest do
  # A sign-up the site refuses must say why, not crash the form (the page just reset, 2026-10-28).
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  @endpoint Bacon8Web.Endpoint

  defp submit(view, email, name) do
    view
    |> form("form", user: %{"email" => email, "name" => name, "password" => "a-long-password-1"})
    |> render_submit()
  end

  test "an email already in use is reported" do
    taken = person("member")
    {:ok, view, _} = live(build_conn(), "/register")

    html = submit(view, taken.email, "someone_new")

    assert Process.alive?(view.pid)
    assert html =~ "already exists"
  end

  test "a user name already in use is reported" do
    taken = person("member")
    {:ok, view, _} = live(build_conn(), "/register")

    html = submit(view, "fresh-#{System.unique_integer([:positive])}@example.com", taken.name)

    assert Process.alive?(view.pid)
    assert html =~ "already taken"
  end
end
