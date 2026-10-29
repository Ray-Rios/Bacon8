defmodule Bacon8Web.HomeIntroTest do
  # The front door (2026-10-28): visitors get the bacon pinned by the grill fork, the typed tagline, Sign Up and
  # Log In at once, and the sections about each part; members go to /games. Every page gets
  # the SVG and CSS cosmos background instead of the three.js scenes.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  @endpoint Bacon8Web.Endpoint

  test "a visitor sees Sign Up and Log In straight away, then every section" do
    {:ok, _view, html} = live(build_conn(), "/")

    assert html =~ ~s(phx-hook="IntroReveal")
    assert html =~ "intro-forks"
    assert html =~ "/images/intro/fork_l-600.webp"
    assert html =~ "<b8-bacon"
    assert html =~ ~s(phx-hook="IntroTagline")
    assert html =~ "Bringing home the bacon."
    # the typing runs the whole tagline (it once stopped at "Bringing home the bac")
    assert html =~ "--n:#{String.length("Bringing home the bacon.")}"
    assert html =~ "SECRET TO EVERYBODY"
    assert html =~ ~s(href="/register")
    assert html =~ ~s(href="/login")

    for id <- ~w(intro-what intro-editor intro-store intro-more intro-plugins intro-open) do
      assert html =~ ~s(id="#{id}"), "missing section #{id}"
    end

    for words <- ["WordPress", "Bringing home", "Stripe", "file store", "holo-sims", "Locked down", "Plugins, WordPress-style"] do
      assert html =~ words, "missing #{words}"
    end
  end

  test "/games has the shining title and the hat shot" do
    {:ok, _view, html} = live(signed_in(person("member")), "/games")
    assert html =~ ~s(class="games-title)
    assert html =~ "games-hat"
    assert html =~ "/images/intro/pierced-720.webp"
  end

  test "a member is sent to the games" do
    assert {:error, {:live_redirect, %{to: "/games"}}} = live(signed_in(person("member")), "/")
  end

  test "the page carries the cosmos background and no 3D canvas" do
    html = build_conn() |> get("/") |> html_response(200)

    assert html =~ ~s(id="global-background-canvas")
    assert html =~ ~s(class="cosmos")
    assert html =~ ~s(data-cosmos="galaxy")
    assert html =~ ~s(<template id="cosmos-layers">)
    refute html =~ "GlobalCameraController"
    refute html =~ "HomeGalaxyScene"
  end

  test "a member's chosen background is the one drawn, and unknown ones fall back to Deep Field" do
    for {kind, drawn} <- [{"aurora", "aurora"}, {"orbit", "orbit"}, {"nonsense", "galaxy"}] do
      html = Phoenix.LiveViewTest.rendered_to_string(Bacon8Web.Components.Cosmos.cosmos(%{kind: kind, id: "bg", __changed__: nil}))
      assert html =~ ~s(data-cosmos="#{drawn}")
    end
  end

  test "every background in the picker can be saved" do
    ids = Enum.map(Bacon8Web.Components.BackgroundSelector.backgrounds(), & &1.id)
    assert ids == ~w(galaxy nebula starfield orbit aurora void gradient solid)

    for id <- ids do
      changeset = Bacon8.Accounts.User.admin_changeset(%Bacon8.Accounts.User{}, %{background_preference: id})
      refute Keyword.has_key?(changeset.errors, :background_preference), "#{id} is refused"
    end
  end
end
