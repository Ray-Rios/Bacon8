defmodule Bacon8Web.DesktopLive do
  @moduledoc """
  Global desktop environment (taskbar + windows).
  
  This LiveComponent provides a persistent desktop environment with taskbar and windows.
  """
  use Bacon8Web, :live_component
  require Logger
  alias Phoenix.PubSub

  def update(assigns, socket) do
    # Subscribe to desktop updates for real-time collaboration
    if connected?(socket) do
      PubSub.subscribe(Bacon8.PubSub, "desktop:public")
      
      # Subscribe to user-specific invite notifications
      if assigns[:current_user] do
        PubSub.subscribe(Bacon8.PubSub, "user:#{assigns.current_user.id}:invites")
        # Subscribe to user notifications (mentions, etc.)
        PubSub.subscribe(Bacon8.PubSub, "user:#{assigns.current_user.id}:notifications")
      end
    end
    
    # Load pending invites count for notification badge
    pending_invite_count = if assigns[:current_user] do
      Bacon8.Forum.count_pending_invites(assigns.current_user.id)
    else
      0
    end
    
    # Load unread mention notifications count
    unread_notification_count = if assigns[:current_user] do
      Bacon8.Notifications.count_unread_notifications(assigns.current_user.id)
    else
      0
    end
    
    # TEMPORARILY DISABLED: Window persistence causing database errors
    # Restore saved windows on mount
    # windows = if socket.assigns[:windows] do
    #   socket.assigns.windows
    # else
    #   restore_saved_windows(assigns[:current_user])
    # end
    
    socket = socket
    |> assign(assigns)
    |> assign_new(:windows, fn -> [] end)
    |> assign_new(:next_z_index, fn -> 1 end)
    |> assign_new(:show_start_menu, fn -> false end)
    |> assign_new(:show_notifications, fn -> false end)
    |> assign_new(:show_audio_panel, fn -> false end)
    |> assign_new(:show_calendar, fn -> false end)
    |> assign_new(:taskbar_projects, fn -> [] end)
    |> assign_new(:calendar_events, fn -> 
       if assigns[:current_user] do
         try do
           Bacon8.Scheduler.list_upcoming_events(10)
         rescue
           _ -> []
         end
       else
         []
       end
    end)
    |> assign_new(:selected_date, fn -> nil end)
    |> assign_new(:pending_invites, fn -> [] end)
    |> assign(:pending_invite_count, pending_invite_count)
    |> assign_new(:mention_notifications, fn -> 
      if assigns[:current_user] do
        Bacon8.Notifications.list_user_notifications(assigns.current_user.id, limit: 10)
      else
        []
      end
    end)
    |> assign(:unread_notification_count, unread_notification_count)
    |> assign_new(:taskbar_visible, fn -> true end)
    |> allow_upload(:files, 
         accept: :any, 
         max_entries: 5, 
         max_file_size: get_max_file_size(assigns[:current_user]),
         auto_upload: true,
         progress: &handle_progress/3
       )

    {:ok, socket}
  end

  # Uploads auto-start (allow_upload auto_upload: true), so each finished entry
  # is saved here - there is no submit step. My Files goes to Bacon8.Drive;
  # /public (staff only) is still the legacy filesystem drive.
  defp handle_progress(:files, entry, socket) do
    with true <- entry.done?,
         window_id when not is_nil(window_id) <- socket.assigns[:upload_window_id],
         %{} = window <- Enum.find(socket.assigns.windows, &(&1.id == window_id)) do
      user = socket.assigns.current_user

      result =
        if my_files_path?(window.current_path),
          do: upload_to_drive(socket, user, window.current_path, entry),
          else: upload_to_public(socket, user, window.current_path, entry)

      socket = refresh_file_manager(socket, window_id)

      case result do
        :ok -> {:noreply, socket}
        {:error, message} -> {:noreply, put_flash(socket, :error, message)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp upload_to_drive(socket, user, path, entry) do
    case drive_folder_for_path(user, path) do
      {:ok, folder_id} ->
        consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
          {:ok, Bacon8.Drive.add_file(user, folder_id, tmp, entry.client_name)}
        end)
        |> case do
          {:ok, _file} -> :ok
          {:error, reason} -> {:error, drive_error_message(reason)}
        end

      _ ->
        consume_uploaded_entry(socket, entry, fn _ -> {:ok, :dropped} end)
        {:error, "That folder no longer exists."}
    end
  end

  defp upload_to_public(socket, user, path, entry) do
    dest = get_file_explorer_real_path(path, user)

    if dest && File.dir?(dest) && can_write_explorer_path?(path, user) do
      case consume_uploaded_entry(socket, entry, fn %{path: tmp} -> copy_upload_to(dest, tmp, entry) end) do
        :rejected -> {:error, "That file name or type isn't allowed."}
        _ -> :ok
      end
    else
      consume_uploaded_entry(socket, entry, fn _ -> {:ok, :dropped} end)
      {:error, "You can't upload files here."}
    end
  end

  defp drive_error_message(:too_large), do: "That file is larger than your account's upload limit."
  defp drive_error_message(:quota_exceeded), do: "Not enough storage space. Free up space or choose a larger storage tier."
  defp drive_error_message(:locked), do: "Your files are locked while your account is restricted."
  defp drive_error_message(:no_storage), do: "Your account type can't store files."
  defp drive_error_message(:account_inactive), do: "Your account is not active."
  defp drive_error_message(:file_type_not_allowed), do: "HTML, SVG and script files can't be uploaded."
  defp drive_error_message({:invalid_name, msg}), do: "Invalid name: #{msg}."
  defp drive_error_message(:not_found), do: "That item no longer exists."
  defp drive_error_message(:cannot_move_into_itself), do: "A folder can't be moved into itself."
  defp drive_error_message(%Ecto.Changeset{} = cs) do
    case cs.errors do
      [{field, {msg, _}} | _] -> "#{Phoenix.Naming.humanize(field)} #{msg}."
      _ -> "That couldn't be saved."
    end
  end
  defp drive_error_message(other) do
    Logger.warning("Drive operation failed: #{inspect(other)}")
    "Something went wrong. Please try again."
  end

  # Per-role single-file limit lives in Bacon8.Drive.Policy.max_upload_bytes/1.
  defp get_max_file_size(user), do: Bacon8.Drive.Policy.upload_limit_for_live_view(user)

  # ==================== EVENT HANDLERS ====================

  def handle_event("toggle_start_menu", _params, socket) do
    {:noreply, assign(socket, show_start_menu: !socket.assigns.show_start_menu, show_notifications: false, show_audio_panel: false, show_calendar: false)}
  end

  def handle_event("toggle_notifications", _params, socket) do
    # Load fresh invites and notifications when opening panel
    {show_notifications, pending_invites, mention_notifications} = if !socket.assigns.show_notifications && socket.assigns.current_user do
      invites = Bacon8.Forum.list_pending_invites_for_user(socket.assigns.current_user.id)
      mentions = Bacon8.Notifications.list_user_notifications(socket.assigns.current_user.id, limit: 20)
      {true, invites, mentions}
    else
      {false, [], []}
    end
    
    {:noreply, assign(socket, 
      show_notifications: show_notifications, 
      pending_invites: pending_invites,
      mention_notifications: mention_notifications,
      show_audio_panel: false, 
      show_calendar: false
    )}
  end

  def handle_event("toggle_audio_panel", _params, socket) do
    {:noreply, assign(socket, show_audio_panel: !socket.assigns.show_audio_panel, show_notifications: false, show_start_menu: false, show_calendar: false)}
  end

  def handle_event("toggle_calendar", _params, socket) do
    show = !socket.assigns.show_calendar
    socket = if show do
      projects = Bacon8.Scheduler.list_projects_for_calendar()
      events = try do
        Bacon8.Scheduler.list_upcoming_events(10)
      rescue
        _ -> []
      end
      assign(socket, show_calendar: show, show_notifications: false, show_start_menu: false, show_audio_panel: false, selected_date: nil, taskbar_projects: projects, calendar_events: events)
    else
      assign(socket, show_calendar: show, show_notifications: false, show_start_menu: false, show_audio_panel: false, selected_date: nil)
    end

    {:noreply, socket}
  end

  def handle_event("select_date", %{"day" => day}, socket) do
    # Construct date string YYYY-MM-DD
    today = Date.utc_today()
    date_str = "#{today.year}-#{String.pad_leading(to_string(today.month), 2, "0")}-#{String.pad_leading(to_string(day), 2, "0")}"
    
    {:noreply, assign(socket, selected_date: date_str)}
  end

  # Calendar notes feature removed - now using project events

  def handle_event("close_note_input", _params, socket) do
    {:noreply, assign(socket, selected_date: nil)}
  end

  def handle_event("toggle_notification_sound", _params, socket) do
    if socket.assigns.current_user do
      new_value = !socket.assigns.current_user.notification_sound_enabled
      
      case Bacon8.Accounts.update_audio_preferences(socket.assigns.current_user, %{notification_sound_enabled: new_value}) do
        {:ok, updated_user} ->
          {:noreply, 
           socket
           |> assign(current_user: updated_user)
           |> push_event("notification_sound_toggled", %{enabled: new_value})}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update audio preferences")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_volume", %{"volume" => volume_str}, socket) do
    if socket.assigns.current_user do
      # Handle both integer strings ("50") and float strings ("0.5")
      volume = case Float.parse(volume_str) do
        {val, _} -> val / 100.0
        :error -> 
          case Integer.parse(volume_str) do
            {val, _} -> val / 100.0
            :error -> 0.5
          end
      end
      
      case Bacon8.Accounts.update_audio_preferences(socket.assigns.current_user, %{master_volume: volume}) do
        {:ok, updated_user} ->
          {:noreply, 
           socket
           |> assign(current_user: updated_user)
           |> push_event("volume_changed", %{volume: volume})}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update volume")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("test_sound", _params, socket) do
    if socket.assigns.current_user do
      volume = socket.assigns.current_user.master_volume || 0.5
      sound_path = "/audio/ui/notification.mp3"
      {:noreply, push_event(socket, "play_sound", %{path: sound_path, volume: volume})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("accept_invite", %{"invite_id" => invite_id}, socket) do
    require Logger
    Logger.info("Desktop: accept_invite called invite_id=#{invite_id} user=#{socket.assigns.current_user && socket.assigns.current_user.id}")
    require Logger
    # invite_id is a UUID string, keep it as-is
    Logger.info("Accepting invite #{invite_id} for user #{socket.assigns.current_user.id}")
    
    case Bacon8.Forum.accept_channel_invite(invite_id, socket.assigns.current_user.id) do
      {:ok, _member} ->
        Logger.info("Successfully accepted invite #{invite_id}")
        # Reload invites and count
        pending_invites = Bacon8.Forum.list_pending_invites_for_user(socket.assigns.current_user.id)
        pending_invite_count = length(pending_invites)
        
        {:noreply,
         socket
         |> assign(pending_invites: pending_invites, pending_invite_count: pending_invite_count)
         |> put_flash(:info, "✓ Joined channel successfully!")}
      
      {:error, reason} ->
        Logger.error("Failed to accept invite #{invite_id}: #{inspect(reason)}")
        message = case reason do
          :not_found -> "Invite not found"
          :forbidden -> "You don't have permission to accept this invite"
          :invite_expired -> "This invite has expired"
          :already_member -> "You're already a member of this channel"
          _ -> "Failed to accept invite: #{inspect(reason)}"
        end
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("schedule_meeting", %{"title" => title}, socket) do
    # In a real implementation, this would create a database record
    # For now, we'll just simulate success
    
    {:noreply, 
     socket
     |> assign(show_calendar: false)
     |> put_flash(:info, "Meeting '#{title}' scheduled successfully in channel!")}
  end

  def handle_event("decline_invite", %{"invite_id" => invite_id}, socket) do
    require Logger
    Logger.info("Desktop: decline_invite called invite_id=#{invite_id} user=#{socket.assigns.current_user && socket.assigns.current_user.id}")
    require Logger
    # invite_id is a UUID string, keep it as-is
    Logger.info("Declining invite #{invite_id} for user #{socket.assigns.current_user.id}")
    
    case Bacon8.Forum.decline_invite(invite_id, socket.assigns.current_user.id) do
      {:ok, _} ->
        Logger.info("Successfully declined invite #{invite_id}")
        # Reload invites and count
        pending_invites = Bacon8.Forum.list_pending_invites_for_user(socket.assigns.current_user.id)
        pending_invite_count = length(pending_invites)
        
        {:noreply, assign(socket, pending_invites: pending_invites, pending_invite_count: pending_invite_count)}
      
      {:error, reason} ->
        Logger.error("Failed to decline invite #{invite_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to decline invite")}
    end
  end

  def handle_event("open_mention", %{"notification_id" => notification_id, "channel_id" => channel_id, "message_id" => message_id}, socket) do
    # Mark notification as read
    if socket.assigns.current_user do
      case Bacon8.Notifications.get_notification(socket.assigns.current_user.id, notification_id) do
        nil -> :ok
        notification -> Bacon8.Notifications.mark_as_read(notification)
      end
    end
    
    # Close notification panel and navigate to the forum with channel/message context
    # Build URL to navigate to the message
    forum_url = "/forum?channel=#{channel_id}&message=#{message_id}"
    
    {:noreply, 
     socket
     |> assign(show_notifications: false)
     |> push_navigate(to: forum_url)}
  end

  def handle_event("mark_all_notifications_read", _params, socket) do
    if socket.assigns.current_user do
      Bacon8.Notifications.mark_all_as_read(socket.assigns.current_user.id)
      
      # Reload notifications
      mention_notifications = Bacon8.Notifications.list_user_notifications(socket.assigns.current_user.id, limit: 20)
      
      {:noreply, assign(socket, 
        mention_notifications: mention_notifications,
        unread_notification_count: 0
      )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_upload", _, socket) do
    {:noreply, socket}
  end

  def handle_event("open_app", %{"app" => app}, socket) do
    Logger.info("Opening app: #{app}")
    
    window_id = Ecto.UUID.generate()
    user = socket.assigns.current_user
    
    # TEMPORARILY DISABLED: Load saved layout if available (causing DB errors)
    # saved_layout = if user do
    #   Bacon8.Desktop.get_window_layout(user.id, app)
    # else
    #   nil
    # end
    
    new_window = case app do
      "file_manager" ->
        # New Windows-like File Explorer
        is_admin = user && user.is_admin
        
        # Calculate storage usage for user
        {storage_used, storage_quota} = drive_storage(user)
        
        # Start at My Files for logged in users, Public for guests
        initial_path = if user, do: "/my-files", else: "/public"
        initial_items = get_file_explorer_items(initial_path, user)

        %{
          id: window_id,
          title: "File Explorer",
          app: "file_manager",
          x: 100,
          y: 80,
          width: 900,
          height: 600,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index,
          # Navigation
          current_path: initial_path,
          current_items: initial_items,
          breadcrumbs: build_file_explorer_breadcrumbs(initial_path),
          history: [initial_path],
          forward_history: [],
          # View options
          view_mode: "details",
          sort_by: "name",
          sort_order: "asc",
          filter_type: "all",
          search_query: "",
          # Selection
          selected_items: [],
          # Storage info
          storage_used: storage_used,
          storage_quota: storage_quota,
          # Permissions
          is_admin: is_admin || false,
          user_id: user && user.id
        }
      
      "text_editor" ->
        %{
          id: window_id,
          title: "Text Editor",
          app: "text_editor",
          x: 200,
          y: 200,
          width: 700,
          height: 500,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index,
          content: ""
        }
      
      "terminal" ->
        %{
          id: window_id,
          title: "Terminal",
          app: "terminal",
          x: 250,
          y: 250,
          width: 800,
          height: 500,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index,
          history: [],
          current_directory: "~"
        }
      
      "calculator" ->
        %{
          id: window_id,
          title: "Calculator",
          app: "calculator",
          x: 300,
          y: 300,
          width: 350,
          height: 450,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index,
          display: "0",
          memory: 0
        }
      
      "notepad" ->
        %{
          id: window_id,
          title: "Notepad",
          app: "notepad",
          x: 350,
          y: 150,
          width: 600,
          height: 400,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index,
          content: ""
        }
      
      "media_player" ->
        %{
          id: window_id,
          title: "Media Player",
          app: "media_player",
          x: 400,
          y: 200,
          width: 600,
          height: 400,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index,
          current_track: nil,
          playing: false
        }
      
      "settings" ->
        %{
          id: window_id,
          title: "Settings",
          app: "settings",
          x: 450,
          y: 250,
          width: 700,
          height: 500,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index
        }
      
      _ ->
        %{
          id: window_id,
          title: "Unknown App",
          app: "unknown",
          x: 100,
          y: 100,
          width: 400,
          height: 300,
          minimized: false,
          maximized: false,
          z_index: socket.assigns.next_z_index
        }
    end
    
    {:noreply, 
     socket
     |> assign(:windows, [new_window | socket.assigns.windows])
     |> assign(:next_z_index, socket.assigns.next_z_index + 1)
     |> assign(:show_start_menu, false)}
  end

  def handle_event("close_window", params, socket) do
    with id when not is_nil(id) <- get_window_id(params) do
      # TEMPORARILY DISABLED: Save window state before closing
      # window_to_close = Enum.find(socket.assigns.windows, &(&1.id == id))
      # if window_to_close && socket.assigns.current_user do
      #   save_window_state(socket.assigns.current_user.id, window_to_close)
      # end
      
      windows = Enum.reject(socket.assigns.windows, &(&1.id == id))
      {:noreply, assign(socket, :windows, windows)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("focus_window", params, socket) do
    with id when not is_nil(id) <- get_window_id(params) do
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == id do
          %{window | z_index: socket.assigns.next_z_index}
        else
          window
        end
      end)
    
    {:noreply, 
     socket
     |> assign(:windows, windows)
     |> assign(:next_z_index, socket.assigns.next_z_index + 1)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("minimize_window", params, socket) do
    with id when not is_nil(id) <- get_window_id(params) do
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == id do
          updated_window = %{window | minimized: !window.minimized}
          
          # Save state
          if socket.assigns.current_user do
            # TEMP DISABLED: save_window_state(socket.assigns.current_user.id, updated_window)
          end
          
          updated_window
        else
          window
        end
      end)
    
      {:noreply, assign(socket, :windows, windows)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(event, params, socket) when event in ["toggle_maximize", "maximize_window", "restore_window"] do
    with id when not is_nil(id) <- get_window_id(params) do
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == id do
          updated_window = %{window | maximized: !window.maximized}
          
          # Save state
          if socket.assigns.current_user do
            # TEMP DISABLED: save_window_state(socket.assigns.current_user.id, updated_window)
          end
          
          updated_window
        else
          window
        end
      end)
    
      {:noreply, assign(socket, :windows, windows)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update_window_position", params, socket) do
    with id when not is_nil(id) <- get_window_id(params) do
      windows = 
        Enum.map(socket.assigns.windows, fn window ->
          if window.id == id do
            updated_window = %{window | x: params["x"], y: params["y"]}
            
            # TEMP DISABLED: Persist to database if user is authenticated
            # if socket.assigns.current_user do
            #   Task.start(fn ->
            #     Bacon8.Desktop.save_window_layout(
            #       socket.assigns.current_user.id,
            #       window.app,
            #       %{x: params["x"], y: params["y"], width: window.width, height: window.height}
            #     )
            #   end)
            # end
            
            updated_window
          else
            window
          end
        end)
      
      {:noreply, assign(socket, :windows, windows)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_file", %{"url" => url}, socket) when not is_nil(url) and url != "" do
    {:noreply, push_event(socket, "open_url", %{url: url})}
  end

  def handle_event("open_file", %{"path" => path}, socket) do
    url = resolve_virtual_path_to_url(path, socket.assigns.current_user)
    if url do
      {:noreply, push_event(socket, "open_url", %{url: url})}
    else
      {:noreply, put_flash(socket, :error, "Cannot open file")}
    end
  end

  def handle_event("update_window_size", params, socket) do
    with id when not is_nil(id) <- get_window_id(params) do
      windows = 
        Enum.map(socket.assigns.windows, fn window ->
          if window.id == id do
            updated_window = %{window | width: params["width"], height: params["height"]}
            
            # TEMP DISABLED: Persist to database if user is authenticated
            # if socket.assigns.current_user do
            #   Task.start(fn ->
            #     Bacon8.Desktop.save_window_layout(
            #       socket.assigns.current_user.id,
            #       window.app,
            #       %{x: window.x, y: window.y, width: params["width"], height: params["height"]}
            #     )
            #   end)
            # end
            
            updated_window
          else
            window
          end
        end)
      
      {:noreply, assign(socket, :windows, windows)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update_window_layout", params, socket) do
    with id when not is_nil(id) <- get_window_id(params) do
      windows = 
        Enum.map(socket.assigns.windows, fn window ->
          if window.id == id do
            updated_window = %{window | 
              width: params["width"], 
              height: params["height"],
              x: params["x"],
              y: params["y"]
            }
            
            # TEMP DISABLED: Persist to database if user is authenticated
            # if socket.assigns.current_user do
            #   Task.start(fn ->
            #     Bacon8.Desktop.save_window_layout(
            #       socket.assigns.current_user.id,
            #       window.app,
            #       %{x: params["x"], y: params["y"], width: params["width"], height: params["height"]}
            #     )
            #   end)
            # end
            
            updated_window
          else
            window
          end
        end)
      
      {:noreply, assign(socket, :windows, windows)}
    else
      _ -> {:noreply, socket}
    end
  end

  # ==================== FILE EXPLORER HANDLERS ====================

  # Navigate to a path
  def handle_event("fm_navigate_to", %{"path" => path, "window_id" => window_id}, socket) do
    user = socket.assigns.current_user
    
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          items = get_file_explorer_items(path, user)
          breadcrumbs = build_file_explorer_breadcrumbs(path)
          
          # Update history for back/forward navigation
          new_history = [path | window.history] |> Enum.take(50)
          
          %{window | 
            current_path: path, 
            current_items: sort_items(items, window.sort_by, window.sort_order),
            breadcrumbs: breadcrumbs,
            history: new_history,
            forward_history: [],
            selected_items: []
          }
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Navigate back in history
  def handle_event("fm_navigate_back", %{"window_id" => window_id}, socket) do
    user = socket.assigns.current_user
    
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" && length(window.history) > 1 do
          [current | [previous | rest]] = window.history
          
          items = get_file_explorer_items(previous, user)
          breadcrumbs = build_file_explorer_breadcrumbs(previous)
          
          %{window | 
            current_path: previous, 
            current_items: sort_items(items, window.sort_by, window.sort_order),
            breadcrumbs: breadcrumbs,
            history: [previous | rest],
            forward_history: [current | window.forward_history],
            selected_items: []
          }
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Navigate forward in history
  def handle_event("fm_navigate_forward", %{"window_id" => window_id}, socket) do
    user = socket.assigns.current_user
    
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" && window.forward_history != [] do
          [next | rest] = window.forward_history
          
          items = get_file_explorer_items(next, user)
          breadcrumbs = build_file_explorer_breadcrumbs(next)
          
          %{window | 
            current_path: next, 
            current_items: sort_items(items, window.sort_by, window.sort_order),
            breadcrumbs: breadcrumbs,
            history: [next | window.history],
            forward_history: rest,
            selected_items: []
          }
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Navigate up one level
  def handle_event("fm_navigate_up", %{"window_id" => window_id}, socket) do
    user = socket.assigns.current_user
    
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" && window.current_path != "/" do
          parent_path = get_file_explorer_parent_path(window.current_path)
          items = get_file_explorer_items(parent_path, user)
          breadcrumbs = build_file_explorer_breadcrumbs(parent_path)
          
          new_history = [parent_path | window.history] |> Enum.take(50)
          
          %{window | 
            current_path: parent_path, 
            current_items: sort_items(items, window.sort_by, window.sort_order),
            breadcrumbs: breadcrumbs,
            history: new_history,
            forward_history: [],
            selected_items: []
          }
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Refresh current view
  def handle_event("fm_refresh", %{"window_id" => window_id}, socket) do
    user = socket.assigns.current_user
    
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          items = get_file_explorer_items(window.current_path, user)
          %{window | current_items: sort_items(items, window.sort_by, window.sort_order)}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Change view mode (icons, list, details)
  def handle_event("fm_set_view", %{"view" => view, "window_id" => window_id}, socket) do
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          %{window | view_mode: view}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Sort files
  def handle_event("fm_sort", %{"sort_by" => sort_by, "window_id" => window_id}, socket) do
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          # Toggle order if same column clicked
          new_order = if window.sort_by == sort_by do
            if window.sort_order == "asc", do: "desc", else: "asc"
          else
            "asc"
          end
          
          sorted_items = sort_items(window.current_items, sort_by, new_order)
          %{window | sort_by: sort_by, sort_order: new_order, current_items: sorted_items}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Toggle sort order
  def handle_event("fm_toggle_sort_order", %{"window_id" => window_id}, socket) do
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          new_order = if window.sort_order == "asc", do: "desc", else: "asc"
          sorted_items = sort_items(window.current_items, window.sort_by, new_order)
          %{window | sort_order: new_order, current_items: sorted_items}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Filter by file type
  def handle_event("fm_filter_type", %{"type" => type, "window_id" => window_id}, socket) do
    user = socket.assigns.current_user
    
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          items = get_file_explorer_items(window.current_path, user)
          filtered = filter_items_by_type(items, type)
          sorted = sort_items(filtered, window.sort_by, window.sort_order)
          %{window | filter_type: type, current_items: sorted}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Search files
  def handle_event("fm_search", %{"value" => query, "window_id" => window_id}, socket) do
    user = socket.assigns.current_user
    
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          items = get_file_explorer_items(window.current_path, user)
          
          filtered = if query == "" do
            items
          else
            Enum.filter(items, fn item ->
              String.contains?(String.downcase(item.name), String.downcase(query))
            end)
          end
          
          sorted = sort_items(filtered, window.sort_by, window.sort_order)
          %{window | search_query: query, current_items: sorted}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Select item
  def handle_event("fm_select_item", %{"item_id" => item_id, "window_id" => window_id}, socket) do
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          selected = if item_id in window.selected_items do
            List.delete(window.selected_items, item_id)
          else
            [item_id | window.selected_items]
          end
          %{window | selected_items: selected}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  # Delete item
  # Preview/play a file (opens in a media player window)
  def handle_event("fm_preview_file", %{"url" => url, "window_id" => window_id} = params, socket) when url != "" do
    item_id = params["item_id"] || "preview"
    
    # Get the file item info from the current window
    window = Enum.find(socket.assigns.windows, &(&1.id == window_id))
    item = if window, do: Enum.find(window.current_items || [], &(to_string(&1.id) == item_id)), else: nil
    
    file_name = if item, do: item.name, else: Path.basename(url)
    extension = String.downcase(Path.extname(file_name))
    
    media_type = cond do
      extension in ~w(.mp3 .wav .ogg .flac .aac .m4a .wma) -> :audio
      extension in ~w(.mp4 .webm .mov .avi .mkv .m4v .ogv .wmv) -> :video
      extension in ~w(.jpg .jpeg .png .gif .webp .svg .bmp .ico) -> :image
      extension in ~w(.pdf) -> :pdf
      extension in ~w(.txt .md .json .xml .html .css .js .ex .exs) -> :text
      true -> :other
    end
    
    window_size = get_preview_window_size(media_type)
    
    # Create a media preview window
    preview_window = %{
      id: Ecto.UUID.generate(),
      app: "media_preview",
      title: "Preview: #{file_name}",
      x: 200,
      y: 100,
      width: window_size.width,
      height: window_size.height,
      minimized: false,
      maximized: false,
      z_index: (socket.assigns.next_z_index || 1000),
      # Media preview specific
      media_url: url,
      media_type: media_type,
      file_name: file_name
    }
    
    windows = socket.assigns.windows ++ [preview_window]
    
    {:noreply, socket
      |> assign(:windows, windows)
      |> assign(:active_window, preview_window.id)
      |> assign(:next_z_index, (socket.assigns.next_z_index || 1000) + 1)}
  end
  
  def handle_event("fm_preview_file", _params, socket) do
    # No URL provided, do nothing
    {:noreply, socket}
  end

  def handle_event("fm_delete_item", %{"path" => path, "window_id" => window_id} = params, socket) do
    user = socket.assigns.current_user

    result =
      cond do
        is_nil(user) ->
          :ok

        my_files_path?(path) ->
          id = params["item_id"]

          case Bacon8.Drive.delete_file(user, id) do
            {:ok, _} -> :ok
            {:error, :not_found} ->
              case Bacon8.Drive.delete_folder(user, id) do
                {:ok, _} -> :ok
                {:error, reason} -> {:error, drive_error_message(reason)}
              end
            {:error, reason} -> {:error, drive_error_message(reason)}
          end

        true ->
          real_path = get_file_explorer_real_path(path, user)

          if real_path && can_delete_path?(path, user) do
            case File.rm(real_path) do
              :ok -> :ok
              {:error, :enoent} -> :ok
              {:error, reason} ->
                Logger.warning("Failed to delete file: #{inspect(reason)}")
                {:error, "That file couldn't be deleted."}
            end
          else
            {:error, "You can't delete that."}
          end
      end

    socket = refresh_file_manager(socket, window_id)

    case result do
      :ok -> {:noreply, socket}
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  # Upload handlers
  def handle_event("fm_validate_upload", params, socket) do
    window_id = params["window_id"]
    {:noreply, assign(socket, :upload_window_id, window_id)}
  end

  def handle_event("fm_upload", %{"window_id" => window_id}, socket) do
    # Entries are saved by handle_progress/3 as each one finishes.
    {:noreply, refresh_file_manager(socket, window_id)}
  end

  # Sharing: private | link | public (Bacon8.Drive.set_visibility/3)
  def handle_event("fm_set_visibility", %{"window_id" => window_id, "item_id" => id, "visibility" => visibility}, socket) do
    result =
      case socket.assigns.current_user do
        nil -> {:error, :not_found}
        user -> Bacon8.Drive.set_visibility(user, id, visibility)
      end

    socket = refresh_file_manager(socket, window_id)

    case result do
      {:ok, _} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, drive_error_message(reason))}
    end
  end

  # New folder handler - prompts for name via JS
  def handle_event("fm_new_folder", %{"window_id" => window_id}, socket) do
    # Push a JS event to prompt the user for a folder name
    {:noreply, push_event(socket, "prompt_folder_name", %{window_id: window_id})}
  end

  # Handle folder creation after user provides name
  def handle_event("fm_create_folder", %{"window_id" => window_id, "name" => name}, socket) when name != "" do
    user = socket.assigns.current_user
    window = Enum.find(socket.assigns.windows, &(&1.id == window_id))
    
    if user && window do
      result =
        with true <- my_files_path?(window.current_path) || {:error, :not_found},
             {:ok, parent_id} <- drive_folder_for_path(user, window.current_path) do
          Bacon8.Drive.create_folder(user, parent_id, name)
        end

      socket = refresh_file_manager(socket, window_id)

      case result do
        {:ok, _folder} -> {:noreply, socket}
        {:error, reason} -> {:noreply, put_flash(socket, :error, drive_error_message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("fm_create_folder", _params, socket) do
    {:noreply, socket}
  end

  # Keep old handlers for compatibility
  def handle_event("change_view_mode", %{"mode" => mode, "window_id" => window_id}, socket) do
    handle_event("fm_set_view", %{"view" => mode, "window_id" => window_id}, socket)
  end

  def handle_event("navigate_to", %{"path" => path, "window_id" => window_id}, socket) do
    handle_event("fm_navigate_to", %{"path" => path, "window_id" => window_id}, socket)
  end

  def handle_event("navigate_back", %{"window_id" => window_id}, socket) do
    handle_event("fm_navigate_back", %{"window_id" => window_id}, socket)
  end

  # ==================== UPLOAD HANDLERS ====================

  def handle_event("validate_upload", params, socket) do
    window_id = params["window_id"]
    {:noreply, assign(socket, :upload_window_id, window_id)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("save_upload", %{"window_id" => window_id}, socket) do
    # Entries are saved by handle_progress/3 as each one finishes.
    {:noreply, refresh_file_manager(socket, window_id)}
  end

  # ==================== HELPERS ====================

  defp get_window_id(params) do
    Map.get(params, "window_id") || Map.get(params, "id")
  end

  defp get_preview_window_size(:image), do: %{width: 800, height: 600}
  defp get_preview_window_size(:video), do: %{width: 854, height: 530}
  defp get_preview_window_size(:audio), do: %{width: 400, height: 200}
  defp get_preview_window_size(:pdf), do: %{width: 800, height: 700}
  defp get_preview_window_size(_), do: %{width: 600, height: 400}

  # ==================== PUBSUB HANDLERS ====================

  def handle_info({:refresh_window, window_id}, socket) do
    # Refresh the window content by re-fetching items
    windows = 
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          items = cond do
            window.current_path == "/" ->
              get_available_drives(socket.assigns.current_user)
            
            String.starts_with?(window.current_path, "public://") ->
              get_public_drive_contents(window.current_path, socket.assigns.current_user)
            
            String.starts_with?(window.current_path, "user://") ->
              get_user_drive_contents(window.current_path, socket.assigns.current_user)
            
            String.starts_with?(window.current_path, "root://") ->
              get_root_drive_contents(window.current_path, socket.assigns.current_user)
            
            true ->
              []
          end
          
          %{window | current_items: items}
        else
          window
        end
      end)
    
    {:noreply, assign(socket, :windows, windows)}
  end

  def handle_info({:new_invite, _invite}, socket) do
    # Update invite count when new invite arrives
    pending_invite_count = if socket.assigns.current_user do
      Bacon8.Forum.count_pending_invites(socket.assigns.current_user.id)
    else
      0
    end
    
    # Play notification sound if enabled
    socket = if socket.assigns.current_user && socket.assigns.current_user.notification_sound_enabled do
      volume = socket.assigns.current_user.master_volume || 0.5
      sound_path = "/audio/ui/notification.mp3"
      push_event(socket, "play_sound", %{path: sound_path, volume: volume})
    else
      socket
    end
    
    {:noreply, assign(socket, pending_invite_count: pending_invite_count)}
  end

  def handle_info({:new_notification, _notification}, socket) do
    # Update notification count when new mention arrives
    unread_notification_count = if socket.assigns.current_user do
      Bacon8.Notifications.count_unread_notifications(socket.assigns.current_user.id)
    else
      0
    end

    # Reload notifications list
    mention_notifications = if socket.assigns.current_user do
      Bacon8.Notifications.list_user_notifications(socket.assigns.current_user.id, limit: 10)
    else
      []
    end
    
    # Play notification sound if enabled
    socket = if socket.assigns.current_user && socket.assigns.current_user.notification_sound_enabled do
      volume = socket.assigns.current_user.master_volume || 0.5
      sound_path = "/audio/ui/notification.mp3"
      push_event(socket, "play_sound", %{path: sound_path, volume: volume})
    else
      socket
    end
    
    {:noreply, assign(socket, unread_notification_count: unread_notification_count, mention_notifications: mention_notifications)}
  end

  # Handle refresh messages for new file explorer
  # NOTE: this module is a LiveComponent, so it never receives handle_info -
  # `send(self(), ...)` from here reaches the page's LiveView instead. Refresh
  # file manager windows by calling refresh_file_manager/2 directly.
  defp refresh_file_manager(socket, window_id) do
    user = socket.assigns.current_user
    {storage_used, storage_quota} = drive_storage(user)

    windows =
      Enum.map(socket.assigns.windows, fn window ->
        if window.id == window_id && window.app == "file_manager" do
          items = get_file_explorer_items(window.current_path, user)

          %{window |
            current_items: sort_items(items, window.sort_by, window.sort_order),
            storage_used: storage_used,
            storage_quota: storage_quota
          }
        else
          window
        end
      end)

    assign(socket, :windows, windows)
  end

  # ==================== DRIVE (My Files) ====================

  defp my_files_path?("/my-files"), do: true
  defp my_files_path?("/my-files/" <> _), do: true
  defp my_files_path?(_), do: false

  # "/my-files/Photos/2026" -> {:ok, folder_id}; "/my-files" -> {:ok, nil}
  defp drive_folder_for_path(user, path) do
    segments =
      path
      |> String.replace_prefix("/my-files", "")
      |> String.split("/", trim: true)

    Bacon8.Drive.resolve_path(user, segments)
  end

  defp drive_storage(nil), do: {0, 0}

  defp drive_storage(user) do
    summary = Bacon8.Drive.summary(user)
    {summary.bytes_used, summary.quota_bytes}
  end

  defp drive_items(user, path) do
    base = String.trim_trailing(path, "/")

    with {:ok, folder_id} <- drive_folder_for_path(user, path),
         {:ok, %{folders: folders, files: files}} <- Bacon8.Drive.list_folder(user, folder_id) do
      Enum.map(folders, &drive_folder_item(&1, base)) ++ Enum.map(files, &drive_file_item(&1, base))
    else
      _ -> []
    end
  end

  defp drive_folder_item(folder, base) do
    modified = DateTime.to_naive(folder.updated_at)

    %{
      id: folder.id,
      name: folder.name,
      type: "folder",
      type_label: "Folder",
      icon: get_file_explorer_icon(folder.name, true),
      path: base <> "/" <> folder.name,
      url: nil,
      size: 0,
      size_formatted: "—",
      modified: modified,
      modified_formatted: format_modified(NaiveDateTime.to_erl(modified)),
      extension: ""
    }
  end

  defp drive_file_item(file, base) do
    modified = DateTime.to_naive(file.updated_at)

    %{
      id: file.id,
      name: file.name,
      type: "file",
      type_label: get_type_label(file.name, false),
      icon: get_file_explorer_icon(file.name, false),
      path: base <> "/" <> file.name,
      url: "/files/" <> file.id,
      size: file.size,
      size_formatted: format_size(file.size),
      modified: modified,
      modified_formatted: format_modified(NaiveDateTime.to_erl(modified)),
      extension: file.name |> Path.extname() |> String.downcase(),
      visibility: file.visibility,
      share_url: share_url(file)
    }
  end

  defp share_url(%{visibility: "link", share_token: token}) when is_binary(token),
    do: Bacon8Web.Endpoint.url() <> "/s/" <> token

  defp share_url(%{visibility: "public", id: id}), do: Bacon8Web.Endpoint.url() <> "/files/" <> id
  defp share_url(_), do: nil

  # ==================== RENDER ====================

  defp render_window_content(assigns, window) do
    case window.app do
      "file_manager" ->
        assigns = assign(assigns, :window, window)
        ~H"""
        <Bacon8Web.Components.FileExplorer.file_explorer
          window={@window}
          current_user={@current_user}
          uploads={@uploads}
          target={@myself}
        />
        """
      "media_preview" ->
        assigns = assign(assigns, :window, window)
        ~H"""
        <div class="h-full flex flex-col bg-gray-900">
          <%= case @window.media_type do %>
            <% :image -> %>
              <div class="flex-1 flex items-center justify-center p-4 overflow-auto">
                <img src={@window.media_url} alt={@window.file_name} class="max-w-full max-h-full object-contain shadow-lg" />
              </div>
            <% :video -> %>
              <div class="flex-1 flex items-center justify-center p-2 bg-black">
                <video controls autoplay class="max-w-full max-h-full" src={@window.media_url}>
                  Your browser does not support video playback.
                </video>
              </div>
            <% :audio -> %>
              <div class="flex-1 flex flex-col items-center justify-center p-4">
                <div class="text-6xl mb-4">🎵</div>
                <div class="text-white text-lg mb-4 text-center"><%= @window.file_name %></div>
                <audio controls autoplay class="w-full max-w-md" src={@window.media_url}>
                  Your browser does not support audio playback.
                </audio>
              </div>
            <% :pdf -> %>
              <div class="flex-1 bg-white">
                <iframe src={@window.media_url} class="w-full h-full border-0" title={@window.file_name}></iframe>
              </div>
            <% :text -> %>
              <div class="flex-1 p-4 overflow-auto">
                <iframe src={@window.media_url} class="w-full h-full bg-white text-black border-0 rounded" title={@window.file_name}></iframe>
              </div>
            <% _ -> %>
              <div class="flex-1 flex flex-col items-center justify-center p-4">
                <div class="text-6xl mb-4">📄</div>
                <div class="text-white text-lg mb-2"><%= @window.file_name %></div>
                <a href={@window.media_url} download={@window.file_name} class="mt-4 px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded text-white transition-colors">
                  Download File
                </a>
              </div>
          <% end %>
        </div>
        """
      "terminal" ->
        ~H"""
        <div class="p-4 font-mono text-sm text-green-400 bg-black h-full">
          <div>Terminal Emulator</div>
          <div class="mt-2">$ <span class="animate-pulse">_</span></div>
        </div>
        """
      "calculator" ->
        ~H"""
        <div class="p-4 bg-gray-900 h-full flex flex-col">
          <div class="text-right text-2xl text-white mb-4 p-2 glass-dark rounded">0</div>
          <div class="grid grid-cols-4 gap-2 flex-1">
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">7</button>
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">8</button>
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">9</button>
            <button class="bg-blue-600 hover:bg-blue-500 text-white rounded p-2">÷</button>
            
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">4</button>
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">5</button>
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">6</button>
            <button class="bg-blue-600 hover:bg-blue-500 text-white rounded p-2">×</button>
            
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">1</button>
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">2</button>
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">3</button>
            <button class="bg-blue-600 hover:bg-blue-500 text-white rounded p-2">-</button>
            
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">0</button>
            <button class="bg-gray-700 hover:bg-gray-600 text-white rounded p-2">.</button>
            <button class="bg-green-600 hover:bg-green-500 text-white rounded p-2">=</button>
            <button class="bg-blue-600 hover:bg-blue-500 text-white rounded p-2">+</button>
          </div>
        </div>
        """
      "notepad" ->
        ~H"""
        <div class="h-full">
          <textarea class="w-full h-full bg-white text-black p-4 font-mono resize-none border-0 focus:outline-none" placeholder="Start typing..."></textarea>
        </div>
        """
      _ ->
        ~H"""
        <div class="p-4 text-center text-gray-400">
          <p>Application content not available</p>
        </div>
        """
    end
  end

  def render(assigns) do
    ~H"""
    <div id="bacon8-desktop" class="pointer-events-none" phx-hook="AudioHook" data-volume={@current_user && @current_user.master_volume || 0.5}>
      <!-- Windows layer - positioned above page content -->
      <div class="fixed inset-0 z-40 pointer-events-none">
        <%= for window <- @windows do %>
          <div class="pointer-events-auto" style={"z-index: #{window.z_index}"}>
            <Bacon8Web.Components.Window.desktop_window window={window} current_user={@current_user} target={@myself}>
              <%= render_window_content(assigns, window) %>
            </Bacon8Web.Components.Window.desktop_window>
          </div>
        <% end %>
      </div>
      
                  <!-- Taskbar - always visible at bottom -->
      <div class="pointer-events-auto">
        <Bacon8Web.Components.Taskbar.taskbar 
          current_user={@current_user}
          open_windows={@windows}
          show_start_menu={@show_start_menu}
          show_notifications={@show_notifications}
          show_audio_panel={@show_audio_panel}
          show_calendar={@show_calendar}
          pending_invite_count={@pending_invite_count}
          unread_notification_count={@unread_notification_count}
          taskbar_projects={@taskbar_projects}
          calendar_events={@calendar_events}
          selected_date={@selected_date}
          target={@myself}
        />
      </div>

      <!-- Notification Panel -->
      <div class="pointer-events-auto">
        <Bacon8Web.Components.NotificationPanel.notification_panel
          show={@show_notifications}
          pending_invites={@pending_invites}
          mention_notifications={@mention_notifications}
          current_user={@current_user}
          target={@myself}
        />
      </div>
    </div>
    """
  end

  defp get_available_drives(user) do
    drives = [
      %{
        id: "public",
        name: "Public Drive",
        description: "Shared files for all users",
        type: :drive,
        icon: "🌐",
        path: "public://",
        size: "Shared",
        modified: DateTime.utc_now()
      }
    ]
    
    if user do
      drives = drives ++ [
        %{
          id: "user_#{user.id}",
          name: "#{user.name || user.email}'s Drive",
          description: "Personal storage space",
          type: :drive,
          icon: "💾",
          path: "user://#{user.id}",
          size: "Personal",
          modified: DateTime.utc_now()
        }
      ]
      
      if user.role in ["admin", "gm"] do
        drives ++ [
          %{
            id: "admin_root",
            name: "System Root",
            description: "Full system access",
            type: :drive,
            icon: "⚡",
            path: "root://",
            size: "System",
            modified: DateTime.utc_now()
          }
        ]
      else
        drives
      end
    else
      drives
    end
  end

  defp get_public_drive_contents(path, user) do
    real_path = get_real_path(path, user)
    list_contents(real_path, path)
  end

  defp get_user_drive_contents(path, user) do
    if path == "user://" do
      Bacon8.Files.list_all_user_content(user)
      |> Enum.map(fn file ->
        %{
          id: file.id,
          name: file.filename,
          type: :file,
          icon: get_file_icon(file.filename, :file),
          path: "user://#{file.filename}",
          size: format_size(file.size),
          modified: file.inserted_at,
          url: file.url
        }
      end)
    else
      case get_real_path(path, user) do
        nil ->
          []

        real_path ->
          # Ensure directory exists
          if !File.exists?(real_path), do: File.mkdir_p!(real_path)
          list_contents(real_path, path)
      end
    end
  end

  defp get_root_drive_contents(path, user) do
    if user.role in ["admin", "gm"] do
      real_path = get_real_path(path, user)
      list_contents(real_path, path)
    else
      []
    end
  end

  defp resolve_virtual_path_to_url(path, user) do
    cond do
      String.starts_with?(path, "user://") ->
        filename = String.replace_prefix(path, "user://", "")
        "/uploads/users/#{user.id}/#{filename}"
        
      String.starts_with?(path, "public://") ->
        filename = String.replace_prefix(path, "public://", "")
        "/uploads/public/#{filename}"
        
      String.starts_with?(path, "root://") ->
        filename = String.replace_prefix(path, "root://", "")
        "/uploads/#{filename}"
        
      true -> nil
    end
  end

  defp get_real_path(path, user) do
    base_path = 
      cond do
        File.exists?("/app/uploads") -> "/app/uploads"
        File.exists?("uploads") -> Path.expand("uploads")
        true -> Application.app_dir(:bacon8, "priv/static/uploads")
      end
    
    # `path` comes from the client (window.current_path is set by fm_navigate_to).
    # Every branch goes through SafePath so `user://../<other id>` cannot escape
    # the drive's root. Returns nil when it would.
    cond do
      !is_binary(path) ->
        nil

      String.starts_with?(path, "root://") && user && user.role in ["admin", "gm"] ->
        Bacon8.SafePath.resolve!(base_path, String.replace_prefix(path, "root://", ""))

      String.starts_with?(path, "public://") ->
        Bacon8.SafePath.resolve!(
          Path.join(base_path, "public"),
          String.replace_prefix(path, "public://", "")
        )

      String.starts_with?(path, "user://") && user ->
        Bacon8.SafePath.resolve!(
          Path.join([base_path, "users", "#{user.id}"]),
          String.replace_prefix(path, "user://", "")
        )

      true -> nil
    end
  end


  # Destination for one uploaded entry, or nil if the name is unusable or the
  # type is active content (HTML/SVG/JS...) that would run on our origin.
  defp upload_destination(dest_dir, client_name) do
    with name when is_binary(name) <- Bacon8.SafePath.filename(client_name),
         false <- Bacon8.SafePath.active_content?(name),
         {:ok, dest} <- Bacon8.SafePath.resolve(dest_dir, name) do
      dest
    else
      _ -> nil
    end
  end

  # consume_uploaded_entries callback shared by the three upload handlers.
  defp copy_upload_to(dest_dir, temp_path, entry) do
    case upload_destination(dest_dir, entry.client_name) do
      nil ->
        Logger.warning("Rejected upload #{inspect(entry.client_name)}: unsafe name or type")
        {:ok, :rejected}

      dest ->
        File.cp!(temp_path, dest)
        {:ok, dest}
    end
  end

  defp list_contents(real_path, virtual_root) do
    if real_path && File.exists?(real_path) && File.dir?(real_path) do
      case File.ls(real_path) do
        {:ok, files} ->
          files
          |> Enum.map(fn file ->
            full_path = Path.join(real_path, file)
            stat = File.stat!(full_path)
            type = if stat.type == :directory, do: :folder, else: :file
            
            # Virtual path for navigation
            virtual_path = 
              if String.ends_with?(virtual_root, "//") do
                virtual_root <> file
              else
                virtual_root <> "/" <> file
              end

            %{
              id: Base.encode64(virtual_path),
              name: file,
              type: type,
              icon: get_file_icon(file, type),
              path: virtual_path,
              size: if(type == :folder, do: "-", else: format_size(stat.size)),
              modified: stat.mtime |> NaiveDateTime.from_erl!()
            }
          end)
          |> Enum.sort_by(&{&1.type != :folder, &1.name})
        _ -> []
      end
    else
      []
    end
  end

  defp get_file_icon(_name, :folder), do: "📁"
  defp get_file_icon(name, :file) do
    ext = Path.extname(name) |> String.downcase()
    case ext do
      ".jpg" -> "🖼️"
      ".png" -> "🖼️"
      ".gif" -> "🖼️"
      ".pdf" -> "📕"
      ".txt" -> "📄"
      ".mp3" -> "🎵"
      ".wav" -> "🎵"
      ".mp4" -> "🎬"
      ".zip" -> "📦"
      _ -> "📄"
    end
  end

  defp format_size(size) do
    cond do
      size < 1024 -> "#{size} B"
      size < 1024 * 1024 -> "#{Float.round(size / 1024, 1)} KB"
      size < 1024 * 1024 * 1024 -> "#{Float.round(size / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(size / (1024 * 1024 * 1024), 1)} GB"
    end
  end

  # ==================== NEW FILE EXPLORER HELPERS ====================

  # Get the base uploads path
  defp get_uploads_base_path do
    cond do
      File.exists?("/app/uploads") -> "/app/uploads"
      File.exists?("uploads") -> Path.expand("uploads")
      true -> Application.app_dir(:bacon8, "priv/static/uploads")
    end
  end

  # Get items for the new file explorer
  defp get_file_explorer_items(path, user) do
    case path do
      "/" ->
        # Root shows nothing - use sidebar navigation
        []
        
      "/my-files" <> _ ->
        if user && my_files_path?(path), do: drive_items(user, path), else: []
        
      "/public" ->
        # Load public folder from filesystem
        base_path = get_uploads_base_path()
        real_path = Path.join(base_path, "public")
        unless File.exists?(real_path), do: File.mkdir_p!(real_path)
        list_file_explorer_contents(real_path, path)
        
      "/public/" <> subpath ->
        base_path = get_uploads_base_path()
        real_path = Bacon8.SafePath.resolve!(Path.join(base_path, "public"), subpath)
        if real_path && File.dir?(real_path) do
          list_file_explorer_contents(real_path, path)
        else
          []
        end
        
      _ ->
        []
    end
  end


  # List directory contents with full metadata
  defp list_file_explorer_contents(real_path, virtual_base) do
    case File.ls(real_path) do
      {:ok, files} ->
        files
        |> Enum.map(fn filename ->
          full_path = Path.join(real_path, filename)
          
          case File.stat(full_path) do
            {:ok, stat} ->
              is_folder = stat.type == :directory
              ext = if is_folder, do: "", else: Path.extname(filename) |> String.downcase()
              
              virtual_path = Path.join(virtual_base, filename)
              
              # Build URL for files
              url = unless is_folder do
                cond do
                  String.starts_with?(virtual_base, "/public") ->
                    String.replace(virtual_path, "/public", "/uploads/public")
                  String.starts_with?(virtual_base, "/my-files") ->
                    # Extract user ID from path
                    virtual_path
                    |> String.replace("/my-files", "/uploads/users")
                  true ->
                    nil
                end
              end
              
              %{
                id: Base.encode64(virtual_path),
                name: filename,
                type: if(is_folder, do: "folder", else: "file"),
                type_label: get_type_label(filename, is_folder),
                icon: get_file_explorer_icon(filename, is_folder),
                path: virtual_path,
                url: url,
                size: stat.size,
                size_formatted: if(is_folder, do: "—", else: format_size(stat.size)),
                modified: stat.mtime |> NaiveDateTime.from_erl!(),
                modified_formatted: format_modified(stat.mtime),
                extension: ext
              }
            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        
      {:error, _} ->
        []
    end
  end

  # Get parent path for file explorer
  defp get_file_explorer_parent_path(path) do
    case path do
      "/" -> "/"
      "/my-files" -> "/"
      "/public" -> "/"
      _ ->
        parent = Path.dirname(path)
        if parent in ["", "/"], do: "/", else: parent
    end
  end

  # Get real filesystem path from virtual path
  defp get_file_explorer_real_path(path, user) do
    base_path = get_uploads_base_path()
    
    # `path` is client-supplied; SafePath keeps `/my-files/../../x` inside the drive.
    case path do
      "/my-files" ->
        if user, do: Path.join([base_path, "users", "#{user.id}"]), else: nil

      "/public" ->
        Path.join(base_path, "public")

      "/public/" <> subpath ->
        Bacon8.SafePath.resolve!(Path.join(base_path, "public"), subpath)

      "/my-files/" <> subpath ->
        if user,
          do: Bacon8.SafePath.resolve!(Path.join([base_path, "users", "#{user.id}"]), subpath),
          else: nil

      _ ->
        nil
    end
  end

  defp can_write_explorer_path?(path, user) when is_binary(path) do
    cond do
      is_nil(user) -> false
      path == "/my-files" or String.starts_with?(path, "/my-files/") -> true
      path == "/public" or String.starts_with?(path, "/public/") -> user.role in ["admin", "gm"]
      true -> false
    end
  end

  defp can_write_explorer_path?(_, _), do: false

  # Build breadcrumbs for file explorer
  defp build_file_explorer_breadcrumbs(path) do
    case path do
      "/" -> []
      "/my-files" -> [%{name: "My Files", path: "/my-files"}]
      "/public" -> [%{name: "Public", path: "/public"}]
      _ ->
        parts = String.split(path, "/", trim: true)
        
        parts
        |> Enum.with_index()
        |> Enum.map(fn {part, idx} ->
          accumulated = "/" <> Enum.join(Enum.take(parts, idx + 1), "/")
          
          # Rename first segment for display
          display_name = case {idx, part} do
            {0, "my-files"} -> "My Files"
            {0, "public"} -> "Public"
            _ -> part
          end
          
          %{name: display_name, path: accumulated}
        end)
    end
  end

  # Sort items by column
  defp sort_items(items, sort_by, order) do
    # Always put folders first
    {folders, files} = Enum.split_with(items, &(&1.type == "folder"))
    
    sorter = case sort_by do
      "name" -> &String.downcase(&1.name)
      "size" -> &(&1.size || 0)
      "type" -> &(&1.extension || "")
      "modified" -> &(&1.modified)
      _ -> &String.downcase(&1.name)
    end
    
    sorted_folders = Enum.sort_by(folders, sorter)
    sorted_files = Enum.sort_by(files, sorter)
    
    if order == "desc" do
      Enum.reverse(sorted_folders) ++ Enum.reverse(sorted_files)
    else
      sorted_folders ++ sorted_files
    end
  end

  # Filter items by type category
  defp filter_items_by_type(items, type) do
    case type do
      "all" -> 
        items
      "images" -> 
        Enum.filter(items, &(&1.type == "folder" || &1.extension in ~w(.jpg .jpeg .png .gif .webp .svg .bmp)))
      "documents" -> 
        Enum.filter(items, &(&1.type == "folder" || &1.extension in ~w(.pdf .doc .docx .txt .md .rtf .odt)))
      "audio" -> 
        Enum.filter(items, &(&1.type == "folder" || &1.extension in ~w(.mp3 .wav .ogg .flac .aac .m4a)))
      "video" -> 
        Enum.filter(items, &(&1.type == "folder" || &1.extension in ~w(.mp4 .avi .mov .mkv .webm .wmv)))
      _ -> 
        items
    end
  end

  # Check if user can delete a path
  defp can_delete_path?(path, user) do
    cond do
      not is_binary(path) -> false
      # Belt and braces: get_file_explorer_real_path already confines the path,
      # but never authorise anything with a parent-directory segment.
      ".." in Path.split(path) -> false
      # Can't delete root paths
      path in ["/", "/my-files", "/public"] -> false
      # User can delete their own files
      String.starts_with?(path, "/my-files") && user -> true
      # Admins can delete public files
      String.starts_with?(path, "/public") && user && user.role in ["admin", "gm"] -> true
      # Otherwise no
      true -> false
    end
  end

  # Get file type label
  defp get_type_label(_filename, true), do: "Folder"
  defp get_type_label(filename, false) do
    ext = Path.extname(filename) |> String.downcase() |> String.trim_leading(".")
    case ext do
      "" -> "File"
      "jpg" -> "JPEG Image"
      "jpeg" -> "JPEG Image"
      "png" -> "PNG Image"
      "gif" -> "GIF Image"
      "webp" -> "WebP Image"
      "svg" -> "SVG Image"
      "pdf" -> "PDF Document"
      "doc" -> "Word Document"
      "docx" -> "Word Document"
      "txt" -> "Text File"
      "md" -> "Markdown File"
      "mp3" -> "MP3 Audio"
      "wav" -> "WAV Audio"
      "ogg" -> "OGG Audio"
      "mp4" -> "MP4 Video"
      "avi" -> "AVI Video"
      "mov" -> "MOV Video"
      "mkv" -> "MKV Video"
      "zip" -> "ZIP Archive"
      "rar" -> "RAR Archive"
      "7z" -> "7-Zip Archive"
      _ -> String.upcase(ext) <> " File"
    end
  end

  # Get icon for file explorer
  defp get_file_explorer_icon(_name, true), do: "📁"
  defp get_file_explorer_icon(name, false) do
    ext = Path.extname(name) |> String.downcase()
    case ext do
      ".jpg" -> "🖼️"
      ".jpeg" -> "🖼️"
      ".png" -> "🖼️"
      ".gif" -> "🖼️"
      ".webp" -> "🖼️"
      ".svg" -> "🖼️"
      ".bmp" -> "🖼️"
      ".pdf" -> "📕"
      ".doc" -> "📝"
      ".docx" -> "📝"
      ".txt" -> "📄"
      ".md" -> "📄"
      ".mp3" -> "🎵"
      ".wav" -> "🎵"
      ".ogg" -> "🎵"
      ".flac" -> "🎵"
      ".mp4" -> "🎬"
      ".avi" -> "🎬"
      ".mov" -> "🎬"
      ".mkv" -> "🎬"
      ".webm" -> "🎬"
      ".zip" -> "📦"
      ".rar" -> "📦"
      ".7z" -> "📦"
      ".tar" -> "📦"
      ".gz" -> "📦"
      ".js" -> "📜"
      ".ts" -> "📜"
      ".html" -> "🌐"
      ".css" -> "🎨"
      ".json" -> "📋"
      ".xml" -> "📋"
      _ -> "📄"
    end
  end

  # Format modified date
  defp format_modified(erl_datetime) do
    case NaiveDateTime.from_erl(erl_datetime) do
      {:ok, dt} ->
        now = NaiveDateTime.utc_now()
        diff_days = NaiveDateTime.diff(now, dt, :day)
        
        cond do
          diff_days == 0 ->
            "Today, #{Calendar.strftime(dt, "%I:%M %p")}"
          diff_days == 1 ->
            "Yesterday, #{Calendar.strftime(dt, "%I:%M %p")}"
          diff_days < 7 ->
            Calendar.strftime(dt, "%A, %I:%M %p")
          true ->
            Calendar.strftime(dt, "%b %d, %Y")
        end
      _ ->
        "Unknown"
    end
  end
end
