defmodule BaconWorld.LiveEventsTest do
  # XP & loot events and the experience pacing (2026-11-03): stored as BaconWorld.Defs rows and in
  # World tuning, read on every kill. Uses the database (Defs' :db source), so it runs alone.
  use Bacon8.DataCase, async: false

  alias BaconWorld.{Defs, LiveEvents, Loot, Progression, Tuning}

  setup do
    old = Application.get_env(:bacon8, Defs)
    Application.put_env(:bacon8, Defs, source: :db)
    Defs.reload("event")

    on_exit(fn ->
      Application.put_env(:bacon8, Defs, old)
      Defs.reload("event")
      Tuning.bust()
    end)
  end

  defp form(name, xp, from_s, to_s) do
    now = DateTime.utc_now()

    %{
      "name" => name,
      "xp_mult" => xp,
      "loot_mult" => "1.5",
      "coin_mult" => "1",
      "starts_at" => now |> DateTime.add(from_s) |> DateTime.to_iso8601(),
      "ends_at" => now |> DateTime.add(to_s) |> DateTime.to_iso8601()
    }
  end

  test "an event running multiplies experience and loot; one to come or one over doesn't" do
    base = Progression.kill_xp(5, 5)
    assert LiveEvents.mult(:xp) == 1.0

    {:ok, double} = LiveEvents.from_form(form("Double XP", "2", -3600, 3600))
    Defs.put(LiveEvents.kind(), "double", double)
    assert LiveEvents.mult(:xp) == 2.0
    assert LiveEvents.mult(:loot) == 1.5
    assert Loot.chance_mult() == 1.5
    assert Progression.kill_xp(5, 5) == base * 2

    {:ok, later} = LiveEvents.from_form(form("Later", "3", 86_400, 90_000))
    {:ok, over} = LiveEvents.from_form(form("Over", "3", -90_000, -86_400))
    Defs.put(LiveEvents.kind(), "later", later)
    Defs.put(LiveEvents.kind(), "over", over)
    assert LiveEvents.status(later) == :upcoming
    assert LiveEvents.status(over) == :over
    assert LiveEvents.mult(:xp) == 2.0

    Defs.delete(LiveEvents.kind(), "double")
    assert LiveEvents.mult(:xp) == 1.0
  end

  test "the form wants a name, both times, and an end after the start" do
    assert {:error, errs} = LiveEvents.from_form(%{"name" => "", "starts_at" => "2026-11-07T10:00", "ends_at" => "2026-11-07T09:00"})
    assert Enum.any?(errs, &(&1 =~ "name"))
    assert Enum.any?(errs, &(&1 =~ "end after"))
    # a datetime-local value is read as UTC
    assert {:ok, e} = LiveEvents.from_form(%{"name" => "Weekend", "xp_mult" => "2", "starts_at" => "2026-11-07T10:00", "ends_at" => "2026-11-09T10:00"})
    assert e.starts_at == "2026-11-07T10:00:00Z" and e.xp_mult == 2.0 and e.coin_mult == 1.0
  end

  test "experience to level follows World tuning's curve multiplier" do
    before = Progression.xp_to_next(10)
    {:ok, _} = Tuning.save(Map.put(Tuning.current(), "xp_curve_mult", 0.5))
    assert Progression.xp_to_next(10) == round(before * 0.5)
  end
end
