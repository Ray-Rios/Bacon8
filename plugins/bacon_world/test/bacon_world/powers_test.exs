defmodule BaconWorld.PowersTest do
  use ExUnit.Case, async: true

  alias BaconWorld.Powers

  defp always, do: fn -> 0.0 end
  defp never, do: fn -> 0.99 end

  test "the powers worn come from the jeweller's bottoms" do
    assert Powers.active(%{"under_bottom" => "jw_phoenix_bottom", "under_top" => "jw_rose_top"}) == ["phoenix"]
    assert Powers.active(%{"under_bottom" => "homespun_bottom"}) == []
    assert Powers.active(nil) == []
  end

  test "swings: brilliance, starfire, snare and the lasso" do
    attack = %{crit_bonus: 0.0, pct: 0}
    {a, []} = Powers.swing(["brilliance"], attack, never())
    assert_in_delta a.crit_bonus, 0.15, 1.0e-9
    {a, ["starfire"]} = Powers.swing(["starfire"], attack, always())
    assert a.mult == 2.0
    {a, ["snare"]} = Powers.swing(["snare"], attack, always())
    assert a.root_ms == 2_000
    {a, fired} = Powers.swing(["lasso"], attack, always())
    assert a.extra_reach == 1.5 and a.pull_m == 1.5 and fired == ["lasso"]
    {a, []} = Powers.swing(["lasso"], attack, never())
    refute Map.has_key?(a, :pull_m)
  end

  test "giving back: riptide, starlit, bloom" do
    hits = [%{damage: 20}, %{damage: 20}]
    assert Powers.after_swing(["riptide"], hits) == {6, 0}
    assert Powers.after_swing(["starlit"], hits) == {0, 10}
    assert Powers.after_swing([], hits) == {0, 0}
    assert Powers.on_kills(["bloom"], 2, 100) == 24
    assert Powers.on_kills(["bloom"], 0, 100) == 0
  end

  test "taking hits: midas, thorns, phoenix" do
    assert Powers.on_hit(["midas"], 30, always()) == {:gold, 15}
    assert Powers.on_hit(["midas"], 30, never()) == {:hit, 30, 0}
    assert Powers.on_hit(["thorns"], 30, never()) == {:hit, 30, 10}
    assert Powers.rebirth(["phoenix"], 0, 90, nil, 0) == 30
    assert Powers.rebirth(["phoenix"], 0, 90, 0, 1_000) == nil
    assert Powers.rebirth(["phoenix"], 0, 90, 0, Powers.phoenix_cooldown_ms()) == 30
    assert Powers.rebirth(["phoenix"], 5, 90, nil, 0) == nil
  end
end
