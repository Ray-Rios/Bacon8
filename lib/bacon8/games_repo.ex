defmodule Bacon8.GamesRepo do
  @moduledoc """
  Isolated Ecto repo for multiplayer game data (characters, stats, settings).

  Kept separate from `Bacon8.Repo` (accounts/web content) so that game data
  for every game can evolve, scale, and be backed up
  independently of the main site database. Player identity still lives in
  `Bacon8.Repo` (`users` table); records here reference `user_id` by value
  only (no cross-database foreign key).
  """

  use Ecto.Repo,
    otp_app: :bacon8,
    adapter: Ecto.Adapters.Postgres
end
