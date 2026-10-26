defmodule Bacon8.Content.AuditTest do
  use ExUnit.Case, async: true

  alias Bacon8.Content.Audit

  defp blocks(list), do: Jason.encode!(%{"rows" => [%{"columns" => [%{"blocks" => list}]}]})
  defp image(settings \\ nil), do: Map.merge(%{"type" => "image", "content" => "/a.png"}, if(settings, do: %{"settings" => settings}, else: %{}))

  test "nothing to check" do
    for empty <- [nil, "", "<p>words</p>", ~s({"rows":[]}), "[]", 5] do
      assert Audit.images_missing_alt(empty) == 0
    end
  end

  test "an image with no alt text counts; with alt text, or marked decorative, it doesn't" do
    assert Audit.images_missing_alt(blocks([image()])) == 1
    assert Audit.images_missing_alt(blocks([image(%{"alt" => ""})])) == 1
    assert Audit.images_missing_alt(blocks([image(%{"alt" => "   "})])) == 1
    assert Audit.images_missing_alt(blocks([image(%{"alt" => "A red ship"})])) == 0
    assert Audit.images_missing_alt(blocks([image(%{"decorative" => true})])) == 0
  end

  test "an image block with no picture yet is not counted, and other blocks are ignored" do
    assert Audit.images_missing_alt(blocks([%{"type" => "image", "content" => ""}, %{"type" => "text", "content" => "<p>x</p>"}])) == 0
  end

  test "counts across rows, columns and gallery pictures" do
    content =
      Jason.encode!(%{
        "rows" => [
          %{"columns" => [%{"blocks" => [image()]}, %{"blocks" => [image(%{"alt" => "ok"}), image()]}]},
          %{"columns" => [%{"blocks" => [%{"type" => "gallery", "media" => [%{"url" => "/1.png", "alt" => "one"}, %{"url" => "/2.png"}, %{"url" => "/3.png", "alt" => ""}]}]}]}
        ]
      })

    assert Audit.images_missing_alt(content) == 2 + 2
  end

  test "old HTML content is checked by its img tags" do
    html = ~s(<p>hi</p><img src="/a.png"><img src="/b.png" alt=""><img src="/c.png" alt="A cat"><IMG SRC='/d.png' ALT='A dog'>)
    assert Audit.images_missing_alt(html) == 2
  end

  test "malformed block data doesn't crash" do
    assert Audit.images_missing_alt(~s({"rows":[{"columns":"x"},{"columns":[{"blocks":[1,null,"s"]}]},5]})) == 0
  end
end
