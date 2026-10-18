defmodule Bacon8.GamesRepo.Migrations.GamesBaseline do
  use Ecto.Migration

  @moduledoc """
  Baseline for the games database's core tables (`Bacon8.GamesRepo`), generated
  from production's schema on 2026-10-16 with `pg_dump --schema-only`. It replaces
  every earlier migration in this folder.

  Plugin tables are not here: each plugin creates its own from
  `plugins/<slug>/priv/games_repo/migrations`. This version sorts first so
  plugins can reference `games` and `game_characters`.

  Production already records version 20260809100000 in `schema_migrations`, so
  this never runs there; it only builds new databases (tests, fresh installs).
  Earlier versions left in production's `schema_migrations` are harmless.

  New changes go in new migrations after this one. Don't edit this file.
  """

  @sql ~S"""
  CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public
  --;;
  CREATE TABLE public.admin_actions (
      id uuid NOT NULL,
      actor_user_id uuid NOT NULL,
      actor_email character varying(255),
      action character varying(255) NOT NULL,
      subject_type character varying(255),
      subject_id uuid,
      details jsonb DEFAULT '{}'::jsonb NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.game_characters (
      id uuid NOT NULL,
      game_id uuid NOT NULL,
      user_id uuid NOT NULL,
      name character varying(255) NOT NULL,
      stats jsonb DEFAULT '{}'::jsonb NOT NULL,
      settings jsonb DEFAULT '{}'::jsonb NOT NULL,
      last_played_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      active_server_id uuid,
      active_session_id uuid,
      session_started_at timestamp(0) without time zone,
      session_last_seen_at timestamp(0) without time zone,
      instance_id uuid,
      instance_location jsonb
  )
  --;;
  CREATE TABLE public.game_releases (
      id uuid NOT NULL,
      game_id uuid NOT NULL,
      build_id character varying(255) NOT NULL,
      manifest jsonb DEFAULT '{}'::jsonb NOT NULL,
      total_bytes bigint DEFAULT 0 NOT NULL,
      notes text,
      is_live boolean DEFAULT false NOT NULL,
      published_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.game_servers (
      id uuid NOT NULL,
      game_id uuid NOT NULL,
      host character varying(255) NOT NULL,
      port integer NOT NULL,
      name character varying(255) NOT NULL,
      region character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
      status character varying(255) DEFAULT 'online'::character varying NOT NULL,
      current_players integer DEFAULT 0 NOT NULL,
      max_players integer DEFAULT 64 NOT NULL,
      map_name character varying(255),
      version character varying(255),
      last_heartbeat_at timestamp(0) without time zone NOT NULL,
      metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      instance_id uuid,
      launched_by_user_id uuid,
      roster jsonb DEFAULT '{}'::jsonb NOT NULL
  )
  --;;
  CREATE TABLE public.games (
      id uuid NOT NULL,
      slug character varying(255) NOT NULL,
      name character varying(255) NOT NULL,
      is_active boolean DEFAULT true NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.server_commands (
      id uuid NOT NULL,
      server_id uuid NOT NULL,
      command character varying(255) NOT NULL,
      payload jsonb DEFAULT '{}'::jsonb NOT NULL,
      issued_by_user_id uuid,
      issued_at timestamp(0) without time zone NOT NULL,
      delivered_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  ALTER TABLE ONLY public.admin_actions
      ADD CONSTRAINT admin_actions_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.game_characters
      ADD CONSTRAINT game_characters_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.game_releases
      ADD CONSTRAINT game_releases_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.game_servers
      ADD CONSTRAINT game_servers_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.games
      ADD CONSTRAINT games_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.server_commands
      ADD CONSTRAINT server_commands_pkey PRIMARY KEY (id)
  --;;
  CREATE INDEX admin_actions_actor_user_id_index ON public.admin_actions USING btree (actor_user_id)
  --;;
  CREATE INDEX admin_actions_inserted_at_index ON public.admin_actions USING btree (inserted_at)
  --;;
  CREATE INDEX admin_actions_subject_type_subject_id_index ON public.admin_actions USING btree (subject_type, subject_id)
  --;;
  CREATE INDEX game_characters_active_server_id_index ON public.game_characters USING btree (active_server_id) WHERE (active_server_id IS NOT NULL)
  --;;
  CREATE UNIQUE INDEX game_characters_game_id_name_index ON public.game_characters USING btree (game_id, name)
  --;;
  CREATE INDEX game_characters_game_id_user_id_index ON public.game_characters USING btree (game_id, user_id)
  --;;
  CREATE INDEX game_characters_instance_id_index ON public.game_characters USING btree (instance_id)
  --;;
  CREATE UNIQUE INDEX game_releases_game_id_build_id_index ON public.game_releases USING btree (game_id, build_id)
  --;;
  CREATE INDEX game_releases_game_id_is_live_index ON public.game_releases USING btree (game_id, is_live)
  --;;
  CREATE UNIQUE INDEX game_servers_game_id_host_port_index ON public.game_servers USING btree (game_id, host, port)
  --;;
  CREATE INDEX game_servers_game_id_launched_by_user_id_index ON public.game_servers USING btree (game_id, launched_by_user_id)
  --;;
  CREATE INDEX game_servers_game_id_status_last_heartbeat_at_index ON public.game_servers USING btree (game_id, status, last_heartbeat_at)
  --;;
  CREATE INDEX game_servers_instance_id_index ON public.game_servers USING btree (instance_id)
  --;;
  CREATE INDEX game_servers_roster_idx ON public.game_servers USING gin (roster jsonb_path_ops)
  --;;
  CREATE UNIQUE INDEX games_slug_index ON public.games USING btree (slug)
  --;;
  CREATE INDEX server_commands_server_id_delivered_at_index ON public.server_commands USING btree (server_id, delivered_at)
  --;;
  ALTER TABLE ONLY public.game_characters
      ADD CONSTRAINT game_characters_active_server_id_fkey FOREIGN KEY (active_server_id) REFERENCES public.game_servers(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.game_characters
      ADD CONSTRAINT game_characters_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.game_releases
      ADD CONSTRAINT game_releases_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.game_servers
      ADD CONSTRAINT game_servers_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.server_commands
      ADD CONSTRAINT server_commands_server_id_fkey FOREIGN KEY (server_id) REFERENCES public.game_servers(id) ON DELETE CASCADE
  """

  def up do
    # A Windows checkout has CRLF line endings, so accept either.
    for statement <- String.split(@sql, ~r/\r?\n--;;\r?\n/, trim: true), do: execute(statement)
  end

  def down, do: raise("The baseline can't be rolled back; drop the database instead.")
end
