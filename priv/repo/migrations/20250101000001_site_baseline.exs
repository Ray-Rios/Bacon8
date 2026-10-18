defmodule Bacon8.Repo.Migrations.SiteBaseline do
  use Ecto.Migration

  @moduledoc """
  Baseline for the site database (`Bacon8.Repo`), generated from production's
  schema on 2026-10-16 with `pg_dump --schema-only`. It replaces every earlier
  migration in this folder.

  Production already records version 20250101000001 in `schema_migrations`, so
  this never runs there; it only builds new databases (tests, fresh installs).
  Earlier versions left in production's `schema_migrations` are harmless.

  New changes go in new migrations after this one. Don't edit this file.
  """

  @sql ~S"""
  CREATE TABLE public.allowed_identifiers (
      id uuid NOT NULL,
      identifier character varying(255) NOT NULL,
      identifier_type character varying(255) NOT NULL,
      reason text,
      added_at timestamp(0) without time zone NOT NULL,
      added_by_user_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.announcements (
      id uuid NOT NULL,
      title character varying(255) NOT NULL,
      content text NOT NULL,
      announcement_type character varying(255) DEFAULT 'info'::character varying,
      is_active boolean DEFAULT true,
      is_dismissible boolean DEFAULT true,
      starts_at timestamp(0) without time zone,
      ends_at timestamp(0) without time zone,
      target_audience character varying(255) DEFAULT 'all'::character varying,
      display_location character varying(255)[] DEFAULT ARRAY['all'::character varying],
      created_by_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.audit_logs (
      id uuid NOT NULL,
      actor_id uuid,
      action character varying(255) NOT NULL,
      target_type character varying(255),
      target_id uuid,
      metadata jsonb,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.behavioral_data (
      id uuid NOT NULL,
      session_id character varying(255),
      device_fingerprint_id uuid,
      mouse_movements integer DEFAULT 0,
      keystrokes integer DEFAULT 0,
      form_focus_time integer,
      time_to_submit integer,
      seems_human boolean DEFAULT false,
      "timestamp" timestamp(0) without time zone NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.blocked_identifiers (
      id uuid NOT NULL,
      identifier character varying(255) NOT NULL,
      identifier_type character varying(255) NOT NULL,
      reason text,
      blocked_at timestamp(0) without time zone NOT NULL,
      blocked_by_user_id uuid,
      expires_at timestamp(0) without time zone,
      auto_blocked boolean DEFAULT false,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.calendar_notes (
      id bigint NOT NULL,
      date date NOT NULL,
      content text,
      user_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      is_all_day boolean DEFAULT true,
      starts_at timestamp(0) without time zone,
      ends_at timestamp(0) without time zone,
      color text DEFAULT '#3b82f6'::text,
      reminder boolean DEFAULT false,
      reminder_at timestamp(0) without time zone
  )
  --;;
  CREATE SEQUENCE public.calendar_notes_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1
  --;;
  ALTER SEQUENCE public.calendar_notes_id_seq OWNED BY public.calendar_notes.id
  --;;
  CREATE TABLE public.cart_items (
      id uuid NOT NULL,
      quantity integer DEFAULT 1 NOT NULL,
      cart_id uuid NOT NULL,
      product_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.carts (
      id uuid NOT NULL,
      user_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      status text DEFAULT 'active'::text,
      session_id text,
      guest_email text,
      guest_name text
  )
  --;;
  CREATE TABLE public.categories (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      description text,
      slug character varying(255) NOT NULL,
      is_active boolean DEFAULT true,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      parent_id uuid,
      "position" integer DEFAULT 0
  )
  --;;
  CREATE TABLE public.channel_invites (
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
  CREATE TABLE public.channel_members (
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
  CREATE TABLE public.chat_channels (
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
  CREATE TABLE public.chat_message_attachments (
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
  CREATE TABLE public.chat_messages (
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
  CREATE TABLE public.chat_reactions (
      id uuid NOT NULL,
      emoji character varying(255) NOT NULL,
      user_id uuid NOT NULL,
      message_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.chat_threads (
      id uuid NOT NULL,
      name character varying(255),
      is_archived boolean DEFAULT false,
      channel_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      parent_message_id uuid
  )
  --;;
  CREATE TABLE public.cms_options (
      id bigint NOT NULL,
      option_name character varying(255) NOT NULL,
      option_value text DEFAULT ''::text NOT NULL,
      autoload character varying(255) DEFAULT 'yes'::character varying NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE SEQUENCE public.cms_options_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1
  --;;
  ALTER SEQUENCE public.cms_options_id_seq OWNED BY public.cms_options.id
  --;;
  CREATE TABLE public.comments (
      id uuid NOT NULL,
      content text NOT NULL,
      is_approved boolean DEFAULT false,
      author_name character varying(255),
      author_email character varying(255),
      user_id uuid,
      post_id uuid NOT NULL,
      parent_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.custom_emojis (
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
  CREATE TABLE public.device_fingerprints (
      id uuid NOT NULL,
      fingerprint_hash character varying(255) NOT NULL,
      user_agent text,
      platform character varying(255),
      first_seen_at timestamp(0) without time zone NOT NULL,
      last_seen_at timestamp(0) without time zone NOT NULL,
      user_id uuid,
      trusted boolean DEFAULT false,
      metadata jsonb,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.dismissed_announcements (
      id uuid NOT NULL,
      user_id uuid NOT NULL,
      announcement_id uuid NOT NULL,
      dismissed_at timestamp(0) without time zone NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.download_tokens (
      id uuid NOT NULL,
      token character varying(255) NOT NULL,
      user_id uuid NOT NULL,
      product_id uuid NOT NULL,
      order_id uuid,
      downloads_remaining integer,
      expires_at timestamp(0) without time zone,
      last_downloaded_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      download_count integer DEFAULT 0,
      max_downloads integer,
      first_downloaded_at timestamp(0) without time zone,
      ip_address text
  )
  --;;
  CREATE TABLE public.drive_blobs (
      sha256 character varying(64) NOT NULL,
      size bigint NOT NULL,
      content_type character varying(255),
      last_referenced_at timestamp without time zone NOT NULL,
      inserted_at timestamp without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.drive_files (
      id uuid NOT NULL,
      owner_id uuid NOT NULL,
      folder_id uuid,
      name character varying(255) NOT NULL,
      blob_sha256 character varying(255) NOT NULL,
      size bigint NOT NULL,
      content_type character varying(255) NOT NULL,
      visibility character varying(255) DEFAULT 'private'::character varying NOT NULL,
      share_token character varying(255),
      legacy_ref character varying(255),
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL,
      CONSTRAINT drive_files_share_token_check CHECK ((((visibility)::text = 'link'::text) = (share_token IS NOT NULL))),
      CONSTRAINT drive_files_visibility_check CHECK (((visibility)::text = ANY ((ARRAY['private'::character varying, 'link'::character varying, 'public'::character varying])::text[])))
  )
  --;;
  CREATE TABLE public.drive_folders (
      id uuid NOT NULL,
      owner_id uuid NOT NULL,
      parent_id uuid,
      name character varying(255) NOT NULL,
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.drive_usage (
      user_id uuid NOT NULL,
      bytes_used bigint DEFAULT 0 NOT NULL,
      file_count integer DEFAULT 0 NOT NULL,
      locked_at timestamp without time zone,
      purge_after timestamp without time zone,
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.email_logs (
      id uuid NOT NULL,
      "to" character varying(255),
      "from" character varying(255),
      subject character varying(255),
      html_body text,
      text_body text,
      provider character varying(255),
      status character varying(255),
      error text,
      sent_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.entitlements (
      id uuid NOT NULL,
      user_id uuid NOT NULL,
      kind character varying(255) NOT NULL,
      key character varying(255) NOT NULL,
      quantity integer,
      source_type character varying(255) NOT NULL,
      source_id character varying(255),
      starts_at timestamp without time zone NOT NULL,
      ends_at timestamp without time zone,
      revoked_at timestamp without time zone,
      revoked_reason character varying(255),
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.login_attempts (
      id uuid NOT NULL,
      identifier character varying(255) NOT NULL,
      identifier_type character varying(255) NOT NULL,
      attempt_count integer DEFAULT 0,
      last_attempt_at timestamp(0) without time zone,
      ip_address character varying(255),
      user_agent text,
      successful boolean DEFAULT false,
      user_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.notification_preferences (
      id uuid NOT NULL,
      email_notifications boolean DEFAULT true,
      push_notifications boolean DEFAULT true,
      desktop_notifications boolean DEFAULT true,
      chat_mentions boolean DEFAULT true,
      chat_direct_messages boolean DEFAULT true,
      order_updates boolean DEFAULT true,
      marketing_emails boolean DEFAULT false,
      digest_frequency character varying(255) DEFAULT 'daily'::character varying,
      quiet_hours_start time(0) without time zone,
      quiet_hours_end time(0) without time zone,
      timezone character varying(255) DEFAULT 'UTC'::character varying,
      user_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.order_items (
      id uuid NOT NULL,
      quantity integer NOT NULL,
      price numeric(10,2) NOT NULL,
      order_id uuid NOT NULL,
      product_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      total numeric(10,2) DEFAULT 0 NOT NULL,
      product_name text DEFAULT ''::text NOT NULL,
      product_sku text,
      is_digital boolean DEFAULT false,
      download_granted boolean DEFAULT false
  )
  --;;
  CREATE TABLE public.orders (
      id uuid NOT NULL,
      status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
      total_amount numeric(10,2) NOT NULL,
      stripe_payment_intent_id character varying(255),
      user_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      billing_address jsonb,
      shipping_address jsonb,
      notes text,
      order_number text DEFAULT ''::text NOT NULL,
      payment_status text DEFAULT 'pending'::text,
      fulfillment_status text DEFAULT 'unfulfilled'::text,
      total numeric(10,2) DEFAULT 0 NOT NULL,
      subtotal numeric(10,2),
      tax numeric(10,2) DEFAULT 0,
      discount numeric(10,2) DEFAULT 0,
      currency text DEFAULT 'USD'::text,
      payment_method text,
      payment_intent_id text,
      stripe_session_id text,
      guest_email text,
      guest_name text,
      metadata jsonb DEFAULT '{}'::jsonb
  )
  --;;
  CREATE TABLE public.pages (
      id uuid NOT NULL,
      title character varying(255) NOT NULL,
      slug character varying(255) NOT NULL,
      content text NOT NULL,
      is_published boolean DEFAULT false,
      meta_description character varying(255),
      template_type character varying(255) DEFAULT 'default'::character varying,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      excerpt text,
      meta_keywords character varying(255),
      featured_image character varying(255),
      category character varying(255),
      "order" integer DEFAULT 0 NOT NULL,
      published_at timestamp(0) without time zone,
      author_id uuid,
      show_share_buttons boolean DEFAULT true,
      share_platforms character varying(255)[] DEFAULT ARRAY['twitter'::character varying, 'facebook'::character varying, 'linkedin'::character varying, 'reddit'::character varying, 'email'::character varying],
      share_buttons_colored boolean DEFAULT false
  )
  --;;
  CREATE TABLE public.plugin_states (
      slug character varying(255) NOT NULL,
      active boolean NOT NULL,
      changed_by_id uuid,
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.posts (
      id uuid NOT NULL,
      title character varying(255) NOT NULL,
      slug character varying(255) NOT NULL,
      content text NOT NULL,
      excerpt text,
      is_published boolean DEFAULT false,
      published_at timestamp(0) without time zone,
      featured_image character varying(255),
      meta_description character varying(255),
      tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
      user_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      show_share_buttons boolean DEFAULT true,
      share_platforms character varying(255)[] DEFAULT ARRAY['twitter'::character varying, 'facebook'::character varying, 'linkedin'::character varying, 'reddit'::character varying, 'email'::character varying],
      share_buttons_colored boolean DEFAULT false
  )
  --;;
  CREATE TABLE public.products (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      description text,
      price numeric(10,2) NOT NULL,
      sku character varying(255),
      stock_quantity integer DEFAULT 0,
      is_active boolean DEFAULT true,
      image_url character varying(255),
      category_id uuid,
      weight numeric(8,2),
      dimensions character varying(255),
      image character varying(255),
      stripe_price_id character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      stripe_product_id character varying(255),
      product_type character varying(255) DEFAULT 'physical'::character varying,
      download_url character varying(255),
      download_limit integer,
      billing_interval character varying(255) DEFAULT 'one_time'::character varying,
      trial_days integer DEFAULT 0,
      grants_storage_bytes bigint,
      grants_role character varying(255),
      grants_features character varying(255)[] DEFAULT ARRAY[]::character varying[],
      featured boolean DEFAULT false,
      sort_order integer DEFAULT 0,
      badge_text character varying(255),
      slug text DEFAULT ''::text NOT NULL,
      original_price numeric(10,2),
      currency text DEFAULT 'USD'::text,
      stock integer DEFAULT 0,
      download_expires_after_days integer,
      file_size_bytes bigint,
      file_name text,
      grants_premium_features boolean DEFAULT false,
      feature_flags jsonb DEFAULT '{}'::jsonb,
      "position" integer DEFAULT 0,
      is_featured boolean DEFAULT false,
      is_digital boolean DEFAULT false,
      main_image text,
      images text[] DEFAULT '{}'::text[]
  )
  --;;
  CREATE TABLE public.project_events (
      id uuid NOT NULL,
      event_type character varying(255) NOT NULL,
      title character varying(255) NOT NULL,
      description text,
      occurred_at timestamp(0) without time zone NOT NULL,
      metadata jsonb DEFAULT '{}'::jsonb,
      project_id uuid,
      task_id uuid,
      triggered_by_user_id uuid,
      triggered_events uuid[] DEFAULT ARRAY[]::uuid[],
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.projects (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      description text,
      owner_id uuid,
      status character varying(255) DEFAULT 'active'::character varying,
      start_date timestamp(0) without time zone,
      end_date timestamp(0) without time zone,
      metadata jsonb,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.scheduled_event_runs (
      id uuid NOT NULL,
      scheduled_event_id uuid NOT NULL,
      started_at timestamp(0) without time zone NOT NULL,
      completed_at timestamp(0) without time zone,
      status character varying(255) DEFAULT 'running'::character varying,
      result jsonb DEFAULT '{}'::jsonb,
      error text,
      duration_ms integer,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.scheduled_events (
      id uuid NOT NULL,
      title character varying(255) NOT NULL,
      description text,
      event_type character varying(255) DEFAULT 'one_time'::character varying NOT NULL,
      status character varying(255) DEFAULT 'active'::character varying,
      scheduled_at timestamp(0) without time zone,
      cron_expression character varying(255),
      timezone character varying(255) DEFAULT 'UTC'::character varying,
      next_run_at timestamp(0) without time zone,
      last_run_at timestamp(0) without time zone,
      run_count integer DEFAULT 0,
      max_runs integer,
      action_type character varying(255),
      action_config jsonb DEFAULT '{}'::jsonb,
      webhook_secret character varying(255),
      webhook_url character varying(255),
      trigger_project_id uuid,
      trigger_on character varying(255),
      target_project_id uuid,
      created_by_id uuid,
      last_error text,
      metadata jsonb DEFAULT '{}'::jsonb,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.streaming_sessions (
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
  CREATE TABLE public.subscriptions (
      id uuid NOT NULL,
      user_id uuid NOT NULL,
      product_id uuid NOT NULL,
      status character varying(255) DEFAULT 'active'::character varying NOT NULL,
      starts_at timestamp(0) without time zone,
      expires_at timestamp(0) without time zone,
      cancelled_at timestamp(0) without time zone,
      trial_ends_at timestamp(0) without time zone,
      stripe_subscription_id character varying(255),
      stripe_customer_id character varying(255),
      storage_bytes_granted bigint DEFAULT 0,
      role_granted character varying(255),
      features_granted character varying(255)[] DEFAULT ARRAY[]::character varying[],
      current_period_start timestamp(0) without time zone,
      current_period_end timestamp(0) without time zone,
      cancel_at_period_end boolean DEFAULT false,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      canceled_at timestamp(0) without time zone,
      ended_at timestamp(0) without time zone,
      trial_start timestamp(0) without time zone,
      trial_end timestamp(0) without time zone,
      metadata jsonb DEFAULT '{}'::jsonb
  )
  --;;
  CREATE TABLE public.suspicious_requests (
      id uuid NOT NULL,
      ip_address character varying(255) NOT NULL,
      path character varying(255) NOT NULL,
      method character varying(255) NOT NULL,
      user_agent text,
      request_type character varying(255) NOT NULL,
      status_code integer,
      blocked boolean DEFAULT false,
      fingerprint_hash character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.task_dependencies (
      id uuid NOT NULL,
      task_id uuid NOT NULL,
      depends_on_task_id uuid NOT NULL,
      dependency_type character varying(255) DEFAULT 'finish-start'::character varying,
      lag_seconds integer DEFAULT 0,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.tasks (
      id uuid NOT NULL,
      project_id uuid NOT NULL,
      title character varying(255) NOT NULL,
      description text,
      assignee_id uuid,
      status character varying(255) DEFAULT 'todo'::character varying,
      percent_complete integer DEFAULT 0,
      duration_seconds integer,
      start_at timestamp(0) without time zone,
      end_at timestamp(0) without time zone,
      earliest_start_at timestamp(0) without time zone,
      latest_finish_at timestamp(0) without time zone,
      lock_version integer DEFAULT 1,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      earliest_finish_at timestamp(0) without time zone
  )
  --;;
  CREATE TABLE public.user_files (
      id uuid NOT NULL,
      filename character varying(255) NOT NULL,
      original_filename character varying(255) NOT NULL,
      content_type character varying(255) NOT NULL,
      file_size integer NOT NULL,
      file_path character varying(255),
      file character varying(255),
      is_public boolean DEFAULT false,
      description text,
      tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
      user_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      folder_path character varying(255) DEFAULT '/'::character varying NOT NULL
  )
  --;;
  CREATE TABLE public.user_folders (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      path character varying(255) NOT NULL,
      parent_path character varying(255) DEFAULT '/'::character varying,
      user_id uuid NOT NULL,
      color character varying(255),
      icon character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.user_media (
      id uuid NOT NULL,
      user_id uuid,
      filename character varying(255) NOT NULL,
      original_filename character varying(255) NOT NULL,
      file_type character varying(255) NOT NULL,
      mime_type character varying(255) NOT NULL,
      file_size bigint NOT NULL,
      file_path text NOT NULL,
      url text NOT NULL,
      alt_text text,
      caption text,
      width integer,
      height integer,
      duration integer,
      metadata jsonb,
      usage_context character varying(255),
      is_public boolean DEFAULT false,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      folder_path character varying(255) DEFAULT '/'::character varying NOT NULL
  )
  --;;
  CREATE TABLE public.user_notifications (
      id uuid NOT NULL,
      type character varying(255) NOT NULL,
      title character varying(255),
      content text,
      read boolean DEFAULT false NOT NULL,
      read_at timestamp(0) without time zone,
      resource_type character varying(255),
      resource_id uuid,
      metadata jsonb DEFAULT '{}'::jsonb,
      user_id uuid NOT NULL,
      actor_id uuid,
      channel_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.user_sessions (
      id uuid NOT NULL,
      session_data jsonb DEFAULT '{}'::jsonb,
      desktop_state jsonb DEFAULT '{}'::jsonb,
      last_activity_at timestamp(0) without time zone,
      user_agent character varying(255),
      ip_address character varying(255),
      device_type character varying(255),
      user_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.users (
      id uuid NOT NULL,
      email character varying(255) NOT NULL,
      name character varying(255),
      password_hash character varying(255) NOT NULL,
      confirmed_at timestamp(0) without time zone,
      is_online boolean DEFAULT false,
      is_admin boolean DEFAULT true,
      last_activity timestamp(0) without time zone,
      avatar_shape character varying(255) DEFAULT 'circle'::character varying,
      avatar_color character varying(255) DEFAULT '#3B82F6'::character varying,
      avatar_file character varying(255),
      avatar_url character varying(255),
      status character varying(255) DEFAULT 'active'::character varying,
      role character varying(255) DEFAULT 'subscriber'::character varying,
      two_factor_secret character varying(255),
      two_factor_enabled boolean DEFAULT false,
      two_factor_backup_codes character varying(255)[] DEFAULT ARRAY[]::character varying[],
      position_x double precision DEFAULT 400.0,
      position_y double precision DEFAULT 300.0,
      email_verified_at timestamp(0) without time zone,
      email_verification_token character varying(255),
      email_verification_sent_at timestamp(0) without time zone,
      failed_login_attempts integer DEFAULT 0,
      locked_until timestamp(0) without time zone,
      password_reset_token character varying(255),
      password_reset_sent_at timestamp(0) without time zone,
      approved_at timestamp(0) without time zone,
      approved_by_id uuid,
      registration_ip character varying(255),
      last_login_ip character varying(255),
      last_login_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      background_preference character varying(255) DEFAULT 'galaxy'::character varying,
      background_custom_data jsonb DEFAULT '{}'::jsonb,
      avatar_opacity integer DEFAULT 100,
      allow_channel_invites boolean DEFAULT true,
      blocked_user_ids uuid[] DEFAULT ARRAY[]::uuid[],
      notification_sound_enabled boolean DEFAULT true,
      master_volume double precision DEFAULT 0.7,
      bio text,
      channel_order uuid[] DEFAULT ARRAY[]::uuid[],
      stripe_customer_id character varying(255),
      storage_quota_bytes bigint DEFAULT 1073741824,
      storage_used_bytes bigint DEFAULT 0,
      subscription_tier character varying(255) DEFAULT 'free'::character varying,
      subscription_features character varying(255)[] DEFAULT ARRAY[]::character varying[],
      channel_allowance integer DEFAULT 5 NOT NULL
  )
  --;;
  CREATE TABLE public.users_tokens (
      id uuid NOT NULL,
      user_id uuid NOT NULL,
      token bytea NOT NULL,
      context character varying(255) NOT NULL,
      sent_to character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL
  )
  --;;
  CREATE TABLE public.window_layouts (
      id uuid NOT NULL,
      user_id uuid NOT NULL,
      app character varying(255) NOT NULL,
      x integer DEFAULT 100 NOT NULL,
      y integer DEFAULT 100 NOT NULL,
      width integer DEFAULT 800 NOT NULL,
      height integer DEFAULT 600 NOT NULL,
      z_index integer DEFAULT 1,
      minimized boolean DEFAULT false,
      maximized boolean DEFAULT false,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      current_path character varying(255),
      view_mode character varying(255) DEFAULT 'grid'::character varying,
      breadcrumbs jsonb DEFAULT '[]'::jsonb,
      is_default boolean DEFAULT false,
      layout_name text DEFAULT ''::text NOT NULL,
      windows_config jsonb DEFAULT '{}'::jsonb
  )
  --;;
  ALTER TABLE ONLY public.calendar_notes ALTER COLUMN id SET DEFAULT nextval('public.calendar_notes_id_seq'::regclass)
  --;;
  ALTER TABLE ONLY public.cms_options ALTER COLUMN id SET DEFAULT nextval('public.cms_options_id_seq'::regclass)
  --;;
  ALTER TABLE ONLY public.allowed_identifiers
      ADD CONSTRAINT allowed_identifiers_identifier_identifier_type_key UNIQUE (identifier, identifier_type)
  --;;
  ALTER TABLE ONLY public.allowed_identifiers
      ADD CONSTRAINT allowed_identifiers_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.announcements
      ADD CONSTRAINT announcements_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.audit_logs
      ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.behavioral_data
      ADD CONSTRAINT behavioral_data_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.blocked_identifiers
      ADD CONSTRAINT blocked_identifiers_identifier_identifier_type_key UNIQUE (identifier, identifier_type)
  --;;
  ALTER TABLE ONLY public.blocked_identifiers
      ADD CONSTRAINT blocked_identifiers_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.calendar_notes
      ADD CONSTRAINT calendar_notes_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.cart_items
      ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.carts
      ADD CONSTRAINT carts_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.categories
      ADD CONSTRAINT categories_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.channel_invites
      ADD CONSTRAINT channel_invites_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.channel_members
      ADD CONSTRAINT channel_members_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.chat_channels
      ADD CONSTRAINT chat_channels_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.chat_message_attachments
      ADD CONSTRAINT chat_message_attachments_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.chat_messages
      ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.chat_reactions
      ADD CONSTRAINT chat_reactions_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.chat_threads
      ADD CONSTRAINT chat_threads_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.cms_options
      ADD CONSTRAINT cms_options_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.comments
      ADD CONSTRAINT comments_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.custom_emojis
      ADD CONSTRAINT custom_emojis_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.device_fingerprints
      ADD CONSTRAINT device_fingerprints_fingerprint_hash_key UNIQUE (fingerprint_hash)
  --;;
  ALTER TABLE ONLY public.device_fingerprints
      ADD CONSTRAINT device_fingerprints_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.dismissed_announcements
      ADD CONSTRAINT dismissed_announcements_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.download_tokens
      ADD CONSTRAINT download_tokens_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.drive_blobs
      ADD CONSTRAINT drive_blobs_pkey PRIMARY KEY (sha256)
  --;;
  ALTER TABLE ONLY public.drive_files
      ADD CONSTRAINT drive_files_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.drive_folders
      ADD CONSTRAINT drive_folders_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.drive_usage
      ADD CONSTRAINT drive_usage_pkey PRIMARY KEY (user_id)
  --;;
  ALTER TABLE ONLY public.email_logs
      ADD CONSTRAINT email_logs_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.entitlements
      ADD CONSTRAINT entitlements_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.login_attempts
      ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.notification_preferences
      ADD CONSTRAINT notification_preferences_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.order_items
      ADD CONSTRAINT order_items_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.orders
      ADD CONSTRAINT orders_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.pages
      ADD CONSTRAINT pages_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.plugin_states
      ADD CONSTRAINT plugin_states_pkey PRIMARY KEY (slug)
  --;;
  ALTER TABLE ONLY public.posts
      ADD CONSTRAINT posts_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.products
      ADD CONSTRAINT products_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.project_events
      ADD CONSTRAINT project_events_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.projects
      ADD CONSTRAINT projects_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.scheduled_event_runs
      ADD CONSTRAINT scheduled_event_runs_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.scheduled_events
      ADD CONSTRAINT scheduled_events_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.streaming_sessions
      ADD CONSTRAINT streaming_sessions_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.subscriptions
      ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.suspicious_requests
      ADD CONSTRAINT suspicious_requests_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.task_dependencies
      ADD CONSTRAINT task_dependencies_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.tasks
      ADD CONSTRAINT tasks_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.user_files
      ADD CONSTRAINT user_files_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.user_folders
      ADD CONSTRAINT user_folders_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.user_media
      ADD CONSTRAINT user_media_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.user_notifications
      ADD CONSTRAINT user_notifications_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.user_sessions
      ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.users
      ADD CONSTRAINT users_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.users_tokens
      ADD CONSTRAINT users_tokens_pkey PRIMARY KEY (id)
  --;;
  ALTER TABLE ONLY public.window_layouts
      ADD CONSTRAINT window_layouts_pkey PRIMARY KEY (id)
  --;;
  CREATE INDEX allowed_identifiers_added_at_index ON public.allowed_identifiers USING btree (added_at)
  --;;
  CREATE UNIQUE INDEX allowed_identifiers_identifier_identifier_type_index ON public.allowed_identifiers USING btree (identifier, identifier_type)
  --;;
  CREATE INDEX announcements_announcement_type_index ON public.announcements USING btree (announcement_type)
  --;;
  CREATE INDEX announcements_created_by_id_index ON public.announcements USING btree (created_by_id)
  --;;
  CREATE INDEX announcements_ends_at_index ON public.announcements USING btree (ends_at)
  --;;
  CREATE INDEX announcements_is_active_index ON public.announcements USING btree (is_active)
  --;;
  CREATE INDEX announcements_starts_at_index ON public.announcements USING btree (starts_at)
  --;;
  CREATE INDEX announcements_target_audience_index ON public.announcements USING btree (target_audience)
  --;;
  CREATE INDEX audit_logs_actor_id_index ON public.audit_logs USING btree (actor_id)
  --;;
  CREATE INDEX audit_logs_target_type_target_id_index ON public.audit_logs USING btree (target_type, target_id)
  --;;
  CREATE INDEX behavioral_data_device_fingerprint_id_index ON public.behavioral_data USING btree (device_fingerprint_id)
  --;;
  CREATE INDEX behavioral_data_seems_human_index ON public.behavioral_data USING btree (seems_human)
  --;;
  CREATE INDEX behavioral_data_session_id_index ON public.behavioral_data USING btree (session_id)
  --;;
  CREATE INDEX behavioral_data_timestamp_index ON public.behavioral_data USING btree ("timestamp")
  --;;
  CREATE INDEX blocked_identifiers_auto_blocked_index ON public.blocked_identifiers USING btree (auto_blocked)
  --;;
  CREATE INDEX blocked_identifiers_blocked_at_index ON public.blocked_identifiers USING btree (blocked_at)
  --;;
  CREATE INDEX blocked_identifiers_expires_at_index ON public.blocked_identifiers USING btree (expires_at)
  --;;
  CREATE UNIQUE INDEX blocked_identifiers_identifier_identifier_type_index ON public.blocked_identifiers USING btree (identifier, identifier_type)
  --;;
  CREATE INDEX calendar_notes_date_index ON public.calendar_notes USING btree (date)
  --;;
  CREATE INDEX calendar_notes_reminder_reminder_at_index ON public.calendar_notes USING btree (reminder, reminder_at)
  --;;
  CREATE UNIQUE INDEX calendar_notes_user_id_date_index ON public.calendar_notes USING btree (user_id, date)
  --;;
  CREATE INDEX calendar_notes_user_id_index ON public.calendar_notes USING btree (user_id)
  --;;
  CREATE INDEX cart_items_cart_id_index ON public.cart_items USING btree (cart_id)
  --;;
  CREATE UNIQUE INDEX cart_items_cart_id_product_id_index ON public.cart_items USING btree (cart_id, product_id)
  --;;
  CREATE INDEX cart_items_product_id_index ON public.cart_items USING btree (product_id)
  --;;
  CREATE INDEX carts_session_id_index ON public.carts USING btree (session_id)
  --;;
  CREATE INDEX carts_status_index ON public.carts USING btree (status)
  --;;
  CREATE UNIQUE INDEX carts_user_id_index ON public.carts USING btree (user_id)
  --;;
  CREATE INDEX categories_is_active_index ON public.categories USING btree (is_active)
  --;;
  CREATE INDEX categories_parent_id_index ON public.categories USING btree (parent_id)
  --;;
  CREATE INDEX categories_position_index ON public.categories USING btree ("position")
  --;;
  CREATE UNIQUE INDEX categories_slug_index ON public.categories USING btree (slug)
  --;;
  CREATE INDEX channel_invites_channel_id_index ON public.channel_invites USING btree (channel_id)
  --;;
  CREATE UNIQUE INDEX channel_invites_code_index ON public.channel_invites USING btree (code)
  --;;
  CREATE INDEX channel_invites_created_by_id_index ON public.channel_invites USING btree (created_by_id)
  --;;
  CREATE INDEX channel_invites_invitee_id_index ON public.channel_invites USING btree (invitee_id)
  --;;
  CREATE INDEX channel_invites_is_revoked_index ON public.channel_invites USING btree (is_revoked)
  --;;
  CREATE INDEX channel_members_channel_id_index ON public.channel_members USING btree (channel_id)
  --;;
  CREATE UNIQUE INDEX channel_members_channel_id_user_id_index ON public.channel_members USING btree (channel_id, user_id)
  --;;
  CREATE INDEX channel_members_channel_id_user_id_last_read_message_id_index ON public.channel_members USING btree (channel_id, user_id, last_read_message_id)
  --;;
  CREATE INDEX channel_members_role_index ON public.channel_members USING btree (role)
  --;;
  CREATE UNIQUE INDEX channel_members_user_id_channel_id_index ON public.channel_members USING btree (user_id, channel_id)
  --;;
  CREATE INDEX channel_members_user_id_index ON public.channel_members USING btree (user_id)
  --;;
  CREATE INDEX chat_channels_channel_type_index ON public.chat_channels USING btree (channel_type)
  --;;
  CREATE INDEX chat_channels_created_by_id_index ON public.chat_channels USING btree (created_by_id)
  --;;
  CREATE UNIQUE INDEX chat_channels_invite_code_index ON public.chat_channels USING btree (invite_code) WHERE (invite_code IS NOT NULL)
  --;;
  CREATE INDEX chat_channels_is_private_index ON public.chat_channels USING btree (is_private)
  --;;
  CREATE INDEX chat_channels_is_public_index ON public.chat_channels USING btree (is_public)
  --;;
  CREATE INDEX chat_channels_is_user_created_index ON public.chat_channels USING btree (is_user_created)
  --;;
  CREATE INDEX chat_channels_owner_id_index ON public.chat_channels USING btree (owner_id)
  --;;
  CREATE INDEX chat_channels_position_index ON public.chat_channels USING btree ("position")
  --;;
  CREATE INDEX chat_message_attachments_channel_id_index ON public.chat_message_attachments USING btree (channel_id)
  --;;
  CREATE INDEX chat_message_attachments_message_id_index ON public.chat_message_attachments USING btree (message_id)
  --;;
  CREATE INDEX chat_message_attachments_user_id_index ON public.chat_message_attachments USING btree (user_id)
  --;;
  CREATE INDEX chat_messages_channel_id_index ON public.chat_messages USING btree (channel_id)
  --;;
  CREATE INDEX chat_messages_inserted_at_index ON public.chat_messages USING btree (inserted_at)
  --;;
  CREATE INDEX chat_messages_is_pinned_index ON public.chat_messages USING btree (is_pinned)
  --;;
  CREATE INDEX chat_messages_message_type_index ON public.chat_messages USING btree (message_type)
  --;;
  CREATE INDEX chat_messages_reply_to_id_index ON public.chat_messages USING btree (reply_to_id)
  --;;
  CREATE INDEX chat_messages_thread_id_index ON public.chat_messages USING btree (thread_id)
  --;;
  CREATE INDEX chat_messages_user_id_index ON public.chat_messages USING btree (user_id)
  --;;
  CREATE INDEX chat_reactions_message_id_index ON public.chat_reactions USING btree (message_id)
  --;;
  CREATE UNIQUE INDEX chat_reactions_user_id_message_id_emoji_index ON public.chat_reactions USING btree (user_id, message_id, emoji)
  --;;
  CREATE INDEX chat_threads_channel_id_index ON public.chat_threads USING btree (channel_id)
  --;;
  CREATE INDEX chat_threads_is_archived_index ON public.chat_threads USING btree (is_archived)
  --;;
  CREATE INDEX chat_threads_parent_message_id_index ON public.chat_threads USING btree (parent_message_id)
  --;;
  CREATE INDEX cms_options_autoload_index ON public.cms_options USING btree (autoload)
  --;;
  CREATE UNIQUE INDEX cms_options_option_name_index ON public.cms_options USING btree (option_name)
  --;;
  CREATE INDEX comments_inserted_at_index ON public.comments USING btree (inserted_at)
  --;;
  CREATE INDEX comments_is_approved_index ON public.comments USING btree (is_approved)
  --;;
  CREATE INDEX comments_parent_id_index ON public.comments USING btree (parent_id)
  --;;
  CREATE INDEX comments_post_id_index ON public.comments USING btree (post_id)
  --;;
  CREATE INDEX comments_user_id_index ON public.comments USING btree (user_id)
  --;;
  CREATE INDEX custom_emojis_category_index ON public.custom_emojis USING btree (category)
  --;;
  CREATE INDEX custom_emojis_created_by_id_index ON public.custom_emojis USING btree (created_by_id)
  --;;
  CREATE UNIQUE INDEX custom_emojis_shortcode_index ON public.custom_emojis USING btree (shortcode)
  --;;
  CREATE UNIQUE INDEX device_fingerprints_fingerprint_hash_index ON public.device_fingerprints USING btree (fingerprint_hash)
  --;;
  CREATE INDEX device_fingerprints_first_seen_at_index ON public.device_fingerprints USING btree (first_seen_at)
  --;;
  CREATE INDEX device_fingerprints_last_seen_at_index ON public.device_fingerprints USING btree (last_seen_at)
  --;;
  CREATE INDEX device_fingerprints_trusted_index ON public.device_fingerprints USING btree (trusted)
  --;;
  CREATE INDEX device_fingerprints_user_id_index ON public.device_fingerprints USING btree (user_id)
  --;;
  CREATE INDEX dismissed_announcements_announcement_id_index ON public.dismissed_announcements USING btree (announcement_id)
  --;;
  CREATE UNIQUE INDEX dismissed_announcements_user_id_announcement_id_index ON public.dismissed_announcements USING btree (user_id, announcement_id)
  --;;
  CREATE INDEX download_tokens_expires_at_index ON public.download_tokens USING btree (expires_at)
  --;;
  CREATE INDEX download_tokens_order_id_index ON public.download_tokens USING btree (order_id)
  --;;
  CREATE INDEX download_tokens_product_id_index ON public.download_tokens USING btree (product_id)
  --;;
  CREATE UNIQUE INDEX download_tokens_token_index ON public.download_tokens USING btree (token)
  --;;
  CREATE INDEX download_tokens_user_id_index ON public.download_tokens USING btree (user_id)
  --;;
  CREATE INDEX download_tokens_user_id_product_id_index ON public.download_tokens USING btree (user_id, product_id)
  --;;
  CREATE INDEX drive_blobs_last_referenced_at_index ON public.drive_blobs USING btree (last_referenced_at)
  --;;
  CREATE INDEX drive_files_blob_sha256_index ON public.drive_files USING btree (blob_sha256)
  --;;
  CREATE UNIQUE INDEX drive_files_legacy_ref_index ON public.drive_files USING btree (legacy_ref) WHERE (legacy_ref IS NOT NULL)
  --;;
  CREATE INDEX drive_files_owner_id_folder_id_index ON public.drive_files USING btree (owner_id, folder_id)
  --;;
  CREATE UNIQUE INDEX drive_files_root_name_index ON public.drive_files USING btree (owner_id, name) WHERE (folder_id IS NULL)
  --;;
  CREATE UNIQUE INDEX drive_files_share_token_index ON public.drive_files USING btree (share_token) WHERE (share_token IS NOT NULL)
  --;;
  CREATE UNIQUE INDEX drive_files_sibling_name_index ON public.drive_files USING btree (owner_id, folder_id, name) WHERE (folder_id IS NOT NULL)
  --;;
  CREATE UNIQUE INDEX drive_folders_root_name_index ON public.drive_folders USING btree (owner_id, name) WHERE (parent_id IS NULL)
  --;;
  CREATE UNIQUE INDEX drive_folders_sibling_name_index ON public.drive_folders USING btree (owner_id, parent_id, name) WHERE (parent_id IS NOT NULL)
  --;;
  CREATE INDEX drive_usage_purge_after_index ON public.drive_usage USING btree (purge_after) WHERE (purge_after IS NOT NULL)
  --;;
  CREATE INDEX email_logs_sent_at_index ON public.email_logs USING btree (sent_at)
  --;;
  CREATE INDEX email_logs_to_index ON public.email_logs USING btree ("to")
  --;;
  CREATE INDEX entitlements_source_type_source_id_index ON public.entitlements USING btree (source_type, source_id)
  --;;
  CREATE INDEX entitlements_user_id_kind_index ON public.entitlements USING btree (user_id, kind)
  --;;
  CREATE INDEX index_channel_members_on_role ON public.channel_members USING btree (role)
  --;;
  CREATE INDEX login_attempts_identifier_index ON public.login_attempts USING btree (identifier)
  --;;
  CREATE INDEX login_attempts_identifier_type_index ON public.login_attempts USING btree (identifier_type)
  --;;
  CREATE INDEX login_attempts_ip_address_index ON public.login_attempts USING btree (ip_address)
  --;;
  CREATE INDEX login_attempts_last_attempt_at_index ON public.login_attempts USING btree (last_attempt_at)
  --;;
  CREATE INDEX login_attempts_user_id_index ON public.login_attempts USING btree (user_id)
  --;;
  CREATE UNIQUE INDEX notification_preferences_user_id_index ON public.notification_preferences USING btree (user_id)
  --;;
  CREATE INDEX order_items_download_granted_index ON public.order_items USING btree (download_granted)
  --;;
  CREATE INDEX order_items_is_digital_index ON public.order_items USING btree (is_digital)
  --;;
  CREATE INDEX order_items_order_id_index ON public.order_items USING btree (order_id)
  --;;
  CREATE INDEX order_items_product_id_index ON public.order_items USING btree (product_id)
  --;;
  CREATE INDEX orders_fulfillment_status_index ON public.orders USING btree (fulfillment_status)
  --;;
  CREATE INDEX orders_inserted_at_index ON public.orders USING btree (inserted_at)
  --;;
  CREATE UNIQUE INDEX orders_order_number_index ON public.orders USING btree (order_number)
  --;;
  CREATE INDEX orders_payment_intent_id_index ON public.orders USING btree (payment_intent_id)
  --;;
  CREATE INDEX orders_payment_status_index ON public.orders USING btree (payment_status)
  --;;
  CREATE INDEX orders_status_index ON public.orders USING btree (status)
  --;;
  CREATE INDEX orders_stripe_payment_intent_id_index ON public.orders USING btree (stripe_payment_intent_id)
  --;;
  CREATE UNIQUE INDEX orders_stripe_session_id_index ON public.orders USING btree (stripe_session_id) WHERE (stripe_session_id IS NOT NULL)
  --;;
  CREATE INDEX orders_user_id_index ON public.orders USING btree (user_id)
  --;;
  CREATE INDEX pages_author_id_index ON public.pages USING btree (author_id)
  --;;
  CREATE INDEX pages_category_index ON public.pages USING btree (category)
  --;;
  CREATE INDEX pages_is_published_index ON public.pages USING btree (is_published)
  --;;
  CREATE INDEX pages_is_published_order_index ON public.pages USING btree (is_published, "order")
  --;;
  CREATE UNIQUE INDEX pages_slug_index ON public.pages USING btree (slug)
  --;;
  CREATE INDEX posts_is_published_index ON public.posts USING btree (is_published)
  --;;
  CREATE INDEX posts_published_at_index ON public.posts USING btree (published_at)
  --;;
  CREATE UNIQUE INDEX posts_slug_index ON public.posts USING btree (slug)
  --;;
  CREATE INDEX posts_tags_index ON public.posts USING btree (tags)
  --;;
  CREATE INDEX posts_user_id_index ON public.posts USING btree (user_id)
  --;;
  CREATE INDEX products_billing_interval_index ON public.products USING btree (billing_interval)
  --;;
  CREATE INDEX products_category_id_index ON public.products USING btree (category_id)
  --;;
  CREATE INDEX products_featured_index ON public.products USING btree (featured)
  --;;
  CREATE INDEX products_is_active_index ON public.products USING btree (is_active)
  --;;
  CREATE INDEX products_is_digital_index ON public.products USING btree (is_digital)
  --;;
  CREATE INDEX products_is_featured_index ON public.products USING btree (is_featured)
  --;;
  CREATE INDEX products_position_index ON public.products USING btree ("position")
  --;;
  CREATE INDEX products_product_type_index ON public.products USING btree (product_type)
  --;;
  CREATE UNIQUE INDEX products_sku_index ON public.products USING btree (sku)
  --;;
  CREATE UNIQUE INDEX products_slug_index ON public.products USING btree (slug)
  --;;
  CREATE INDEX products_stripe_price_id_index ON public.products USING btree (stripe_price_id)
  --;;
  CREATE INDEX products_stripe_product_id_index ON public.products USING btree (stripe_product_id)
  --;;
  CREATE INDEX project_events_event_type_index ON public.project_events USING btree (event_type)
  --;;
  CREATE INDEX project_events_occurred_at_index ON public.project_events USING btree (occurred_at)
  --;;
  CREATE INDEX project_events_project_id_index ON public.project_events USING btree (project_id)
  --;;
  CREATE INDEX project_events_task_id_index ON public.project_events USING btree (task_id)
  --;;
  CREATE INDEX projects_owner_id_index ON public.projects USING btree (owner_id)
  --;;
  CREATE INDEX scheduled_event_runs_scheduled_event_id_index ON public.scheduled_event_runs USING btree (scheduled_event_id)
  --;;
  CREATE INDEX scheduled_event_runs_started_at_index ON public.scheduled_event_runs USING btree (started_at)
  --;;
  CREATE INDEX scheduled_event_runs_status_index ON public.scheduled_event_runs USING btree (status)
  --;;
  CREATE INDEX scheduled_events_created_by_id_index ON public.scheduled_events USING btree (created_by_id)
  --;;
  CREATE INDEX scheduled_events_event_type_index ON public.scheduled_events USING btree (event_type)
  --;;
  CREATE INDEX scheduled_events_next_run_at_index ON public.scheduled_events USING btree (next_run_at)
  --;;
  CREATE INDEX scheduled_events_status_index ON public.scheduled_events USING btree (status)
  --;;
  CREATE INDEX scheduled_events_target_project_id_index ON public.scheduled_events USING btree (target_project_id)
  --;;
  CREATE INDEX scheduled_events_trigger_project_id_index ON public.scheduled_events USING btree (trigger_project_id)
  --;;
  CREATE UNIQUE INDEX scheduled_events_webhook_secret_index ON public.scheduled_events USING btree (webhook_secret) WHERE (webhook_secret IS NOT NULL)
  --;;
  CREATE INDEX streaming_sessions_channel_id_index ON public.streaming_sessions USING btree (channel_id)
  --;;
  CREATE INDEX streaming_sessions_is_active_index ON public.streaming_sessions USING btree (is_active)
  --;;
  CREATE INDEX streaming_sessions_status_index ON public.streaming_sessions USING btree (status)
  --;;
  CREATE INDEX streaming_sessions_streamer_id_index ON public.streaming_sessions USING btree (streamer_id)
  --;;
  CREATE INDEX streaming_sessions_user_id_index ON public.streaming_sessions USING btree (user_id)
  --;;
  CREATE UNIQUE INDEX subscriptions_active_unique ON public.subscriptions USING btree (user_id, product_id) WHERE ((status)::text = ANY (ARRAY[('active'::character varying)::text, ('trial'::character varying)::text]))
  --;;
  CREATE INDEX subscriptions_current_period_end_index ON public.subscriptions USING btree (current_period_end)
  --;;
  CREATE INDEX subscriptions_product_id_index ON public.subscriptions USING btree (product_id)
  --;;
  CREATE INDEX subscriptions_status_index ON public.subscriptions USING btree (status)
  --;;
  CREATE INDEX subscriptions_stripe_subscription_id_index ON public.subscriptions USING btree (stripe_subscription_id)
  --;;
  CREATE INDEX subscriptions_user_id_index ON public.subscriptions USING btree (user_id)
  --;;
  CREATE INDEX subscriptions_user_id_status_index ON public.subscriptions USING btree (user_id, status)
  --;;
  CREATE INDEX suspicious_requests_inserted_at_index ON public.suspicious_requests USING btree (inserted_at)
  --;;
  CREATE INDEX suspicious_requests_ip_address_index ON public.suspicious_requests USING btree (ip_address)
  --;;
  CREATE INDEX suspicious_requests_request_type_index ON public.suspicious_requests USING btree (request_type)
  --;;
  CREATE INDEX task_dependencies_depends_on_task_id_index ON public.task_dependencies USING btree (depends_on_task_id)
  --;;
  CREATE INDEX task_dependencies_task_id_index ON public.task_dependencies USING btree (task_id)
  --;;
  CREATE INDEX tasks_assignee_id_index ON public.tasks USING btree (assignee_id)
  --;;
  CREATE INDEX tasks_project_id_index ON public.tasks USING btree (project_id)
  --;;
  CREATE UNIQUE INDEX unique_task_dependency ON public.task_dependencies USING btree (task_id, depends_on_task_id)
  --;;
  CREATE INDEX user_files_content_type_index ON public.user_files USING btree (content_type)
  --;;
  CREATE INDEX user_files_inserted_at_index ON public.user_files USING btree (inserted_at)
  --;;
  CREATE INDEX user_files_is_public_index ON public.user_files USING btree (is_public)
  --;;
  CREATE INDEX user_files_user_id_folder_path_index ON public.user_files USING btree (user_id, folder_path)
  --;;
  CREATE INDEX user_files_user_id_index ON public.user_files USING btree (user_id)
  --;;
  CREATE INDEX user_folders_user_id_parent_path_index ON public.user_folders USING btree (user_id, parent_path)
  --;;
  CREATE UNIQUE INDEX user_folders_user_path_unique ON public.user_folders USING btree (user_id, path)
  --;;
  CREATE INDEX user_media_file_type_index ON public.user_media USING btree (file_type)
  --;;
  CREATE INDEX user_media_inserted_at_index ON public.user_media USING btree (inserted_at)
  --;;
  CREATE INDEX user_media_usage_context_index ON public.user_media USING btree (usage_context)
  --;;
  CREATE INDEX user_media_user_id_folder_path_index ON public.user_media USING btree (user_id, folder_path)
  --;;
  CREATE INDEX user_media_user_id_index ON public.user_media USING btree (user_id)
  --;;
  CREATE INDEX user_notifications_resource_type_resource_id_index ON public.user_notifications USING btree (resource_type, resource_id)
  --;;
  CREATE INDEX user_notifications_user_id_index ON public.user_notifications USING btree (user_id)
  --;;
  CREATE INDEX user_notifications_user_id_inserted_at_index ON public.user_notifications USING btree (user_id, inserted_at)
  --;;
  CREATE INDEX user_notifications_user_id_read_index ON public.user_notifications USING btree (user_id, read)
  --;;
  CREATE INDEX user_sessions_last_activity_at_index ON public.user_sessions USING btree (last_activity_at)
  --;;
  CREATE INDEX user_sessions_user_id_index ON public.user_sessions USING btree (user_id)
  --;;
  CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email)
  --;;
  CREATE INDEX users_email_verification_token_index ON public.users USING btree (email_verification_token)
  --;;
  CREATE INDEX users_email_verified_at_index ON public.users USING btree (email_verified_at)
  --;;
  CREATE INDEX users_is_admin_index ON public.users USING btree (is_admin)
  --;;
  CREATE INDEX users_locked_until_index ON public.users USING btree (locked_until)
  --;;
  CREATE UNIQUE INDEX users_name_unique_index ON public.users USING btree (name)
  --;;
  CREATE INDEX users_password_reset_token_index ON public.users USING btree (password_reset_token)
  --;;
  CREATE INDEX users_stripe_customer_id_index ON public.users USING btree (stripe_customer_id)
  --;;
  CREATE INDEX users_subscription_tier_index ON public.users USING btree (subscription_tier)
  --;;
  CREATE UNIQUE INDEX users_tokens_context_token_index ON public.users_tokens USING btree (context, token)
  --;;
  CREATE INDEX users_tokens_user_id_index ON public.users_tokens USING btree (user_id)
  --;;
  CREATE INDEX users_two_factor_enabled_index ON public.users USING btree (two_factor_enabled)
  --;;
  CREATE INDEX window_layouts_is_default_index ON public.window_layouts USING btree (is_default)
  --;;
  CREATE UNIQUE INDEX window_layouts_user_id_app_index ON public.window_layouts USING btree (user_id, app)
  --;;
  CREATE INDEX window_layouts_user_id_index ON public.window_layouts USING btree (user_id)
  --;;
  CREATE UNIQUE INDEX window_layouts_user_id_layout_name_index ON public.window_layouts USING btree (user_id, layout_name)
  --;;
  ALTER TABLE ONLY public.allowed_identifiers
      ADD CONSTRAINT allowed_identifiers_added_by_user_id_fkey FOREIGN KEY (added_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.announcements
      ADD CONSTRAINT announcements_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.behavioral_data
      ADD CONSTRAINT behavioral_data_device_fingerprint_id_fkey FOREIGN KEY (device_fingerprint_id) REFERENCES public.device_fingerprints(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.blocked_identifiers
      ADD CONSTRAINT blocked_identifiers_blocked_by_user_id_fkey FOREIGN KEY (blocked_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.calendar_notes
      ADD CONSTRAINT calendar_notes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.cart_items
      ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id) REFERENCES public.carts(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.cart_items
      ADD CONSTRAINT cart_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.carts
      ADD CONSTRAINT carts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.categories
      ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.channel_invites
      ADD CONSTRAINT channel_invites_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.channel_invites
      ADD CONSTRAINT channel_invites_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.channel_invites
      ADD CONSTRAINT channel_invites_invitee_id_fkey FOREIGN KEY (invitee_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.channel_invites
      ADD CONSTRAINT channel_invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.channel_members
      ADD CONSTRAINT channel_members_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.channel_members
      ADD CONSTRAINT channel_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_channels
      ADD CONSTRAINT chat_channels_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.chat_channels
      ADD CONSTRAINT chat_channels_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_message_attachments
      ADD CONSTRAINT chat_message_attachments_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.chat_message_attachments
      ADD CONSTRAINT chat_message_attachments_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_message_attachments
      ADD CONSTRAINT chat_message_attachments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.chat_messages
      ADD CONSTRAINT chat_messages_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_messages
      ADD CONSTRAINT chat_messages_reply_to_id_fkey FOREIGN KEY (reply_to_id) REFERENCES public.chat_messages(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.chat_messages
      ADD CONSTRAINT chat_messages_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.chat_threads(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.chat_messages
      ADD CONSTRAINT chat_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_reactions
      ADD CONSTRAINT chat_reactions_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_reactions
      ADD CONSTRAINT chat_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_threads
      ADD CONSTRAINT chat_threads_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.chat_threads
      ADD CONSTRAINT chat_threads_parent_message_id_fkey FOREIGN KEY (parent_message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.comments
      ADD CONSTRAINT comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.comments(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.comments
      ADD CONSTRAINT comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.comments
      ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.custom_emojis
      ADD CONSTRAINT custom_emojis_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.device_fingerprints
      ADD CONSTRAINT device_fingerprints_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.dismissed_announcements
      ADD CONSTRAINT dismissed_announcements_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES public.announcements(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.dismissed_announcements
      ADD CONSTRAINT dismissed_announcements_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.download_tokens
      ADD CONSTRAINT download_tokens_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.download_tokens
      ADD CONSTRAINT download_tokens_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.download_tokens
      ADD CONSTRAINT download_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.drive_files
      ADD CONSTRAINT drive_files_blob_sha256_fkey FOREIGN KEY (blob_sha256) REFERENCES public.drive_blobs(sha256) ON DELETE RESTRICT
  --;;
  ALTER TABLE ONLY public.drive_files
      ADD CONSTRAINT drive_files_folder_id_fkey FOREIGN KEY (folder_id) REFERENCES public.drive_folders(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.drive_files
      ADD CONSTRAINT drive_files_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.drive_folders
      ADD CONSTRAINT drive_folders_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.drive_folders
      ADD CONSTRAINT drive_folders_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.drive_folders(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.drive_usage
      ADD CONSTRAINT drive_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.entitlements
      ADD CONSTRAINT entitlements_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.login_attempts
      ADD CONSTRAINT login_attempts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.notification_preferences
      ADD CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.order_items
      ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.order_items
      ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.orders
      ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.pages
      ADD CONSTRAINT pages_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.plugin_states
      ADD CONSTRAINT plugin_states_changed_by_id_fkey FOREIGN KEY (changed_by_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.posts
      ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.products
      ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.project_events
      ADD CONSTRAINT project_events_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.project_events
      ADD CONSTRAINT project_events_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.project_events
      ADD CONSTRAINT project_events_triggered_by_user_id_fkey FOREIGN KEY (triggered_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.scheduled_event_runs
      ADD CONSTRAINT scheduled_event_runs_scheduled_event_id_fkey FOREIGN KEY (scheduled_event_id) REFERENCES public.scheduled_events(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.scheduled_events
      ADD CONSTRAINT scheduled_events_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.scheduled_events
      ADD CONSTRAINT scheduled_events_target_project_id_fkey FOREIGN KEY (target_project_id) REFERENCES public.projects(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.scheduled_events
      ADD CONSTRAINT scheduled_events_trigger_project_id_fkey FOREIGN KEY (trigger_project_id) REFERENCES public.projects(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.streaming_sessions
      ADD CONSTRAINT streaming_sessions_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.streaming_sessions
      ADD CONSTRAINT streaming_sessions_streamer_id_fkey FOREIGN KEY (streamer_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.streaming_sessions
      ADD CONSTRAINT streaming_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.subscriptions
      ADD CONSTRAINT subscriptions_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT
  --;;
  ALTER TABLE ONLY public.subscriptions
      ADD CONSTRAINT subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.task_dependencies
      ADD CONSTRAINT task_dependencies_depends_on_task_id_fkey FOREIGN KEY (depends_on_task_id) REFERENCES public.tasks(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.task_dependencies
      ADD CONSTRAINT task_dependencies_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.tasks
      ADD CONSTRAINT tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.user_files
      ADD CONSTRAINT user_files_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.user_folders
      ADD CONSTRAINT user_folders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.user_media
      ADD CONSTRAINT user_media_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.user_notifications
      ADD CONSTRAINT user_notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.user_notifications
      ADD CONSTRAINT user_notifications_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.chat_channels(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.user_notifications
      ADD CONSTRAINT user_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.user_sessions
      ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.users
      ADD CONSTRAINT users_approved_by_id_fkey FOREIGN KEY (approved_by_id) REFERENCES public.users(id) ON DELETE SET NULL
  --;;
  ALTER TABLE ONLY public.users_tokens
      ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  --;;
  ALTER TABLE ONLY public.window_layouts
      ADD CONSTRAINT window_layouts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
  """

  def up do
    # A Windows checkout has CRLF line endings, so accept either.
    for statement <- String.split(@sql, ~r/\r?\n--;;\r?\n/, trim: true), do: execute(statement)
  end

  def down, do: raise("The baseline can't be rolled back; drop the database instead.")
end
