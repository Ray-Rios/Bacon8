defmodule ChatChannels.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  @moduledoc """
  The chat tables, moved out of the site baseline so the plugin owns them (BACON8.md, chat phase 4).

  The baseline created them until 2026-10-26. Production already has them, so every statement
  here is idempotent (IF NOT EXISTS; constraints are looked up in pg_constraint): on production
  it changes nothing, on a fresh database it builds the tables. The statements are the baseline's own.
  """

  @sql ~S"""
  CREATE TABLE IF NOT EXISTS public.channel_invites (
      id uuid NOT NULL,
      channel_id uuid NOT NULL,
      inviter_id uuid NOT NULL,
      code character varying(255) NOT NULL,
      max_uses integer,
      uses integer DEFAULT 0,
      expires_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      invitee_id uuid,
      accepted_at timestamp(0) without time zone,
      revoked_at timestamp(0) without time zone,
      is_revoked boolean DEFAULT false,
      created_by_id uuid
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.channel_members (
      id uuid NOT NULL,
      channel_id uuid NOT NULL,
      user_id uuid NOT NULL,
      role character varying(255) DEFAULT 'member'::character varying NOT NULL,
      nickname character varying(255),
      is_muted boolean DEFAULT false,
      is_banned boolean DEFAULT false,
      joined_at timestamp(0) without time zone NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      last_read_message_id uuid,
      last_seen_at timestamp(0) without time zone
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.chat_channels (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      description text,
      topic character varying(255),
      channel_type character varying(255) DEFAULT 'text'::character varying,
      is_private boolean DEFAULT false,
      created_by_id uuid,
      "position" integer DEFAULT 0,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      owner_id uuid,
      is_public boolean DEFAULT true NOT NULL,
      is_user_created boolean DEFAULT false NOT NULL,
      max_participants integer DEFAULT 50,
      invite_code character varying(255),
      settings jsonb DEFAULT '{}'::jsonb,
      icon_path character varying(255)
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.chat_message_attachments (
      id uuid NOT NULL,
      filename character varying(255) NOT NULL,
      content_type character varying(255),
      file_size integer,
      file character varying(255) NOT NULL,
      message_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      channel_id uuid,
      user_id uuid
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.chat_messages (
      id uuid NOT NULL,
      content text NOT NULL,
      message_type character varying(255) DEFAULT 'text'::character varying,
      is_pinned boolean DEFAULT false,
      edited_at timestamp(0) without time zone,
      user_id uuid NOT NULL,
      channel_id uuid NOT NULL,
      reply_to_id uuid,
      thread_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.chat_reactions (
      id uuid NOT NULL,
      emoji character varying(255) NOT NULL,
      user_id uuid NOT NULL,
      message_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.chat_threads (
      id uuid NOT NULL,
      name character varying(255),
      is_archived boolean DEFAULT false,
      channel_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      parent_message_id uuid
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.custom_emojis (
      id uuid NOT NULL,
      shortcode character varying(255) NOT NULL,
      emoji character varying(255),
      image_url character varying(255),
      category character varying(255) DEFAULT 'Custom'::character varying,
      created_by_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE IF NOT EXISTS public.streaming_sessions (
      id uuid NOT NULL,
      channel_id uuid NOT NULL,
      streamer_id uuid NOT NULL,
      title character varying(255) NOT NULL,
      stream_type character varying(255) NOT NULL,
      is_active boolean DEFAULT true NOT NULL,
      viewer_count integer DEFAULT 0,
      started_at timestamp(0) without time zone NOT NULL,
      ended_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      user_id uuid,
      status text DEFAULT 'pending'::text
  )
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_invites_pkey' AND conrelid = 'public.channel_invites'::regclass) THEN
    ALTER TABLE ONLY public.channel_invites ADD CONSTRAINT channel_invites_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_members_pkey' AND conrelid = 'public.channel_members'::regclass) THEN
    ALTER TABLE ONLY public.channel_members ADD CONSTRAINT channel_members_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_channels_pkey' AND conrelid = 'public.chat_channels'::regclass) THEN
    ALTER TABLE ONLY public.chat_channels ADD CONSTRAINT chat_channels_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_message_attachments_pkey' AND conrelid = 'public.chat_message_attachments'::regclass) THEN
    ALTER TABLE ONLY public.chat_message_attachments ADD CONSTRAINT chat_message_attachments_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_messages_pkey' AND conrelid = 'public.chat_messages'::regclass) THEN
    ALTER TABLE ONLY public.chat_messages ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_reactions_pkey' AND conrelid = 'public.chat_reactions'::regclass) THEN
    ALTER TABLE ONLY public.chat_reactions ADD CONSTRAINT chat_reactions_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_threads_pkey' AND conrelid = 'public.chat_threads'::regclass) THEN
    ALTER TABLE ONLY public.chat_threads ADD CONSTRAINT chat_threads_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'custom_emojis_pkey' AND conrelid = 'public.custom_emojis'::regclass) THEN
    ALTER TABLE ONLY public.custom_emojis ADD CONSTRAINT custom_emojis_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'streaming_sessions_pkey' AND conrelid = 'public.streaming_sessions'::regclass) THEN
    ALTER TABLE ONLY public.streaming_sessions ADD CONSTRAINT streaming_sessions_pkey PRIMARY KEY (id);
  END IF; END $$
  --;;
  CREATE INDEX IF NOT EXISTS channel_invites_channel_id_index ON public.channel_invites USING btree (channel_id)
  --;;
  CREATE UNIQUE INDEX IF NOT EXISTS channel_invites_code_index ON public.channel_invites USING btree (code)
  --;;
  CREATE INDEX IF NOT EXISTS channel_invites_created_by_id_index ON public.channel_invites USING btree (created_by_id)
  --;;
  CREATE INDEX IF NOT EXISTS channel_invites_invitee_id_index ON public.channel_invites USING btree (invitee_id)
  --;;
  CREATE INDEX IF NOT EXISTS channel_invites_is_revoked_index ON public.channel_invites USING btree (is_revoked)
  --;;
  CREATE INDEX IF NOT EXISTS channel_members_channel_id_index ON public.channel_members USING btree (channel_id)
  --;;
  CREATE UNIQUE INDEX IF NOT EXISTS channel_members_channel_id_user_id_index ON public.channel_members USING btree (channel_id, user_id)
  --;;
  CREATE INDEX IF NOT EXISTS channel_members_channel_id_user_id_last_read_message_id_index ON public.channel_members USING btree (channel_id, user_id, last_read_message_id)
  --;;
  CREATE INDEX IF NOT EXISTS channel_members_role_index ON public.channel_members USING btree (role)
  --;;
  CREATE UNIQUE INDEX IF NOT EXISTS channel_members_user_id_channel_id_index ON public.channel_members USING btree (user_id, channel_id)
  --;;
  CREATE INDEX IF NOT EXISTS channel_members_user_id_index ON public.channel_members USING btree (user_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_channels_channel_type_index ON public.chat_channels USING btree (channel_type)
  --;;
  CREATE INDEX IF NOT EXISTS chat_channels_created_by_id_index ON public.chat_channels USING btree (created_by_id)
  --;;
  CREATE UNIQUE INDEX IF NOT EXISTS chat_channels_invite_code_index ON public.chat_channels USING btree (invite_code) WHERE (invite_code IS NOT NULL)
  --;;
  CREATE INDEX IF NOT EXISTS chat_channels_is_private_index ON public.chat_channels USING btree (is_private)
  --;;
  CREATE INDEX IF NOT EXISTS chat_channels_is_public_index ON public.chat_channels USING btree (is_public)
  --;;
  CREATE INDEX IF NOT EXISTS chat_channels_is_user_created_index ON public.chat_channels USING btree (is_user_created)
  --;;
  CREATE INDEX IF NOT EXISTS chat_channels_owner_id_index ON public.chat_channels USING btree (owner_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_channels_position_index ON public.chat_channels USING btree ("position")
  --;;
  CREATE INDEX IF NOT EXISTS chat_message_attachments_channel_id_index ON public.chat_message_attachments USING btree (channel_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_message_attachments_message_id_index ON public.chat_message_attachments USING btree (message_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_message_attachments_user_id_index ON public.chat_message_attachments USING btree (user_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_messages_channel_id_index ON public.chat_messages USING btree (channel_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_messages_inserted_at_index ON public.chat_messages USING btree (inserted_at)
  --;;
  CREATE INDEX IF NOT EXISTS chat_messages_is_pinned_index ON public.chat_messages USING btree (is_pinned)
  --;;
  CREATE INDEX IF NOT EXISTS chat_messages_message_type_index ON public.chat_messages USING btree (message_type)
  --;;
  CREATE INDEX IF NOT EXISTS chat_messages_reply_to_id_index ON public.chat_messages USING btree (reply_to_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_messages_thread_id_index ON public.chat_messages USING btree (thread_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_messages_user_id_index ON public.chat_messages USING btree (user_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_reactions_message_id_index ON public.chat_reactions USING btree (message_id)
  --;;
  CREATE UNIQUE INDEX IF NOT EXISTS chat_reactions_user_id_message_id_emoji_index ON public.chat_reactions USING btree (user_id, message_id, emoji)
  --;;
  CREATE INDEX IF NOT EXISTS chat_threads_channel_id_index ON public.chat_threads USING btree (channel_id)
  --;;
  CREATE INDEX IF NOT EXISTS chat_threads_is_archived_index ON public.chat_threads USING btree (is_archived)
  --;;
  CREATE INDEX IF NOT EXISTS chat_threads_parent_message_id_index ON public.chat_threads USING btree (parent_message_id)
  --;;
  CREATE INDEX IF NOT EXISTS custom_emojis_category_index ON public.custom_emojis USING btree (category)
  --;;
  CREATE INDEX IF NOT EXISTS custom_emojis_created_by_id_index ON public.custom_emojis USING btree (created_by_id)
  --;;
  CREATE UNIQUE INDEX IF NOT EXISTS custom_emojis_shortcode_index ON public.custom_emojis USING btree (shortcode)
  --;;
  CREATE INDEX IF NOT EXISTS index_channel_members_on_role ON public.channel_members USING btree (role)
  --;;
  CREATE INDEX IF NOT EXISTS streaming_sessions_channel_id_index ON public.streaming_sessions USING btree (channel_id)
  --;;
  CREATE INDEX IF NOT EXISTS streaming_sessions_is_active_index ON public.streaming_sessions USING btree (is_active)
  --;;
  CREATE INDEX IF NOT EXISTS streaming_sessions_status_index ON public.streaming_sessions USING btree (status)
  --;;
  CREATE INDEX IF NOT EXISTS streaming_sessions_streamer_id_index ON public.streaming_sessions USING btree (streamer_id)
  --;;
  CREATE INDEX IF NOT EXISTS streaming_sessions_user_id_index ON public.streaming_sessions USING btree (user_id)
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_invites_channel_id_fkey' AND conrelid = 'public.channel_invites'::regclass) THEN
    ALTER TABLE ONLY public.channel_invites ADD CONSTRAINT channel_invites_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_invites_created_by_id_fkey' AND conrelid = 'public.channel_invites'::regclass) THEN
    ALTER TABLE ONLY public.channel_invites ADD CONSTRAINT channel_invites_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_invites_invitee_id_fkey' AND conrelid = 'public.channel_invites'::regclass) THEN
    ALTER TABLE ONLY public.channel_invites ADD CONSTRAINT channel_invites_invitee_id_fkey FOREIGN KEY (invitee_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_invites_inviter_id_fkey' AND conrelid = 'public.channel_invites'::regclass) THEN
    ALTER TABLE ONLY public.channel_invites ADD CONSTRAINT channel_invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_members_channel_id_fkey' AND conrelid = 'public.channel_members'::regclass) THEN
    ALTER TABLE ONLY public.channel_members ADD CONSTRAINT channel_members_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'channel_members_user_id_fkey' AND conrelid = 'public.channel_members'::regclass) THEN
    ALTER TABLE ONLY public.channel_members ADD CONSTRAINT channel_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_channels_created_by_id_fkey' AND conrelid = 'public.chat_channels'::regclass) THEN
    ALTER TABLE ONLY public.chat_channels ADD CONSTRAINT chat_channels_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_channels_owner_id_fkey' AND conrelid = 'public.chat_channels'::regclass) THEN
    ALTER TABLE ONLY public.chat_channels ADD CONSTRAINT chat_channels_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_message_attachments_channel_id_fkey' AND conrelid = 'public.chat_message_attachments'::regclass) THEN
    ALTER TABLE ONLY public.chat_message_attachments ADD CONSTRAINT chat_message_attachments_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE SET NULL;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_message_attachments_message_id_fkey' AND conrelid = 'public.chat_message_attachments'::regclass) THEN
    ALTER TABLE ONLY public.chat_message_attachments ADD CONSTRAINT chat_message_attachments_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_message_attachments_user_id_fkey' AND conrelid = 'public.chat_message_attachments'::regclass) THEN
    ALTER TABLE ONLY public.chat_message_attachments ADD CONSTRAINT chat_message_attachments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_messages_channel_id_fkey' AND conrelid = 'public.chat_messages'::regclass) THEN
    ALTER TABLE ONLY public.chat_messages ADD CONSTRAINT chat_messages_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_messages_reply_to_id_fkey' AND conrelid = 'public.chat_messages'::regclass) THEN
    ALTER TABLE ONLY public.chat_messages ADD CONSTRAINT chat_messages_reply_to_id_fkey FOREIGN KEY (reply_to_id) REFERENCES public.chat_messages(id) ON DELETE SET NULL;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_messages_thread_id_fkey' AND conrelid = 'public.chat_messages'::regclass) THEN
    ALTER TABLE ONLY public.chat_messages ADD CONSTRAINT chat_messages_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.chat_threads(id) ON DELETE SET NULL;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_messages_user_id_fkey' AND conrelid = 'public.chat_messages'::regclass) THEN
    ALTER TABLE ONLY public.chat_messages ADD CONSTRAINT chat_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_reactions_message_id_fkey' AND conrelid = 'public.chat_reactions'::regclass) THEN
    ALTER TABLE ONLY public.chat_reactions ADD CONSTRAINT chat_reactions_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_reactions_user_id_fkey' AND conrelid = 'public.chat_reactions'::regclass) THEN
    ALTER TABLE ONLY public.chat_reactions ADD CONSTRAINT chat_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_threads_channel_id_fkey' AND conrelid = 'public.chat_threads'::regclass) THEN
    ALTER TABLE ONLY public.chat_threads ADD CONSTRAINT chat_threads_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chat_threads_parent_message_id_fkey' AND conrelid = 'public.chat_threads'::regclass) THEN
    ALTER TABLE ONLY public.chat_threads ADD CONSTRAINT chat_threads_parent_message_id_fkey FOREIGN KEY (parent_message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'custom_emojis_created_by_id_fkey' AND conrelid = 'public.custom_emojis'::regclass) THEN
    ALTER TABLE ONLY public.custom_emojis ADD CONSTRAINT custom_emojis_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'streaming_sessions_channel_id_fkey' AND conrelid = 'public.streaming_sessions'::regclass) THEN
    ALTER TABLE ONLY public.streaming_sessions ADD CONSTRAINT streaming_sessions_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'streaming_sessions_streamer_id_fkey' AND conrelid = 'public.streaming_sessions'::regclass) THEN
    ALTER TABLE ONLY public.streaming_sessions ADD CONSTRAINT streaming_sessions_streamer_id_fkey FOREIGN KEY (streamer_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  --;;
  DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'streaming_sessions_user_id_fkey' AND conrelid = 'public.streaming_sessions'::regclass) THEN
    ALTER TABLE ONLY public.streaming_sessions ADD CONSTRAINT streaming_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF; END $$
  """

  def up do
    # A Windows checkout has CRLF line endings, so accept either.
    for statement <- String.split(@sql, ~r/\r?\n\s*--;;\r?\n/, trim: true), do: execute(statement)
  end

  def down, do: :ok
end
