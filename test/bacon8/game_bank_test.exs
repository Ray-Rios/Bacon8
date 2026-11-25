defmodule Bacon8.GameBankTest do
  # An account's bank in a game (Bacon8.GameBank, 2026-11-24): shared by the player's characters there, written whole
  # with the revision it read, a stale write refused with the bank as it is now.
  use Bacon8.DataCase, async: false

  alias Bacon8.GameBank

  setup do
    %{user: user_fixture()}
  end

  test "an empty bank at first; a write names the revision it read", %{user: user} do
    assert %{data: %{"slots" => %{}, "coins" => 0}, revision: 0} = GameBank.get("tears_of_babylon", user.id)
    bank = %{"slots" => %{"bank0" => %{"item" => "pistol_p9", "qty" => 1}}, "coins" => 50}
    assert {:ok, %{revision: 1, data: ^bank}} = GameBank.put("tears_of_babylon", user.id, bank, 0)
    assert %{data: ^bank, revision: 1} = GameBank.get("tears_of_babylon", user.id)

    # another character still holding revision 0 can't write over it
    assert {:error, :stale, %{revision: 1, data: ^bank}} = GameBank.put("tears_of_babylon", user.id, %{"slots" => %{}, "coins" => 0}, 0)
    assert {:ok, %{revision: 2}} = GameBank.put("tears_of_babylon", user.id, %{"slots" => %{}, "coins" => 50}, 1)

    # one bank per game
    assert %{revision: 0} = GameBank.get("rays-space-sim", user.id)
  end

  test "only bank slots with an item and a count, and whole coins", %{user: user} do
    assert {:error, _} = GameBank.put("tears_of_babylon", user.id, %{"slots" => %{"bag3" => %{"item" => "x", "qty" => 1}}, "coins" => 0}, 0)
    assert {:error, _} = GameBank.put("tears_of_babylon", user.id, %{"slots" => %{"bank100" => %{"item" => "x", "qty" => 1}}, "coins" => 0}, 0)
    assert {:error, _} = GameBank.put("tears_of_babylon", user.id, %{"slots" => %{"bank1" => %{"item" => "x", "qty" => 0}}, "coins" => 0}, 0)
    assert {:error, _} = GameBank.put("tears_of_babylon", user.id, %{"slots" => %{}, "coins" => -5}, 0)
    assert {:error, _} = GameBank.put("tears_of_babylon", user.id, "a bank", 0)
    assert %{revision: 0} = GameBank.get("tears_of_babylon", user.id)
  end
end
