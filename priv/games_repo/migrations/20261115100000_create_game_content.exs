defmodule Bacon8.GamesRepo.Migrations.CreateGameContent do
  use Ecto.Migration

  @moduledoc """
  Every game's definitions on one hub service (2026-11-15, `Bacon8.GameContent`), as build mode
  went the day before (`20261115000000_create_game_building`):

    * `game_defs` - a game's definitions, a row each: `kind` ("monster", "loot_table", "camp",
      "camp_template", "merchant", "event", "zone", "item"...), `id`, and its `data` as JSON.
      It is Bacon World's `bacon_world_defs` renamed, with `game_slug` (its rows `"bacon_world"`,
      the default) now part of the key, so two games may each have a "goblin".
    * `game_content_history` - every change made through the hub (what it was before and after,
      and who), so any of them can be undone.

  Bacon World's old name stays as a view of its own rows, so a pod of the old code that is still
  serving while this runs can read as before. A database without Bacon World's table gets
  `game_defs` new.
  """

  def up do
    execute("""
    DO $$
    BEGIN
      IF to_regclass('public.bacon_world_defs') IS NOT NULL
         AND (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.bacon_world_defs')) = 'r' THEN
        ALTER TABLE bacon_world_defs RENAME TO game_defs;
        ALTER TABLE game_defs ADD COLUMN game_slug varchar(255) NOT NULL DEFAULT 'bacon_world';
        EXECUTE (
          SELECT format('ALTER TABLE game_defs DROP CONSTRAINT %I', conname)
          FROM pg_constraint WHERE conrelid = 'game_defs'::regclass AND contype = 'p'
        );
        ALTER TABLE game_defs ADD CONSTRAINT game_defs_pkey PRIMARY KEY (game_slug, kind, id);
        CREATE VIEW bacon_world_defs AS
          SELECT kind, id, data, position, inserted_at, updated_at
          FROM game_defs WHERE game_slug = 'bacon_world'
          WITH LOCAL CHECK OPTION;
      ELSE
        CREATE TABLE game_defs (
          game_slug varchar(255) NOT NULL DEFAULT 'bacon_world',
          kind varchar(255) NOT NULL,
          id varchar(255) NOT NULL,
          data jsonb NOT NULL DEFAULT '{}'::jsonb,
          position integer NOT NULL DEFAULT 0,
          inserted_at timestamp(0) NOT NULL,
          updated_at timestamp(0) NOT NULL,
          CONSTRAINT game_defs_pkey PRIMARY KEY (game_slug, kind, id)
        );
      END IF;
    END
    $$;
    """)

    # a counting id (this repo's default is a UUID): the history reads newest first by it
    create table(:game_content_history, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :game_slug, :string, null: false
      add :kind, :string, null: false
      add :ref_id, :string, null: false
      add :action, :string, null: false
      add :before, :map
      add :after, :map
      add :user_id, :string
      add :user_name, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:game_content_history, [:game_slug, :id])
    create index(:game_content_history, [:game_slug, :kind, :ref_id, :id])
  end

  def down do
    drop table(:game_content_history)

    execute("""
    DO $$
    BEGIN
      IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.bacon_world_defs')) = 'v' THEN
        DROP VIEW bacon_world_defs;
        DELETE FROM game_defs WHERE game_slug <> 'bacon_world';
        ALTER TABLE game_defs DROP CONSTRAINT game_defs_pkey;
        ALTER TABLE game_defs DROP COLUMN game_slug;
        ALTER TABLE game_defs ADD CONSTRAINT bacon_world_defs_pkey PRIMARY KEY (kind, id);
        ALTER TABLE game_defs RENAME TO bacon_world_defs;
      ELSE
        DROP TABLE game_defs;
      END IF;
    END
    $$;
    """)
  end
end
