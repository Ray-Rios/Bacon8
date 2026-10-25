defmodule Bacon8.GameCardsTest do
  # Not async: uploads and the card row are shared per plugin.
  use Bacon8.DataCase, async: false

  alias Bacon8.GameCards

  # Bacon World ships a card folder: plugins/bacon_world/priv/static/card/.
  @slug "bacon_world"

  setup do
    on_exit(fn -> File.rm_rf(GameCards.upload_dir(@slug)) end)
    :ok
  end

  defp picture!(name, bytes \\ <<"RIFF", 0, 0, 0, 0, "WEBP", "VP8 ", 0, 0>>) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{name}")
    File.write!(path, bytes)
    path
  end

  test "a plugin's card comes from its folder" do
    card = GameCards.get(@slug)
    assert card.fronts == ["/plugins/bacon_world/card/front-1.webp"]
    assert card.back == "/plugins/bacon_world/card/back.webp"
    assert card.tagline =~ "browser"
    assert card.details =~ "Baconator"
    assert card.play_label == "Play"
    assert card.seconds == 5
    refute card.customized
  end

  test "a plugin without a card folder gets an empty card" do
    card = GameCards.get("bacon_store")
    assert card.fronts == []
    assert card.back == nil
    assert card.play_label == "Play"
  end

  test "an admin's card overrides the folder, and reset brings it back" do
    {:ok, url} = GameCards.store_upload(@slug, picture!("a.webp"), "a.webp")
    assert url =~ ~r{^/uploads/public/game_cards/bacon_world/[\w-]+\.webp$}

    Phoenix.PubSub.subscribe(Bacon8.PubSub, GameCards.topic())

    attrs = %{
      "fronts" => [url, "/plugins/bacon_world/card/front-1.webp"],
      "back" => nil,
      "tagline" => "New tagline",
      "details" => "One.\n\nTwo.",
      "play_label" => "Enter",
      "seconds" => "9"
    }

    assert {:ok, card} = GameCards.save(@slug, attrs)
    assert_received {:game_card_changed, @slug}
    assert card.fronts == [url, "/plugins/bacon_world/card/front-1.webp"]
    assert card.back == nil
    assert card.tagline == "New tagline"
    assert card.play_label == "Enter"
    assert card.seconds == 9
    assert card.customized
    assert GameCards.for_plugins([@slug])[@slug] == card

    file = Path.join(GameCards.upload_dir(@slug), Path.basename(url))
    assert File.exists?(file)

    # Removed from the card: the upload goes on the next save.
    assert {:ok, _} = GameCards.save(@slug, %{attrs | "fronts" => ["/plugins/bacon_world/card/front-1.webp"]})
    refute File.exists?(file)

    assert {:ok, card} = GameCards.reset(@slug)
    refute card.customized
    assert card.tagline =~ "browser"
  end

  test "only this card's own pictures can be saved" do
    for bad <- ["/uploads/public/game_cards/rays_space_sim/x.webp", "https://example.com/x.webp",
                "/plugins/bacon_world/card/../../lib/x.webp", "/plugins/bacon_world/card/missing.webp"] do
      assert {:error, _} = GameCards.save(@slug, %{"fronts" => [bad]})
      assert {:error, _} = GameCards.save(@slug, %{"fronts" => [], "back" => bad})
    end

    too_many = List.duplicate("/plugins/bacon_world/card/front-1.webp", GameCards.max_fronts() + 1)
    assert {:error, _} = GameCards.save(@slug, %{"fronts" => too_many})
    assert {:error, _} = GameCards.save(@slug, %{"fronts" => [], "tagline" => String.duplicate("x", 141)})
    assert {:error, _} = GameCards.save("no_such_plugin", %{"fronts" => []})
  end

  test "uploads must really be pictures" do
    assert {:error, _} = GameCards.store_upload(@slug, picture!("x.webp", "<html>hi</html>"), "x.webp")
    assert {:error, _} = GameCards.store_upload(@slug, picture!("x.svg"), "x.svg")
    assert {:ok, _} = GameCards.store_upload(@slug, picture!("x.png", <<0x89, "PNG", 13, 10, 26, 10>>), "x.png")
    assert {:ok, _} = GameCards.store_upload(@slug, picture!("x.jpg", <<0xFF, 0xD8, 0xFF, 0xE0>>), "x.JPG")
  end

  test "seconds are kept between 2 and 60" do
    assert GameCards.from_data(@slug, %{"seconds" => 0}).seconds == 2
    assert GameCards.from_data(@slug, %{"seconds" => "600"}).seconds == 60
    assert GameCards.from_data(@slug, %{"seconds" => "soon"}).seconds == 5
  end
end
