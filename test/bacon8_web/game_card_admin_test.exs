defmodule Bacon8Web.GameCardAdminTest do
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

  alias Bacon8.GameCards

  @endpoint Bacon8Web.Endpoint
  @slug "bacon_world"

  # The section as a plugin's admin page embeds it.
  defmodule Page do
    use Phoenix.LiveView

    def mount(_params, _session, socket), do: {:ok, socket}

    def render(assigns) do
      ~H"""
      <.live_component module={Bacon8Web.GameCardAdmin} id="game-card" plugin="bacon_world" current_user={nil} />
      """
    end
  end

  setup do
    on_exit(fn ->
      GameCards.reset(@slug)
      File.rm_rf(GameCards.upload_dir(@slug))
    end)

    :ok
  end

  test "shows the plugin's card, and saves an edit with an uploaded picture" do
    {:ok, view, html} = live_isolated(build_conn(), Page)

    # The preview is the real card, front and back.
    assert html =~ ~s(id="gc-preview-bacon_world")
    assert html =~ "/plugins/bacon_world/card/front-1.webp"
    assert html =~ "/plugins/bacon_world/card/back.webp"
    assert html =~ "Baconator"

    view |> form("#game-card-form", card: %{tagline: "Fresh tagline", seconds: "7"}) |> render_change()

    picture =
      file_input(view, "#game-card-form", :fronts, [
        %{name: "new.png", content: <<0x89, "PNG", 13, 10, 26, 10, 0, 0>>, type: "image/png"}
      ])

    render_upload(picture, "new.png")
    html = render(view)
    assert html =~ ~r{/uploads/public/game_cards/bacon_world/[\w-]+\.png}
    assert html =~ "Unsaved changes"

    view |> form("#game-card-form") |> render_submit()
    assert render(view) =~ "Saved."

    card = GameCards.get(@slug)
    assert card.customized
    assert card.tagline == "Fresh tagline"
    assert card.seconds == 7
    assert [_folder, uploaded] = card.fronts
    assert uploaded =~ ".png"

    view |> element("button", "Reset to the plugin's card") |> render_click()
    refute GameCards.get(@slug).customized
  end

  test "the games list shows each active game as a card" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Bacon8Web.Components.GameCard.game_card
        id="x"
        game={%{name: "Bacon World", path: "/games/bacon_world", description: "d", icon: "🕹️"}}
        card={GameCards.get("bacon_world")}
      />
      """)

    assert html =~ ~s(phx-hook="GameCard")
    assert html =~ ~s(class="gc-pic on")
    assert html =~ ~s(href="/games/bacon_world")
    assert html =~ "Play"
  end
end
