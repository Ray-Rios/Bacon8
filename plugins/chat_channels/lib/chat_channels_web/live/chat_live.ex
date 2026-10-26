defmodule ChatChannelsWeb.ChatLive do
  use Bacon8Web, :live_view
  require Logger
  alias Phoenix.PubSub
  import Bacon8Web.CoreComponents
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
        <div 
          id="forum-sidebar" 
          phx-hook="SidebarResizer" 
          data-sidebar-open={@sidebar_open}
          class="dark-glass border-r border-cyan-500/30 flex flex-col flex-none overflow-hidden z-40 relative"
        >
          <div class="flex-1 overflow-y-auto p-4 overflow-x-hidden sidebar-content">
            <label id="allow-invites" class="mb-4 flex items-center gap-2 text-xs text-gray-400 cursor-pointer">
              <input type="checkbox" phx-click="toggle_invites" checked={@allow_invites} class="rounded" />
              Let people invite me to channels
            </label>

            <%!-- Invitations (they used to be in the desktop's notification panel) --%>
            <%= if @pending_invites != [] do %>
              <div class="mb-6" id="pending-invites">
                <h2 class="text-xs font-semibold text-amber-400 uppercase tracking-wide mb-2">
                  Invitations (<%= length(@pending_invites) %>)
                </h2>
                <ul class="space-y-2">
                  <%= for invite <- @pending_invites do %>
                    <li class="rounded-lg border border-amber-500/30 bg-amber-500/10 p-2 text-sm">
                      <div class="text-gray-200">
                        <span class="font-semibold text-cyan-300"><%= invite.inviter.name || invite.inviter.email %></span>
                        invited you to
                        <span class="font-semibold text-purple-300">#<%= invite.channel.name %></span>
                      </div>
                      <div class="mt-2 flex gap-2">
                        <button type="button" phx-click="accept_invite" phx-value-invite_id={invite.id}
                                class="flex-1 rounded bg-green-600 px-2 py-1 text-xs font-medium text-white hover:bg-green-700">Accept</button>
                        <button type="button" phx-click="decline_invite" phx-value-invite_id={invite.id}
                                class="flex-1 rounded bg-gray-600 px-2 py-1 text-xs font-medium text-white hover:bg-gray-700">Decline</button>
                      </div>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <%!-- Public Channels Section --%>
            <div class="mb-6">
                <div class="flex items-center justify-between mb-2">
                  <h2 class="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Public Channels</h2>
                  <div class="flex items-center gap-2">
                    <button phx-click={if @current_user && (Map.get(@current_user, :is_admin, false) || @current_user.role in ["admin","gm"]), do: "show_create_channel", else: "show_create_user_channel"} class="flex items-center space-x-2 text-sm text-gray-700 dark:text-gray-200 bg-gray-100 dark:bg-gray-700 px-2 py-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600">
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path></svg>
                      <span>Create new channel</span>
                    </button>
                  </div>
                </div>
              <ul class="space-y-0.5" id="public-channels-list" phx-hook="Sortable" data-group="public">
                <%= for channel <- @public_channels do %>
                  <li draggable="true" data-id={channel.id} class="cursor-move">
                    <a href="#" phx-click="switch_channel" phx-value-channel_id={channel.id} class={"flex items-center px-2 py-1.5 rounded text-sm hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors #{active_channel_class(channel, @current_channel)}"}>
                      <%= if channel.icon_path do %>
                        <img src={channel.icon_path} class="w-5 h-5 rounded-full object-cover mr-2 flex-shrink-0" />
                      <% else %>
                        <span class="mr-2 text-gray-500">#</span>
                      <% end %>
                      <span class="truncate"><%= channel.name %></span>
                    </a>
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- Private Channels Section --%>
            <div class="mb-6">
              <div class="flex items-center justify-between mb-2">
                <h2 class="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Private Channels</h2>
                <%!-- leave a small spacer to visually align --%>
                <div class="w-24"></div>
              </div>
              <ul class="space-y-0.5" id="private-channels-list" phx-hook="Sortable" data-group="private">
                <%= for channel <- @private_channels do %>
                  <li draggable="true" data-id={channel.id} class="cursor-move">
                    <a href="#" phx-click="switch_channel" phx-value-channel_id={channel.id} class={"flex items-center px-2 py-1.5 rounded text-sm hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors #{active_channel_class(channel, @current_channel)}"}>
                      <%= if channel.icon_path do %>
                        <img src={channel.icon_path} class="w-5 h-5 rounded-full object-cover mr-2 flex-shrink-0" />
                      <% else %>
                        <svg class="w-3 h-3 mr-2 flex-shrink-0 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"></path>
                        </svg>
                      <% end %>
                      <span class="truncate"><%= channel.name %></span>
                    </a>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
          <!-- Handle -->
          <div class="resize-handle absolute top-0 right-0 w-2 h-full cursor-col-resize hover:bg-blue-500/50 transition-colors z-20 flex items-center justify-center">
            <div class="w-1 h-8 bg-gray-400/50 rounded-full"></div>
          </div>
        </div>
        
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
          <div class="p-2 border-b border-cyan-500/30 flex items-center justify-between dark-glass shadow-sm h-14 relative z-30">
            <div class="flex items-center gap-3 flex-1 min-w-0">
              <form phx-change="validate_channel_icon" phx-drop-target={@uploads.channel_icon.ref} class="flex items-center relative group/icon-upload">
                <.live_file_input upload={@uploads.channel_icon} class="hidden" id="channel-icon-input" />
                
                <%= if @current_channel.icon_path do %>
                  <div class="relative">
                    <button type="button" phx-click="toggle_sidebar" class="relative" title="Toggle Sidebar (Drag & Drop to change icon)">
                       <img src={@current_channel.icon_path} class="w-10 h-10 rounded-full object-cover" />
                    </button>
                    <%= if ChatChannels.can_manage_channel?(@current_user, @current_channel) do %>
                      <button type="button" phx-click="remove_channel_icon" class="absolute -top-1 -right-1 w-5 h-5 bg-red-600 hover:bg-red-700 rounded-full flex items-center justify-center text-white text-xs opacity-0 group-hover/icon-upload:opacity-100 transition-opacity" title="Remove icon">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
                      </button>
                    <% end %>
                  </div>
                <% else %>
                  <%= if ChatChannels.can_manage_channel?(@current_user, @current_channel) do %>
                    <button type="button" onclick="this.parentElement.querySelector('input[type=file]').click()" class="cursor-pointer w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center border border-gray-600 hover:border-blue-500 transition-colors text-gray-400 hover:text-blue-400" title="Click or Drag & Drop to Upload Channel Icon">
                       <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path></svg>
                    </button>
                  <% else %>
                    <button type="button" phx-click="toggle_sidebar" class="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center border border-gray-600 text-gray-400" title="Toggle Sidebar">
                      <span class="text-lg font-bold">#</span>
                    </button>
                  <% end %>
                <% end %>
              </form>

              <div class="min-w-0">
                <h1 class="text-lg font-bold text-gray-800 dark:text-gray-200 truncate flex items-center gap-2">
                  #<%= @current_channel.name %>
                  <%= if @current_channel.description do %>
                    <span class="text-xs font-normal text-gray-500 dark:text-gray-400 truncate hidden sm:inline-block border-l border-gray-600 pl-2 ml-2"><%= @current_channel.description %></span>
                  <% end %>
                </h1>
              </div>
            </div>
            
            <div class="flex items-center space-x-4 ml-4">
              <%!-- Online Users --%>
              <div class="flex items-center space-x-3 text-xs text-gray-500 dark:text-gray-400 border-r border-gray-700 pr-4">
                <div class="flex items-center gap-2">
                  <svg class="w-3 h-3 text-green-400" fill="currentColor" viewBox="0 0 8 8"><circle cx="4" cy="4" r="4" /></svg>
                  <span class="hidden sm:inline"><%= Enum.count(assigns[:online_users] || []) %> online</span>
                </div>
                <div class="flex items-center -space-x-1">
                  <%= for user <- Enum.take(assigns[:online_users] || [], 5) do %>
                    <div class="relative group/avatar z-0 hover:z-10">
                      <%= avatar_tag(user, size_class: "w-6 h-6 cursor-pointer transition-transform hover:scale-110") %>
                      
                      <!-- User Hover Card -->
                      <div class="absolute right-0 top-full mt-2 w-80 bg-gray-800 border border-gray-700 rounded-lg shadow-xl z-50 opacity-0 invisible group-hover/avatar:opacity-100 group-hover/avatar:visible transition-all duration-200 p-4 pointer-events-none group-hover/avatar:pointer-events-auto text-left">
                        <div class="flex items-start space-x-4 mb-3">
                          <%= avatar_tag(user, size_class: "w-20 h-20") %>
                          <div class="flex-1 min-w-0">
                            <div class="font-bold text-white text-lg truncate"><%= Map.get(user, :name) || Map.get(user, :email) || "Unknown" %></div>
                            <%= if Map.get(user, :inserted_at) do %>
                              <div class="text-xs text-gray-400">Joined <%= Calendar.strftime(user.inserted_at, "%b %Y") %></div>
                            <% end %>
                            <%= if Map.get(user, :role) do %>
                              <div class={[
                                "mt-1 inline-block px-2 py-0.5 rounded text-xs font-bold border",
                                case user.role do
                                  "admin" -> "bg-red-900 text-red-200 border-red-700"
                                  "gm" -> "bg-purple-900 text-purple-200 border-purple-700"
                                  "editor" -> "bg-blue-900 text-blue-200 border-blue-700"
                                  "moderator" -> "bg-green-900 text-green-200 border-green-700"
                                  "member" -> "bg-gray-700 text-gray-200 border-gray-600"
                                  _ -> "bg-gray-700 text-gray-300 border-gray-600"
                                end
                              ]}>
                                <%= String.upcase(user.role) %>
                              </div>
                            <% end %>
                          </div>
                        </div>
                        
                        <%= if Map.get(user, :bio) do %>
                          <div class="text-sm text-gray-300 border-t border-gray-700 pt-2 break-words">
                            <%= user.bio %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <%= if Enum.count(assigns[:online_users] || []) > 5 do %>
                    <div class="w-6 h-6 rounded-full bg-gray-200 dark:bg-gray-700 border border-white text-[10px] flex items-center justify-center text-gray-800 dark:text-gray-200 z-0 relative">+<%= Enum.count(assigns[:online_users] || []) - 5 %></div>
                  <% end %>
                </div>
              </div>

              <%!-- Invite button for private channels --%>
                  <%= if @current_channel.is_private && (@current_user.is_admin || @current_user.role in ["admin", "gm", "editor"] || 
                    (@current_channel.owner_id && @current_channel.owner_id == @current_user.id) || @can_moderate) do %>
                <button phx-click="show_invite_modal" class="px-3 py-1.5 bg-green-600 hover:bg-green-700 text-white text-xs rounded transition-colors flex items-center gap-1.5">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3H4"></path>
                  </svg>
                  Invite
                </button>
              <% end %>
              
              <%!-- Members button - visible to all channel members/moderators --%>
              <%= if @current_user && @current_channel.is_private do %>
                <button phx-click="open_members_modal" phx-value-channel_id={@current_channel.id} class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white text-xs rounded transition-colors flex items-center gap-1.5" title="View Members">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"></path>
                  </svg>
                  Members
                </button>
              <% end %>
              
              <%!-- Delete button - only for admins and channel owners --%>
              <%= if @current_user && String.downcase(@current_channel.name) != "general" && (
                    Map.get(@current_user, :is_admin, false) || @current_user.role == "admin" ||
                    ( @current_channel.is_private && ((Map.has_key?(@current_channel, :owner_id) && @current_channel.owner_id == @current_user.id) || (Map.has_key?(@current_channel, :created_by_id) && @current_channel.created_by_id == @current_user.id)) )
                  ) do %>
                <button 
                  phx-click="show_delete_channel_confirm" 
                  class="px-3 py-1.5 bg-red-600 hover:bg-red-700 text-white text-xs rounded transition-colors flex items-center gap-1.5"
                  title="Delete Channel"
                >
                  <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                  Delete
                </button>
              <% end %>
            </div>
          </div>

        <div class="flex-1 relative flex flex-col min-h-0">
          <div id="messages" class="flex-1 px-4 pt-4 pb-2 overflow-y-auto dark-glass" phx-hook="MessageList" data-auto-scroll={if @auto_scroll_enabled, do: "true", else: "false"}>
            
            <%!-- Pinned Messages Section (Scrollable) --%>
            <%= if length(@pinned_messages) > 0 do %>
              <div class="dark-glass border border-yellow-500/30 p-3 mb-4 rounded-lg shadow-lg">
                <div class="text-xs font-bold text-yellow-400 mb-3 flex items-center gap-2">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"></path></svg>
                  PINNED MESSAGES
                </div>
                <div class="space-y-3">
                  <%= for message <- @pinned_messages do %>
                    <div class="bg-black/20 rounded-lg p-3 border border-yellow-500/10 hover:border-yellow-500/30 transition-colors">
                      <%!-- Show context if this is a pinned reply --%>
                      <%= if message.reply_to_id do %>
                        <div class="text-xs text-gray-500 mb-1 flex items-center gap-1">
                          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"></path></svg>
                          Reply to a message
                        </div>
                      <% end %>
                      <.message_item 
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
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

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
        <%= if @editing_message_id do %>
          <div class="p-3 border-t border-cyan-500/30 dark-glass bg-gray-800/90">
            <div class="text-xs text-gray-400 mb-2 flex items-center justify-between">
              <span>Editing message</span>
              <button type="button" phx-click="cancel_edit" class="text-gray-500 hover:text-gray-300">✕</button>
            </div>
            <.form for={%{}} phx-submit="apply_edit_message" phx-change="validate_edit" phx-drop-target={@uploads.edit_attachment.ref} class="mb-0">
              <input type="hidden" name="message_id" value={@editing_message_id} />
              
              <%!-- File upload previews for Edit --%>
              <%= if length(@uploads.edit_attachment.entries) > 0 do %>
                <div class="mb-2 flex flex-wrap gap-2">
                  <%= for entry <- @uploads.edit_attachment.entries do %>
                    <div class="relative group">
                      <.live_img_preview entry={entry} class="h-16 w-16 object-cover rounded border border-gray-300 dark:border-gray-600" />
                      <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} phx-value-upload_config="edit_attachment" class="absolute -top-2 -right-2 bg-red-500 text-white rounded-full w-5 h-5 flex items-center justify-center text-xs shadow-sm opacity-0 group-hover:opacity-100 transition-opacity">✕</button>
                      <div class="absolute bottom-0 left-0 right-0 h-1 bg-gray-200 rounded-b">
                        <div class="h-full bg-blue-500 rounded-b transition-all" style={"width: #{entry.progress}%"}></div>
                      </div>
                      <%= for err <- upload_errors(@uploads.edit_attachment, entry) do %>
                        <div class="absolute top-0 left-0 w-full h-full bg-red-500/50 flex items-center justify-center rounded">
                          <span class="text-white text-xs font-bold"><%= error_to_string(err) %></span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="relative">
                <textarea 
                  id="edit-message-textarea"
                  name="content" 
                  class="w-full p-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 pr-10" 
                  rows="2"
                  phx-hook="ChatInput"
                ><%= @editing_message_content %></textarea>
                <div class="absolute bottom-2 right-2 flex items-center space-x-2">
                  <label class="cursor-pointer text-gray-400 hover:text-gray-600 dark:hover:text-gray-200" title="Attach file">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                    </svg>
                    <.live_file_input upload={@uploads.edit_attachment} class="sr-only" />
                  </label>
                  <.emoji_picker target="#edit-message-textarea" id="edit-emoji-picker" />
                </div>
              </div>
              <div class="mt-2 flex space-x-2 justify-end">
                <button type="button" phx-click="cancel_edit" class="px-3 py-1 text-sm bg-gray-500 text-white rounded hover:bg-gray-600">Cancel</button>
                <% is_uploading = Enum.any?(@uploads.edit_attachment.entries, fn entry -> entry.progress < 100 end) %>
                <button type="submit" phx-disable-with="Saving..." disabled={is_uploading} class={"px-3 py-1 text-sm rounded text-white " <> if(is_uploading, do: "bg-blue-400 cursor-not-allowed", else: "bg-blue-600 hover:bg-blue-700")}>
                  <%= if is_uploading, do: "Uploading...", else: "Save" %>
                </button>
              </div>
            </.form>
          </div>
        <% end %>

        <%!-- Reply Form - Rendered outside the stream for proper upload handling --%>
        <%= if @replying_to_message_id do %>
          <div class="p-3 border-t border-cyan-500/30 dark-glass bg-gray-800/90">
            <div class="text-xs text-gray-400 mb-2 flex items-center justify-between">
              <span>Replying to message</span>
              <button type="button" phx-click="cancel_reply" class="text-gray-500 hover:text-gray-300">✕</button>
            </div>
            <.form for={%{}} phx-submit="send_reply" phx-change="validate_reply" phx-drop-target={@uploads.reply_attachment.ref} class="mb-0">
              <input type="hidden" name="reply_to_id" value={@replying_to_message_id} />
              
              <%!-- File upload previews for Reply --%>
              <%= if length(@uploads.reply_attachment.entries) > 0 do %>
                <div class="mb-2 flex flex-wrap gap-2">
                  <%= for entry <- @uploads.reply_attachment.entries do %>
                    <div class="relative group">
                      <.live_img_preview entry={entry} class="h-16 w-16 object-cover rounded border border-gray-300 dark:border-gray-600" />
                      <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} phx-value-upload_config="reply_attachment" class="absolute -top-2 -right-2 bg-red-500 text-white rounded-full w-5 h-5 flex items-center justify-center text-xs shadow-sm opacity-0 group-hover:opacity-100 transition-opacity">✕</button>
                      <div class="absolute bottom-0 left-0 right-0 h-1 bg-gray-200 rounded-b">
                        <div class="h-full bg-blue-500 rounded-b transition-all" style={"width: #{entry.progress}%"}></div>
                      </div>
                      <%= for err <- upload_errors(@uploads.reply_attachment, entry) do %>
                        <div class="absolute top-0 left-0 w-full h-full bg-red-500/50 flex items-center justify-center rounded">
                          <span class="text-white text-xs font-bold"><%= error_to_string(err) %></span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="relative">
                <textarea 
                  id="reply-message-textarea"
                  name="content" 
                  class="w-full p-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 pr-10" 
                  rows="2" 
                  placeholder="Write a reply..."
                  phx-hook="ChatInput"
                ><%= @reply_message_content %></textarea>
                <div class="absolute bottom-2 right-2 flex items-center space-x-2">
                  <label class="cursor-pointer text-gray-400 hover:text-gray-600 dark:hover:text-gray-200" title="Attach file">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                    </svg>
                    <.live_file_input upload={@uploads.reply_attachment} class="sr-only" />
                  </label>
                  <.emoji_picker target="#reply-message-textarea" id="reply-emoji-picker" />
                </div>
              </div>
              <div class="mt-2 flex space-x-2 justify-end">
                <button type="button" phx-click="cancel_reply" class="px-3 py-1 text-sm bg-gray-500 text-white rounded hover:bg-gray-600">Cancel</button>
                <% is_uploading = Enum.any?(@uploads.reply_attachment.entries, fn entry -> entry.progress < 100 end) %>
                <button type="submit" phx-disable-with="Sending..." disabled={is_uploading} class={"px-3 py-1 text-sm rounded text-white " <> if(is_uploading, do: "bg-blue-400 cursor-not-allowed", else: "bg-green-600 hover:bg-green-700")}>
                  <%= if is_uploading, do: "Uploading...", else: "Reply" %>
                </button>
              </div>
            </.form>
          </div>
        <% end %>

        <div class="p-2 border-t border-cyan-500/30 dark-glass">
          <form phx-submit="send_message" phx-change="validate_message" phx-drop-target={@uploads.forum_attachment.ref} onsubmit="return false;">
            <%!-- File upload previews --%>
            <%= if length(@uploads.forum_attachment.entries) > 0 do %>
              <div class="mb-2 p-2 bg-gray-50 dark:bg-gray-700 rounded-lg">
                <div class="text-xs text-gray-600 dark:text-gray-400 mb-1 font-medium">
                  Attachments (<%= length(@uploads.forum_attachment.entries) %>/5)
                </div>
                <div class="space-y-2">
                  <%= for entry <- @uploads.forum_attachment.entries do %>
                    <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-600 rounded">
                      <div class="flex items-center flex-1 min-w-0 mr-2">
                        <svg class="w-4 h-4 text-gray-500 dark:text-gray-300 flex-shrink-0 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                        </svg>
                        <span class="text-sm text-gray-700 dark:text-gray-200 truncate"><%= entry.client_name %></span>
                      </div>
                      <div class="flex items-center space-x-2 flex-shrink-0">
                        <div class="w-16 bg-gray-200 dark:bg-gray-500 rounded-full h-1.5">
                          <div class="bg-blue-500 h-1.5 rounded-full transition-all" style={"width: #{entry.progress}%"}></div>
                        </div>
                        <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} class="text-red-500 hover:text-red-700 text-xs">✕</button>
                      </div>
                    </div>
                    <%= for err <- upload_errors(@uploads.forum_attachment, entry) do %>
                      <p class="text-xs text-red-500 mt-1"><%= error_to_string(err) %></p>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>
            
            <div class="flex items-end space-x-2">
              <div class="flex-1 relative">
                <textarea 
                  id="chat-input-textarea"
                  name="message" 
                  value={@current_message}
                  placeholder="Type a message..." 
                  class="w-full py-1 px-3 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-sm text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none pr-20 leading-5"
                  rows="1"
                  phx-hook="ChatInput"
                  phx-keydown="typing"
                  phx-debounce="300"
                ></textarea>
                <div class="absolute bottom-1.5 right-2 flex items-center gap-1">
                  <label for={@uploads.forum_attachment.ref} class="cursor-pointer text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 p-1 rounded transition-colors" title="Attach files">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                    </svg>
                    <.live_file_input upload={@uploads.forum_attachment} class="sr-only" />
                  </label>
                  <.emoji_picker target="#chat-input-textarea" id="main-chat-emoji" />
                </div>
              </div>
              <div class="flex flex-col space-y-1">
                <% is_uploading = Enum.any?(@uploads.forum_attachment.entries, fn entry -> entry.progress < 100 end) %>
                <button type="submit" disabled={is_uploading} class={"flex items-center justify-center h-[30px] w-[30px] rounded-md transition-colors border border-transparent " <> if(is_uploading, do: "bg-gray-400 cursor-not-allowed", else: "bg-blue-500 text-white hover:bg-blue-600")}>
                  <%= if is_uploading do %>
                    <svg class="animate-spin w-4 h-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                  <% else %>
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
                    </svg>
                  <% end %>
                </button>
              </div>
            </div>
          </form>
        </div>
        </div>
      </div>

    <%!-- Delete Channel Confirmation Modal --%>
    <%!-- Channel Member Management Modal --%>
    <%= if @show_channel_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="hide_members_modal"></div>
        <div class="relative bg-white dark:bg-gray-800 rounded-xl shadow-xl p-6 max-w-3xl w-full mx-4 border">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100">Members — #<%= @editing_channel.name %></h3>
            <button phx-click="hide_members_modal" class="text-gray-500 hover:text-gray-700">✕</button>
          </div>

          <div class="space-y-3">
            <% can_manage = ChatChannels.can_manage_channel?(@current_user, @editing_channel) %>
            <% can_moderate = ChatChannels.can_moderate_channel?(@current_user, @editing_channel) %>
            <% show_actions = can_manage || can_moderate %>
            
            <div class={"grid gap-4 font-medium text-sm text-gray-500 dark:text-gray-300 border-b pb-2 " <> if(show_actions, do: "grid-cols-3", else: "grid-cols-2")}>
              <div>Member</div>
              <div>Role</div>
              <%= if show_actions do %>
                <div class="text-right">Actions</div>
              <% end %>
            </div>

            <%= for member <- (@channel_members || []) do %>
              <div class={"grid gap-4 items-center py-2 border-b " <> if(show_actions, do: "grid-cols-3", else: "grid-cols-2")}>
                <div class="flex items-center gap-3">
                  <%= if member.user do %>
                    <%= avatar_tag(member.user, size_class: "w-8 h-8") %>
                    <div class="text-sm flex items-center gap-1">
                      <%= member.user.name || member.user.email %>
                      <%= if @editing_channel.owner_id == member.user_id do %>
                        <span class="text-yellow-500" title="Channel Owner">👑</span>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="w-8 h-8 rounded-full bg-gray-600 flex items-center justify-center text-white text-sm">?</div>
                    <div class="text-sm text-gray-400">Unknown user</div>
                  <% end %>
                </div>

                <div>
                  <%= if member.role == "invited" do %>
                    <div class="inline-flex items-center gap-2 text-xs text-gray-600 dark:text-gray-300">
                      <span class="px-2 py-0.5 rounded bg-yellow-100 dark:bg-yellow-700 text-yellow-800 dark:text-yellow-100">Invited</span>
                      <span class="text-xs text-gray-500">(pending)</span>
                    </div>
                  <% else %>
                    <%= if member.is_banned do %>
                      <div class="inline-flex items-center gap-2">
                        <span class="px-2 py-0.5 rounded bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-100 text-xs font-bold">BANNED</span>
                        <span class="text-sm text-gray-500 dark:text-gray-400"><%= String.capitalize(member.role) %></span>
                      </div>
                    <% else %>
                      <%= if is_nil(member.id) and member.role == "owner" do %>
                        <div class="inline-flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200">Owner</div>
                      <% else %>
                        <%= if member.user_id == @current_user.id do %>
                          <div class="inline-flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200"><%= String.capitalize(member.role) %></div>
                        <% else %>
                          <%= if can_manage do %>
                            <form phx-change="change_member_role" phx-submit="noop" class="inline-block">
                              <input type="hidden" name="member_id" value={member.id} />
                              <select name="new_role" class="p-1 rounded bg-gray-100 dark:bg-gray-700 text-sm border">
                                <option value="moderator" selected={member.role == "moderator"}>Moderator</option>
                                <option value="member" selected={member.role == "member"}>Member</option>
                              </select>
                            </form>
                          <% else %>
                            <div class="inline-flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200"><%= String.capitalize(member.role) %></div>
                          <% end %>
                        <% end %>
                      <% end %>
                    <% end %>
                  <% end %>
                </div>

                <%= if show_actions do %>
                  <div class="text-right">
                    <div class="inline-flex gap-2">
                      <%= if member.role == "invited" do %>
                        <button phx-click="revoke_invite" phx-value-invite_id={Map.get(member, :_invite_id)} class="px-2 py-1 bg-red-500 hover:bg-red-600 text-white rounded text-xs">Revoke Invite</button>
                      <% else %>
                        <%!-- Only show member-management actions for real ChannelMember records (member.id present). Owner pseudo entries don't get manage buttons here. --%>
                        <%= if member.id && member.user_id != @current_user.id do %>
                          <%!-- Moderators cannot ban/kick the Owner --%>
                          <%= if can_moderate && member.role != "owner" && member.user_id != @editing_channel.owner_id do %>
                            <%= if member.is_banned do %>
                              <button phx-click="unban_member" phx-value-member_id={member.id} class="px-2 py-1 bg-green-500 hover:bg-green-600 text-white rounded text-xs">Unban</button>
                            <% else %>
                              <button phx-click="ban_member" phx-value-member_id={member.id} class="px-2 py-1 bg-red-500 hover:bg-red-600 text-white rounded text-xs">Ban</button>
                            <% end %>
                            <button phx-click="kick_member" phx-value-member_id={member.id} class="px-2 py-1 bg-gray-500 hover:bg-gray-600 text-white rounded text-xs">Kick</button>
                          <% end %>
                        <% end %>

                        <%!-- Only show Make Owner button if member is not already the owner --%>
                        <%= if member.role != "owner" && @editing_channel.owner_id != member.user_id && member.user_id != @current_user.id do %>
                          <%= if can_manage do %>
                            <button phx-click="transfer_ownership" phx-value-new_owner_id={member.user_id} class="px-2 py-1 bg-blue-500 hover:bg-blue-600 text-white rounded text-xs">Make Owner</button>
                          <% end %>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>

    <%!-- Create Channel Modal (used for both admin/system channel creation and user-created private channels) --%>
    <%= if @show_create_channel_form do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="hide_create_channel"></div>
        <div class="relative bg-gray-800 rounded-xl shadow-xl p-6 max-w-md w-full mx-4 border border-cyan-500/50">
          <h3 class="text-xl font-bold text-white mb-4"><%= if @creating_user_channel, do: "Create Private Channel", else: "Create Channel" %></h3>

          <.form for={@channel_form} phx-submit={if @creating_user_channel, do: "create_user_channel", else: "create_channel"} phx-change="validate_channel" class="space-y-3">
            <div>
              <.input field={@channel_form[:name]} label="Name" class="w-full mt-1 p-2 rounded bg-gray-900 text-white" />
            </div>

            <div>
              <.input field={@channel_form[:description]} type="textarea" label="Description (optional)" class="w-full mt-1 p-2 rounded bg-gray-900 text-white" rows="3" />
            </div>

            <div class="flex items-center gap-3">
              <.input field={@channel_form[:is_private]} type="checkbox" label="Private channel (only invited/members can view)" />
            </div>

            <div class="flex justify-end gap-3 mt-4">
              <button phx-click="hide_create_channel" type="button" class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded">Cancel</button>
              <button type="submit" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded">Create</button>
            </div>
          </.form>

        </div>
      </div>
    <% end %>
    <%= if @show_delete_channel_confirm do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="cancel_delete_channel"></div>
        <div class="relative bg-gray-800 rounded-xl shadow-xl p-6 max-w-md w-full mx-4 border border-red-500/50">
          <div class="flex items-start mb-4">
            <div class="flex-shrink-0">
              <svg class="h-10 w-10 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
            </div>
            <div class="ml-4">
              <h3 class="text-lg font-medium text-white mb-2">Delete Channel</h3>
              <p class="text-gray-300 text-sm mb-4">
                Are you sure you want to delete <span class="font-bold text-white">#<%= @current_channel.name %></span>?
              </p>
              <p class="text-red-400 text-sm font-medium">
                ⚠️ This will permanently delete:
              </p>
              <ul class="text-gray-300 text-sm mt-2 ml-4 space-y-1">
                <li>• All messages in this channel</li>
                <li>• All uploaded files and attachments</li>
                <li>• All reactions and threads</li>
              </ul>
              <p class="text-red-400 text-sm font-bold mt-3">
                This action cannot be undone!
              </p>
            </div>
          </div>
          
          <div class="flex justify-end gap-3">
            <button 
              phx-click="cancel_delete_channel" 
              class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors"
            >
              Cancel
            </button>
            <button 
              phx-click="confirm_delete_channel" 
              class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded transition-colors font-medium"
            >
              Delete Permanently
            </button>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Image Viewer Modal -->
    <%= if @show_image_viewer do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/90" phx-click="close_image_viewer"></div>
        <div class="relative max-w-7xl max-h-screen w-full h-full p-8 flex flex-col">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-white font-medium"><%= @viewer_image_filename %></h3>
            <div class="flex gap-2">
              <a href={@viewer_image_url} download={@viewer_image_filename} class="p-2 bg-gray-800 hover:bg-gray-700 rounded-lg transition-colors">
                <svg class="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1M4 4h16v8H4z" />
                </svg>
              </a>
              <button phx-click="close_image_viewer" class="p-2 bg-gray-800 hover:bg-gray-700 rounded-lg transition-colors">
                <svg class="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>
          <div class="flex-1 flex items-center justify-center overflow-hidden">
            <img src={@viewer_image_url} alt={@viewer_image_filename} class="max-w-full max-h-full object-contain" />
          </div>
        </div>
      </div>
    <% end %>

    <!-- Invite Modal -->
    <%= if @show_invite_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="hide_invite_modal"></div>
        <div class="relative bg-gray-800 rounded-xl shadow-xl p-6 max-w-md w-full mx-4 border border-cyan-500/50">
          <h3 class="text-xl font-bold text-white mb-4">Invite Users to <%= @current_channel.name %></h3>
          <p class="text-gray-300 text-sm mb-4">Invite people by username/email or create a shareable invite code.</p>

          <div class="grid grid-cols-1 gap-4">
            <%!-- Personal invite form (username or email) --%>
            <div class="bg-gray-900 rounded p-3">
              <h4 class="text-sm font-semibold text-white mb-2">Invite a specific user</h4>
              <.form phx-submit="create_personal_invite" for={%{}} class="flex gap-2 items-center">
                <input name="invitee_id" placeholder="username or email" class="flex-1 p-2 rounded bg-gray-800 text-white text-sm" />
                <button type="submit" class="px-3 py-2 bg-indigo-600 hover:bg-indigo-700 text-white text-sm rounded">Invite</button>
              </.form>
            </div>

            <%!-- Channel invite code form (creates server-side invite) --%>
            <div class="bg-gray-900 rounded p-3">
              <h4 class="text-sm font-semibold text-white mb-2">Create invite code</h4>
              <.form phx-submit="create_channel_invite" for={%{}} class="space-y-2">
                <div class="flex gap-2">
                  <input name="max_uses" placeholder="Max uses (optional)" class="flex-1 p-2 rounded bg-gray-800 text-white text-sm" />
                  <input name="expires_at" type="datetime-local" class="p-2 rounded bg-gray-800 text-white text-sm" />
                </div>
                <div class="flex justify-end gap-2">
                  <button type="submit" class="px-3 py-2 bg-cyan-600 hover:bg-cyan-700 text-white text-sm rounded">Create code</button>
                </div>
              </.form>
            </div>
          </div>
          <div class="flex justify-end gap-3">
            <button phx-click="hide_invite_modal" class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors">
              Close
            </button>
          </div>
        </div>
      </div>
    <% end %>
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

  defp active_channel_class(channel, current_channel) do
    if channel.id == current_channel.id do
      "bg-blue-500 text-white"
    else
      "text-gray-600 dark:text-gray-400"
    end
  end

  # Helper for upload errors
  defp error_to_string(:too_large), do: "File is too large (max 100MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"

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