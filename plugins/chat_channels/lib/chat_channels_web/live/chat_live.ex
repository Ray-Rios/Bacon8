defmodule ChatChannelsWeb.ChatLive do
  use Bacon8Web, :live_view
  require Logger
  alias Phoenix.PubSub
  import ChatChannelsWeb.ChatComponents

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user do
      # Get all channels - needed for both static and live render
      all_channels = ChatChannels.list_channels()
      
      # Split channels strictly by is_private flag
      {public_channels, all_private_channels_unfiltered} = Enum.split_with(all_channels, fn ch ->
        !ch.is_private
      end)
      
      # For private channels, filter to only those the user can access
      visible_private_channels = Enum.filter(all_private_channels_unfiltered, fn ch ->
        can_access_channel?(ch, user)
      end)
      
      # Sort channels based on user preference
      {public_channels, all_private_channels} = sort_channels(public_channels, visible_private_channels, user)
      
      # Default channel should be first public or first private accessible
      default_channel = List.first(public_channels) || List.first(all_private_channels) || ChatChannels.get_or_create_default_channel()

      # Only subscribe to PubSub when connected (not in static render)
      # Note: user_sessions disconnect is handled by UserAuth.on_mount hook
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Bacon8.PubSub, "chat:channels")
      end

      socket = assign(socket,
        public_channels: public_channels,
        private_channels: all_private_channels,
        current_channel: default_channel,
        pinned_messages: [],
        current_message: "",
        online_users: [],
        pending_invites: ChatChannels.list_pending_invites_for_user(user.id),
        allow_invites: ChatChannels.allow_invites?(user.id),
        last_read_message_id: nil,
        last_seen_at: nil,
        typing_users: MapSet.new(),
        show_create_channel_form: false,
        creating_user_channel: false,
        channel_form: to_form(ChatChannels.change_channel(%ChatChannels.Channel{})),
        page_title: "Chat - #{default_channel.name}",
        can_moderate: ChatChannels.can_moderate_channel?(user, default_channel),
        show_channel_modal: false,
        editing_channel: nil,
        message_attachments: [],
        show_attachments: false,
        active_stream: nil,
        show_delete_channel_confirm: false,
        editing_message_id: nil,
        editing_message_content: "",
        replying_to_message_id: nil,
        reply_message_content: "",
        can_create_more_channels: length(visible_private_channels) < 5,
        show_image_viewer: false,
        viewer_image_url: nil,
        viewer_image_filename: nil,
        show_invite_modal: false,
        tracked_channel_id: nil,
        auto_scroll_enabled: true,
        sidebar_open: true,
        loading: not connected?(socket)
      )
      |> stream(:messages, [], dom_id: fn m -> "messages-#{m.id}" end)
      |> allow_upload(:forum_attachment,
        accept: ~w(.jpg .jpeg .png .gif .webp .pdf .mp4 .webm .mov .avi .mp3 .wav .ogg .m4a .flac .zip .tar .gz),
        max_entries: 5,
        max_file_size: 100_000_000,
        auto_upload: true
      )
      |> allow_upload(:reply_attachment,
        accept: ~w(.jpg .jpeg .png .gif .webp .pdf .mp4 .webm .mov .avi .mp3 .wav .ogg .m4a .flac .zip .tar .gz),
        max_entries: 5,
        max_file_size: 100_000_000,
        auto_upload: true
      )
      |> allow_upload(:edit_attachment,
        accept: ~w(.jpg .jpeg .png .gif .webp .pdf .mp4 .webm .mov .avi .mp3 .wav .ogg .m4a .flac .zip .tar .gz),
        max_entries: 5,
        max_file_size: 100_000_000,
        auto_upload: true
      )
      |> allow_upload(:channel_icon,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 5_000_000,
        auto_upload: true,
        progress: &handle_channel_icon_progress/3
      )

      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/login")}
    end
  end

  @impl true
  def handle_params(%{"channel_id" => channel_id}, _uri, socket) do
    # Skip heavy work in disconnected state - mount will re-run when connected
    if not connected?(socket) do
      {:noreply, assign(socket, loading: true)}
    else
      channel = ChatChannels.get_channel!(channel_id)
      user = socket.assigns.current_user
      
      # Check if user has access to this channel
      has_access = can_access_channel?(channel, user)
      
      if has_access do
        messages = ChatChannels.list_messages(channel_id)
        # populate last_read_message_id if we have a channel membership record
        last_read = case ChatChannels.get_channel_member(channel_id, user && user.id) do
          %_{} = m -> m.last_read_message_id
          _ -> nil
        end
        active_stream = ChatChannels.get_active_stream(channel_id)
        
        # Handle channel switching and presence tracking
        # Only unsubscribe if we are tracking a DIFFERENT channel
        if socket.assigns[:tracked_channel_id] && socket.assigns.tracked_channel_id != channel.id do
          PubSub.unsubscribe(Bacon8.PubSub, "channel:#{socket.assigns.tracked_channel_id}")
          PubSub.unsubscribe(Bacon8.PubSub, "presence:channel:#{socket.assigns.tracked_channel_id}")
          Bacon8Web.Presence.untrack(self(), "presence:channel:#{socket.assigns.tracked_channel_id}", to_string(user.id))
        end
        
        # Subscribe to new channel if not already tracked
        if socket.assigns[:tracked_channel_id] != channel.id do
          PubSub.subscribe(Bacon8.PubSub, "channel:#{channel_id}")
          PubSub.subscribe(Bacon8.PubSub, "presence:channel:#{channel_id}")

          if user do
            Logger.info("handle_params tracking presence for user #{user.id} in channel #{channel_id}")
            case Bacon8Web.Presence.track(self(), "presence:channel:#{channel_id}", to_string(user.id), %{
              name: user.name || user.email,
              email: user.email,
              avatar_url: user.avatar_url,
              avatar_color: user.avatar_color,
              avatar_shape: user.avatar_shape,
              avatar_opacity: user.avatar_opacity,
              role: user.role,
              bio: Map.get(user, :bio),
              inserted_at: user.inserted_at,
              online_at: DateTime.utc_now()
            }) do
              {:ok, _} -> Logger.info("Successfully tracked user #{user.id}")
              {:error, reason} -> Logger.error("Failed to track user #{user.id}: #{inspect(reason)}")
            end
          end
        end

        # Refresh presence list for new channel
        presences = Bacon8Web.Presence.list("presence:channel:#{channel_id}")
        Logger.info("handle_params presences for channel #{channel_id}: #{inspect(Map.keys(presences))}")
        online_users = Enum.map(presences, fn {uid, meta} ->
          metas = Map.get(meta, :metas, [])
          latest = List.last(metas) || %{}
          Map.put(latest, :id, uid)
        end)
        
        can_moderate = ChatChannels.can_moderate_channel?(user, channel)
        pinned_messages = ChatChannels.list_pinned_messages(channel.id)

        {:noreply, 
         socket
         |> assign(
          current_channel: channel,
          tracked_channel_id: channel.id,
          pinned_messages: pinned_messages,
          last_read_message_id: last_read,
          active_stream: active_stream,
          page_title: "Chat - #{channel.name}",
          online_users: online_users,
          can_moderate: can_moderate,
          loading: false
        )
        |> stream(:messages, messages, reset: true, dom_id: fn m -> "messages-#{m.id}" end)}
      else
        # User doesn't have access - redirect to general channel
        general_channel = ChatChannels.get_or_create_default_channel()
        
        socket = socket
          |> put_flash(:error, "You don't have access to that channel")
          |> push_navigate(to: "/chat/#{general_channel.id}")
        
        {:noreply, socket}
      end
    end
  end

  def handle_params(_params, _uri, socket) do
    # Skip heavy work in disconnected state
    if not connected?(socket) do
      {:noreply, assign(socket, loading: true)}
    else
      if socket.assigns[:current_channel] do
        channel = socket.assigns.current_channel
        messages = ChatChannels.list_messages(channel.id)
        pinned_messages = ChatChannels.list_pinned_messages(channel.id)
        
        # Subscribe to channel updates and presence updates if not already tracked
        if socket.assigns[:tracked_channel_id] != channel.id do
          PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")
          PubSub.subscribe(Bacon8.PubSub, "presence:channel:#{channel.id}")

          if socket.assigns.current_user do
            user = socket.assigns.current_user
            case Bacon8Web.Presence.track(self(), "presence:channel:#{channel.id}", to_string(user.id), %{
              name: user.name || user.email,
              email: user.email,
              avatar_url: user.avatar_url,
              avatar_color: user.avatar_color,
              avatar_shape: user.avatar_shape,
              avatar_opacity: user.avatar_opacity,
              role: user.role,
              bio: Map.get(user, :bio),
              inserted_at: user.inserted_at,
              online_at: DateTime.utc_now()
            }) do
              {:ok, _} -> Logger.info("Successfully tracked user #{user.id}")
              {:error, reason} -> Logger.error("Failed to track user #{user.id}: #{inspect(reason)}")
            end
          end
        end
        
        last_read = case ChatChannels.get_channel_member(channel.id, socket.assigns.current_user && socket.assigns.current_user.id) do
          %_{} = m -> m.last_read_message_id
          _ -> nil
        end

        # Fetch online users with full avatar info
        presences = Bacon8Web.Presence.list("presence:channel:#{channel.id}")
        online_users = Enum.map(presences, fn {user_id, meta} ->
          metas = Map.get(meta, :metas, [])
          latest = List.last(metas) || %{}
          Map.merge(latest, %{id: user_id})
        end)

        {:noreply, 
         socket
         |> assign( 
          pinned_messages: pinned_messages, 
          last_read_message_id: last_read, 
          online_users: online_users,
          tracked_channel_id: channel.id,
          can_moderate: ChatChannels.can_moderate_channel?(socket.assigns.current_user, channel),
          loading: false
        )
        |> stream(:messages, messages, reset: true, dom_id: fn m -> "messages-#{m.id}" end)}
      else
        {:noreply, assign(socket, loading: false)}
      end
    end
  end

  @impl true
  def handle_event("typing", _params, socket) do
    # TODO: Implement typing indicators
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    # Push event to client-side hook to toggle sidebar
    {:noreply, push_event(socket, "toggle_sidebar", %{})}
  end

  @impl true
  def handle_event("send_message", %{"message" => content} = _params, socket) when content != "" do
    require Logger
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    # Re-fetch user from database to check for ban status (socket user might be stale)
    fresh_user = Bacon8.Accounts.get_user(user.id)
    
    # Check if user has been banned or disabled since page load
    if fresh_user == nil or fresh_user.status != "active" or fresh_user.role == "banned" do
      Logger.info("Blocked message from banned/disabled user #{user.id}")
      {:noreply, 
       socket
       |> put_flash(:error, "Your account has been suspended.")
       |> redirect(to: "/auth/logout")}
    else
      # Debug logging
      Logger.info("User attempting to send message - is_admin: #{inspect(Map.get(user, :is_admin))}, role: #{inspect(Map.get(user, :role))}, channel is_private: #{channel.is_private}")

      # Check if user has access to post in this channel
      if !can_access_channel?(channel, fresh_user) do
        Logger.warning("User #{user.id} denied access to channel #{channel.id}")
        {:noreply, put_flash(socket, :error, "You don't have permission to post in this channel.")}
      else
      # 1. Create the message record first so we have a message id to attach files under
      case ChatChannels.create_message(user, channel.id, %{content: content}) do
        {:ok, message} ->
          # 2. Process uploaded files and attach them to the created message
          # Note: consume_uploaded_entries requires {:ok, value} or {:postpone, value} return
          # So we wrap errors in {:ok, {:error, reason}} and filter them later
          results = consume_uploaded_entries(socket, :forum_attachment, fn %{path: path}, entry ->
            case Bacon8.Files.check_storage_limit(user, entry.client_size) do
              :ok ->
                context = "forum/#{channel.id}/messages/#{message.id}"
                case Bacon8.Uploads.upload_file(user, path, entry, context: context) do
                  {:ok, url_path} ->
                    # Create message attachment (channel_id is populated inside helper)
                    case ChatChannels.create_message_attachment(message, %{
                      "filename" => entry.client_name,
                      "content_type" => entry.client_type,
                      "file_size" => entry.client_size,
                      "file" => url_path,
                      "user_id" => user.id
                    }) do
                      {:ok, attachment} -> {:ok, {:success, attachment}}
                      {:error, reason} -> {:ok, {:error, reason}}
                    end

                  {:error, reason} ->
                    {:ok, {:error, reason}}
                end
              {:error, reason} ->
                {:ok, {:error, reason}}
            end
          end)

          # Check for errors (wrapped in {:error, reason} inside the result)
          upload_errors = Enum.filter(results, fn
            {:error, _} -> true
            _ -> false
          end)

          socket = if Enum.empty?(upload_errors) do
            socket
            |> assign(current_message: "")
            |> push_event("clear_input", %{id: "chat-input-textarea"})
          else
            # Extract first error message for display
            error_msg = case List.first(upload_errors) do
              {:error, reason} when is_binary(reason) -> reason
              {:error, reason} -> inspect(reason)
              _ -> "Unknown upload error"
            end
            put_flash(socket, :error, "Upload failed: #{error_msg}")
            |> assign(current_message: "")
            |> push_event("clear_input", %{id: "chat-input-textarea"})
          end

          {:noreply, socket}

        {:error, :rate_limited} ->
          {:noreply, put_flash(socket, :error, "You're sending messages too quickly — slow down a bit.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
      end
    end
  end

  def handle_event("send_message", _params, socket) do
    # Handle case where message is empty but files are attached
    # If files are attached, we should allow sending even if text is empty
    # But we need to create a message with empty content first
    
    if length(socket.assigns.uploads.forum_attachment.entries) > 0 do
       handle_event("send_message", %{"message" => " "}, socket)
    else
       {:noreply, socket}
    end
  end

  def handle_event("send_reply", params, socket) do
    content = params["content"] || ""
    reply_to_id = params["reply_to_id"]

    # Check for pending uploads
    if Enum.any?(socket.assigns.uploads.reply_attachment.entries, fn entry -> !entry.done? end) do
      {:noreply, put_flash(socket, :error, "Please wait for files to finish uploading.")}
    else
      user = socket.assigns.current_user
      channel = socket.assigns.current_channel

      # Allow empty content if files are attached
      has_uploads = length(socket.assigns.uploads.reply_attachment.entries) > 0
      
      if content == "" && !has_uploads do
        {:noreply, socket}
      else
        content = if content == "" && has_uploads, do: " ", else: content
        
        if user && Map.get(user, :role) == "banned" do
          {:noreply, put_flash(socket, :error, "You are banned from posting messages.")}
        else
          if !can_access_channel?(channel, user) do
            {:noreply, put_flash(socket, :error, "You don't have permission to post in this channel.")}
          else
            # Check if user has already replied to this message
            # We need to fetch the parent message to check its replies
            case ChatChannels.get_message(reply_to_id) do
              nil ->
                {:noreply, put_flash(socket, :error, "Message you are replying to no longer exists.")}
              parent_message ->
                has_replied = Enum.any?(parent_message.replies || [], fn r -> r.user_id == user.id end)

                if has_replied do
                  {:noreply, put_flash(socket, :error, "You have already replied to this message.")}
                else
                  case ChatChannels.create_message(user, channel.id, %{content: content, parent_id: reply_to_id}) do
                    {:ok, message} ->
                      # Process uploaded files for reply
                      # Note: consume_uploaded_entries requires {:ok, value} return
                      consume_uploaded_entries(socket, :reply_attachment, fn %{path: path}, entry ->
                        context = "forum/#{channel.id}/messages/#{message.id}"
                        case Bacon8.Uploads.upload_file(user, path, entry, context: context) do
                          {:ok, url_path} ->
                            case ChatChannels.create_message_attachment(message, %{
                              "filename" => entry.client_name,
                              "content_type" => entry.client_type,
                              "file_size" => entry.client_size,
                              "file" => url_path,
                              "user_id" => user.id
                            }) do
                              {:ok, attachment} -> {:ok, {:success, attachment}}
                              {:error, reason} -> {:ok, {:error, reason}}
                            end
                          {:error, reason} -> {:ok, {:error, reason}}
                        end
                      end)
                      
                      # Re-fetch message to get attachments
                      message = case ChatChannels.get_message(message.id) do
                        nil -> message
                        msg -> msg
                      end
                      
                      # Refresh the root message to update the UI
                      root_id = get_root_message_id(message)
                      socket = refresh_message(socket, root_id)
                      
                      {:noreply, 
                       socket 
                       |> assign(replying_to_message_id: nil, reply_message_content: "")
                       |> put_flash(:info, "Reply sent")}
                    {:error, :rate_limited} ->
                      {:noreply, put_flash(socket, :error, "You're sending messages too quickly.")}
                    {:error, _} ->
                      {:noreply, put_flash(socket, :error, "Failed to send reply")}
                  end
                end
            end
          end
        end
      end
    end
  end

  def handle_event("update_message", %{"message" => message}, socket) do
    # Broadcast typing indicator
    if String.length(message) > 0 do
      PubSub.broadcast(Bacon8.PubSub, "channel:#{socket.assigns.current_channel.id}", 
        {:user_typing, socket.assigns.current_user.id})
    end
    
    {:noreply, assign(socket, current_message: message)}
  end

  def handle_event("start_reply", %{"message_id" => message_id}, socket) do
    old_id = socket.assigns.replying_to_message_id
    
    socket = 
      socket
      |> assign(replying_to_message_id: message_id)
      |> refresh_message(old_id)
      |> refresh_message(message_id)
      
    {:noreply, socket}
  end

  def handle_event("cancel_reply", _params, socket) do
    old_id = socket.assigns.replying_to_message_id
    
    socket = 
      socket
      |> assign(replying_to_message_id: nil)
      |> refresh_message(old_id)
      
    {:noreply, socket}
  end



  # Open message inline edit
  def handle_event("start_edit_message", %{"message_id" => message_id}, socket) do
    old_id = socket.assigns.editing_message_id
    
    case ChatChannels.get_message(message_id) do
      nil -> 
        {:noreply, put_flash(socket, :error, "Message not found")}
      message ->
        socket = 
          socket
          |> assign(editing_message_id: message_id, editing_message_content: message.content)
          |> refresh_message(old_id)
          |> refresh_message(message_id)
          
        {:noreply, socket}
    end
  end

  # Apply edited content
  def handle_event("apply_edit_message", params, socket) do
    message_id = params["message_id"]
    content = params["content"] || ""

    # Check for pending uploads
    if Enum.any?(socket.assigns.uploads.edit_attachment.entries, fn entry -> !entry.done? end) do
      {:noreply, put_flash(socket, :error, "Please wait for files to finish uploading.")}
    else
      case ChatChannels.get_message(message_id) do
        nil -> 
          {:noreply, put_flash(socket, :error, "Message not found")}
        message ->
          user = socket.assigns.current_user
          channel = socket.assigns.current_channel

          # Allow empty content if files are attached
          has_uploads = length(socket.assigns.uploads.edit_attachment.entries) > 0
          content = if content == "" && has_uploads, do: " ", else: content

          case ChatChannels.update_message_by_user(user, message, %{content: content}) do
            {:ok, updated_message} ->
              # Process uploaded files for edit
              # Note: consume_uploaded_entries requires {:ok, value} return
              consume_uploaded_entries(socket, :edit_attachment, fn %{path: path}, entry ->
                context = "forum/#{channel.id}/messages/#{updated_message.id}"
                case Bacon8.Uploads.upload_file(user, path, entry, context: context) do
                  {:ok, url_path} ->
                    case ChatChannels.create_message_attachment(updated_message, %{
                      "filename" => entry.client_name,
                      "content_type" => entry.client_type,
                      "file_size" => entry.client_size,
                      "file" => url_path,
                      "user_id" => user.id
                    }) do
                      {:ok, attachment} -> {:ok, {:success, attachment}}
                      {:error, reason} -> {:ok, {:error, reason}}
                    end
                  {:error, reason} -> {:ok, {:error, reason}}
                end
              end)
              
              # Re-fetch message to get attachments
              updated_message = case ChatChannels.get_message(updated_message.id) do
                nil -> updated_message # Should not happen, but fallback to current struct
                msg -> msg
              end
              
              # Refresh the root message to update the UI
              root_id = get_root_message_id(updated_message)
              socket = refresh_message(socket, root_id)
              
              socket = 
                socket 
                |> assign(editing_message_id: nil, editing_message_content: "") 
                |> put_flash(:info, "Message updated")
              
              {:noreply, socket}

            {:error, :forbidden} ->
              {:noreply, put_flash(socket, :error, "You don't have permission to edit this message")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to update message")}
          end
      end
    end
  end
  
  def handle_event("cancel_edit", _params, socket) do
    old_id = socket.assigns.editing_message_id
    
    socket = 
      socket
      |> assign(editing_message_id: nil, editing_message_content: "")
      |> refresh_message(old_id)
      
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_invites", _params, socket) do
    {:ok, allow?} = ChatChannels.set_allow_invites(socket.assigns.current_user.id, !socket.assigns.allow_invites)
    {:noreply, assign(socket, allow_invites: allow?)}
  end

  def handle_event("toggle_auto_scroll", %{"enabled" => enabled}, socket) do
    new_state = enabled == "true"
    {:noreply, assign(socket, auto_scroll_enabled: new_state)}
  end

  def handle_event("toggle_auto_scroll", _params, socket) do
    new_state = !socket.assigns.auto_scroll_enabled
    {:noreply, assign(socket, auto_scroll_enabled: new_state)}
  end

  def handle_event("toggle_pin", %{"message_id" => message_id}, socket) do
    case ChatChannels.get_message(message_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Message not found")}
        
      message ->
        # Don't allow pinning replies - only top-level messages can be pinned
        if message.reply_to_id != nil and not message.is_pinned do
          {:noreply, put_flash(socket, :error, "Replies cannot be pinned. Pin the original message instead.")}
        else
          user = socket.assigns.current_user

          case ChatChannels.toggle_message_pin(user, message) do
            {:ok, updated_message} ->
              status = if updated_message.is_pinned, do: "pinned", else: "unpinned"
              {:noreply, put_flash(socket, :info, "Message #{status}")}
            
            {:error, :forbidden} ->
              {:noreply, put_flash(socket, :error, "Permission denied")}
              
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update pin status")}
          end
        end
    end
  end

  def handle_event("delete_message", %{"message_id" => message_id}, socket) do
    case ChatChannels.get_message(message_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Message not found")}
      message ->
        user = socket.assigns.current_user
        
        # Delegate permission check and deletion to the context
        case ChatChannels.delete_message_by_user(user, message) do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Message deleted")}
          {:error, :forbidden} ->
            {:noreply, put_flash(socket, :error, "You don't have permission to delete this message")}
          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete message")}
        end
    end
  end

  def handle_event("toggle_reaction", %{"message_id" => message_id, "emoji" => emoji}, socket) do
    case ChatChannels.get_message(message_id) do
      nil ->
        {:noreply, socket}
      message ->
        user = socket.assigns.current_user
        
        # Toggle reaction - allows up to 5 different emoji reactions per user per message
        case ChatChannels.toggle_reaction(message, user, emoji) do
          {:error, :limit_reached} ->
            {:noreply, put_flash(socket, :error, "You can only add up to 5 reactions per message. Remove one to add another.")}
          _ ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("delete_attachment", %{"attachment_id" => attachment_id}, socket) do
    user = socket.assigns.current_user
    
    case ChatChannels.get_attachment(attachment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Attachment not found")}
        
      attachment ->
        # attachment already preloaded by ChatChannels.get_attachment
        can_delete = attachment.user_id == user.id || (attachment.message && attachment.message.user_id == user.id) || user.role in ["admin", "gm", "editor"] || Map.get(user, :is_admin, false)

        if can_delete do
          case ChatChannels.delete_attachment(attachment) do
            {:ok, _} -> {:noreply, put_flash(socket, :info, "Attachment deleted")}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete attachment")}
          end
        else
          {:noreply, put_flash(socket, :error, "You don't have permission to delete this attachment")}
        end
    end
  end

  def handle_event("toggle_create_channel", _params, socket) do
    {:noreply, assign(socket, show_create_channel_form: !socket.assigns.show_create_channel_form)}
  end

  def handle_event("save_channel", %{"channel" => channel_params}, socket) do
    user = socket.assigns.current_user
    
    case ChatChannels.create_user_channel(user, channel_params) do
      {:ok, channel} ->
        # Subscribe to the new channel
        PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")
        
        socket = assign(socket,
          show_create_channel_form: false,
          current_channel: channel,
          page_title: "Chat - #{channel.name}"
        )
        |> stream(:messages, [], reset: true, dom_id: fn m -> "messages-#{m.id}" end)
        
        {:noreply, push_patch(socket, to: "/chat/#{channel.id}")}
        
      {:error, changeset} ->
        {:noreply, assign(socket, channel_form: to_form(changeset))}
    end
  end

  def handle_event("reorder_channels", %{"group" => _group, "ids" => ids}, socket) do
    user = socket.assigns.current_user
    
    try do
      # Update user preference instead of global order
      {:ok, _settings} = ChatChannels.reorder_channels(user, ids)

      # Re-sort channels based on new user preference
      {public_channels, private_channels} = sort_channels(socket.assigns.public_channels, socket.assigns.private_channels, user)
      
      {:noreply, assign(socket, public_channels: public_channels, private_channels: private_channels)}
    rescue
      e -> 
        Logger.error("Failed to reorder channels: #{inspect(e)}")
        {:noreply, put_flash(socket, :error, "Failed to reorder channels")}
    end
  end

  def handle_event("switch_channel", %{"channel_id" => channel_id}, socket) do
    # Just navigate, let handle_params take care of subscription/unsubscription
    {:noreply, push_patch(socket, to: "/chat/#{channel_id}")}
  end

  # Channel CRUD Events
  def handle_event("show_create_channel", _params, socket) do
    user = socket.assigns.current_user
    
    if user && (user.is_admin || user.role in ["admin", "gm"]) do
      {:noreply, assign(socket, show_create_channel_form: true)}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to create channels.")}
    end
  end

  def handle_event("hide_create_channel", _params, socket) do
    {:noreply, assign(socket, show_create_channel_form: false, channel_form: to_form(ChatChannels.change_channel(%ChatChannels.Channel{})))}
  end

  def handle_event("validate_channel", %{"channel" => channel_params}, socket) do
    changeset = 
      %ChatChannels.Channel{}
      |> ChatChannels.change_channel(channel_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, channel_form: to_form(changeset, action: :validate))}
  end

  def handle_event("create_channel", %{"channel" => channel_params}, socket) do
    user = socket.assigns.current_user
    
    # Check if user has permission to create channels
    if user && (user.is_admin || user.role in ["admin", "gm"]) do
      case ChatChannels.create_channel(channel_params) do
        {:ok, channel} ->
          # Refresh channel lists after creation
          all_channels = ChatChannels.list_channels()
          user_owned = ChatChannels.list_user_owned_channels(user.id)
          user_member = ChatChannels.list_user_member_channels(user.id)
          
          {public_system_channels, private_system_channels} = Enum.split_with(all_channels, fn ch ->
            !ch.is_private
          end)
          
          visible_private_system = Enum.filter(private_system_channels, fn ch ->
            ChatChannels.is_channel_member?(ch.id, user.id) || ch.owner_id == user.id || user.is_admin
          end)
          
          all_private_channels = (user_owned ++ user_member ++ visible_private_system) |> Enum.uniq_by(& &1.id)

          {:noreply,
           socket
           |> assign(show_create_channel_form: false, channel_form: to_form(ChatChannels.change_channel(%ChatChannels.Channel{})))
           |> assign(public_channels: public_system_channels, private_channels: all_private_channels)
           |> put_flash(:info, "Channel '#{channel.name}' created successfully!")}

        {:error, changeset} ->
          {:noreply, assign(socket, channel_form: to_form(changeset))}
      end
    else
      {:noreply,
       socket
       |> assign(show_create_channel_form: false)
       |> put_flash(:error, "You don't have permission to create channels. Contact an admin.")}
    end
  end

  def handle_event("show_delete_channel_confirm", _params, socket) do
    if can_delete_channel?(socket.assigns.current_user, socket.assigns.current_channel) do
      {:noreply, assign(socket, show_delete_channel_confirm: true)}
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to delete this channel.")}
    end
  end

  def handle_event("cancel_delete_channel", _params, socket) do
    {:noreply, assign(socket, show_delete_channel_confirm: false)}
  end

  def handle_event("confirm_delete_channel", _params, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    if can_delete_channel?(user, channel) do
      case ChatChannels.delete_channel_by_user(user, channel) do
        {:ok, _} ->
          # Refresh channel lists
          all_channels = ChatChannels.list_channels()
          user_owned = ChatChannels.list_user_owned_channels(user.id)
          user_member = ChatChannels.list_user_member_channels(user.id)
          
          {public_system_channels, private_system_channels} = Enum.split_with(all_channels, fn ch ->
            !ch.is_private
          end)
          
          visible_private_system = Enum.filter(private_system_channels, fn ch ->
            ChatChannels.is_channel_member?(ch.id, user.id) || ch.owner_id == user.id || user.is_admin
          end)
          
          all_private_channels = (user_owned ++ user_member ++ visible_private_system) |> Enum.uniq_by(& &1.id)

          # Navigate to default channel
          default = List.first(public_system_channels) || List.first(all_private_channels) || ChatChannels.get_or_create_default_channel()

          {:noreply, 
           socket
           |> assign(
             public_channels: public_system_channels,
             private_channels: all_private_channels,
             current_channel: default,
             show_delete_channel_confirm: false
           )
           |> stream(:messages, ChatChannels.list_messages(default.id), reset: true, dom_id: fn m -> "messages-#{m.id}" end)
           |> put_flash(:info, "Channel '#{channel.name}' deleted successfully. All messages and files have been removed.")
           |> push_navigate(to: ~p"/chat/#{default.id}")}

        {:error, :protected_channel} ->
          {:noreply, 
           socket
           |> assign(show_delete_channel_confirm: false)
           |> put_flash(:error, "The General channel cannot be deleted")}

        {:error, _} ->
          {:noreply, 
           socket
           |> assign(show_delete_channel_confirm: false)
           |> put_flash(:error, "Failed to delete channel")}
      end
    else
        {:noreply, 
         socket
         |> assign(show_delete_channel_confirm: false)
         |> put_flash(:error, "You don't have permission to delete this channel")}
    end
  end

  def handle_event("delete_channel", %{"channel_id" => channel_id}, socket) do
    user = socket.assigns.current_user

    # Ensure channel exists
    channel = ChatChannels.get_channel!(channel_id)

    # Protect General channel
    if String.downcase(channel.name) == "general" do
      {:noreply, put_flash(socket, :error, "The General channel cannot be deleted")}
    else
      # Only owner, admin, gm, or editor can delete a channel
      can_delete = (Map.has_key?(channel, :owner_id) && channel.owner_id == user.id) or
           (Map.has_key?(channel, :created_by_id) && channel.created_by_id == user.id) or
           Map.get(user, :is_admin, false) or
           user.role in ["admin", "gm", "editor"]
      
      if can_delete do
        case ChatChannels.delete_channel_by_user(user, channel) do
        {:ok, _} ->
          # Refresh channel lists
          all_channels = ChatChannels.list_channels()
          {public_channels, all_private_unfiltered} = Enum.split_with(all_channels, fn ch -> !ch.is_private end)
          private_channels = Enum.filter(all_private_unfiltered, fn ch -> can_access_channel?(ch, user) end)

          socket = assign(socket,
            public_channels: public_channels,
            private_channels: private_channels
          )

      # If deleted channel was current, navigate to default
      if socket.assigns.current_channel.id == channel.id do
        default = ChatChannels.get_or_create_default_channel()
        {:noreply, socket |> assign(current_channel: default) |> stream(:messages, ChatChannels.list_messages(default.id), reset: true, dom_id: fn m -> "messages-#{m.id}" end) |> push_navigate(to: ~p"/chat/#{default.id}")}
      else
        {:noreply, put_flash(socket, :info, "Channel deleted")}
      end

        {:error, :protected_channel} ->
          {:noreply, put_flash(socket, :error, "The General channel cannot be deleted")}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to delete this channel")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete channel")}
        end
      else
        {:noreply, put_flash(socket, :error, "You don't have permission to delete this channel")}
      end
    end
  end

  # Member management events
  def handle_event("open_members_modal", %{"channel_id" => channel_id}, socket) do
    require Logger
    channel = ChatChannels.get_channel!(channel_id)
    members = ChatChannels.list_channel_members(channel_id)
    Logger.info("open_members_modal: channel=#{channel.name} (#{channel_id}) members_count=#{length(members)}")

    {:noreply, assign(socket, show_channel_modal: true, editing_channel: channel, channel_members: members)}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("change_member_role", %{"member_id" => member_id, "new_role" => new_role}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    # Permission: must be able to manage channel (owner/admins) to change roles
    if ChatChannels.can_manage_channel?(user, channel) do
      case ChatChannels.get_channel_member_by_id(member_id) do
        nil -> {:noreply, put_flash(socket, :error, "Member not found")}
        member ->
          case ChatChannels.update_channel_member(member, %{role: new_role}) do
            {:ok, _} ->
              members = ChatChannels.list_channel_members(channel.id)
              {:noreply, assign(socket, channel_members: members) |> put_flash(:info, "Role updated")}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to change role")}
          end
      end
    else
      {:noreply, put_flash(socket, :error, "Permission denied")}
    end
  end

  def handle_event("ban_member", %{"member_id" => member_id}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    if ChatChannels.can_moderate_channel?(user, channel) do
      case ChatChannels.get_channel_member_by_id(member_id) do
        nil -> {:noreply, put_flash(socket, :error, "Member not found")}
        member ->
          if member.user_id == user.id do
            {:noreply, put_flash(socket, :error, "You cannot ban yourself")}
          else
            case ChatChannels.update_channel_member(member, %{is_banned: true}) do
              {:ok, _} ->
                members = ChatChannels.list_channel_members(channel.id)
                {:noreply, assign(socket, channel_members: members) |> put_flash(:info, "Member banned")}
              {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to ban member")}
            end
          end
      end
    else
      {:noreply, put_flash(socket, :error, "Permission denied")}
    end
  end

  def handle_event("unban_member", %{"member_id" => member_id}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    if ChatChannels.can_moderate_channel?(user, channel) do
      case ChatChannels.get_channel_member_by_id(member_id) do
        nil -> {:noreply, put_flash(socket, :error, "Member not found")}
        member ->
          case ChatChannels.update_channel_member(member, %{is_banned: false}) do
            {:ok, _} ->
              members = ChatChannels.list_channel_members(channel.id)
              {:noreply, assign(socket, channel_members: members) |> put_flash(:info, "Member unbanned")}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to unban member")}
          end
      end
    else
      {:noreply, put_flash(socket, :error, "Permission denied")}
    end
  end

  def handle_event("kick_member", %{"member_id" => member_id}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    if ChatChannels.can_manage_channel?(user, channel) do
      case ChatChannels.get_channel_member_by_id(member_id) do
        nil -> {:noreply, put_flash(socket, :error, "Member not found")}
        member ->
          if member.user_id == user.id do
            {:noreply, put_flash(socket, :error, "You cannot kick yourself")}
          else
            case ChatChannels.remove_channel_member(member.channel_id, member.user_id) do
              {:ok, _} ->
                members = ChatChannels.list_channel_members(channel.id)
                {:noreply, assign(socket, channel_members: members) |> put_flash(:info, "Member removed")}
              {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to remove member")}
            end
          end
      end
    else
      {:noreply, put_flash(socket, :error, "Permission denied")}
    end
  end

  # Reply handlers
  # (Removed duplicate start_reply and cancel_reply handlers)


  def handle_event("validate_channel_icon", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_channel_icon", _params, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    if ChatChannels.can_manage_channel?(user, channel) do
      case ChatChannels.update_channel(channel, %{icon_path: nil}) do
        {:ok, updated_channel} ->
          {:noreply, assign(socket, current_channel: updated_channel) |> put_flash(:info, "Channel icon removed")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove channel icon")}
      end
    else
      {:noreply, put_flash(socket, :error, "Permission denied")}
    end
  end

  def handle_event("trigger_channel_icon_upload", _params, socket) do
    {:noreply, socket}
  end





  def handle_event("create_personal_invite", %{"invitee_id" => invitee_id}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    # Check rate limiting first
    if !ChatChannels.can_send_invite?(user.id) do
      {:noreply, put_flash(socket, :error, "You're sending invites too quickly. Please wait before sending more.")}
    else
      if ChatChannels.can_invite_to_channel?(user, channel) do
        case ChatChannels.create_personal_invite(user.id, invitee_id, channel.id) do
          {:ok, invite} ->
            # Tell the invitee through the hub's notifications (the bell, and its sound)
            ChatChannels.Notices.invite(invite)
            
            # Show friendly invite info: username/email if available
            name = (invite.invitee && (invite.invitee.name || invite.invitee.email)) || invite.invitee_id || invite.code
            {:noreply, put_flash(socket, :info, "Invite created for #{name}")}
          {:error, :invitee_not_found} -> {:noreply, put_flash(socket, :error, "No user found with that username/email")}
          {:error, :already_member} -> {:noreply, put_flash(socket, :error, "User is already a member of this channel")}
          {:error, :invite_already_pending} -> {:noreply, put_flash(socket, :error, "You already have a pending invite for this user")}
          {:error, :invitee_blocked_invites} -> {:noreply, put_flash(socket, :error, "This user has blocked channel invites or has blocked you")}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create invite")}
        end
      else
        {:noreply, put_flash(socket, :error, "You don't have permission to invite")}
      end
    end
  end

  def handle_event("create_channel_invite", %{"max_uses" => max_uses, "expires_at" => expires_at}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    if ChatChannels.can_invite_to_channel?(user, channel) do
      max_uses_int = case Integer.parse(max_uses || "0") do
        {int, _} -> int
        :error -> 0
      end

      attrs = %{
        inviter_id: user.id,
        channel_id: channel.id,
        max_uses: if(max_uses_int > 0, do: max_uses_int, else: nil),
        expires_at: (if expires_at in [nil, "", "null"], do: nil, else: DateTime.from_iso8601(expires_at) |> elem(1))
      }

      case ChatChannels.create_channel_invite(attrs) do
        {:ok, invite} -> {:noreply, put_flash(socket, :info, "Invite code: #{invite.code}")}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create invite code")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to create invites")}
    end
  end

  def handle_event("transfer_ownership", %{"new_owner_id" => new_owner_id}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel

    if ChatChannels.can_manage_channel?(user, channel) do
      case ChatChannels.transfer_channel_ownership(user, channel, new_owner_id) do
        {:ok, updated_channel} ->
          members = ChatChannels.list_channel_members(channel.id)
          {:noreply, socket |> assign(current_channel: updated_channel, channel_members: members) |> put_flash(:info, "Ownership transferred")}
        {:error, :forbidden} -> {:noreply, put_flash(socket, :error, "Permission denied")}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to transfer ownership")}
      end
    else
      {:noreply, put_flash(socket, :error, "Permission denied")}
    end
  end

  def handle_event("revoke_invite", %{"invite_id" => invite_id}, socket) do
    user = socket.assigns.current_user

    case ChatChannels.revoke_channel_invite(user, invite_id) do
      {:ok, _invite} ->
        members = ChatChannels.list_channel_members(socket.assigns.current_channel.id)
        {:noreply, assign(socket, channel_members: members) |> put_flash(:info, "Invite revoked")}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, "Permission denied")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to revoke invite")}
    end
  end

  def handle_event("hide_members_modal", _params, socket) do
    {:noreply, assign(socket, show_channel_modal: false, editing_channel: nil, channel_members: nil)}
  end

  # Invite Modal
  def handle_event("show_invite_modal", _params, socket) do
    {:noreply, assign(socket, show_invite_modal: true)}
  end

  def handle_event("hide_invite_modal", _params, socket) do
    {:noreply, assign(socket, show_invite_modal: false)}
  end

  # Image Viewer
  def handle_event("open_image_viewer", %{"url" => url, "filename" => filename}, socket) do
    {:noreply, assign(socket, show_image_viewer: true, viewer_image_url: url, viewer_image_filename: filename)}
  end

  def handle_event("close_image_viewer", _params, socket) do
    {:noreply, assign(socket, show_image_viewer: false, viewer_image_url: nil, viewer_image_filename: nil)}
  end

  # User-Created Channel Events
  def handle_event("show_create_user_channel", _params, socket) do
    if socket.assigns.can_create_more_channels do
      # When opening the user-created channel form, default to a private channel checked
      {:noreply, assign(socket, show_create_channel_form: true, creating_user_channel: true, channel_form: to_form(ChatChannels.change_channel(%ChatChannels.Channel{is_private: true})))}
    else
      {:noreply, put_flash(socket, :error, "You've reached the maximum of 5 channels")}
    end
  end

  def handle_event("create_user_channel", %{"channel" => channel_params}, socket) do
    user = socket.assigns.current_user
    
    # Add owner_id and user_created flag
    # parse checkbox values robustly (checkbox may be "on", "true" or boolean)
    is_private = case channel_params["is_private"] do
      "true" -> true
      "on" -> true
      true -> true
      _ -> false
    end
    
    # Permission check: Only Admins/GMs can create public channels
    if !is_private && !(user.is_admin || user.role in ["admin", "gm"]) do
      {:noreply, put_flash(socket, :error, "Only Admins and GMs can create public channels.")}
    else
      channel_params = Map.merge(channel_params, %{
        "owner_id" => user.id,
        "is_user_created" => true,
        "is_private" => is_private,
        "is_public" => !is_private
      })
      
      case ChatChannels.create_user_channel(user, channel_params) do
        {:ok, channel} ->
          # Refresh channel lists
          all_channels = ChatChannels.list_channels()
          {public_channels, all_private_unfiltered} = Enum.split_with(all_channels, fn ch -> !ch.is_private end)
          private_channels = Enum.filter(all_private_unfiltered, fn ch -> can_access_channel?(ch, user) end)
          
          # Sort channels based on user preference
          {public_channels, private_channels} = sort_channels(public_channels, private_channels, user)
          
          {:noreply,
           socket
           |> assign(
             show_create_channel_form: false,
             creating_user_channel: false,
             channel_form: to_form(ChatChannels.change_channel(%ChatChannels.Channel{})),
             public_channels: public_channels,
             private_channels: private_channels,
             can_create_more_channels: length(private_channels) < 5
           )
           |> put_flash(:info, "Channel '#{channel.name}' created!")
           |> push_navigate(to: ~p"/chat/#{channel.id}")}
        
        {:error, %Ecto.Changeset{} = changeset} ->
          error_msg = if changeset.errors[:owner_id] do
            "You can only create up to 5 channels"
          else
            "Failed to create channel"
          end
          {:noreply, assign(socket, channel_form: to_form(changeset)) |> put_flash(:error, error_msg)}
      end
    end
  end

  def handle_event("accept_invite", %{"invite_id" => invite_id}, socket) do
    user = socket.assigns.current_user

    case ChatChannels.accept_channel_invite(invite_id, user.id) do
      {:ok, _member} ->
        {:noreply,
         socket
         |> reload_channel_lists()
         |> assign(pending_invites: ChatChannels.list_pending_invites_for_user(user.id))
         |> put_flash(:info, "Joined channel!")}

      {:error, :already_member} ->
        {:noreply,
         socket
         |> assign(pending_invites: ChatChannels.list_pending_invites_for_user(user.id))
         |> put_flash(:info, "You're already in that channel")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(pending_invites: ChatChannels.list_pending_invites_for_user(user.id))
         |> put_flash(:error, "That invite can't be accepted any more")}
    end
  end

  def handle_event("decline_invite", %{"invite_id" => invite_id}, socket) do
    user = socket.assigns.current_user

    case ChatChannels.decline_invite(invite_id, user.id) do
      {:ok, _invite} -> :ok
      {:error, _reason} -> :ok
    end

    {:noreply, assign(socket, pending_invites: ChatChannels.list_pending_invites_for_user(user.id))}
  end

  def handle_event("join_channel_with_invite", %{"code" => code}, socket) do
    user = socket.assigns.current_user
    
    case ChatChannels.use_channel_invite(code, user.id) do
      {:ok, _member} ->
        # Reload channels to include newly joined channel
        all_channels = ChatChannels.list_channels()
        {public_channels, all_private_channels_unfiltered} = Enum.split_with(all_channels, fn ch -> !ch.is_private end)
        visible_private_channels = Enum.filter(all_private_channels_unfiltered, fn ch ->
          can_access_channel?(ch, user)
        end)
        
        {:noreply,
         socket
         |> assign(
           public_channels: Enum.sort_by(public_channels, & &1.name),
           private_channels: Enum.sort_by(visible_private_channels, & &1.name)
         )
         |> put_flash(:info, "Successfully joined channel!")}
      
      {:error, reason} ->
        message = case reason do
          :invalid_invite -> "Invalid invite code"
          :invite_expired -> "This invite has expired"
          :already_member -> "You're already a member"
          _ -> "Failed to join channel"
        end
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # Streaming Events
  def handle_event("start_stream", %{"type" => stream_type}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel
    
    case ChatChannels.start_stream(%{
      channel_id: channel.id,
      streamer_id: user.id,
      stream_type: stream_type,
      title: "#{user.name || user.email}'s Stream"
    }) do
      {:ok, session} ->
        {:noreply, assign(socket, active_stream: session)}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to start stream")}
    end
  end

  def handle_event("end_stream", %{"session_id" => session_id}, socket) do
    case ChatChannels.end_stream(session_id) do
      {:ok, _} ->
        {:noreply, assign(socket, active_stream: nil)}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to end stream")}
    end
  end

  def handle_event("validate_message", %{"message" => content}, socket) do
    {:noreply, assign(socket, current_message: content)}
  end

  def handle_event("validate_reply", params, socket) do
    content = params["content"] || ""
    {:noreply, assign(socket, reply_message_content: content)}
  end

  def handle_event("validate_edit", params, socket) do
    content = params["content"] || ""
    {:noreply, assign(socket, editing_message_content: content)}
  end

  def handle_event("messages_read", %{"last_read_id" => last_read_id}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.current_channel
    
    if user && channel && last_read_id do
      _ = ChatChannels.mark_channel_messages_read(user.id, channel.id, last_read_id)
      {:noreply, assign(socket, :last_read_message_id, last_read_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("messages_read", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("load_older", %{"before_id" => before_id}, socket) do
    channel = socket.assigns.current_channel

    if channel && before_id do
      older = ChatChannels.list_messages_cursor(channel.id, %{before: before_id, limit: 50})

      # Prepend older messages to the stream
      # stream_insert with at: 0 inserts at the beginning
      socket = Enum.reduce(older, socket, fn msg, sock ->
        stream_insert(sock, :messages, msg, at: 0)
      end)
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # (Removed duplicate cancel_edit handler)


  def handle_event("toggle_uploads", _params, socket) do
    {:noreply, assign(socket, show_attachments: !socket.assigns.show_attachments)}
  end

  def handle_event("cancel-upload", %{"ref" => ref, "upload_config" => config_name}, socket) do
    config = String.to_existing_atom(config_name)
    {:noreply, cancel_upload(socket, config, ref)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :forum_attachment, ref)}
  end

  def handle_event("upload_files", _params, socket) do
    # Handle file uploads
    {:noreply, assign(socket, show_attachments: false)}
  end

  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  # Ignore desktop window manager events in ChatLive
  def handle_event("update_window_position", _params, socket) do
    {:noreply, socket}
  end

  def handle_channel_icon_progress(:channel_icon, entry, socket) do
    if entry.done? do
      # Note: consume_uploaded_entries requires {:ok, value} return
      results = consume_uploaded_entries(socket, :channel_icon, fn %{path: path}, _entry ->
        user = socket.assigns.current_user
        channel = socket.assigns.current_channel
        
        # Check permissions (owner or admin)
        if ChatChannels.can_manage_channel?(user, channel) do
           context = "channel_icons/#{channel.id}"
           case Bacon8.Uploads.upload_file(user, path, entry, context: context) do
             {:ok, url_path} ->
               # Update channel
               case ChatChannels.update_channel(channel, %{icon_path: url_path}) do
                 {:ok, _updated_channel} ->
                   {:ok, {:success, url_path}}
                 {:error, _} ->
                   {:ok, {:error, "Failed to update channel"}}
               end
             {:error, reason} -> {:ok, {:error, reason}}
           end
        else
           {:ok, {:error, "Permission denied"}}
        end
      end)
      
      # Check for errors
      has_error = Enum.any?(results, fn
        {:error, _} -> true
        _ -> false
      end)
      
      # Refresh channel to show new icon
      channel = ChatChannels.get_channel!(socket.assigns.current_channel.id)
      socket = assign(socket, current_channel: channel)
      
      if has_error do
        {:noreply, put_flash(socket, :error, "Failed to upload channel icon")}
      else
        {:noreply, put_flash(socket, :info, "Channel icon updated")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    if message.reply_to_id do
      # It's a reply, update the root parent message recursively
      root_id = get_root_message_id(message)
      case ChatChannels.get_message(root_id) do
        nil -> {:noreply, socket} # Root message deleted, ignore
        root -> 
          # Update pinned messages if root (or any ancestor) is pinned
          socket = update_pinned_message_if_needed(socket, root)
          {:noreply, stream_insert(socket, :messages, root)}
      end
    else
      # Messages are stored oldest -> newest. When a new message arrives we should
      # append it to the end so the conversation remains chronological in real-time
      {:noreply, stream_insert(socket, :messages, message)}
    end
  end

  def handle_info({:message_updated, updated_message}, socket) do
    # Update pinned messages list if needed
    pinned_messages = if updated_message.is_pinned do
      # Add or update in pinned list
      existing = Enum.find(socket.assigns.pinned_messages, &(&1.id == updated_message.id))
      if existing do
        Enum.map(socket.assigns.pinned_messages, fn m -> if m.id == updated_message.id, do: updated_message, else: m end)
      else
        [updated_message | socket.assigns.pinned_messages] |> Enum.sort_by(& &1.inserted_at, :desc)
      end
    else
      # Remove from pinned list if it was unpinned
      Enum.filter(socket.assigns.pinned_messages, &(&1.id != updated_message.id))
    end

    socket = assign(socket, pinned_messages: pinned_messages)
    
    if updated_message.reply_to_id do
      root_id = get_root_message_id(updated_message)
      case ChatChannels.get_message(root_id) do
        nil -> {:noreply, socket}
        root -> {:noreply, stream_insert(socket, :messages, root)}
      end
    else
      {:noreply, stream_insert(socket, :messages, updated_message)}
    end
  end

  def handle_info({:reaction_added, reaction}, socket) do
    case ChatChannels.get_message(reaction.message_id) do
      nil -> {:noreply, socket}
      message -> 
        # Update pinned messages if this message (or its parent) is pinned
        socket = update_pinned_message_if_needed(socket, message)
        
        if message.reply_to_id do
          root_id = get_root_message_id(message)
          case ChatChannels.get_message(root_id) do
            nil -> {:noreply, socket}
            root -> 
              # Also update pinned if root is pinned
              socket = update_pinned_message_if_needed(socket, root)
              {:noreply, stream_insert(socket, :messages, root)}
          end
        else
          {:noreply, stream_insert(socket, :messages, message)}
        end
    end
  end

  def handle_info({:reaction_removed, reaction}, socket) do
    case ChatChannels.get_message(reaction.message_id) do
      nil -> {:noreply, socket}
      message -> 
        # Update pinned messages if this message (or its parent) is pinned
        socket = update_pinned_message_if_needed(socket, message)
        
        if message.reply_to_id do
          root_id = get_root_message_id(message)
          case ChatChannels.get_message(root_id) do
            nil -> {:noreply, socket}
            root -> 
              # Also update pinned if root is pinned
              socket = update_pinned_message_if_needed(socket, root)
              {:noreply, stream_insert(socket, :messages, root)}
          end
        else
          {:noreply, stream_insert(socket, :messages, message)}
        end
    end
  end

  def handle_info({:user_banned, user_id, channel_id}, socket) do
    if socket.assigns.current_user.id == user_id and socket.assigns.current_channel.id == channel_id do
      default_channel = ChatChannels.get_or_create_default_channel()
      
      socket = socket
      |> put_flash(:error, "You have been banned from this channel.")
      |> push_navigate(to: "/chat/#{default_channel.id}")
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:message_deleted, %ChatChannels.Message{} = message}, socket) do
    # Remove the deleted message from pinned list if it was pinned
    pinned_messages = Enum.filter(socket.assigns.pinned_messages, &(&1.id != message.id))
    
    # Also update pinned messages if the deleted message was a reply to a pinned message
    pinned_messages = update_pinned_messages_for_deleted_reply(pinned_messages, message)
    
    socket = assign(socket, pinned_messages: pinned_messages)

    if message.reply_to_id do
      # It was a reply, we need to update the root parent message in the stream
      root_id = get_root_message_id(message)
      case ChatChannels.get_message(root_id) do
        nil -> {:noreply, socket}
        root -> {:noreply, stream_insert(socket, :messages, root)}
      end
    else
      {:noreply, stream_delete(socket, :messages, message)}
    end
  end

  def handle_info({:message_deleted, message_id}, socket) do
    # Fallback for legacy calls or if message struct wasn't passed
    # Remove from pinned if the message itself was pinned
    pinned_messages = Enum.filter(socket.assigns.pinned_messages, &(&1.id != message_id))
    
    # Also refresh any pinned message that contained this as a reply
    pinned_messages = Enum.map(pinned_messages, fn pinned_msg ->
      if message_contains_reply?(pinned_msg, message_id) do
        ChatChannels.get_message(pinned_msg.id) || pinned_msg
      else
        pinned_msg
      end
    end)
    
    {:noreply, 
     socket 
     |> assign(pinned_messages: pinned_messages)
     |> stream_delete(:messages, %{id: message_id})}
  end

  def handle_info({:channels_reordered, _ids}, socket) do
    user = socket.assigns.current_user

    # Recompute channels to reflect new order
    all_channels = ChatChannels.list_channels()
    {public_channels, all_private_channels_unfiltered} = Enum.split_with(all_channels, fn ch -> !ch.is_private end)
    visible_private_channels = Enum.filter(all_private_channels_unfiltered, fn ch -> can_access_channel?(ch, user) end)
    
    # Sort channels based on user preference
    {public_channels, visible_private_channels} = sort_channels(public_channels, visible_private_channels, user)
    
    {:noreply, assign(socket, public_channels: public_channels, private_channels: visible_private_channels)}
  end

  def handle_info({:channel_created, _channel}, socket) do
    user = socket.assigns.current_user

    # Recompute channels the same way we do on mount — keep ordering & access rules consistent
    all_channels = ChatChannels.list_channels()
    {public_channels, all_private_channels_unfiltered} = Enum.split_with(all_channels, fn ch -> !ch.is_private end)
    visible_private_channels = Enum.filter(all_private_channels_unfiltered, fn ch -> can_access_channel?(ch, user) end)
    
    # Sort channels based on user preference
    {public_channels, visible_private_channels} = sort_channels(public_channels, visible_private_channels, user)
    
    {:noreply, assign(socket, public_channels: public_channels, private_channels: visible_private_channels)}
  end
  
  def handle_info({:channel_updated, updated_channel}, socket) do
    # Update channel in all relevant lists
    update_channel_in_list = fn list ->
      Enum.map(list, fn channel ->
        if channel.id == updated_channel.id, do: updated_channel, else: channel
      end)
    end
    
    public_channels = update_channel_in_list.(socket.assigns.public_channels)
    private_channels = update_channel_in_list.(socket.assigns.private_channels)
    
    # Re-sort
    {public_channels, private_channels} = sort_channels(public_channels, private_channels, socket.assigns.current_user)
    
    socket = socket
    |> assign(public_channels: public_channels)
    |> assign(private_channels: private_channels)
    
    # Update current channel if it's the one being edited
    socket = if socket.assigns.current_channel.id == updated_channel.id do
      can_moderate = ChatChannels.can_moderate_channel?(socket.assigns.current_user, updated_channel)
      assign(socket, current_channel: updated_channel, page_title: "Chat - #{updated_channel.name}", can_moderate: can_moderate)
    else
      socket
    end
    
    {:noreply, socket}
  end
  
  def handle_info({:channel_deleted, channel_id}, socket) do
    # Remove channel from all lists
    remove_channel_from_list = fn list ->
      Enum.filter(list, &(&1.id != channel_id))
    end
    
    socket = socket
    |> assign(public_channels: remove_channel_from_list.(socket.assigns.public_channels))
    |> assign(private_channels: remove_channel_from_list.(socket.assigns.private_channels))
    
    # If the deleted channel is the current one, switch to default
    if socket.assigns.current_channel.id == channel_id do
      default_channel = ChatChannels.get_or_create_default_channel()

      # Unsubscribe from the deleted channel presence/topic and subscribe to the new default channel + presence
      try do
        PubSub.unsubscribe(Bacon8.PubSub, "presence:channel:#{channel_id}")
        if connected?(socket) and socket.assigns.current_user do
          Bacon8Web.Presence.untrack(self(), "presence:channel:#{channel_id}", to_string(socket.assigns.current_user.id))
        end
      rescue
        _ -> :ok
      end
      try do
        PubSub.unsubscribe(Bacon8.PubSub, "channel:#{channel_id}")
      rescue
        _ -> :ok
      end

      # Subscribe to default channel topic
      PubSub.subscribe(Bacon8.PubSub, "channel:#{default_channel.id}")
      # also subscribe to presence topic and track our presence in it
      PubSub.subscribe(Bacon8.PubSub, "presence:channel:#{default_channel.id}")
      if connected?(socket) and socket.assigns.current_user do
        user = socket.assigns.current_user
        Bacon8Web.Presence.track(self(), "presence:channel:#{default_channel.id}", to_string(user.id), %{
          name: user.name || user.email,
          email: user.email,
          avatar_url: user.avatar_url,
          avatar_color: user.avatar_color,
          avatar_shape: user.avatar_shape,
          avatar_opacity: user.avatar_opacity,
          role: user.role,
          bio: Map.get(user, :bio),
          inserted_at: user.inserted_at,
          online_at: DateTime.utc_now()
        })
      end
      
      socket = assign(socket,
        current_channel: default_channel,
        page_title: "Chat - #{default_channel.name}",
        can_moderate: ChatChannels.can_moderate_channel?(socket.assigns.current_user, default_channel)
      )
      |> stream(:messages, ChatChannels.list_messages(default_channel.id), reset: true, dom_id: fn m -> "messages-#{m.id}" end)
      
      # Refresh online users list for the new channel with full avatar info
      online_users = Bacon8Web.Presence.list("presence:channel:#{default_channel.id}") |> Enum.map(fn {uid, meta} ->
        metas = Map.get(meta, :metas, [])
        latest = List.last(metas) || %{}
        Map.merge(latest, %{id: uid})
      end)

      {:noreply, assign(socket, online_users: online_users) |> push_navigate(to: "/chat/#{default_channel.id}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:user_typing, user_id}, socket) do
    if user_id != socket.assigns.current_user.id do
      typing_users = MapSet.put(socket.assigns.typing_users, user_id)
      
      # Remove typing indicator after 3 seconds
      Process.send_after(self(), {:stop_typing, user_id}, 3000)
      
      {:noreply, assign(socket, typing_users: typing_users)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%{event: "presence_diff", payload: _diff} = _msg, socket) do
    # When presence changes, refresh the presence list for current channel
    channel = socket.assigns.current_channel
    topic = "presence:channel:#{channel.id}"
    presences = Bacon8Web.Presence.list(topic)
    Logger.info("handle_info presence_diff for channel #{channel.id}. Presences: #{inspect(Map.keys(presences))}")

    # Transform presences into a list of users with metadata
    online_users =
      presences
      |> Enum.map(fn {user_id, meta} ->
        # meta may have :metas list, take the most recent
        metas = Map.get(meta, :metas, [])
        latest = List.last(metas) || %{}
        Map.put(latest, :id, user_id)
      end)

    {:noreply, assign(socket, online_users: online_users)}
  end

  def handle_info({:stop_typing, user_id}, socket) do
    typing_users = MapSet.delete(socket.assigns.typing_users, user_id)
    {:noreply, assign(socket, typing_users: typing_users)}
  end

  def handle_info({:stream_started, session}, socket) do
    {:noreply, assign(socket, active_stream: session)}
  end

  def handle_info(:stream_ended, socket) do
    {:noreply, assign(socket, active_stream: nil)}
  end

  # Handle emoji picker events
  def handle_info({:add_reaction, message_id, emoji}, socket) do
    case ChatChannels.get_message(message_id) do
      nil -> {:noreply, socket}
      message ->
        user = socket.assigns.current_user
        ChatChannels.toggle_reaction(message, user, emoji)
        {:noreply, socket}
    end
  end

  def handle_info({:insert_emoji, emoji}, socket) do
    # Append emoji to the current message content
    new_content = (socket.assigns.message_content || "") <> emoji
    {:noreply, assign(socket, message_content: new_content)}
  end

  # The sidebar's channel lists, after membership changed (an invite was accepted).
  defp reload_channel_lists(socket) do
    user = socket.assigns.current_user
    {public, private} = Enum.split_with(ChatChannels.list_channels(), fn ch -> !ch.is_private end)
    private = Enum.filter(private, &can_access_channel?(&1, user))
    {public, private} = sort_channels(public, private, user)
    assign(socket, public_channels: public, private_channels: private)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Bacon8Web.Components.PageContainer.fullscreen_container>
      <%= if @loading do %>
        <%!-- Loading state while WebSocket connects --%>
        <div class="flex-1 flex items-center justify-center">
          <div class="text-center">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-cyan-500 mx-auto mb-4"></div>
            <p class="text-gray-400">Connecting to chat...</p>
          </div>
        </div>
      <% else %>
      <div class="flex-1 flex flex-row overflow-hidden">
        <%!-- Sidebar with glass theme --%>
    <.chat_sidebar allow_invites={@allow_invites} current_channel={@current_channel} current_user={@current_user} pending_invites={@pending_invites} private_channels={@private_channels} public_channels={@public_channels} sidebar_open={@sidebar_open} />
        
        <%!-- Collapsed sidebar indicator/handle --%>
        <div 
          id="sidebar-collapsed-handle"
          phx-update="ignore"
          class="hidden w-1 h-full bg-gray-600/30 hover:bg-blue-500/50 cursor-pointer flex-shrink-0 transition-colors"
          title="Click to expand sidebar"
        ></div>

        <%!-- Main chat area with glass theme --%>
        <div class="flex-1 flex flex-col">
          <%!-- Channel header with glass theme --%>
    <.channel_header can_moderate={@can_moderate} current_channel={@current_channel} current_user={@current_user} uploads={@uploads} />

        <div class="flex-1 relative flex flex-col min-h-0">
          <div id="messages" class="flex-1 px-4 pt-4 pb-2 overflow-y-auto dark-glass" phx-hook="MessageList" data-auto-scroll={if @auto_scroll_enabled, do: "true", else: "false"}>
            
            <%!-- Pinned Messages Section (Scrollable) --%>
    <.pinned_messages_panel can_moderate={@can_moderate} current_user={@current_user} editing_message_content={@editing_message_content} editing_message_id={@editing_message_id} last_read_message_id={@last_read_message_id} pinned_messages={@pinned_messages} reply_message_content={@reply_message_content} replying_to_message_id={@replying_to_message_id} uploads={@uploads} />

            <div id="messages-list" phx-update="stream">
              <% 
                # Combine pinned messages (at top) with regular messages (excluding pinned ones to avoid duplicates)
                # Note: With streams, we handle pinned messages separately in the UI, 
                # but the stream contains all messages.
                # We should render pinned messages in a separate container above the stream if we want them fixed at top.
                # Or we can just render the stream.
                # The original code filtered @messages. With streams, we iterate @streams.messages.
              %>
              
              <%= for {dom_id, message} <- @streams.messages do %>
                <%!-- Don't render pinned messages in the main stream to avoid duplication if they are shown above --%>
                <%= unless message.is_pinned do %>
                  <.message_item 
                    id={dom_id}
                    message={message} 
                    current_user={@current_user} 
                    can_moderate={@can_moderate} 
                    replying_to_message_id={@replying_to_message_id} 
                    editing_message_id={@editing_message_id} 
                    editing_message_content={@editing_message_content}
                    reply_message_content={@reply_message_content}
                    last_read_message_id={@last_read_message_id}
                    uploads={@uploads}
                  />
                <% end %>
              <% end %>
            </div>
          </div>
          
          <!-- Auto-scroll Toggle Button -->
          <button 
            id="auto-scroll-toggle" 
            phx-click="toggle_auto_scroll"
            class={"absolute bottom-4 right-4 z-50 w-[30px] h-[30px] rounded-full shadow-lg transition-all duration-300 flex items-center justify-center border border-gray-600 " <> if(@auto_scroll_enabled, do: "bg-blue-600 text-white hover:bg-blue-700", else: "bg-gray-800 text-gray-400 hover:bg-gray-700")}
            title={if @auto_scroll_enabled, do: "Disable Auto-scroll", else: "Enable Auto-scroll"}
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
            </svg>
          </button>
          
          <!-- New Messages Notifier -->
          <div 
            id="new-messages-notifier" 
            class="absolute bottom-14 right-4 w-max bg-blue-600 text-white px-3 py-1.5 rounded shadow cursor-pointer z-50 text-xs animate-bounce hidden"
          >
            New messages ⬇
          </div>
        </div>

        <%!-- Edit Form - Rendered outside the stream for proper upload handling --%>
    <.edit_form :if={@editing_message_id} editing_message_content={@editing_message_content} editing_message_id={@editing_message_id} uploads={@uploads} />

        <%!-- Reply Form - Rendered outside the stream for proper upload handling --%>
    <.reply_form :if={@replying_to_message_id} reply_message_content={@reply_message_content} replying_to_message_id={@replying_to_message_id} uploads={@uploads} />

    <.composer current_message={@current_message} uploads={@uploads} />
        </div>
      </div>

    <%!-- Delete Channel Confirmation Modal --%>
    <%!-- Channel Member Management Modal --%>
    <.members_modal :if={@show_channel_modal} channel_members={@channel_members} current_user={@current_user} editing_channel={@editing_channel} show_channel_modal={@show_channel_modal} />

    <%!-- Create Channel Modal (used for both admin/system channel creation and user-created private channels) --%>
    <.create_channel_modal :if={@show_create_channel_form} channel_form={@channel_form} creating_user_channel={@creating_user_channel} current_channel={@current_channel} show_create_channel_form={@show_create_channel_form} show_delete_channel_confirm={@show_delete_channel_confirm} />

    <!-- Image Viewer Modal -->
    <.image_viewer :if={@show_image_viewer} show_image_viewer={@show_image_viewer} viewer_image_filename={@viewer_image_filename} viewer_image_url={@viewer_image_url} />

    <!-- Invite Modal -->
    <.invite_modal :if={@show_invite_modal} current_channel={@current_channel} show_invite_modal={@show_invite_modal} />
    <% end %>
    </Bacon8Web.Components.PageContainer.fullscreen_container>
    """
  end

  # Authorization helper - check if user can access a channel
  defp can_access_channel?(channel, user) do
    require Logger
    # Public channels are accessible to everyone
    if !channel.is_private do
      true
    else
      # Private channels require explicit permission
      # Check is_admin field directly (it's a boolean field on the user)
      is_admin = Map.get(user, :is_admin, false) == true
      is_staff = Map.get(user, :role, nil) in ["admin", "gm", "editor"]
      is_owner = Map.get(channel, :owner_id) == user.id
      is_creator = Map.get(channel, :created_by_id) == user.id
      
      # Check if member and NOT banned
      member = ChatChannels.get_channel_member(channel.id, user.id)
      is_member = member != nil
      is_banned = member && member.is_banned
      
      result = (is_admin || is_staff || is_owner || is_creator || is_member) && !is_banned
      
      Logger.info("can_access_channel? - Channel: #{channel.name}, User: #{user.email}, is_admin: #{is_admin}, is_staff: #{is_staff}, is_owner: #{is_owner}, is_creator: #{is_creator}, is_member: #{is_member}, is_banned: #{is_banned}, result: #{result}")
      
      result
    end
  end

  # (Removed unused update_message_replies function)


  defp refresh_message(socket, nil), do: socket
  defp refresh_message(socket, message_id) do
    case ChatChannels.get_message(message_id) do
      nil -> socket
      message -> 
        # Always refresh the root message to ensure nested replies are updated
        root_id = get_root_message_id(message)
        case ChatChannels.get_message(root_id) do
          nil -> socket
          root -> stream_insert(socket, :messages, root)
        end
    end
  end

  defp get_root_message_id(%{reply_to_id: nil, id: id}), do: id
  defp get_root_message_id(%{reply_to_id: parent_id}) do
    case ChatChannels.get_message(parent_id) do
      nil -> parent_id # Should not happen, but return parent_id as best guess
      parent -> get_root_message_id(parent)
    end
  end

  # Helper to update a message in the pinned_messages list if it exists there
  defp update_pinned_message_if_needed(socket, message) do
    pinned_messages = socket.assigns.pinned_messages
    
    # Check if this message is in the pinned list
    if Enum.any?(pinned_messages, &(&1.id == message.id)) do
      updated_pinned = Enum.map(pinned_messages, fn m ->
        if m.id == message.id, do: message, else: m
      end)
      assign(socket, pinned_messages: updated_pinned)
    else
      # Check if any pinned message contains this as a reply (nested)
      # We need to refresh the whole pinned message to get updated replies
      updated_pinned = Enum.map(pinned_messages, fn pinned_msg ->
        if message_contains_reply?(pinned_msg, message.id) do
          # Refresh the pinned message from DB to get updated reply data
          ChatChannels.get_message(pinned_msg.id) || pinned_msg
        else
          pinned_msg
        end
      end)
      assign(socket, pinned_messages: updated_pinned)
    end
  end

  # Check if a message contains a specific reply (recursively)
  defp message_contains_reply?(message, reply_id) do
    replies = if Ecto.assoc_loaded?(message.replies), do: message.replies, else: []
    Enum.any?(replies, fn r ->
      r.id == reply_id || message_contains_reply?(r, reply_id)
    end)
  end

  # Update pinned messages when a reply is deleted (refresh parent if needed)
  defp update_pinned_messages_for_deleted_reply(pinned_messages, deleted_message) do
    # If the deleted message was a reply, check if its parent is pinned
    if deleted_message.reply_to_id do
      Enum.map(pinned_messages, fn pinned_msg ->
        # Check if this pinned message contains the deleted reply
        if message_contains_reply?(pinned_msg, deleted_message.id) or 
           pinned_msg.id == deleted_message.reply_to_id or
           get_root_message_id(deleted_message) == pinned_msg.id do
          # Refresh the pinned message from DB to get updated reply data
          ChatChannels.get_message(pinned_msg.id) || pinned_msg
        else
          pinned_msg
        end
      end)
    else
      pinned_messages
    end
  end

  defp sort_channels(public_channels, private_channels, user) do
    order = ChatChannels.channel_order(user.id)
    
    # Helper to get sort index
    get_sort_index = fn channel ->
      if String.downcase(channel.name) == "general" do
        -1 # Always first
      else
        Enum.find_index(order, &(&1 == channel.id)) || 9999 # Default to end if not in order
      end
    end
    
    sorted_public = Enum.sort_by(public_channels, get_sort_index)
    sorted_private = Enum.sort_by(private_channels, get_sort_index)
    
    {sorted_public, sorted_private}
  end

  defp can_delete_channel?(user, channel) do
    # Protect General channel
    if String.downcase(channel.name) == "general" do
      false
    else
      # Only owner, creator, admin, gm, or editor can delete a channel
      (Map.has_key?(channel, :owner_id) && channel.owner_id == user.id) or 
      (Map.has_key?(channel, :created_by_id) && channel.created_by_id == user.id) or
      Map.get(user, :is_admin, false) or 
      user.role in ["admin", "gm", "editor"]
    end
  end
end 