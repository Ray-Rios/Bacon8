defmodule Bacon8.GamesRepo.Migrations.CreateGameBuilding do
  use Ecto.Migration

  @moduledoc """
  Build mode for every game on one hub service (2026-11-14, `Bacon8.Building`):

    * `game_placements` - what is placed in each game's zones: Bacon World's
      `bacon_world_placements` renamed, with `game_slug` (its rows `"bacon_world"`, the default)
      and `frame` (the frame in the zone a piece is placed in; RaysSpaceSim: a planet's).
    * `game_asset_rules` - who may place an asset and its hit points, one set for every game:
      Bacon World's `bacon_world_asset_rules` renamed.

  Bacon World's old names stay, as views of these (its rows only), so its code reads and writes as
  before. A database without Bacon World's tables gets the two tables new.
  """

  def up do
    execute("""
    DO $$
    BEGIN
      IF to_regclass('public.bacon_world_placements') IS NOT NULL
         AND (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.bacon_world_placements')) = 'r' THEN
        ALTER TABLE bacon_world_placements RENAME TO game_placements;
        ALTER TABLE game_placements ADD COLUMN game_slug varchar(255) NOT NULL DEFAULT 'bacon_world';
        ALTER TABLE game_placements ADD COLUMN frame varchar(255);
        CREATE VIEW bacon_world_placements AS
          SELECT id, zone, asset, x, y, z, rot, scale, data, placed_by, character_id, inserted_at, updated_at
          FROM game_placements WHERE game_slug = 'bacon_world'
          WITH LOCAL CHECK OPTION;
      ELSE
        CREATE TABLE game_placements (
          id uuid PRIMARY KEY,
          game_slug varchar(255) NOT NULL DEFAULT 'bacon_world',
          zone varchar(255) NOT NULL,
          frame varchar(255),
          asset varchar(255) NOT NULL,
          x double precision NOT NULL,
          y double precision NOT NULL DEFAULT 0.0,
          z double precision NOT NULL,
          rot double precision NOT NULL DEFAULT 0.0,
          scale double precision NOT NULL DEFAULT 1.0,
          data jsonb NOT NULL DEFAULT '{}'::jsonb,
          placed_by uuid,
          character_id uuid,
          inserted_at timestamp(0) NOT NULL,
          updated_at timestamp(0) NOT NULL
        );
      END IF;

      IF to_regclass('public.bacon_world_asset_rules') IS NOT NULL
         AND (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.bacon_world_asset_rules')) = 'r' THEN
        ALTER TABLE bacon_world_asset_rules RENAME TO game_asset_rules;
        CREATE VIEW bacon_world_asset_rules AS SELECT * FROM game_asset_rules;
      ELSE
        CREATE TABLE game_asset_rules (
          asset varchar(255) PRIMARY KEY,
          min_role varchar(255) NOT NULL,
          hp integer DEFAULT 10,
          updated_by uuid,
          inserted_at timestamp(0) NOT NULL,
          updated_at timestamp(0) NOT NULL
        );
      END IF;
    END
    $$;
    """)

    create index(:game_placements, [:game_slug, :zone])
  end

  def down do
    drop index(:game_placements, [:game_slug, :zone])

    execute("""
    DO $$
    BEGIN
      IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.bacon_world_placements')) = 'v' THEN
        DROP VIEW bacon_world_placements;
        DELETE FROM game_placements WHERE game_slug <> 'bacon_world';
        ALTER TABLE game_placements DROP COLUMN frame;
        ALTER TABLE game_placements DROP COLUMN game_slug;
        ALTER TABLE game_placements RENAME TO bacon_world_placements;
      ELSE
        DROP TABLE game_placements;
      END IF;

      IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.bacon_world_asset_rules')) = 'v' THEN
        DROP VIEW bacon_world_asset_rules;
        ALTER TABLE game_asset_rules RENAME TO bacon_world_asset_rules;
      ELSE
        DROP TABLE game_asset_rules;
      END IF;
    END
    $$;
    """)
  end
end
