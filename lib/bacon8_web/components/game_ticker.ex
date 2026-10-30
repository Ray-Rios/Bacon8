defmodule Bacon8Web.Components.GameTicker do
  @moduledoc """
  The front page's lower-left corner (2026-10-29): the games, one at a time. A small picture-only
  game card on the left (its card's first picture, linking where its Play goes), and beside it
  the game's name, whether it's online, its zones or servers with who is in each, and how many
  play now and ever have (`Bacon8.GameStatus`). The `GameTicker` hook (assets/js/game_ticker.ts)
  turns to the next game every few seconds, pauses while pointed at, and keeps its place when
  the numbers refresh. Dismissible for the visit. Styles: assets/css/game_ticker.css.
  """
  use Phoenix.Component

  attr :games, :list, required: true
  attr :seconds, :integer, default: 6

  def ticker(assigns) do
    ~H"""
    <aside :if={@games != []} id="game-ticker" class="gt" phx-hook="GameTicker" data-seconds={@seconds} aria-label="Games right now">
      <button type="button" class="gt-x" data-gt-close aria-label="Hide">✕</button>
      <div :for={{g, i} <- Enum.with_index(@games)} id={"gt-#{g.slug}"} class={["gt-slide", i == 0 && "is-on"]} data-gt-slide={i}>
        <.link navigate={g.href} class="gt-card" aria-label={"Open #{g.name}"}>
          <img :if={g.image} src={g.image} alt="" loading="lazy" decoding="async" />
          <span :if={!g.image} class="gt-noimg" aria-hidden="true">🎮</span>
          <i class="gt-glint" aria-hidden="true"></i>
        </.link>
        <div class="gt-info">
          <div class="gt-name">{g.name}</div>
          <div class={["gt-state", g.online && "is-up"]}>
            <i aria-hidden="true"></i>{if g.online, do: "Online", else: "Offline"}
          </div>
          <ul :if={g.zones != []} class="gt-zones">
            <li :for={z <- Enum.take(g.zones, 3)} class={[z.online && "is-up"]}>
              <i aria-hidden="true"></i><span class="gt-zn">{z.name}</span><b>{z.players}</b>
            </li>
            <li :if={length(g.zones) > 3} class="gt-more">+{length(g.zones) - 3} more</li>
          </ul>
          <div class="gt-counts">
            <span><b>{number(g.current_players)}</b> playing now</span>
            <span><b>{number(g.total_players)}</b> {if g.total_players == 1, do: "player", else: "players"}</span>
          </div>
        </div>
      </div>
      <div :if={length(@games) > 1} class="gt-dots">
        <button :for={{g, i} <- Enum.with_index(@games)} type="button" data-gt-go={i} class={[i == 0 && "is-on"]} aria-label={g.name}></button>
      </div>
    </aside>
    """
  end

  defp number(n) when is_integer(n) and n >= 1000,
    do: n |> Integer.to_string() |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()

  defp number(n) when is_integer(n), do: Integer.to_string(n)
  defp number(_), do: "0"
end
