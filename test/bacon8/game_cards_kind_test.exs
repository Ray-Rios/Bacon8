defmodule Bacon8.GameCardsKindTest do
  # In the browser or a download (2026-10-29): a download game's card opens the CMS page picked for
  # it. RaysSpaceSim's page and card come from migration 20261029110000.
  use Bacon8.DataCase, async: false

  alias Bacon8.{Content, GameCards}

  test "RaysSpaceSim is a download whose card opens its page; Bacon World plays in the browser" do
    assert %{kind: "download", page: "rays-space-sim", play_path: "/pages/rays-space-sim"} = GameCards.get("rays_space_sim")
    assert %{is_published: true, title: "RaysSpaceSim"} = Content.get_page_by_slug("rays-space-sim")
    assert %{kind: "browser", page: nil, play_path: nil} = GameCards.get("bacon_world")
  end

  test "an admin picks the page; a page that doesn't exist is refused; a browser game has none" do
    base = %{"fronts" => [], "tagline" => "", "details" => "", "play_label" => "Play", "seconds" => 5}
    assert {:error, "That page doesn't exist."} = GameCards.validate("rays_space_sim", Map.merge(base, %{"kind" => "download", "page" => "nope"}))
    assert {:ok, %{"kind" => "download", "page" => "rays-space-sim"}} = GameCards.validate("rays_space_sim", Map.merge(base, %{"kind" => "download", "page" => "rays-space-sim"}))
    assert {:ok, %{"kind" => "browser", "page" => ""}} = GameCards.validate("bacon_world", Map.merge(base, %{"kind" => "browser", "page" => "rays-space-sim"}))
    assert {:error, _} = GameCards.validate("bacon_world", Map.merge(base, %{"kind" => "cartridge"}))

    {:ok, card} = GameCards.save("bacon_world", Map.merge(base, %{"kind" => "download", "page" => "rays-space-sim"}))
    assert card.play_path == "/pages/rays-space-sim"
  end
end
