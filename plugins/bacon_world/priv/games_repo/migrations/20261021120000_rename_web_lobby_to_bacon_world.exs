defmodule BaconWorld.GamesRepo.Migrations.RenameWebLobbyToBaconWorld do
  use Ecto.Migration

  @moduledoc """
  Web Lobby became Bacon World (ADR 0001, phase 1; BACON8.md §5: a stored-name
  change). 20261016000000_create_web_lobby_tables stays as it was (invariant 14);
  this renames what it created, so a fresh install and production end up with
  the same schema.

  Renamed: the three tables, their primary keys, their unique indexes and the
  two foreign keys (Ecto matches constraint errors by these default names), and
  the `games` row (characters follow by `game_id`).

  If new code booted before this ran, `Bacon8.Plugins.ensure_game/1` may have
  created a 'bacon_world' row already. Then every row pointing at the old game
  (found through the foreign keys on `games.id`, so a plugin's own tables are
  covered too) moves onto it first, and only then is the old row deleted: those
  foreign keys are ON DELETE CASCADE.
  """

  @tables [
    {"web_lobby_zones", "bacon_world_zones"},
    {"web_lobby_spells", "bacon_world_spells"},
    {"web_lobby_character_spells", "bacon_world_character_spells"}
  ]

  # Primary keys and unique indexes. Renaming an index that backs a constraint
  # renames the constraint as well.
  @indexes [
    {"web_lobby_zones_pkey", "bacon_world_zones_pkey"},
    {"web_lobby_spells_pkey", "bacon_world_spells_pkey"},
    {"web_lobby_character_spells_pkey", "bacon_world_character_spells_pkey"},
    {"web_lobby_zones_slug_index", "bacon_world_zones_slug_index"},
    {"web_lobby_spells_slug_index", "bacon_world_spells_slug_index"},
    {"web_lobby_character_spells_character_id_spell_id_index", "bacon_world_character_spells_character_id_spell_id_index"}
  ]

  @foreign_keys [
    {"web_lobby_character_spells_character_id_fkey", "bacon_world_character_spells_character_id_fkey"},
    {"web_lobby_character_spells_spell_id_fkey", "bacon_world_character_spells_spell_id_fkey"}
  ]

  def up do
    for {old, new} <- @tables, do: execute("ALTER TABLE IF EXISTS #{old} RENAME TO #{new}")
    for {old, new} <- @indexes, do: execute("ALTER INDEX IF EXISTS #{old} RENAME TO #{new}")
    for {old, new} <- @foreign_keys, do: execute(rename_constraint(old, new))
    execute(move_game("web_lobby", "bacon_world", "Bacon World"))
  end

  def down do
    execute(move_game("bacon_world", "web_lobby", "Web Lobby"))

    for {old, new} <- Enum.reverse(@foreign_keys), do: execute(rename_constraint(new, old))

    for {old, new} <- Enum.reverse(@indexes), do: execute("ALTER INDEX IF EXISTS #{new} RENAME TO #{old}")
    for {old, new} <- Enum.reverse(@tables), do: execute("ALTER TABLE IF EXISTS #{new} RENAME TO #{old}")
  end

  # Renames a constraint if it exists, on whichever table it is on now (the
  # table renames run first going up and last going down).
  defp rename_constraint(from, to) do
    """
    DO $$
    DECLARE rel regclass;
    BEGIN
      SELECT conrelid INTO rel FROM pg_constraint WHERE conname = '#{from}';
      IF rel IS NOT NULL THEN
        EXECUTE format('ALTER TABLE %s RENAME CONSTRAINT %I TO %I', rel, '#{from}', '#{to}');
      END IF;
    END $$
    """
  end

  defp move_game(from, to, name) do
    """
    DO $$
    DECLARE
      old_id uuid;
      new_id uuid;
      ref record;
    BEGIN
      SELECT id INTO old_id FROM games WHERE slug = '#{from}';
      IF old_id IS NULL THEN
        RETURN;
      END IF;

      SELECT id INTO new_id FROM games WHERE slug = '#{to}';
      IF new_id IS NULL THEN
        UPDATE games SET slug = '#{to}', name = '#{name}', updated_at = now() WHERE id = old_id;
        RETURN;
      END IF;

      -- Both rows exist: move everything onto the '#{to}' row, then drop the old one.
      FOR ref IN
        SELECT c.conrelid::regclass AS tbl, a.attname AS col
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.contype = 'f' AND c.confrelid = 'games'::regclass AND array_length(c.conkey, 1) = 1
      LOOP
        EXECUTE format('UPDATE %s SET %I = $1 WHERE %I = $2', ref.tbl, ref.col, ref.col) USING new_id, old_id;
      END LOOP;

      UPDATE games SET name = '#{name}', updated_at = now() WHERE id = new_id;
      DELETE FROM games WHERE id = old_id;
    END $$
    """
  end
end
