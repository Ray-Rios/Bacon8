defmodule Bacon8Web.ProfileLive do
  use Bacon8Web, :live_view
  alias Bacon8.Accounts


  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    
    # Redirect to login if not authenticated
    if current_user == nil do
      {:ok, push_navigate(socket, to: "/login")}
    else
      changeset = Accounts.change_user_profile(current_user, %{})
      password_changeset = Accounts.User.password_changeset(current_user, %{})
      custom_data = current_user.background_custom_data || %{}
      avatar_opacity = Map.get(current_user, :avatar_opacity) || 100

      # Load blocked users
      blocked_users = Accounts.list_blocked_users(current_user.id)

      # Load previous avatars
      previous_avatars = Bacon8.Uploads.list_user_uploads(current_user.id, "avatar")

      # Load data usage
      data_usage = Bacon8.Files.get_user_data_usage(current_user.id)

      socket = 
        assign(socket,
          page_title: "Profile Settings",
          user: current_user,
          form: to_form(changeset),
          password_form: to_form(password_changeset),
          show_success: false,
          active_tab: "profile",
          selected_background: current_user.background_preference || "galaxy",
          custom_data: custom_data,
          avatar_opacity: avatar_opacity,
          blocked_users: blocked_users,
          previous_avatars: previous_avatars,
          data_usage: data_usage
        )
        |> allow_upload(:avatar, 
          accept: ~w(.jpg .jpeg .png .gif .webp image/jpeg image/png image/gif image/webp), 
          max_entries: 1, 
          max_file_size: 1_000_000,
          auto_upload: true,
          progress: &handle_progress/3
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  @impl true
  def handle_event("validate_password", %{"user" => password_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.User.password_change_changeset(password_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, password_form: to_form(changeset))}
  end

  @impl true
  def handle_event("change_password", %{"user" => password_params}, socket) do
    case Accounts.update_user_password(socket.assigns.user, password_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:password_form, to_form(Accounts.User.password_changeset(socket.assigns.user, %{})))
         |> put_flash(:info, "Password updated successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("validate_avatar", _params, socket) do
    # Check if user has reached the limit of 10 avatars
    if length(socket.assigns.previous_avatars) >= 10 do
      {:noreply, 
       socket 
       |> put_flash(:error, "You have reached the maximum limit of 10 avatars. Please delete some before uploading new ones.")
       |> cancel_upload(:avatar, List.first(socket.assigns.uploads.avatar.entries).ref)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.update_user_profile(socket.assigns.user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:form, to_form(Accounts.change_user_profile(user, %{})))
         |> assign(:show_success, true)
         |> put_flash(:info, "Profile updated successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("resend_verification", _params, socket) do
    case Bacon8.Accounts.EmailVerification.send_verification_email(socket.assigns.user) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> put_flash(:info, "Verification email sent! Please check your inbox.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to send verification email: #{reason}")}
    end
  end

  @impl true
  def handle_event("close_success", _params, socket) do
    {:noreply, assign(socket, show_success: false)}
  end

  @impl true
  def handle_event("remove_avatar", _params, socket) do
    case Accounts.update_user_profile(socket.assigns.user, %{avatar_url: nil}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(user: updated_user)
         |> assign(form: to_form(Accounts.change_user_profile(updated_user, %{})))
         |> put_flash(:info, "Avatar removed successfully!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove avatar")}
    end
  end

  @impl true
  def handle_event("select_avatar_color", %{"color" => color}, socket) do
    # Save color immediately to database
    case Accounts.update_user_profile(socket.assigns.user, %{avatar_color: color}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(user: updated_user)
         |> assign(form: to_form(Accounts.change_user_profile(updated_user, %{})))
         |> put_flash(:info, "Avatar color updated!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update avatar color")}
    end
  end

  @impl true
  def handle_event("update_avatar_opacity", %{"opacity" => opacity}, socket) do
    opacity_int = String.to_integer(opacity)
    # Save opacity immediately to database
    case Accounts.update_user_profile(socket.assigns.user, %{avatar_opacity: opacity_int}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(user: updated_user)
         |> assign(avatar_opacity: opacity_int)
         |> assign(form: to_form(Accounts.change_user_profile(updated_user, %{})))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update avatar opacity")}
    end
  end

  @impl true
  def handle_event("select_avatar_shape", %{"avatar_shape" => shape}, socket) do
    require Logger
    Logger.info("Avatar shape event received: #{inspect(shape)}")
    
    # Save avatar shape immediately to database
    case Accounts.update_user_profile(socket.assigns.user, %{avatar_shape: shape}) do
      {:ok, updated_user} ->
        Logger.info("Avatar shape updated successfully to: #{updated_user.avatar_shape}")
        {:noreply,
         socket
         |> assign(user: updated_user)
         |> assign(form: to_form(Accounts.change_user_profile(updated_user, %{})))}

      {:error, changeset} ->
        Logger.error("Failed to update avatar shape: #{inspect(changeset.errors)}")
        {:noreply, put_flash(socket, :error, "Failed to update avatar shape")}
    end
  end

  @impl true
  def handle_event("select_background", %{"background" => background}, socket) do
    # Save the background preference immediately
    case Accounts.update_user(socket.assigns.user, %{
      background_preference: background,
      background_custom_data: socket.assigns.custom_data
    }) do
      {:ok, updated_user} ->
        socket = assign(socket, user: updated_user, selected_background: background)
        
        # Push real-time background update via client hook
        {:noreply, push_event(socket, "background_update", %{
          background: background,
          custom_data: socket.assigns.custom_data,
          global: true
        })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update background")}
    end
  end

  @impl true
  def handle_event("update_custom_setting", params, socket) do
    # Handle both _target format and direct field updates
    {field, value} = case params do
      %{"_target" => [field]} -> {field, params[field]}
      %{"gradient_start" => value} -> {"gradient_start", value}
      %{"gradient_end" => value} -> {"gradient_end", value}
      %{"solid_color" => value} -> {"solid_color", value}
      _ -> {nil, nil}
    end
    
    if field && value do
      custom_data = socket.assigns.custom_data || %{}
      updated_data = Map.put(custom_data, field, value)
      
      # Save immediately to user preferences
      case Accounts.update_user(socket.assigns.user, %{
        background_custom_data: updated_data
      }) do
        {:ok, updated_user} ->
          socket = assign(socket, user: updated_user, custom_data: updated_data)
          
          # Push real-time background update for custom settings via client hook
          {:noreply, push_event(socket, "background_update", %{
            background: socket.assigns.selected_background,
            custom_data: updated_data,
            global: true
          })}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update background")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_glass_setting", params, socket) do
    # Handle both _target format and direct field updates
    {field, value} = case params do
      %{"_target" => [field]} -> {field, params[field]}
      %{"glass_opacity" => value} -> {"glass_opacity", value}
      %{"glass_blur" => value} -> {"glass_blur", value}
      _ -> {nil, nil}
    end
    
    if field && value do
      custom_data = socket.assigns.custom_data || %{}
      updated_data = Map.put(custom_data, field, value)
      
      # Save immediately to user preferences
      case Accounts.update_user(socket.assigns.user, %{
        background_custom_data: updated_data
      }) do
        {:ok, updated_user} ->
          socket = assign(socket, user: updated_user, custom_data: updated_data)
          
          # Push real-time update to glass theme system via client hook
          {:noreply, push_event(socket, "glass_theme_update", %{
            theme: Map.get(updated_data, "glass_theme", "dark"),
            opacity: Map.get(updated_data, "glass_opacity", "0.3"),
            blur: Map.get(updated_data, "glass_blur", "15"),
            custom_color: Map.get(updated_data, "glass_custom_color"),
            global: true
          })}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save glass setting")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_glass_theme", %{"theme" => theme}, socket) do
    custom_data = socket.assigns.custom_data || %{}
    updated_data = Map.put(custom_data, "glass_theme", theme)
    
    # Save immediately to user preferences
    case Accounts.update_user(socket.assigns.user, %{
      background_custom_data: updated_data
    }) do
      {:ok, updated_user} ->
        socket = 
          socket
          |> assign(user: updated_user, custom_data: updated_data)
          |> put_flash(:info, "Glass theme updated!")
        
        # Push theme update to global glass theme system via client hook
        {:noreply, push_event(socket, "glass_theme_update", %{
          theme: theme,
          opacity: Map.get(updated_data, "glass_opacity", "0.3"),
          blur: Map.get(updated_data, "glass_blur", "15"),
          custom_color: Map.get(updated_data, "glass_custom_color"),
          global: true
        })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save glass theme")}
    end
  end

  @impl true
  def handle_event("update_glass_custom_color", %{"color" => color}, socket) do
    custom_data = socket.assigns.custom_data || %{}
    updated_data = Map.put(custom_data, "glass_custom_color", color)
    
    # Save immediately to user preferences
    case Accounts.update_user(socket.assigns.user, %{
      background_custom_data: updated_data
    }) do
      {:ok, updated_user} ->
        socket = assign(socket, user: updated_user, custom_data: updated_data)
        
        # Push real-time update to glass theme system via client hook
        {:noreply, push_event(socket, "glass_theme_update", %{
          theme: Map.get(updated_data, "glass_theme", "dark"),
          opacity: Map.get(updated_data, "glass_opacity", "0.3"),
          blur: Map.get(updated_data, "glass_blur", "15"),
          custom_color: color,
          global: true
        })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save custom color")}
    end
  end

  @impl true
  def handle_event("update_gradient_start", %{"color" => color}, socket) do
    custom_data = socket.assigns.custom_data || %{}
    updated_data = Map.put(custom_data, "gradient_start", color)
    
    # Save immediately to user preferences
    case Accounts.update_user(socket.assigns.user, %{
      background_custom_data: updated_data
    }) do
      {:ok, updated_user} ->
        socket = assign(socket, user: updated_user, custom_data: updated_data)
        
        # Push real-time background update
        {:noreply, push_event(socket, "background_update", %{
          background: socket.assigns.selected_background,
          custom_data: updated_data,
          global: true
        })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update gradient start color")}
    end
  end

  @impl true
  def handle_event("update_gradient_end", %{"color" => color}, socket) do
    custom_data = socket.assigns.custom_data || %{}
    updated_data = Map.put(custom_data, "gradient_end", color)
    
    # Save immediately to user preferences
    case Accounts.update_user(socket.assigns.user, %{
      background_custom_data: updated_data
    }) do
      {:ok, updated_user} ->
        socket = assign(socket, user: updated_user, custom_data: updated_data)
        
        # Push real-time background update
        {:noreply, push_event(socket, "background_update", %{
          background: socket.assigns.selected_background,
          custom_data: updated_data,
          global: true
        })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update gradient end color")}
    end
  end

  @impl true
  def handle_event("update_solid_color", %{"color" => color}, socket) do
    custom_data = socket.assigns.custom_data || %{}
    updated_data = Map.put(custom_data, "solid_color", color)
    
    # Save immediately to user preferences
    case Accounts.update_user(socket.assigns.user, %{
      background_custom_data: updated_data
    }) do
      {:ok, updated_user} ->
        socket = assign(socket, user: updated_user, custom_data: updated_data)
        
        # Push real-time background update
        {:noreply, push_event(socket, "background_update", %{
          background: socket.assigns.selected_background,
          custom_data: updated_data,
          global: true
        })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update solid color")}
    end
  end

  # Privacy Settings Event Handlers

  @impl true
  def handle_event("toggle_invites", _params, socket) do
    new_value = !socket.assigns.user.allow_channel_invites

    case Accounts.update_invite_preferences(socket.assigns.user, %{allow_channel_invites: new_value}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(user: updated_user)
         |> put_flash(:info, "Invite preferences updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update preferences")}
    end
  end

  @impl true
  def handle_event("unblock_user", %{"user_id" => user_id_str}, socket) do
    user_id = String.to_integer(user_id_str)

    case Accounts.unblock_user(socket.assigns.user, user_id) do
      {:ok, updated_user} ->
        blocked_users = Accounts.list_blocked_users(updated_user.id)

        {:noreply,
         socket
         |> assign(user: updated_user, blocked_users: blocked_users)
         |> put_flash(:info, "User unblocked")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to unblock user")}
    end
  end

  @impl true
  def handle_event("select_previous_avatar", %{"url" => url}, socket) do
    case Accounts.update_user_profile(socket.assigns.user, %{avatar_url: url}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(user: updated_user)
         |> put_flash(:info, "Avatar updated successfully!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update avatar")}
    end
  end

  @impl true
  def handle_event("delete_previous_avatar", %{"url" => url}, socket) do
    case Bacon8.Uploads.delete_file(url) do
      :ok ->
        # If current avatar is the deleted one, remove it from profile
        socket = 
          if socket.assigns.user.avatar_url == url do
             {:ok, updated_user} = Accounts.update_user_profile(socket.assigns.user, %{avatar_url: nil})
             assign(socket, user: updated_user)
          else
             socket
          end

        # Refresh list
        previous_avatars = Bacon8.Uploads.list_user_uploads(socket.assigns.user.id, "avatar")
        
        {:noreply, 
         socket 
         |> assign(previous_avatars: previous_avatars)
         |> put_flash(:info, "Avatar deleted")}
         
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete file")}
    end
  end

  # Handle progress updates from auto-upload
  def handle_progress(:avatar, entry, socket) when entry.done? do
    # File is fully uploaded, now process it
    uploaded_file = consume_uploaded_entry(socket, entry, fn %{path: path} ->
      case Bacon8.Uploads.upload_file(socket.assigns.user, path, entry, context: "avatar") do
        {:ok, url} -> {:ok, url}
        {:error, _reason} -> {:postpone, :error}
      end
    end)

    # consume_uploaded_entry unwraps {:ok, value} and returns just value
    case uploaded_file do
      avatar_url when is_binary(avatar_url) ->
        case Accounts.update_user_profile(socket.assigns.user, %{avatar_url: avatar_url}) do
          {:ok, updated_user} ->
            # Refresh list
            previous_avatars = Bacon8.Uploads.list_user_uploads(updated_user.id, "avatar")

            {:noreply,
             socket
             |> assign(user: updated_user, previous_avatars: previous_avatars)
             |> assign(form: to_form(Accounts.change_user_profile(updated_user, %{})))
             |> put_flash(:info, "Avatar updated successfully!")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save avatar")}
        end

      {:postpone, _} ->
        {:noreply, put_flash(socket, :error, "Avatar upload failed")}

      _other ->
        {:noreply, put_flash(socket, :error, "Avatar upload failed")}
    end
  end

  def handle_progress(:avatar, _entry, socket) do
    # Progress update but not done yet
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div phx-hook="ProfileSettings" id="profile-container">
    <Bacon8Web.Components.PageContainer.page_container max_width="max-w-[85%]">
        <div class="max-w-4xl mx-auto" phx-hook="AudioHook" id="profile-audio-hook">
          <div class="mb-8">
            <h1 class="text-3xl font-bold text-white mb-2">Profile Settings</h1>
            <p class="text-gray-400">Manage your account settings and preferences</p>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <!-- Profile Preview -->
            <div class="lg:col-span-1">
              <div class="glass-dark rounded-lg p-6">
                <h2 class="text-lg font-semibold text-white mb-4">Profile Preview</h2>
                <div class="text-center">
                  <div class="inline-block mb-4">
                    <%= avatar_tag(@user, size_class: "w-24 h-24 text-2xl") %>
                  </div>
                  <h3 class="text-xl font-semibold text-white mb-1"><%= @user.name || "No name set" %></h3>
                  <p class="text-gray-400 mb-2"><%= @user.email %></p>
                  <div class="flex items-center justify-center space-x-2 text-sm">
                    <%= if @user.is_admin do %>
                      <span class="bg-purple-600 text-white px-2 py-1 rounded-full text-xs">Admin</span>
                    <% end %>
                    <%= if @user.email_verified_at do %>
                      <span class="bg-green-600 text-white px-2 py-1 rounded-full text-xs">Verified</span>
                    <% else %>
                      <span class="bg-yellow-600 text-white px-2 py-1 rounded-full text-xs">Unverified</span>
                    <% end %>
                  </div>
                  
                  <div class="mt-6 pt-6 border-t border-gray-700">
                    <h4 class="text-sm font-medium text-gray-400 mb-2">Storage Usage</h4>
                    <div class="w-full bg-gray-700 rounded-full h-2.5 mb-1">
                      <div class="bg-blue-600 h-2.5 rounded-full" style={"width: #{min((@data_usage.total_size_bytes / @data_usage.limit) * 100, 100)}%"}></div>
                    </div>
                    <div class="flex justify-between text-xs text-gray-400">
                      <span><%= Bacon8.Files.format_file_size(@data_usage.total_size_bytes) %></span>
                      <span><%= Bacon8.Files.format_file_size(@data_usage.limit) %></span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Profile Settings Form -->
            <div class="lg:col-span-2">
              <!-- Tabs -->
              <div class="glass-dark rounded-t-lg border-b-0">
                <div class="flex flex-wrap">
                  <button phx-click="switch_tab" phx-value-tab="profile" 
                          class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors #{if @active_tab == "profile", do: "text-blue-400 border-blue-400 bg-gray-750", else: "text-gray-400 border-transparent hover:text-white"}"}>
                    Profile Settings
                  </button>
                  <button phx-click="switch_tab" phx-value-tab="appearance" 
                          class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors #{if @active_tab == "appearance", do: "text-blue-400 border-blue-400 bg-gray-750", else: "text-gray-400 border-transparent hover:text-white"}"}>
                    Background
                  </button>
                  <button phx-click="switch_tab" phx-value-tab="glass_theme" 
                          class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors #{if @active_tab == "glass_theme", do: "text-blue-400 border-blue-400 bg-gray-750", else: "text-gray-400 border-transparent hover:text-white"}"}>
                    Glass Theme
                  </button>
                  <button phx-click="switch_tab" phx-value-tab="security" 
                          class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors #{if @active_tab == "security", do: "text-blue-400 border-blue-400 bg-gray-750", else: "text-gray-400 border-transparent hover:text-white"}"}>
                    Security
                  </button>
                  <button phx-click="switch_tab" phx-value-tab="email" 
                          class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors #{if @active_tab == "email", do: "text-blue-400 border-blue-400 bg-gray-750", else: "text-gray-400 border-transparent hover:text-white"}"}>
                    Email Settings
                  </button>
                  <button phx-click="switch_tab" phx-value-tab="privacy" 
                          class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors #{if @active_tab == "privacy", do: "text-blue-400 border-blue-400 bg-gray-750", else: "text-gray-400 border-transparent hover:text-white"}"}>
                    Privacy
                  </button>
                  <%!-- Pages from active plugins (BACON8.md §9), e.g. the store's orders and library --%>
                  <.link :for={item <- Bacon8.Plugins.profile_tabs(@current_user)} navigate={item.path}
                         class="px-6 py-4 text-sm font-medium border-b-2 border-transparent text-gray-400 hover:text-white transition-colors">
                    <Bacon8Web.Components.Gem.icon icon={item.icon} /> <%= item.label %>
                  </.link>
                </div>
              </div>

              <!-- Tab Content -->
              <%= if @active_tab == "profile" do %>
                <!-- Profile Settings -->
                <div class="glass-dark rounded-b-lg rounded-tr-lg p-6">
                  <h2 class="text-lg font-semibold text-white mb-6">Profile Settings</h2>

                  <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-6">
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                      <div>
                        <.input field={@form[:name]} label="Display Name" placeholder="Enter your name..." label_class="text-white" />
                      </div>
                      
                      <div>
                        <.input field={@form[:email]} label="Email Address" placeholder="your@email.com" label_class="text-white" />
                      </div>
                      
                      <div class="col-span-1 md:col-span-2">
                        <.input field={@form[:bio]} type="textarea" label="Bio" placeholder="Tell us about yourself..." label_class="text-white" rows="3" />
                        <p class="text-xs text-gray-400 mt-1">Max 500 characters</p>
                      </div>
                    </div>

                    <div class="pt-4">
                      <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg transition-colors font-medium">
                        Save Profile
                      </button>
                    </div>
                  </.form>

                  <!-- Avatar Settings (outside form - auto-saves) -->
                  <div class="space-y-6 mt-6 pt-6 border-t border-gray-700">
                    <h3 class="text-md font-semibold text-white">Avatar Settings</h3>
                    
                    <div>
                      <label class="block text-sm font-medium text-gray-300 mb-3">Avatar Image</label>
                      <div class="glass-dark rounded-lg p-4 border border-gray-600">
                        <!-- Upload Area -->
                        <.form for={%{}} phx-change="validate_avatar" phx-submit="upload_avatar" id="avatar-upload-form">
                          <div class="flex flex-col items-center justify-center">
                            <%= if has_custom_avatar?(@user) do %>
                              <div class="mb-4">
                                <%= avatar_tag(@user, size_class: "w-32 h-32") %>
                              </div>
                              <button type="button" phx-click="remove_avatar" class="mb-4 text-red-400 hover:text-red-300 text-sm">
                                Remove Custom Avatar
                              </button>
                            <% end %>
                            
                            <div class="w-full">
                              <div class="border-2 border-dashed border-gray-600 rounded-lg p-6 text-center hover:border-gray-500 transition-colors"
                                   phx-drop-target={@uploads.avatar.ref}>
                                <svg class="mx-auto h-12 w-12 text-gray-400 mb-4" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                                  <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                                </svg>
                                <div class="text-sm text-gray-300">
                                  <label for={@uploads.avatar.ref} class="cursor-pointer">
                                    <span class="text-blue-400 hover:text-blue-300">Upload a file</span>
                                    <span> or drag and drop</span>
                                  </label>
                                  <.live_file_input upload={@uploads.avatar} class="sr-only" />
                                </div>
                                <p class="text-xs text-gray-500 mt-2">PNG, JPG, GIF, WEBP up to 1MB</p>
                              </div>
                              
                              <!-- Upload Progress -->
                              <%= for entry <- @uploads.avatar.entries do %>
                                <div class="mt-4 bg-gray-700 rounded-lg p-3">
                                  <div class="flex items-center justify-between mb-2">
                                    <span class="text-sm text-gray-300"><%= entry.client_name %></span>
                                    <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} class="text-red-400 hover:text-red-300">
                                      ✕
                                    </button>
                                  </div>
                                  <div class="w-full bg-gray-600 rounded-full h-2">
                                    <div class="bg-blue-600 h-2 rounded-full transition-all duration-300" style={"width: #{entry.progress}%"}></div>
                                  </div>
                                  <%= for err <- upload_errors(@uploads.avatar, entry) do %>
                                    <p class="text-red-400 text-sm mt-1"><%= error_to_string(err) %></p>
                                  <% end %>
                                  <%= if entry.progress == 100 do %>
                                    <p class="text-green-400 text-sm mt-1">✓ Uploading...</p>
                                  <% end %>
                                </div>
                              <% end %>
                            </div>
                          </div>
                        </.form>
                      </div>
                    </div>

                    <!-- Previous Avatars -->
                    <%= if length(@previous_avatars) > 0 do %>
                      <div class="mt-4">
                        <label class="block text-sm font-medium text-gray-300 mb-3">Previous Avatars</label>
                        <div class="grid grid-cols-4 sm:grid-cols-5 gap-4">
                          <%= for avatar <- @previous_avatars do %>
                            <div class="relative group">
                              <button type="button" phx-click="select_previous_avatar" phx-value-url={avatar.url} class={"w-full aspect-square rounded-lg overflow-hidden border-2 transition-all " <> if(@user.avatar_url == avatar.url, do: "border-blue-500 ring-2 ring-blue-500/50", else: "border-transparent hover:border-blue-500")}>
                                <img src={avatar.url} class="w-full h-full object-cover" />
                              </button>
                              <button type="button" phx-click="delete_previous_avatar" phx-value-url={avatar.url} class="absolute top-1 right-1 bg-red-600 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity shadow-lg hover:bg-red-700" title="Delete" data-confirm="Are you sure you want to delete this avatar?">
                                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                                  <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                                </svg>
                              </button>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <div>
                      <label class="block text-sm font-medium text-gray-300 mb-3">Avatar Border Color</label>
                      <div class="space-y-4">
                        <div class="flex items-center gap-4">
                          <div 
                            class="w-16 h-16 rounded-lg border-2 border-gray-600"
                            style={"background-color: #{@user.avatar_color || "#3B82F6"}"}
                          ></div>
                          <div class="flex-1 space-y-3">
                            <div>
                              <label class="block text-xs text-gray-400 mb-1">Color</label>
                              <input 
                                type="color" 
                                id="avatar-color-picker"
                                phx-hook="ColorPicker"
                                data-event="select_avatar_color"
                                value={@user.avatar_color || "#3B82F6"}
                                class="w-full h-10 rounded cursor-pointer bg-gray-700 border border-gray-600"
                              />
                            </div>
                            <div>
                              <label class="block text-xs text-gray-400 mb-1">Opacity: <span id="opacity-value"><%= @avatar_opacity %></span>%</label>
                              <input 
                                type="range" 
                                id="avatar-opacity-slider"
                                phx-hook="OpacitySlider"
                                min="0" 
                                max="100" 
                                value={@avatar_opacity}
                                class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-blue-500"
                              />
                            </div>
                          </div>
                        </div>
                        <p class="text-xs text-gray-500">This color is used as your avatar border/glow effect</p>
                      </div>
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-300 mb-2">Avatar Shape</label>
                      <form phx-change="select_avatar_shape" id="avatar-shape-form">
                        <select 
                          name="avatar_shape" 
                          class="w-full bg-gray-700 text-white px-4 py-2 rounded-lg border border-gray-600 focus:border-blue-500 focus:outline-none"
                        >
                          <option value="circle" selected={@user.avatar_shape == "circle"}>Circle</option>
                          <option value="square" selected={@user.avatar_shape == "square"}>Square</option>
                          <option value="rounded" selected={@user.avatar_shape == "rounded"}>Rounded Square</option>
                        </select>
                      </form>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @active_tab == "appearance" do %>
                <!-- Appearance Settings -->
                <div class="glass-dark rounded-b-lg rounded-tr-lg p-6 border border-gray-700">
                  <div class="space-y-6">
                    <div>
                      <h2 class="text-2xl font-bold text-white mb-2">Background Theme</h2>
                      <p class="text-gray-400">Choose how your site looks</p>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <!-- Galaxy -->
                      <button
                        phx-click="select_background"
                        phx-value-background="galaxy"
                        class={"relative overflow-hidden rounded-lg border-2 transition-all duration-300 hover:scale-105 #{if @selected_background == "galaxy", do: "border-blue-500 ring-2 ring-blue-500 ring-opacity-50", else: "border-gray-700 hover:border-gray-500"}"}
                      >
                        <div class="h-32 bg-gradient-to-br from-indigo-900 via-purple-900 to-black relative">
                          <%= if @selected_background == "galaxy" do %>
                            <div class="absolute top-2 right-2 bg-blue-500 text-white px-2 py-1 rounded-full text-xs font-bold">
                              ✓ Active
                            </div>
                          <% end %>
                        </div>
                        <div class="bg-gray-900 p-4 text-left">
                          <h4 class="font-bold text-white mb-1">Galaxy</h4>
                          <p class="text-sm text-gray-400">Swirling cosmic particles with stars</p>
                        </div>
                      </button>

                      <!-- Nebula -->
                      <button
                        phx-click="select_background"
                        phx-value-background="nebula"
                        class={"relative overflow-hidden rounded-lg border-2 transition-all duration-300 hover:scale-105 #{if @selected_background == "nebula", do: "border-blue-500 ring-2 ring-blue-500 ring-opacity-50", else: "border-gray-700 hover:border-gray-500"}"}
                      >
                        <div class="h-32 bg-gradient-to-br from-pink-900 via-purple-900 to-blue-900 relative">
                          <%= if @selected_background == "nebula" do %>
                            <div class="absolute top-2 right-2 bg-blue-500 text-white px-2 py-1 rounded-full text-xs font-bold">
                              ✓ Active
                            </div>
                          <% end %>
                        </div>
                        <div class="bg-gray-900 p-4 text-left">
                          <h4 class="font-bold text-white mb-1">Nebula</h4>
                          <p class="text-sm text-gray-400">Colorful gas clouds with gentle motion</p>
                        </div>
                      </button>

                      <!-- Starfield -->
                      <button
                        phx-click="select_background"
                        phx-value-background="starfield"
                        class={"relative overflow-hidden rounded-lg border-2 transition-all duration-300 hover:scale-105 #{if @selected_background == "starfield", do: "border-blue-500 ring-2 ring-blue-500 ring-opacity-50", else: "border-gray-700 hover:border-gray-500"}"}
                      >
                        <div class="h-32 bg-gradient-to-b from-gray-900 to-black relative">
                          <%= for i <- 1..20 do %>
                            <div
                              class="absolute w-1 h-1 bg-white rounded-full opacity-70"
                              style={"left: #{rem(i * 17, 100)}%; top: #{rem(i * 23, 100)}%;"}
                            >
                            </div>
                          <% end %>
                          <%= if @selected_background == "starfield" do %>
                            <div class="absolute top-2 right-2 bg-blue-500 text-white px-2 py-1 rounded-full text-xs font-bold">
                              ✓ Active
                            </div>
                          <% end %>
                        </div>
                        <div class="bg-gray-900 p-4 text-left">
                          <h4 class="font-bold text-white mb-1">Starfield</h4>
                          <p class="text-sm text-gray-400">Classic hyperspace scrolling stars</p>
                        </div>
                      </button>

                      <!-- Void -->
                      <button
                        phx-click="select_background"
                        phx-value-background="void"
                        class={"relative overflow-hidden rounded-lg border-2 transition-all duration-300 hover:scale-105 #{if @selected_background == "void", do: "border-blue-500 ring-2 ring-blue-500 ring-opacity-50", else: "border-gray-700 hover:border-gray-500"}"}
                      >
                        <div class="h-32 bg-black relative">
                          <%= for i <- 1..18 do %>
                            <div
                              class="absolute w-1 h-1 bg-white rounded-full opacity-60"
                              style={"left: #{rem(i * 19, 100)}%; top: #{rem(i * 29, 100)}%;"}
                            >
                            </div>
                          <% end %>
                          <%= if @selected_background == "void" do %>
                            <div class="absolute top-2 right-2 bg-blue-500 text-white px-2 py-1 rounded-full text-xs font-bold">
                              ✓ Active
                            </div>
                          <% end %>
                        </div>
                        <div class="bg-gray-900 p-4 text-left">
                          <h4 class="font-bold text-white mb-1">Void</h4>
                          <p class="text-sm text-gray-400">Minimal dark space with subtle stars</p>
                        </div>
                      </button>

                      <!-- Gradient -->
                      <button
                        phx-click="select_background"
                        phx-value-background="gradient"
                        class={"relative overflow-hidden rounded-lg border-2 transition-all duration-300 hover:scale-105 #{if @selected_background == "gradient", do: "border-blue-500 ring-2 ring-blue-500 ring-opacity-50", else: "border-gray-700 hover:border-gray-500"}"}
                      >
                        <div class="h-32 bg-gradient-to-br from-blue-600 to-purple-600 relative">
                          <%= if @selected_background == "gradient" do %>
                            <div class="absolute top-2 right-2 bg-blue-500 text-white px-2 py-1 rounded-full text-xs font-bold">
                              ✓ Active
                            </div>
                          <% end %>
                        </div>
                        <div class="bg-gray-900 p-4 text-left">
                          <h4 class="font-bold text-white mb-1">Gradient</h4>
                          <p class="text-sm text-gray-400">Smooth color transitions (customizable)</p>
                        </div>
                      </button>

                      <!-- Solid -->
                      <button
                        phx-click="select_background"
                        phx-value-background="solid"
                        class={"relative overflow-hidden rounded-lg border-2 transition-all duration-300 hover:scale-105 #{if @selected_background == "solid", do: "border-blue-500 ring-2 ring-blue-500 ring-opacity-50", else: "border-gray-700 hover:border-gray-500"}"}
                      >
                        <div class="h-32 bg-gray-900 relative">
                          <%= if @selected_background == "solid" do %>
                            <div class="absolute top-2 right-2 bg-blue-500 text-white px-2 py-1 rounded-full text-xs font-bold">
                              ✓ Active
                            </div>
                          <% end %>
                        </div>
                        <div class="bg-gray-900 p-4 text-left">
                          <h4 class="font-bold text-white mb-1">Solid Color</h4>
                          <p class="text-sm text-gray-400">Single color background (customizable)</p>
                        </div>
                      </button>
                    </div>

                    <!-- Custom Settings -->
                    <%= if @selected_background in ["gradient", "solid"] do %>
                      <div class="bg-gray-900 rounded-lg p-6 border border-gray-700">
                        <h4 class="text-lg font-bold text-white mb-4">Customize Colors</h4>
                        
                        <%= if @selected_background == "gradient" do %>
                          <div class="space-y-4">
                            <div>
                              <label class="block text-sm text-gray-400 mb-2">Start Color</label>
                              <input
                                type="color"
                                id={"gradient-start-color-#{get_in(@custom_data, ["gradient_start"]) || "default"}"}
                                value={get_in(@custom_data, ["gradient_start"]) || "#3B82F6"}
                                phx-hook="ColorPicker"
                                data-event="update_gradient_start"
                                class="w-full h-12 rounded cursor-pointer"
                              />
                            </div>
                            <div>
                              <label class="block text-sm text-gray-400 mb-2">End Color</label>
                              <input
                                type="color"
                                id={"gradient-end-color-#{get_in(@custom_data, ["gradient_end"]) || "default"}"}
                                value={get_in(@custom_data, ["gradient_end"]) || "#9333EA"}
                                phx-hook="ColorPicker"
                                data-event="update_gradient_end"
                                class="w-full h-12 rounded cursor-pointer"
                              />
                            </div>
                          </div>
                        <% else %>
                          <div>
                            <label class="block text-sm text-gray-400 mb-2">Background Color</label>
                            <input
                              type="color"
                              id={"solid-color-#{get_in(@custom_data, ["solid_color"]) || "default"}"}
                              value={get_in(@custom_data, ["solid_color"]) || "#1F2937"}
                              phx-hook="ColorPicker"
                              data-event="update_solid_color"
                              class="w-full h-12 rounded cursor-pointer"
                            />
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @active_tab == "glass_theme" do %>
                <!-- Glass Theme Settings -->
                <div class="glass-dark rounded-b-lg rounded-tr-lg p-6 border border-gray-700">
                  <div class="space-y-6">
                    <div>
                      <h2 class="text-2xl font-bold text-white mb-2">Frosted Glass Effects</h2>
                      <p class="text-gray-400">Customize the appearance of panels, navbar, and taskbar. Changes apply instantly.</p>
                    </div>

                    <!-- Glass Settings Form - Real-time updates -->
                    <form phx-change="update_glass_setting" class="space-y-6">
                      <!-- Theme Selection -->
                      <div>
                        <label class="block text-sm text-gray-400 mb-3">Glass Theme</label>
                        <div class="grid grid-cols-4 gap-3">
                          <%= for {theme, label, color} <- [
                            {"dark", "Dark", "#1F2937"},
                            {"blue", "Blue", "#3B82F6"},
                            {"purple", "Purple", "#9333EA"},
                            {"green", "Green", "#22C55E"},
                            {"red", "Red", "#EF4444"},
                            {"amber", "Amber", "#F59E0B"},
                            {"teal", "Teal", "#14B8A6"},
                            {"light", "Frosted", "#F3F4F6"}
                          ] do %>
                            <button
                              type="button"
                              phx-click="update_glass_theme"
                              phx-value-theme={theme}
                              class={"flex flex-col items-center justify-center p-3 rounded-lg border transition-all #{if (get_in(@custom_data, ["glass_theme"]) || "dark") == theme, do: "border-white ring-2 ring-white/20 bg-white/5", else: "border-gray-700 hover:border-gray-500 hover:bg-white/5"}"}
                            >
                              <div class="glass-swatch mb-2" style={"--swatch: #{color}"}></div>
                              <span class="text-xs text-gray-300"><%= label %></span>
                            </button>
                          <% end %>
                        </div>
                      </div>

                      <!-- Custom Color Picker for Glass -->
                      <div>
                        <label class="block text-sm text-gray-400 mb-3">Glass Tint Color</label>
                        <div class="flex items-center space-x-4">
                          <input
                            type="color"
                            id={"glass-custom-color-picker-#{get_in(@custom_data, ["glass_custom_color"]) || "default"}"}
                            value={get_in(@custom_data, ["glass_custom_color"]) || "#000000"}
                            phx-hook="ColorPicker"
                            data-event="update_glass_custom_color"
                            class="glass-picker w-20 h-16 cursor-pointer"
                          />
                          <div class="flex-1">
                            <p class="text-sm text-gray-300">Choose a custom tint color for your glass panels</p>
                          </div>
                        </div>
                      </div>

                      <div>
                        <label class="block text-sm text-gray-400 mb-3">Glass Opacity</label>
                        <input
                          type="range"
                          min="0.05"
                          max="0.9"
                          step="0.05"
                          name="glass_opacity"
                          id={"glass-opacity-#{get_in(@custom_data, ["glass_opacity"]) || "0.4"}"}
                          value={get_in(@custom_data, ["glass_opacity"]) || "0.4"}
                          phx-debounce="300"
                          class="w-full h-3 bg-gray-700 rounded-lg appearance-none cursor-pointer slider-blue"
                        />
                        <div class="flex justify-between text-xs text-gray-500 mt-2">
                          <span>More Transparent</span>
                          <span class="text-center">Current: <%= get_in(@custom_data, ["glass_opacity"]) || "0.4" %></span>
                          <span>More Opaque</span>
                        </div>
                      </div>
                      
                      <div>
                        <label class="block text-sm text-gray-400 mb-3">Blur Intensity</label>
                        <input
                          type="range"
                          min="5"
                          max="25"
                          step="5"
                          name="glass_blur"
                          id={"glass-blur-#{get_in(@custom_data, ["glass_blur"]) || "15"}"}
                          value={get_in(@custom_data, ["glass_blur"]) || "15"}
                          phx-debounce="300"
                          class="w-full h-3 bg-gray-700 rounded-lg appearance-none cursor-pointer slider-blue"
                        />
                        <div class="flex justify-between text-xs text-gray-500 mt-2">
                          <span>Less Blur</span>
                          <span class="text-center">Current: <%= get_in(@custom_data, ["glass_blur"]) || "15" %>px</span>
                          <span>More Blur</span>
                        </div>
                      </div>
                    </form>
                  </div>
                </div>
              <% end %>

              <%= if @active_tab == "security" do %>
                <!-- Security Settings -->
                <div class="glass-dark rounded-b-lg rounded-tr-lg p-6 border border-gray-700">
                  <h2 class="text-lg font-semibold text-white mb-6">Security Settings</h2>

                  <.form for={@password_form} phx-submit="change_password" phx-change="validate_password" class="space-y-6">
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                      <div>
                        <.input field={@password_form[:current_password]} type="password" label="Current Password" placeholder="Enter current password..." />
                      </div>
                      <div>
                        <.input field={@password_form[:password]} type="password" label="New Password" placeholder="Enter new password..." />
                      </div>
                    </div>

                    <div>
                      <.input field={@password_form[:password_confirmation]} type="password" label="Confirm New Password" placeholder="Confirm new password..." />
                    </div>

                    <div class="pt-4">
                      <button type="submit" class="bg-red-600 hover:bg-red-700 text-white px-6 py-3 rounded-lg transition-colors font-medium">
                        Change Password
                      </button>
                    </div>
                  </.form>

                  <hr class="border-gray-600 my-6">

                  <div>
                    <h3 class="text-lg font-medium text-white mb-4">Two-Factor Authentication</h3>
                    <%= if @user.two_factor_enabled do %>
                      <div class="flex items-center space-x-2 text-green-400 mb-4">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"></path>
                        </svg>
                        <span>Two-factor authentication is enabled</span>
                      </div>
                      <button class="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded-lg transition-colors text-sm">
                        Disable 2FA
                      </button>
                    <% else %>
                      <div class="flex items-center space-x-2 text-yellow-400 mb-4">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L5.082 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
                        </svg>
                        <span>Two-factor authentication is disabled</span>
                      </div>
                      <p class="text-gray-400 text-sm mb-4">Add an extra layer of security to your account by enabling two-factor authentication.</p>
                      <button class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg transition-colors text-sm">
                        Enable 2FA
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @active_tab == "email" do %>
                <!-- Email Settings -->
                <div class="glass-dark rounded-b-lg rounded-tr-lg p-6 border border-gray-700">
                  <h2 class="text-lg font-semibold text-white mb-6">Email Settings</h2>

                  <div class="space-y-6">
                    <div>
                      <h3 class="text-lg font-medium text-white mb-4">Primary Email Address</h3>
                      <div class="bg-gray-700 rounded-lg p-4">
                        <div class="flex items-center justify-between">
                          <div>
                            <p class="text-white font-medium"><%= @user.email %></p>
                            <%= if @user.email_verified_at do %>
                              <div class="flex items-center space-x-2 text-green-400 mt-1">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                                </svg>
                                <span class="text-sm">Verified</span>
                              </div>
                            <% else %>
                              <div class="flex items-center space-x-2 text-yellow-400 mt-1">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L5.082 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
                                </svg>
                                <span class="text-sm">Not Verified</span>
                              </div>
                            <% end %>
                          </div>
                          <%= unless @user.email_verified_at do %>
                            <button phx-click="resend_verification" class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg transition-colors text-sm">
                              Send Verification
                            </button>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <div>
                      <h3 class="text-lg font-medium text-white mb-4">Email Notifications</h3>
                      <div class="space-y-3">
                        <label class="flex items-center">
                          <input type="checkbox" class="rounded bg-gray-700 border-gray-600 text-blue-600 focus:ring-blue-500 focus:ring-2" checked>
                          <span class="ml-2 text-gray-300">Account security alerts</span>
                        </label>
                        <label class="flex items-center">
                          <input type="checkbox" class="rounded bg-gray-700 border-gray-600 text-blue-600 focus:ring-blue-500 focus:ring-2" checked>
                          <span class="ml-2 text-gray-300">Important updates</span>
                        </label>
                        <label class="flex items-center">
                          <input type="checkbox" class="rounded bg-gray-700 border-gray-600 text-blue-600 focus:ring-blue-500 focus:ring-2">
                          <span class="ml-2 text-gray-300">Marketing emails</span>
                        </label>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @active_tab == "privacy" do %>
                <!-- Privacy Settings -->
                <div class="glass-dark rounded-b-lg rounded-tr-lg p-6 border border-gray-700">
                  <h2 class="text-lg font-semibold text-white mb-6">Privacy Settings</h2>

                  <div class="space-y-6">
                    <!-- Invite Privacy -->
                    <div>
                      <h3 class="text-lg font-medium text-white mb-4 flex items-center gap-2">
                        <span>🔒</span>
                        <span>Channel Invites</span>
                      </h3>
                      
                      <div class="space-y-4">
                        <label class="flex items-center justify-between p-4 bg-gray-800/50 rounded-lg">
                          <div class="flex-1">
                            <span class="text-gray-200 font-medium">Allow channel invites</span>
                            <p class="text-sm text-gray-400 mt-1">When disabled, you won't receive any channel invitations</p>
                          </div>
                          <label class="relative inline-flex items-center cursor-pointer ml-4">
                            <input type="checkbox" 
                                   phx-click="toggle_invites" 
                                   checked={@user.allow_channel_invites}
                                   class="sr-only peer">
                            <div class="w-11 h-6 bg-gray-700 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-800 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                          </label>
                        </label>

                        <!-- Blocked Users -->
                        <div class="p-4 bg-gray-800/50 rounded-lg">
                          <div class="flex items-center justify-between mb-3">
                            <h4 class="text-gray-200 font-medium">Blocked Users</h4>
                            <span class="text-sm text-gray-400"><%= length(@blocked_users) %> blocked</span>
                          </div>
                          <p class="text-sm text-gray-400 mb-4">These users cannot send you channel invites</p>
                          
                          <%= if Enum.empty?(@blocked_users) do %>
                            <div class="text-center py-6 text-gray-500">
                              <p class="text-sm">No blocked users</p>
                            </div>
                          <% else %>
                            <div class="space-y-2 max-h-64 overflow-y-auto">
                              <%= for blocked <- @blocked_users do %>
                                <div class="flex items-center justify-between p-3 bg-gray-700/50 rounded">
                                  <div class="flex items-center gap-3">
                                    <%= if blocked.avatar_url do %>
                                      <img src={blocked.avatar_url} class="w-8 h-8 rounded-full" alt="" />
                                    <% else %>
                                      <div class="w-8 h-8 rounded-full bg-gray-600 flex items-center justify-center text-white text-sm">
                                        <%= String.first(blocked.name || blocked.email) |> String.upcase() %>
                                      </div>
                                    <% end %>
                                    <div>
                                      <p class="text-white text-sm font-medium"><%= blocked.name || "User" %></p>
                                      <p class="text-gray-400 text-xs"><%= blocked.email %></p>
                                    </div>
                                  </div>
                                  <button 
                                    phx-click="unblock_user" 
                                    phx-value-user_id={blocked.id}
                                    class="px-3 py-1 text-sm text-red-400 hover:text-red-300 hover:bg-red-900/20 rounded transition-colors"
                                  >
                                    Unblock
                                  </button>
                                </div>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <!-- Info about audio controls -->
                    <div class="p-4 bg-blue-900/20 border border-blue-500/30 rounded-lg">
                      <div class="flex items-start gap-3">
                        <span class="text-2xl">🔊</span>
                        <div>
                          <h4 class="text-blue-300 font-medium mb-1">Audio Settings</h4>
                          <p class="text-sm text-gray-400">Volume and notification sound controls are available in the taskbar speaker icon (🔊) at the bottom right of your screen.</p>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>

              <!-- Account Information -->
              <div class="glass-dark rounded-lg p-6 border border-gray-700 mt-6">
                <h3 class="text-lg font-semibold text-white mb-4">Account Information</h3>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                  <div>
                    <span class="text-gray-400">Member since:</span>
                    <span class="text-white ml-2"><%= Calendar.strftime(@user.inserted_at, "%B %d, %Y") %></span>
                  </div>
                  <div>
                    <span class="text-gray-400">Last login:</span>
                    <span class="text-white ml-2">
                      <%= if @user.last_login_at do %>
                        <%= Calendar.strftime(@user.last_login_at, "%m/%d/%Y %I:%M %p") %>
                      <% else %>
                        Never
                      <% end %>
                    </span>
                  </div>
                  <div>
                    <span class="text-gray-400">Account status:</span>
                    <span class="text-white ml-2"><%= String.capitalize(@user.status || "active") %></span>
                  </div>
                  <div>
                    <span class="text-gray-400">Two-factor auth:</span>
                    <span class="text-white ml-2">
                      <%= if @user.two_factor_enabled, do: "Enabled", else: "Disabled" %>
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
    </Bacon8Web.Components.PageContainer.page_container>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:too_many_files), do: "You have selected too many files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
  defp error_to_string(error), do: inspect(error)
end