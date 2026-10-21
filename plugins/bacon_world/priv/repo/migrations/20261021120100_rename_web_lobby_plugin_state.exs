defmodule BaconWorld.Repo.Migrations.RenameWebLobbyPluginState do
  use Ecto.Migration

  @moduledoc """
  Web Lobby became Bacon World (ADR 0001, phase 1): carry an admin's saved
  activation over to the new slug. Nothing to do when Web Lobby was never
  toggled on /admin/plugins (no row). If a 'bacon_world' row already exists, it
  was saved by the new code and wins; the old row is left alone (no plugin has
  that slug any more, so it is ignored).

  Other stored 'web_lobby' values were counted before writing this (2026-10-21:
  none in wallet_transactions.game_slug, entitlements.key or anywhere else in
  the site database). Ledger rows would keep the slug they were written with.
  """

  def up do
    execute(move_state("web_lobby", "bacon_world"))
  end

  def down do
    execute(move_state("bacon_world", "web_lobby"))
  end

  defp move_state(from, to) do
    """
    UPDATE plugin_states SET slug = '#{to}'
    WHERE slug = '#{from}'
      AND NOT EXISTS (SELECT 1 FROM plugin_states WHERE slug = '#{to}')
    """
  end
end
