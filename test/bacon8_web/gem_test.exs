defmodule Bacon8Web.Components.GemTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

  alias Bacon8Web.Components.Gem

  test "amounts are grouped by thousands" do
    assert Gem.format(0) == "0"
    assert Gem.format(999) == "999"
    assert Gem.format(1500) == "1,500"
    assert Gem.format(1_234_567) == "1,234,567"
    assert Gem.format(-2500) == "-2,500"
    assert Gem.format(nil) == "0"
  end

  test "the gem, an amount, and the \"gem\" icon" do
    assigns = %{}

    html = rendered_to_string(~H"<Gem.gem size={24} still />")
    assert html =~ ~s(<b8-gem size="24" still)
    assert html =~ "--gem-size:24px"

    html = rendered_to_string(~H"<Gem.gems amount={1500} />")
    assert html =~ "<b8-gem"
    assert html =~ "1,500"

    assert rendered_to_string(~H|<Gem.icon icon="gem" />|) =~ "<b8-gem"
    assert rendered_to_string(~H|<Gem.icon icon="🛒" />|) =~ "🛒"
  end
end
