defmodule Bacon8Web.Components.Cosmos do
  @moduledoc """
  The site's cosmic backgrounds (2026-10-28): layered SVG and CSS, no WebGL, so a phone pays
  almost nothing for them. They replaced the three.js scenes, which kept a phone's main thread
  14-33% busy on every page while it sat idle.

  Depth comes from parallax, not rendering: star layers at three distances drift at three speeds
  (and, with a mouse, lean with the pointer: `BackgroundUpdater`), glowing clouds sit behind
  them, and a few things move in 3D through CSS transforms (the warp streaks, a ringed planet's
  moon). Every animation moves or fades a whole layer (transform and opacity only), which the
  browser hands to the graphics chip without repainting. Phones get fewer layers; "reduce motion"
  stops them all.

  One set of layers serves every kind: `data-cosmos` picks which show and how (assets/css/
  cosmos.css), so switching kinds is changing one attribute (`BackgroundUpdater`, the profile's
  background picker). The star tiles are `priv/static/images/cosmos/*.svg`.

  Kinds (`Bacon8.Accounts.User.background_preference`): "galaxy" (Deep Field, the default),
  "nebula", "starfield" (Warp), "orbit", "aurora", "void".
  """
  use Phoenix.Component

  @kinds ~w(galaxy nebula starfield orbit aurora void)
  def kinds, do: @kinds

  @doc "The name and line the profile's background picker shows for each kind."
  def catalogue do
    [
      %{id: "galaxy", name: "Deep Field", description: "Layers of stars drifting past a glowing band of galaxy"},
      %{id: "nebula", name: "Nebula", description: "Slow clouds of coloured gas behind the stars"},
      %{id: "starfield", name: "Warp", description: "Stars streaking past at light speed"},
      %{id: "orbit", name: "Orbit", description: "A ringed planet, its moon swinging round it"},
      %{id: "aurora", name: "Aurora", description: "Northern lights rippling over a starry sky"},
      %{id: "void", name: "Void", description: "Deep black with a scatter of distant stars"}
    ]
  end

  # Twinkling stars and warp streaks: fixed positions (the same on every page and for everyone,
  # so nothing jumps between pages), from a seeded generator at compile time.
  :rand.seed(:exsss, {8, 8, 8})

  @twinkles (for i <- 1..12 do
               %{x: Float.round(:rand.uniform() * 96 + 2, 1), y: Float.round(:rand.uniform() * 92 + 2, 1),
                 s: 6 + :rand.uniform(9), t: Float.round(3 + :rand.uniform() * 5, 1), d: Float.round(-:rand.uniform() * 8, 1), i: i}
             end)

  @streaks (for i <- 1..32 do
              %{a: round(i * 360 / 32 + :rand.uniform() * 9), d: Float.round(-:rand.uniform() * 3.2, 2),
                t: Float.round(2.2 + :rand.uniform() * 1.6, 2), w: Float.round(1 + :rand.uniform() * 1.2, 1)}
            end)

  @doc """
  The background, for the root layout. `kind` is one of `kinds/0`; anything else is Deep Field.
  It keeps the id the layout's background has always had (`global-background-canvas`).
  """
  attr :kind, :string, default: "galaxy"
  attr :id, :string, default: "global-background-canvas"

  def cosmos(assigns) do
    assigns = assign(assigns, kind: if(assigns.kind in @kinds, do: assigns.kind, else: "galaxy"))

    ~H"""
    <div id={@id} phx-update="ignore" class="cosmos" data-cosmos={@kind} data-bg-type="cosmos" aria-hidden="true">
      <.layers />
    </div>
    """
  end

  @doc """
  The layers alone, also kept in a `<template>` so the background can be switched to a cosmos
  from a flat colour without reloading (`BackgroundUpdater`).
  """
  attr :uid, :string, default: "cw", doc: "prefix for the planet's SVG ids; unique per copy on a page"

  def layers(assigns) do
    assigns = assign(assigns, twinkles: @twinkles, streaks: @streaks)

    ~H"""
    <div class="c-sky"></div>
    <div class="c-glow c-glow-1"></div>
    <div class="c-glow c-glow-2"></div>
    <div class="c-glow c-glow-3"></div>
    <div class="c-layer c-far"><i></i></div>
    <div class="c-layer c-mid"><i></i></div>
    <div class="c-aurora"><i></i><i></i></div>
    <div class="c-planet">
      <div class="c-bob">
        <svg viewBox="0 0 400 400" class="c-world">
          <defs>
            <radialGradient id={"#{@uid}-body"} cx="35%" cy="32%" r="75%">
              <stop offset="0" stop-color="#f6c38b" />
              <stop offset=".45" stop-color="#c46a4a" />
              <stop offset=".8" stop-color="#5a2a4a" />
              <stop offset="1" stop-color="#1a0d24" />
            </radialGradient>
            <linearGradient id={"#{@uid}-band"} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-color="#fff" stop-opacity="0" />
              <stop offset=".5" stop-color="#ffe3c2" stop-opacity=".22" />
              <stop offset="1" stop-color="#fff" stop-opacity="0" />
            </linearGradient>
            <linearGradient id={"#{@uid}-ring"} x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stop-color="#9fd8ff" stop-opacity="0" />
              <stop offset=".2" stop-color="#cde9ff" stop-opacity=".7" />
              <stop offset=".5" stop-color="#ffffff" stop-opacity=".35" />
              <stop offset=".8" stop-color="#cde9ff" stop-opacity=".7" />
              <stop offset="1" stop-color="#9fd8ff" stop-opacity="0" />
            </linearGradient>
            <clipPath id={"#{@uid}-clip"}><circle cx="200" cy="200" r="110" /></clipPath>
          </defs>
          <%!-- the ring's far half, behind the planet --%>
          <path d="M20 200 A180 46 0 0 1 380 200" fill="none" stroke={"url(##{@uid}-ring)"} stroke-width="14" />
          <circle cx="200" cy="200" r="110" fill={"url(##{@uid}-body)"} />
          <g clip-path={"url(##{@uid}-clip)"} opacity=".9">
            <rect x="60" y="150" width="280" height="16" fill={"url(##{@uid}-band)"} transform="rotate(-12 200 200)" />
            <rect x="60" y="196" width="280" height="26" fill={"url(##{@uid}-band)"} transform="rotate(-12 200 200)" />
            <rect x="60" y="246" width="280" height="12" fill={"url(##{@uid}-band)"} transform="rotate(-12 200 200)" />
          </g>
          <%!-- its near half, in front --%>
          <path d="M380 200 A180 46 0 0 1 20 200" fill="none" stroke={"url(##{@uid}-ring)"} stroke-width="14" />
        </svg>
        <div class="c-orbit"><div class="c-moonarm"><b class="c-moon"></b></div></div>
      </div>
    </div>
    <div class="c-layer c-near"><i></i></div>
    <div class="c-twinkle">
      <b :for={t <- @twinkles} style={"--x:#{t.x}%;--y:#{t.y}%;--s:#{t.s}px;--t:#{t.t}s;--d:#{t.d}s"}></b>
    </div>
    <div class="c-warp">
      <s :for={s <- @streaks} style={"--a:#{s.a}deg;--d:#{s.d}s;--t:#{s.t}s;--w:#{s.w}px"}></s>
    </div>
    """
  end
end
