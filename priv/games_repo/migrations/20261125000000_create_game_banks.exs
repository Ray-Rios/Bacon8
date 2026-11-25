defmodule Bacon8.GamesRepo.Migrations.CreateGameBanks do
  use Ecto.Migration

  @moduledoc """
  An account's bank in a game (2026-11-24, `Bacon8.GameBank`): one row per player per game, shared by all of that
  player's characters there, as Bacon World's bank is (its own `bacon_world_bank_items`). For the games that keep their
  characters' bags themselves (Tears of Babylon, RaysSpaceSim): the bank's slots and coins as JSON, and a revision that
  every write must name (two characters, or two windows, can't write over each other).
  """

  def change do
    create table(:game_banks, primary_key: false) do
      add :user_id, :uuid, null: false, primary_key: true
      add :game_slug, :string, null: false, primary_key: true
      add :data, :map, null: false, default: %{}
      add :revision, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end
  end
end
