defmodule Bacon8.GameBank do
  @moduledoc """
  An account's bank in a game (2026-11-24, the owner: a Banker in Tears of Babylon and RaysSpaceSim "for their
  adventures"): what the player keeps there, shared by all their characters in that game, as Bacon World's bank is
  (`BaconWorld.Bank`, 100 slots, account-wide). For the games that keep their characters' bags themselves, so the
  hub keeps the bank as they send it: `%{"slots" => %{"bank0" => %{"item", "qty"}, ...}, "coins" => n}`.

  Every write names the revision it read (`put/4`); a stale one is refused with what is there now, so two characters
  (or two windows) can't write over each other. Moving an item between bags and bank is the game's: it writes the
  bank, then the character.
  """

  use Ecto.Schema
  import Ecto.Query
  alias Bacon8.GamesRepo

  @slots 100
  @max_bytes 131_072

  @primary_key false
  schema "game_banks" do
    field :user_id, Ecto.UUID, primary_key: true
    field :game_slug, :string, primary_key: true
    field :data, :map, default: %{}
    field :revision, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  @doc "How many slots a bank has (\"bank0\"..\"bank99\")."
  def slots, do: @slots

  @doc "The bank: `%{data, revision}` (an empty one at revision 0 when there is none)."
  def get(slug, user_id) do
    case GamesRepo.one(from b in __MODULE__, where: b.user_id == ^user_id and b.game_slug == ^slug) do
      nil -> %{data: %{"slots" => %{}, "coins" => 0}, revision: 0}
      b -> %{data: b.data, revision: b.revision}
    end
  end

  @doc """
  Writes the bank, if `revision` is still the one there. `{:ok, %{data, revision}}`, `{:error, :stale, current}`, or
  `{:error, message}` for a bank that isn't one.
  """
  def put(slug, user_id, data, revision) when is_integer(revision) do
    with {:ok, data} <- clean(data) do
      GamesRepo.transaction(fn ->
        row = GamesRepo.one(from b in __MODULE__, where: b.user_id == ^user_id and b.game_slug == ^slug, lock: "FOR UPDATE")
        have = if row, do: row.revision, else: 0

        cond do
          have != revision ->
            GamesRepo.rollback({:stale, %{data: (row && row.data) || %{"slots" => %{}, "coins" => 0}, revision: have}})

          row ->
            {:ok, b} = row |> Ecto.Changeset.change(data: data, revision: have + 1) |> GamesRepo.update()
            %{data: b.data, revision: b.revision}

          true ->
            {:ok, b} = GamesRepo.insert(%__MODULE__{user_id: user_id, game_slug: slug, data: data, revision: 1})
            %{data: b.data, revision: b.revision}
        end
      end)
      |> case do
        {:ok, bank} -> {:ok, bank}
        {:error, {:stale, current}} -> {:error, :stale, current}
      end
    end
  end

  def put(_slug, _user_id, _data, _revision), do: {:error, "A write names the revision it read."}

  # only bank slots with an item and a count, and the coins
  defp clean(%{} = data) do
    slots = Map.get(data, "slots", %{})
    coins = Map.get(data, "coins", 0)

    cond do
      not is_map(slots) -> {:error, "slots must be an object"}
      not (is_integer(coins) and coins >= 0) -> {:error, "coins must be a whole number, 0 or more"}
      Enum.any?(slots, fn {k, v} -> not valid_slot?(k, v) end) -> {:error, "a slot is bank0..bank#{@slots - 1} with an item and a qty"}
      byte_size(Jason.encode!(data)) > @max_bytes -> {:error, "The bank is too big."}
      true -> {:ok, %{"slots" => Map.new(slots, fn {k, v} -> {k, %{"item" => v["item"], "qty" => v["qty"]}} end), "coins" => coins}}
    end
  end

  defp clean(_), do: {:error, "The bank is an object."}

  defp valid_slot?("bank" <> n, %{"item" => item, "qty" => qty}) when is_binary(item) and is_integer(qty) and qty > 0 do
    case Integer.parse(n) do
      {i, ""} -> i >= 0 and i < @slots and byte_size(item) in 1..120
      _ -> false
    end
  end

  defp valid_slot?(_, _), do: false
end
