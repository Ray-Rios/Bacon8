defmodule Bacon8Web.Components.GameCard do
  @moduledoc """
  A game's card on /games (`Bacon8.GameCards`): a literal card. The front cycles
  through the game's pictures under its name and tagline; hovering turns it over with a
  glassy shine to the back: a picture, the details and a Play button. On touch screens a
  tap turns it. Styles: `.gc` in `assets/css/app.css`; behaviour: the `GameCard` hook
  (`assets/js/game_card.ts`).
  """
  use Phoenix.Component

  @doc """
  `game` is a `Bacon8.Plugins.active_games/0` entry, `card` its `Bacon8.GameCards.t()`.
  With `preview`, the Play button doesn't navigate (the admin's preview).
  """
  attr :id, :string, required: true
  attr :game, :map, required: true
  attr :card, :map, required: true
  attr :preview, :boolean, default: false

  def game_card(assigns) do
    card = assigns.card
    fronts = card.fronts

    assigns =
      assigns
      |> assign(:fronts, fronts)
      |> assign(:back, card.back || List.first(fronts))
      |> assign(:back_fallback, is_nil(card.back))
      |> assign(:tagline, card.tagline || Map.get(assigns.game, :description))
      |> assign(:paragraphs, paragraphs(card.details))
      |> assign(:icon, Map.get(assigns.game, :icon, "🎮"))

    ~H"""
    <div
      id={@id}
      class="gc"
      phx-hook="GameCard"
      data-seconds={@card.seconds}
      tabindex="0"
      role="group"
      aria-label={@game.name}
    >
      <div class="gc-inner">
        <div class="gc-face gc-front">
          <%= if @fronts == [] do %>
            <div class="gc-nopic">{@icon}</div>
          <% else %>
            <img
              :for={{src, i} <- Enum.with_index(@fronts)}
              src={src}
              class={["gc-pic", i == 0 && "on"]}
              alt=""
              loading={if i == 0, do: "eager", else: "lazy"}
              draggable="false"
            />
          <% end %>
          <div class="gc-gloss"></div>
          <div class="gc-title">
            <h2><span class="gc-icon">{@icon}</span>{@game.name}</h2>
            <p :if={@tagline}>{@tagline}</p>
          </div>
          <div :if={length(@fronts) > 1} class="gc-dots">
            <i :for={{_src, i} <- Enum.with_index(@fronts)} class={i == 0 && "on"}></i>
          </div>
        </div>

        <div class="gc-face gc-back">
          <img :if={@back} src={@back} class={["gc-backpic", @back_fallback && "fallback"]} alt="" loading="lazy" draggable="false" />
          <div class="gc-gloss"></div>
          <div class="gc-panel">
            <h2>{@game.name}</h2>
            <div class="gc-details">
              <p :for={p <- @paragraphs}>{p}</p>
              <p :if={@paragraphs == [] and @tagline}>{@tagline}</p>
            </div>
            <%= if @preview do %>
              <span class="gc-play" aria-disabled="true"><span class="gc-play-arrow">▶</span>{@card.play_label}</span>
            <% else %>
              <.link navigate={@game.path} class="gc-play"><span class="gc-play-arrow">▶</span>{@card.play_label}</.link>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp paragraphs(nil), do: []

  defp paragraphs(text) do
    text
    |> String.split(~r/\R\s*\R/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
