defmodule ChatChannels do
  @moduledoc """
  The Chat Channels context: channels, messages, reactions, invites and custom emojis.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias ChatChannels.{Channel, Message, Reaction, Thread, ChannelMember, ChannelInvite, UserSettings}

  @default_channel_allowance 5

  @doc """
  How many channels this user may create.

  Falls back to the default when the user cannot be read, rather than to zero or
  to unlimited. Zero would lock everyone out of channel creation on a transient
  database hiccup; unlimited would turn the same hiccup into a way past a paid
  limit. The default is wrong in the least damaging direction.
  """
  def channel_allowance(user_id) when is_binary(user_id) do
    case Repo.get(UserSettings, user_id) do
      %{channel_allowance: n} when is_integer(n) -> n
      _ -> @default_channel_allowance
    end
  end

  def channel_allowance(_), do: @default_channel_allowance

  def default_channel_allowance, do: @default_channel_allowance

  @doc "Sets a user's allowance outright (admin use). Returns `{:ok, n}` or `{:error, :out_of_range}`."
  def set_channel_allowance(user_id, n) when is_binary(user_id) and is_integer(n) and n >= 0 and n <= 1000 do
    upsert_settings(user_id, %{channel_allowance: n}, [:channel_allowance])
    {:ok, n}
  end

  def set_channel_allowance(_user_id, _n), do: {:error, :out_of_range}

  @doc """
  Adds `n` (negative to take away) to a user's allowance, never below zero. The store calls this
  when a channel-slot pass is bought, restored or ends. Starts from the default for a user
  without settings.
  """
  def add_channel_allowance(user_id, n) when is_binary(user_id) and is_integer(n) do
    {:ok, uuid} = Ecto.UUID.dump(user_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{rows: [[total]]} =
      Repo.query!(
        """
        INSERT INTO chat_user_settings (user_id, channel_allowance, inserted_at, updated_at)
        VALUES ($1, GREATEST($2::integer + $3::integer, 0), $4, $4)
        ON CONFLICT (user_id) DO UPDATE
          SET channel_allowance = GREATEST(chat_user_settings.channel_allowance + $3::integer, 0), updated_at = $4
        RETURNING channel_allowance
        """,
        [uuid, @default_channel_allowance, n, now]
      )

    {:ok, total}
  end

  @doc "The order a user keeps their channel list in (channel ids; empty when they never sorted it)."
  def channel_order(user_id) when is_binary(user_id) do
    case Repo.get(UserSettings, user_id) do
      %{channel_order: order} when is_list(order) -> order
      _ -> []
    end
  end

  def channel_order(_), do: []

  @doc "True unless the user switched channel invitations off."
  def allow_invites?(user_id) when is_binary(user_id) do
    case Repo.get(UserSettings, user_id) do
      %{allow_invites: false} -> false
      _ -> true
    end
  end

  def allow_invites?(_), do: true

  @doc "Switches channel invitations on or off for a user."
  def set_allow_invites(user_id, allow?) when is_binary(user_id) and is_boolean(allow?) do
    upsert_settings(user_id, %{allow_invites: allow?}, [:allow_invites])
    {:ok, allow?}
  end

  defp upsert_settings(user_id, changes, fields) do
    Repo.insert!(
      struct(UserSettings, Map.put(changes, :user_id, user_id)),
      on_conflict: {:replace, fields ++ [:updated_at]},
      conflict_target: :user_id
    )
  end

  @doc """
  Channels this user owns. Games use it to offer a player their own channels
  (e.g. to build a world in).
  """
  def list_owned_channels(user_id) do
    from(c in Channel, where: c.owner_id == ^user_id, order_by: [asc: c.position, asc: c.name])
    |> Repo.all()
  end

  # Channels
  def list_channels do
    from(c in Channel, order_by: [asc: c.position, asc: c.name])
    |> Repo.all()
  end

  def list_text_channels do
    from(c in Channel, 
      where: c.channel_type == "text",
      order_by: [asc: c.position, asc: c.name]
    )
    |> Repo.all()
  end

  def list_voice_channels do
    from(c in Channel, 
      where: c.channel_type in ["voice", "video"],
      order_by: [asc: c.position, asc: c.name]
    )
    |> Repo.all()
  end

  def get_channel!(id) do
    Repo.get!(Channel, id)
  end

  def get_channel(id) do
    Repo.get(Channel, id)
  end

  def create_channel(attrs \\ %{}) do
    # Set position to be last
    max_position = from(c in Channel, select: max(c.position)) |> Repo.one() || 0
    
    # Ensure consistent key types - use string keys to match form params
    attrs = 
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()
      |> Map.put("position", max_position + 1)
    
    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, channel} ->
        pubsub_broadcast("chat:channels", {:channel_created, channel})
        Task.start(fn -> Bacon8.Audit.log(channel.created_by_id || channel.owner_id, "create_channel", "channel", channel.id, %{name: channel.name}) end)
        {:ok, channel}
      error -> error
    end
  end

  def update_channel(%Channel{} = channel, attrs) do
    # Re-fetch the current row so the old-icon comparison (and the changeset
    # base) reflect the latest DB state, not a struct the caller may be
    # holding from before another session's concurrent update (e.g. a
    # LiveView socket assign that hasn't been refreshed) — otherwise the
    # previous icon file never gets deleted and orphans accumulate.
    current = Repo.get!(Channel, channel.id)

    current
    |> Channel.changeset(attrs)
    |> Channel.put_icon(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_channel} ->
        # If icon_path changed, delete the old icon file (only if it really is this channel's:
        # a row saved before Channel.icon_path?/2 existed may name any file)
        if current.icon_path && current.icon_path != updated_channel.icon_path &&
             Channel.icon_path?(current, current.icon_path) do
          Bacon8.Uploads.delete_file(current.icon_path)
        end

        pubsub_broadcast("chat:channels", {:channel_updated, updated_channel})

        # Plugins may keep data tied to a channel (a game might mirror its name
        # and publicity into a world built for it). Best effort for them: an
        # edit the website already accepted is not failed here.
        Bacon8.Plugins.notify({:channel_updated, updated_channel, current})

        {:ok, updated_channel}
      error -> error
    end
  end

  def delete_channel(%Channel{} = channel) do
    # Protect the General channel from deletion
    if String.downcase(channel.name) == "general" do
      {:error, :protected_channel}
    else
      # PLUGINS GO FIRST, AND OUTSIDE THE TRANSACTION.
      #
      # Their data tied to this channel (a game world built for it) may live in
      # the other database, so it cannot join the transaction below - and if it
      # could, it still would not belong there: a rolled-back channel delete
      # would need that data resurrected.
      #
      # Doing it first means the bad case is plugin data deleted while its
      # channel survives - recoverable. The other order leaves plugin data
      # whose channel, and so whose access control list, is gone.
      Bacon8.Plugins.notify({:channel_deleted, channel.id})

      # Start transaction to ensure all-or-nothing deletion
      Repo.transaction(fn ->
        # 1. Get all messages in this channel with their attachments
        messages = from(m in Message,
          where: m.channel_id == ^channel.id,
          preload: [:attachments]
        ) |> Repo.all()

        # 2. Collect all attachment URL paths for cleanup (cleaner than reconstructing FS paths)
        attachment_file_paths =
          messages
          |> Enum.flat_map(& &1.attachments)
          |> Enum.map(fn attachment -> attachment.file end)
          |> Enum.filter(& &1)

        # 3. Delete all reactions for messages in this channel
        from(r in Reaction, 
          join: m in Message, on: r.message_id == m.id,
          where: m.channel_id == ^channel.id
        ) |> Repo.delete_all()

        # 4. Delete all threads in this channel (can delete directly by channel_id)
        from(t in Thread, where: t.channel_id == ^channel.id) |> Repo.delete_all()

        # 5. Delete all messages in this channel (this cascades to attachments via DB)
        from(m in Message, where: m.channel_id == ^channel.id) |> Repo.delete_all()

        # 6. Delete the channel itself
        case Repo.delete(channel) do
          {:ok, deleted_channel} ->
            # 7. Broadcast channel deletion
            pubsub_broadcast("chat:channels", {:channel_deleted, deleted_channel.id})
            Task.start(fn -> Bacon8.Audit.log(nil, "delete_channel", "channel", deleted_channel.id, %{name: deleted_channel.name}) end)
            
            # 8. Queue background job to delete files and channel directories from filesystem
            Task.start(fn ->
              # Delete the channel icon and its containing directory (only one
              # icon should ever exist at a time, so wipe the whole dir rather
              # than just the referenced filename in case stray files remain)
              #
              # Only the channel's own icon folder: icon_path is a stored string, and a row
              # saved before Channel.icon_path?/2 existed may name any file under uploads/.
              if Channel.icon_path?(deleted_channel, deleted_channel.icon_path) do
                case Bacon8.Uploads.url_to_path(deleted_channel.icon_path) do
                  nil -> :ok
                  path -> File.rm_rf(Path.dirname(path))
                end
              end

              # Delete individual attachment files
              Enum.each(attachment_file_paths, fn url_path ->
                Bacon8.Uploads.delete_file(url_path)
              end)
              
              # Delete channel directory for each user who uploaded to this channel
              # Extract unique user_ids from attachment paths
              user_dirs = attachment_file_paths
                |> Enum.map(fn path ->
                  # Extract user_id from path: /uploads/{user_id}/forum/{channel_id}/...
                  case String.split(path, "/", parts: 5) do
                    ["", "uploads", user_id, "forum", _] -> user_id
                    _ -> nil
                  end
                end)
                |> Enum.filter(& &1)
                |> Enum.uniq()
              
              # Remove channel directories for each user
              Enum.each(user_dirs, fn user_id ->
                channel_dir = Path.join([Bacon8.Uploads.base_dir(), user_id, "forum", deleted_channel.id])
                File.rm_rf(channel_dir)
              end)
            end)

            deleted_channel

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc "Delete a channel with permission checks for a user. Owners/creators, admins, and editors are allowed."
  def delete_channel_by_user(%{id: user_id} = user, %Channel{} = channel) do
    if String.downcase(channel.name) == "general" do
      {:error, :protected_channel}
    else
      is_admin_or_gm = Map.get(user, :is_admin, false) || user.role in ["admin", "gm", "editor"]
      
      # If channel is public, ONLY admins/GMs can delete it, even if they are the owner
      if !channel.is_private && !is_admin_or_gm do
        {:error, :forbidden}
      else
        can_delete = (Map.has_key?(channel, :owner_id) && channel.owner_id == user_id) ||
                     (Map.has_key?(channel, :created_by_id) && channel.created_by_id == user_id) ||
                     is_admin_or_gm

        if can_delete do
          delete_channel(channel)
        else
          {:error, :forbidden}
        end
      end
    end
  end

  def reorder_channels(%Bacon8.Accounts.User{} = user, ids) do
    # Filter out invalid UUIDs just in case
    valid_ids = Enum.filter(ids, fn id -> 
      case Ecto.UUID.cast(id) do
        {:ok, _} -> true
        _ -> false
      end
    end)

    {:ok, upsert_settings(user.id, %{channel_order: valid_ids}, [:channel_order])}
  end

  def reorder_channels(ids) do
    Repo.transaction(fn ->
      Enum.with_index(ids)
      |> Enum.each(fn {id, index} ->
        # Ensure ID is a valid UUID before querying to avoid crashes
        case Ecto.UUID.cast(id) do
          {:ok, uuid} ->
            from(c in Channel, where: c.id == ^uuid)
            |> Repo.update_all(set: [position: index])
          _ -> 
            # Skip invalid IDs
            :ok
        end
      end)
    end)
    
    # Broadcast update so other users see the new order
    pubsub_broadcast("chat:channels", {:channels_reordered, ids})
  end

  def change_channel(%Channel{} = channel, attrs \\ %{}) do
    Channel.changeset(channel, attrs)
  end

  def get_or_create_default_channel do
    case Repo.get_by(Channel, name: "general") do
      nil ->
        {:ok, channel} = create_channel(%{
          name: "general",
          description: "General discussion",
          channel_type: "text"
        })
        channel
      channel -> channel
    end
  end

  def list_public_channels do
    from(c in Channel,
      where: c.is_private == false,
      order_by: [asc: c.position, asc: c.name]
    )
    |> Repo.all()
  end

  def create_user_channel(user, attrs) do
    # Normalize attrs + set position for user channels
    max_position = from(c in Channel, where: c.owner_id == ^user.id, select: max(c.position)) |> Repo.one() || 0

    # Ensure we interpret is_private when provided as strings from forms
    is_private = case Map.get(attrs, "is_private") do
      "true" -> true
      "on" -> true
      true -> true
      _ -> false
    end

    attrs = Map.merge(attrs, %{
      "owner_id" => user.id,
      "created_by_id" => user.id,
      "position" => max_position + 1,
      "is_private" => is_private,
      "is_public" => !is_private,
      "is_user_created" => true
    })

    case Repo.transaction(fn ->
      # Create the channel
      channel = case create_channel(attrs) do
        {:ok, channel} -> channel
        {:error, changeset} -> Repo.rollback(changeset)
      end

      # Auto-create owner membership
      owner_attrs = %{
        channel_id: channel.id,
        user_id: user.id,
        role: "owner",
        joined_at: DateTime.utc_now()
      }

      case create_channel_member(owner_attrs) do
        {:ok, _member} -> channel
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end) do
      {:ok, channel} ->
        Task.start(fn -> Bacon8.Audit.log(user.id, "create_user_channel", "channel", channel.id, %{name: channel.name}) end)
        {:ok, channel}

      other ->
        other
    end
  end

  # Messages
  def list_messages(channel_id, limit \\ 50) do
    from(m in Message,
      join: u in assoc(m, :user),
      where: m.channel_id == ^channel_id,
      where: is_nil(m.reply_to_id),
      where: is_nil(u.role) or u.role != "banned",
      # Load the most recent N messages (desc), then reverse so callers receive
      # chronological order (oldest -> newest). This makes the initial view
      # show the latest window of messages while preserving ascending ordering
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      preload: [
        :user, reactions: :user, thread: [], attachments: :user,
        replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user]]]
      ]
    )
    |> Repo.all()
    |> filter_banned_content()
    # Reverse to get chronological order (oldest -> newest)
    |> Enum.reverse()
  end

  defp filter_banned_content(messages) do
    messages
    |> Enum.filter(fn m -> 
      is_nil(m.user) or is_nil(m.user.role) or m.user.role != "banned"
    end)
    |> Enum.map(fn m ->
      # Filter attachments
      filtered_attachments = Enum.filter(m.attachments || [], fn att ->
        case att do
          %{user_id: nil} -> true
          %{user: u} when not is_nil(u) -> is_nil(u.role) or u.role != "banned"
          _ -> true
        end
      end)
      
      # Recursively filter replies if loaded
      filtered_replies = if Ecto.assoc_loaded?(m.replies) do
        filter_banned_content(m.replies)
      else
        []
      end

      %{m | attachments: filtered_attachments, replies: filtered_replies}
    end)
  end


  @doc "Cursor based pagination: load messages before a given message id (older messages)"
  def list_messages_cursor(channel_id, opts \\ %{}) do
    limit = opts[:limit] || 50
    before_id = opts[:before]

    base_query = from(m in Message,
      join: u in assoc(m, :user),
      where: m.channel_id == ^channel_id,
      where: is_nil(m.reply_to_id),
      where: is_nil(u.role) or u.role != "banned",
      preload: [
        :user, reactions: :user, thread: [], attachments: :user,
        replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user]]]
      ]
    )

    query =
      if before_id do
        case Repo.get(Message, before_id) do
          nil -> from(m in base_query, order_by: [asc: m.inserted_at], limit: ^limit)
          %Message{inserted_at: ts} ->
            from(m in base_query, where: m.inserted_at < ^ts, order_by: [desc: m.inserted_at], limit: ^limit)
        end
      else
        from(m in base_query, order_by: [asc: m.inserted_at], limit: ^limit)
      end

    results = Repo.all(query)

    results = case before_id do
      nil -> results
      _ -> Enum.reverse(results)
    end

    filter_banned_content(results)
  end

  def get_message!(id) do
    Repo.get!(Message, id) |> Repo.preload([
      :user, reactions: :user, thread: [], attachments: :user,
      replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user]]]
    ])
  end

  def get_message(id) do
    Repo.get(Message, id) |> Repo.preload([
      :user, reactions: :user, thread: [], attachments: :user,
      replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user, replies: [:user, reactions: :user, attachments: :user]]]
    ])
  end

  def create_message(user, channel_id, attrs \\ %{}, opts \\ []) do
    # Defensive check - disallow banned users from creating messages
    result = cond do
      user && Map.get(user, :role) == "banned" ->
        {:error, :banned}

      user && not (Map.get(user, :is_admin, false) || user.role in ["admin", "gm", "editor"]) ->
        case Bacon8.RateLimiter.check_and_increment_rate("chat:messages:#{user.id}", 30, 60_000) do
          :ok -> :ok
          {:error, :rate_limited, _reset} -> {:error, :rate_limited}
        end

      true -> :ok
    end

    # Stop early on errors
    if result != :ok do
      result
    else
      # Ensure the channel exists and the user is allowed to post into it
      channel = get_channel(channel_id)

      if is_nil(channel) do
        {:error, :not_found}
      else
        create_message_in(user, channel, channel_id, attrs, opts)
      end
    end
  end

  defp create_message_in(user, channel, channel_id, attrs, opts) do
    if not can_post_in_channel?(user, channel) do
      {:error, :forbidden}
    else
      # Map parent_id to reply_to_id if present
      attrs =
        if Map.has_key?(attrs, :parent_id) do
          Map.put(attrs, :reply_to_id, attrs.parent_id)
        else
          attrs
        end

      # After checks, proceed to create message
      %Message{}
      |> Message.changeset(attrs, opts)
      |> Ecto.Changeset.put_assoc(:user, user)
      |> Ecto.Changeset.put_change(:channel_id, channel_id)
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          # Audit log: message created
          Task.start(fn -> Bacon8.Audit.log(user.id, "create_message", "message", message.id, %{channel_id: channel_id}) end)

          # Process @mentions and create notifications (async)
          Task.start(fn ->
            ChatChannels.Notices.mentions(message, user)
          end)

          # Preload replies (empty) so it's a list, not NotLoaded
          message = Repo.preload(message, [:user, :reactions, :attachments, :replies])
          pubsub_broadcast("channel:#{channel_id}", {:new_message, message})
          {:ok, message}

        error ->
          error
      end
    end
  end

  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Ecto.Changeset.put_change(:edited_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
    |> case do
      {:ok, updated_message} ->
        updated_message = Repo.preload(updated_message, [:user, :reactions, :attachments])
        pubsub_broadcast("channel:#{updated_message.channel_id}", {:message_updated, updated_message})
        {:ok, updated_message}
      error -> error
    end
  end

  def delete_message(%Message{} = message) do
    # Preload attachments so we can clean up files
    message = Repo.preload(message, [:attachments])
    # Repo.all returns the results newest -> oldest (desc), reverse to oldest -> newest
    pubsub_broadcast("channel:#{message.channel_id}", {:message_deleted, message})
    Task.start(fn -> Bacon8.Audit.log(nil, "delete_message", "message", message.id, %{channel_id: message.channel_id}) end)

    # Collect attachment paths for cleanup before deletion
    attachment_paths = message.attachments |> Enum.map(fn att -> att.file end) |> Enum.filter(& &1)

    # Delete DB record (attachments are set to delete_all via migration/associations)
    result = Repo.delete(message)

    # Cleanup files asynchronously via Uploads.delete_file (handles URL->FS mapping)
    if length(attachment_paths) > 0 do
      Task.start(fn ->
        Enum.each(attachment_paths, fn url_path ->
          Bacon8.Uploads.delete_file(url_path)
        end)
      end)
    end

    result
  end

  @doc "Delete a message with permission check for a given user (admins/editors, owner, or channel moderator)."
  def delete_message_by_user(%{id: user_id} = user, %Message{} = message) do
    # Ensure channel is loaded for permission check
    message = Repo.preload(message, :channel)
    channel = message.channel

    can_delete = message.user_id == user_id || 
                 Map.get(user, :is_admin, false) || 
                 user.role in ["admin", "gm", "editor"] ||
                 can_moderate_channel?(user, channel)

    if can_delete do
      delete_message(message)
    else
      {:error, :forbidden}
    end
  end

  @doc "Update a message with permission check for a given user (admins/editors, owner, or channel moderator)."
  def update_message_by_user(%{id: user_id} = user, %Message{} = message, attrs) do
    # Ensure channel is loaded for permission check
    message = Repo.preload(message, :channel)
    channel = message.channel

    # Check if user is banned in this channel
    member = get_channel_member(channel.id, user_id)
    is_banned = member && member.is_banned

    if is_banned do
      {:error, :forbidden}
    else
      can_edit = message.user_id == user_id || 
                 Map.get(user, :is_admin, false) || 
                 user.role in ["admin", "gm", "editor"] ||
                 can_moderate_channel?(user, channel)

      if can_edit do
        update_message(message, attrs)
      else
        {:error, :forbidden}
      end
    end
  end

  @doc "Toggle the pinned status of a message. Only channel moderators/owners can do this."
  def toggle_message_pin(%{id: _user_id} = user, %Message{} = message) do
    message = Repo.preload(message, :channel)
    channel = message.channel

    if can_moderate_channel?(user, channel) do
      new_status = !message.is_pinned
      
      message
      |> Message.changeset(%{is_pinned: new_status})
      |> Repo.update()
      |> case do
        {:ok, updated_message} ->
          updated_message = Repo.preload(updated_message, [:user, :reactions, :attachments])
          pubsub_broadcast("channel:#{message.channel_id}", {:message_updated, updated_message})
          {:ok, updated_message}
        error -> error
      end
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Create a message attachment that belongs to a message and channel.
  Accepts attrs: filename, content_type, file_size, file (url/path), user_id
  """
  def create_message_attachment(%Message{} = message, attrs) do
    attrs = attrs
            |> Map.put("message_id", message.id)
            |> Map.put("channel_id", message.channel_id)

    %ChatChannels.MessageAttachment{}
    |> ChatChannels.MessageAttachment.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, attachment} ->
        # Broadcast message updated so clients can refresh attachments
        updated = get_message!(message.id)
        pubsub_broadcast("channel:#{message.channel_id}", {:message_updated, updated})
        {:ok, attachment}
      error -> error
    end
  end

  def get_attachment!(id) do
    Repo.get!(ChatChannels.MessageAttachment, id) |> Repo.preload([:message, :user, :channel])
  end

  def get_attachment(id) do
    Repo.get(ChatChannels.MessageAttachment, id) |> Repo.preload([:message, :user, :channel])
  end

  def delete_attachment(%ChatChannels.MessageAttachment{} = attachment) do
    # Broadcast update to update message attachments on clients
    message = Repo.preload(attachment, [:message]) |> Map.get(:message)

    # Capture file path/url for deletion
    file_path = attachment.file

    result = Repo.delete(attachment)

    # Cleanup file if exists
    if file_path do
      Task.start(fn -> Bacon8.Uploads.delete_file(file_path) end)
    end

    if message do
      pubsub_broadcast("channel:#{message.channel_id}", {:message_updated, get_message!(message.id)})
    end

    result
  end

  # Reactions
  @doc """
  Toggles a reaction on a message. If the user has already reacted with this emoji,
  the reaction is removed. Otherwise, a new reaction is added.
  """
  @max_reactions_per_user 5

  def toggle_reaction(message, user, emoji) do
    case Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji) do
      nil ->
        # No existing reaction with this emoji - check if user is at limit
        user_reaction_count = count_user_reactions(message.id, user.id)
        
        if user_reaction_count >= @max_reactions_per_user do
          {:error, :limit_reached}
        else
          # Add the reaction
          %Reaction{}
          |> Reaction.changeset(%{message_id: message.id, user_id: user.id, emoji: emoji})
          |> Repo.insert()
          |> case do
            {:ok, reaction} ->
              pubsub_broadcast("channel:#{message.channel_id}", {:reaction_added, reaction})
              {:ok, :added, reaction}
            error -> error
          end
        end
      reaction ->
        # Existing reaction - remove it
        case Repo.delete(reaction) do
          {:ok, deleted_reaction} ->
            pubsub_broadcast("channel:#{message.channel_id}", {:reaction_removed, deleted_reaction})
            {:ok, :removed, deleted_reaction}
          error -> error
        end
    end
  end

  @doc """
  Counts how many reactions a user has on a specific message.
  """
  def count_user_reactions(message_id, user_id) do
    from(r in Reaction,
      where: r.message_id == ^message_id and r.user_id == ^user_id,
      select: count(r.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns the maximum number of reactions allowed per user per message.
  """
  def max_reactions_per_user, do: @max_reactions_per_user

  def add_reaction(message, user, emoji) do
    case Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji) do
      nil ->
        # Check if user is at limit
        user_reaction_count = count_user_reactions(message.id, user.id)
        
        if user_reaction_count >= @max_reactions_per_user do
          {:error, :limit_reached}
        else
          %Reaction{}
          |> Reaction.changeset(%{message_id: message.id, user_id: user.id, emoji: emoji})
          |> Repo.insert()
          |> case do
            {:ok, reaction} ->
              reaction = Repo.preload(reaction, :user)
              pubsub_broadcast("channel:#{message.channel_id}", {:reaction_added, reaction})
              {:ok, reaction}
            error -> error
          end
        end
      reaction ->
        {:ok, reaction}
    end
  end

  def remove_reaction(message, user, emoji) do
    case Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji) do
      nil -> {:error, :not_found}
      reaction ->
        reaction = Repo.preload(reaction, :user)
        pubsub_broadcast("channel:#{message.channel_id}", {:reaction_removed, reaction})
        Repo.delete(reaction)
    end
  end

  @doc """
  Removes all reactions from a user on a specific message.
  Used to enforce one-reaction-per-user policy.
  """
  def remove_all_user_reactions(message, user) do
    from(r in Reaction,
      where: r.message_id == ^message.id and r.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload(:user)
    |> Enum.each(fn reaction ->
      pubsub_broadcast("channel:#{message.channel_id}", {:reaction_removed, reaction})
      Repo.delete(reaction)
    end)
    
    :ok
  end

  # Threads
  def create_thread(message, user, attrs \\ %{}) do
    %Thread{}
    |> Thread.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:message, message)
    |> Ecto.Changeset.put_assoc(:user, user)
    |> Repo.insert()
  end

  def list_thread_messages(thread_id, limit \\ 50) do
    from(m in Message,
      where: m.thread_id == ^thread_id,
      order_by: [asc: m.inserted_at],
      limit: ^limit,
      preload: [:user, :reactions, attachments: :user]
    )
    |> Repo.all()
  end

  # Search
  def search_messages(channel_id, query) do
    search_term = "%#{query}%"
    
    from(m in Message,
      where: m.channel_id == ^channel_id and ilike(m.content, ^search_term),
      order_by: [desc: m.inserted_at],
      limit: 20,
      preload: [:user]
    )
    |> Repo.all()
  end

  def count_messages_in_channel(channel_id) do
    from(m in Message, where: m.channel_id == ^channel_id, select: count())
    |> Repo.one()
  end

  # ============================================
  # User-Created Channels
  # ============================================

  def list_user_owned_channels(user_id) do
    from(c in Channel,
      where: c.owner_id == ^user_id and c.is_user_created == true,
      order_by: [desc: c.inserted_at],
      preload: [:owner, :members]
    )
    |> Repo.all()
  end

  def list_user_member_channels(user_id) do
    from(m in ChatChannels.ChannelMember,
      where: m.user_id == ^user_id,
      join: c in assoc(m, :channel),
      where: c.is_user_created == true,
      preload: [channel: [:owner, :members]],
      order_by: [desc: m.joined_at]
    )
    |> Repo.all()
    |> Enum.map(& &1.channel)
  end

  # Note: use create_user_channel(user, attrs) which creates the channel and owner membership

  # ============================================
  # Channel Members
  # ============================================

  alias ChatChannels.ChannelMember

  def is_channel_member?(channel_id, user_id) do
    Repo.exists?(from m in ChannelMember, where: m.channel_id == ^channel_id and m.user_id == ^user_id)
  end

  def get_channel_member(channel_id, user_id) do
    Repo.get_by(ChannelMember, channel_id: channel_id, user_id: user_id)
  end

  def get_channel_member_by_id(id) do
    Repo.get(ChannelMember, id) |> Repo.preload(:user)
  end

  def create_channel_member(attrs \\ %{}) do
    %ChannelMember{}
    |> ChannelMember.changeset(attrs)
    |> Repo.insert()
  end

  def update_channel_member(%ChannelMember{} = member, attrs) do
    member
    |> ChannelMember.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_member} ->
        # A ban and a removal have to do the same thing to a running world.
        # Reading the RESULT rather than the attrs catches both spellings of
        # is_banned and the role being set to "banned", which is the other way
        # this happens and which the old attrs check missed entirely.
        if updated_member.is_banned or updated_member.role == "banned" do
          pubsub_broadcast("channel:#{member.channel_id}", {:user_banned, member.user_id, member.channel_id})
          Bacon8.Plugins.notify({:channel_member_removed, member.channel_id, member.user_id})
        end

        {:ok, updated_member}
      error -> error
    end
  end

  def list_pinned_messages(channel_id) do
    from(m in Message,
      join: u in assoc(m, :user),
      where: m.channel_id == ^channel_id and m.is_pinned == true,
      where: is_nil(u.role) or u.role != "banned",
      order_by: [desc: m.inserted_at],
      preload: [
        :user, :reactions, :thread, attachments: :user,
        replies: [:user, :reactions, attachments: :user, replies: [:user, :reactions, attachments: :user, replies: [:user, :reactions, attachments: :user]]]
      ]
    )
    |> Repo.all()
    |> filter_banned_content()
  end

  @doc "Mark messages read for a user in a channel (set last_read_message_id and last_seen_at)."
  def mark_channel_messages_read(user_id, channel_id, last_message_id) do
    case get_channel_member(channel_id, user_id) do
      nil -> {:error, :not_member}
      member -> update_channel_member(member, %{last_read_message_id: last_message_id, last_seen_at: DateTime.truncate(DateTime.utc_now(), :second)})
    end
  end

  def remove_channel_member(channel_id, user_id) do
    case get_channel_member(channel_id, user_id) do
      nil -> {:error, :not_found}
      member ->
        case Repo.delete(member) do
          {:ok, deleted_member} ->
            pubsub_broadcast("channel:#{channel_id}", {:user_kicked, user_id, channel_id})

            # AND OUT OF ANYTHING A PLUGIN GATES ON MEMBERSHIP (e.g. a running
            # game world that admits channel members). Removing the
            # membership stops the next join; someone already inside is only
            # removed by this.
            #
            # Deliberately synchronous: this is the security half of the
            # action, and a caller that got {:ok, _} should be able to believe
            # the kick happened.
            Bacon8.Plugins.notify({:channel_member_removed, channel_id, user_id})

            {:ok, deleted_member}
          error -> error
        end
    end
  end

  def list_channel_members(channel_id) do
    # Base members from channel_members table
    members =
      from(m in ChannelMember,
        where: m.channel_id == ^channel_id,
        preload: [:user],
        order_by: [asc: m.joined_at]
      )
      |> Repo.all()

    # Ensure channel owner appears in the list (may not have a ChannelMember row)
    channel = Repo.get(Channel, channel_id)

    owner_member =
      if channel && channel.owner_id do
        owner_present = Enum.any?(members, fn m -> Map.get(m, :user_id) == channel.owner_id end)

        if owner_present do
          []
        else
          case Repo.get(Bacon8.Accounts.User, channel.owner_id) do
            nil -> []
            owner_user ->
              [%ChannelMember{channel_id: channel.id, user_id: owner_user.id, role: "owner", user: owner_user, id: nil, joined_at: channel.inserted_at}]
          end
        end
      else
        []
      end

    # Include any pending channel invites (targeted invitee_id present, not accepted, not revoked)
    pending_invites =
      from(i in ChannelInvite,
        where: i.channel_id == ^channel_id and not i.is_revoked and is_nil(i.accepted_at) and not is_nil(i.invitee_id),
        preload: [:invitee, :inviter]
      )
      |> Repo.all()

    invite_members =
      Enum.map(pending_invites, fn invite ->
        %ChannelMember{channel_id: channel_id, user_id: invite.invitee_id, role: "invited", user: invite.invitee, id: nil, joined_at: invite.inserted_at}
        |> Map.put(:_invite_id, invite.id)
      end)

    members ++ owner_member ++ invite_members
  end

  # Permission helpers
  @doc "Return the role string for a user in a channel (or nil if not a member)."
  def user_role_in_channel(channel_id, user_id) do
    case get_channel_member(channel_id, user_id) do
      nil -> nil
      %ChannelMember{role: role} -> role
    end
  end

  @doc "Returns true if the user can fully manage the channel (owner, channel creator, or site admin)."
  def can_manage_channel?(nil, _channel), do: false
  def can_manage_channel?(%{id: user_id} = user, %Channel{} = channel) do
    is_admin = Map.get(user, :is_admin, false) || Map.get(user, :role) in ["admin", "gm", "editor"]
    is_owner = Map.get(channel, :owner_id) == user_id
    # Removed is_creator check to prevent former owners from retaining control
    # is_creator = Map.get(channel, :created_by_id) == user_id

    cond do
      is_admin -> true
      is_owner -> true
      # is_creator -> true
      true -> user_role_in_channel(channel.id, user_id) == "owner"
    end
  end

  @doc "Returns true if the user can moderate a channel (owner, moderator, or site admin)."
  def can_moderate_channel?(nil, _channel), do: false
  def can_moderate_channel?(%{id: user_id} = user, %Channel{} = channel) do
    is_admin = Map.get(user, :is_admin, false) || Map.get(user, :role) in ["admin", "gm", "editor"]

    cond do
      is_admin -> true
      # the owner on the channel row moderates it even without a member row (can_manage_channel?
      # already lets them manage it, which includes moderating)
      Map.get(channel, :owner_id) == user_id -> true
      true -> user_role_in_channel(channel.id, user_id) in ["owner", "moderator"]
    end
  end

  @doc "Returns true if a user is allowed to post in a channel.
  - Private channels: must be a member and not banned
  - Public channels: disallow site-level 'banned' users"
  def can_post_in_channel?(nil, %Channel{} = channel) do
    # anonymous users cannot post in private channels
    !channel.is_private
  end

  def can_post_in_channel?(%{id: user_id} = user, %Channel{} = channel) do
    # site level ban prevents posting anywhere
    if Map.get(user, :role) == "banned" do
      false
    else
      # Allow admins and staff to post in private channels
      if Map.get(user, :is_admin, false) || Map.get(user, :role) in ["admin", "gm", "editor"] do
        true
      else
        if channel.is_private do
        case get_channel_member(channel.id, user_id) do
          %ChannelMember{is_banned: true} -> false
          %ChannelMember{} -> true
          nil -> false
        end
        else
          # Check for ban in public channel
          case get_channel_member(channel.id, user_id) do
            %ChannelMember{is_banned: true} -> false
            _ -> true
          end
        end
      end
    end
  end

  @doc "Returns true if a user can create invites for a channel.
  Owners and moderators can always invite; members can invite if channel is public/user-created (configurable later)."
  def can_invite_to_channel?(nil, _channel), do: false
  def can_invite_to_channel?(%{id: user_id} = user, %Channel{} = channel) do
    # site admins always can
    is_admin = Map.get(user, :is_admin, false) || Map.get(user, :role) in ["admin", "gm", "editor"]

    cond do
      is_admin -> true
      true ->
        member = get_channel_member(channel.id, user_id)
        cond do
          member == nil -> false
          member.is_banned -> false
          member.role in ["owner", "moderator"] -> true
          # allow regular members to invite to public user-created channels
          member.role == "member" and channel.is_public == true -> true
          true -> false
        end
    end
  end

  # ============================================
  # Channel Invites
  # ============================================

  alias ChatChannels.ChannelInvite

  def create_channel_invite(attrs \\ %{}) do
    %ChannelInvite{}
    |> ChannelInvite.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, invite} -> {:ok, Repo.preload(invite, [:invitee, :inviter, :channel])}
      error -> error
    end
  end

  @doc "Create a personal invite targeted at a specific user (invitee_id)."
  def create_personal_invite(inviter_id, invitee_identifier, channel_id, opts \\ %{}) do
    # Accept either user id (UUID) or username/email. Resolve to user id when possible.
    resolved_invitee_id =
      cond do
        is_binary(invitee_identifier) ->
          # Try as UUID first
          case Ecto.UUID.cast(invitee_identifier) do
            {:ok, uuid} -> uuid
            :error ->
              # Try resolving by username or email via Accounts
              case Bacon8.Accounts.get_user_by_email_or_username(invitee_identifier) do
                nil -> nil
                user -> user.id
              end
          end
        is_nil(invitee_identifier) -> nil
        true -> nil
      end

    if resolved_invitee_id == nil do
      {:error, :invitee_not_found}
    else
      # Check if user is already a member
      if get_channel_member(channel_id, resolved_invitee_id) do
        {:error, :already_member}
      else
        # Check if there's already a pending invite
        existing_invite = from(i in ChannelInvite,
          where: i.inviter_id == ^inviter_id,
          where: i.invitee_id == ^resolved_invitee_id,
          where: i.channel_id == ^channel_id,
          where: is_nil(i.accepted_at),
          where: i.is_revoked == false,
          where: is_nil(i.revoked_at),
          limit: 1
        ) |> Repo.one()

        if existing_invite do
          {:error, :invite_already_pending}
        else
          # Check if invitee can receive invites
          invitee = Bacon8.Accounts.get_user(resolved_invitee_id)
          
          if invitee && !can_receive_invite?(invitee, inviter_id) do
            {:error, :invitee_blocked_invites}
          else
            attrs = Map.merge(%{inviter_id: inviter_id, invitee_id: resolved_invitee_id, channel_id: channel_id}, opts)
            create_channel_invite(attrs)
          end
        end
      end
    end
  end

  def get_invite_by_code(code) do
    Repo.get_by(ChannelInvite, code: code)
    |> Repo.preload([:channel, :inviter])
  end

  def use_channel_invite(code, user_id) do
    case get_invite_by_code(code) do
      nil ->
        {:error, :invalid_invite}
      
      invite ->
        # Ensure invite is still valid for use
        if invite.is_revoked == true || (!!invite.revoked_at) do
          {:error, :invite_revoked}
        else
          if ChannelInvite.is_valid?(invite) do
            # If invite is targeted to a specific invitee, verify the caller
            if invite.invitee_id && invite.invitee_id != user_id do
              {:error, :invite_not_for_user}
            else
              # Check if already a member
              if is_channel_member?(invite.channel_id, user_id) do
                {:error, :already_member}
              else
                Repo.transaction(fn ->
                  # Add user as member
                  case create_channel_member(%{
                    channel_id: invite.channel_id,
                    user_id: user_id,
                    role: "member"
                  }) do
                    {:ok, member} ->
                      # Increment invite usage
                      invite
                      |> Ecto.Changeset.change(uses: invite.uses + 1)
                      |> Repo.update!()
                      # Mark accepted timestamp when invite is personal
                      if invite.invitee_id do
                        invite
                        |> ChannelInvite.accept()
                        |> Repo.update!()
                      end
                      
                      member
                    
                    {:error, changeset} ->
                      Repo.rollback(changeset)
                  end
                end)
              end
            end
          else
            {:error, :invite_expired}
          end
        end
    end
  end

  @doc "Accept a channel invite by ID (used for personal invites). Returns {:ok, member} or {:error, reason}."
  def accept_channel_invite(invite_id, user_id) do
    case Repo.get(ChannelInvite, invite_id) do
      nil -> {:error, :not_found}
      invite ->
        if invite.is_revoked || (invite.invitee_id && invite.invitee_id != user_id) do
          {:error, :forbidden}
        else
          if ChannelInvite.is_valid?(invite) do
            # Check if already a member
            if is_channel_member?(invite.channel_id, user_id) do
              # Mark invite as accepted even though already member
              invite
              |> Ecto.Changeset.change(uses: invite.uses + 1)
              |> ChannelInvite.accept()
              |> Repo.update()
              {:error, :already_member}
            else
              Repo.transaction(fn ->
                case create_channel_member(%{channel_id: invite.channel_id, user_id: user_id, role: "member"}) do
                  {:ok, member} ->
                    invite
                    |> Ecto.Changeset.change(uses: invite.uses + 1)
                    |> ChannelInvite.accept()
                    |> Repo.update!()
                    member

                  {:error, changeset} -> Repo.rollback(changeset)
                end
              end)
            end
          else
            {:error, :invite_expired}
          end
        end
    end
  end

  @doc "Revoke a channel invite. Only the inviter, channel owner, or site admins can revoke." 
  def revoke_channel_invite(%{id: user_id} = user, invite_id) do
    case Repo.get(ChannelInvite, invite_id) do
      nil -> {:error, :not_found}
      invite ->
        # Permission check: inviter, channel owner or site admin
        channel = get_channel!(invite.channel_id)
        is_admin = Map.get(user, :is_admin, false) || Map.get(user, :role) in ["admin", "gm", "editor"]

        if invite.inviter_id == user_id || channel.owner_id == user_id || is_admin do
          invite
          |> ChannelInvite.revoke()
          |> Repo.update()
        else
          {:error, :forbidden}
        end
    end
  end

  @doc "Transfer ownership of a channel to a new owner. Only owners, channel creator or site admins can transfer."
  def transfer_channel_ownership(%{id: user_id} = user, %Channel{} = channel, new_owner_id) do
    # Permission: must be current owner, creator, or admin
    is_admin = Map.get(user, :is_admin, false) || Map.get(user, :role) in ["admin", "gm", "editor"]
    allowed = is_admin || channel.owner_id == user_id || channel.created_by_id == user_id

    if not allowed do
      {:error, :forbidden}
    else
      Repo.transaction(fn ->
        # Update channel owner_id
        case update_channel(channel, %{owner_id: new_owner_id}) do
          {:ok, updated_channel} ->
            # Demote previous owner member role (if present and different)
            if channel.owner_id && channel.owner_id != new_owner_id do
              case get_channel_member(channel.id, channel.owner_id) do
                nil -> :ok
                member -> update_channel_member(member, %{role: "member"})
              end
            end

            # Promote new owner to member-owner role
            case get_channel_member(channel.id, new_owner_id) do
              nil -> create_channel_member(%{channel_id: channel.id, user_id: new_owner_id, role: "owner"})
              member -> update_channel_member(member, %{role: "owner"})
            end

            updated_channel

          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  # ============================================
  # Streaming Sessions
  # ============================================

  alias ChatChannels.StreamingSession

  def start_stream(attrs \\ %{}) do
    %StreamingSession{}
    |> StreamingSession.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, session} ->
        pubsub_broadcast("channel:#{session.channel_id}", {:stream_started, session})
        {:ok, session}
      error -> error
    end
  end

  def end_stream(session_id) do
    case Repo.get(StreamingSession, session_id) do
      nil -> {:error, :not_found}
      session ->
        session
        |> StreamingSession.changeset(%{is_active: false, ended_at: DateTime.truncate(DateTime.utc_now(), :second)})
        |> Repo.update()
        |> case do
          {:ok, updated_session} ->
            pubsub_broadcast("channel:#{session.channel_id}", :stream_ended)
            {:ok, updated_session}
          error -> error
        end
    end
  end

  def get_active_stream(channel_id) do
    from(s in StreamingSession,
      where: s.channel_id == ^channel_id and s.is_active == true,
      preload: [:streamer],
      limit: 1
    )
    |> Repo.one()
  end

  def update_stream_viewer_count(session_id, count) do
    case Repo.get(StreamingSession, session_id) do
      nil -> {:error, :not_found}
      session ->
        session
        |> StreamingSession.changeset(%{viewer_count: count})
        |> Repo.update()
    end
  end

  # Wrapper to broadcast locally (Phoenix.PubSub) and to Redis-based pubsub when enabled
  defp pubsub_broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Bacon8.PubSub, topic, message)
    if Application.get_env(:bacon8, :enable_redis, false) do
      Bacon8.RedisPubSub.publish(topic, message)
    else
      :ok
    end
  end

  # Invite Management Functions
  
  @doc "Get all pending invites for a user (not accepted, not expired, not revoked)"
  def list_pending_invites_for_user(user_id) do
    from(i in ChannelInvite,
      where: i.invitee_id == ^user_id,
      where: is_nil(i.accepted_at),
      where: i.is_revoked == false,
      where: is_nil(i.revoked_at),
      where: is_nil(i.expires_at) or i.expires_at > ^DateTime.utc_now(),
      where: is_nil(i.max_uses) or i.uses < i.max_uses,
      order_by: [desc: i.inserted_at],
      preload: [:channel, :inviter]
    )
    |> Repo.all()
  end

  @doc "Count pending invites for a user (for notification badge)"
  def count_pending_invites(user_id) do
    from(i in ChannelInvite,
      where: i.invitee_id == ^user_id,
      where: is_nil(i.accepted_at),
      where: i.is_revoked == false,
      where: is_nil(i.revoked_at),
      where: is_nil(i.expires_at) or i.expires_at > ^DateTime.utc_now(),
      where: is_nil(i.max_uses) or i.uses < i.max_uses,
      select: count(i.id)
    )
    |> Repo.one()
  end

  @doc "Decline/ignore an invite (marks as revoked so user doesn't see it again)"
  def decline_invite(invite_id, user_id) do
    case Repo.get(ChannelInvite, invite_id) do
      nil -> {:error, :not_found}
      invite ->
        if invite.invitee_id == user_id do
          invite
          |> ChannelInvite.revoke()
          |> Repo.update()
        else
          {:error, :forbidden}
        end
    end
  end

  @doc "Check rate limiting: prevent users from sending too many invites in a short period"
  def can_send_invite?(inviter_id) do
    # Count invites sent in last hour
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-1, :hour)
    
    count = from(i in ChannelInvite,
      where: i.inviter_id == ^inviter_id,
      where: i.inserted_at > ^one_hour_ago,
      select: count(i.id)
    )
    |> Repo.one()
    
    # Limit to 10 invites per hour
    count < 10
  end

  @doc "Check if a user can be invited (not blocked, has invites enabled)"
  def can_receive_invite?(invitee, inviter_id) do
    # Check if invites are enabled
    invites_enabled = allow_invites?(Map.get(invitee, :id))
    
    # Check if inviter is blocked
    blocked_ids = Map.get(invitee, :blocked_user_ids, [])
    not_blocked = inviter_id not in blocked_ids
    
    invites_enabled && not_blocked
  end

  @doc "Get shareable invite link for a channel invite code"
  def get_invite_link(code) do
    # (ChatChannelsWeb.InviteLive is the page at this address.)
    "/chat/invite/#{code}"
  end

  # Custom Emojis
  alias ChatChannels.CustomEmoji

  @doc "List all custom emojis"
  def list_custom_emojis do
    from(e in CustomEmoji, order_by: [asc: e.category, asc: e.shortcode])
    |> Repo.all()
  end

  @doc "Get a custom emoji by shortcode"
  def get_custom_emoji_by_shortcode(shortcode) do
    Repo.get_by(CustomEmoji, shortcode: shortcode)
  end

  @doc "Get a custom emoji by id"
  def get_custom_emoji!(id) do
    Repo.get!(CustomEmoji, id)
  end

  @doc "Create a custom emoji (Admin/GM/Editor only)"
  def create_custom_emoji(user, attrs) do
    if can_manage_emojis?(user) do
      %CustomEmoji{}
      |> CustomEmoji.changeset(Map.put(attrs, :created_by_id, user.id))
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  @doc "Update a custom emoji"
  def update_custom_emoji(user, %CustomEmoji{} = emoji, attrs) do
    if can_manage_emojis?(user) do
      emoji
      |> CustomEmoji.changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc "Delete a custom emoji"
  def delete_custom_emoji(user, %CustomEmoji{} = emoji) do
    if can_manage_emojis?(user) do
      Repo.delete(emoji)
    else
      {:error, :unauthorized}
    end
  end

  @doc "Check if user can manage custom emojis"
  def can_manage_emojis?(nil), do: false
  def can_manage_emojis?(user) do
    Map.get(user, :is_admin, false) || user.role in ["admin", "gm", "editor"]
  end
end
