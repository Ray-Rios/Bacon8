defmodule Bacon8Web.FileManagerComponent do
  @moduledoc """
  OS-style file manager component with drag & drop support for Bacon8.
  Can be launched as a window from anywhere in the application.
  """
  use Bacon8Web, :live_component

  alias Bacon8.Files

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket = 
      socket
      |> assign(assigns)
      |> assign_defaults()
      |> load_files()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="file-manager-window bg-gray-900 border border-gray-700 rounded-lg shadow-2xl" style={"width: #{@width}px; height: #{@height}px;"}>
      <!-- Window Header -->
      <div class="file-manager-header glass-dark border-b border-gray-700 px-4 py-2 flex items-center justify-between rounded-t-lg">
        <div class="flex items-center space-x-2">
          <div class="flex space-x-1">
            <button class="w-3 h-3 bg-red-500 rounded-full" phx-click="close_window" phx-target={@myself}></button>
            <button class="w-3 h-3 bg-yellow-500 rounded-full" phx-click="minimize_window" phx-target={@myself}></button>
            <button class="w-3 h-3 bg-green-500 rounded-full" phx-click="maximize_window" phx-target={@myself}></button>
          </div>
          <h3 class="text-sm font-medium text-gray-200">File Manager</h3>
        </div>
        <div class="flex items-center space-x-2">
          <!-- View Mode Toggle -->
          <button 
            class={"px-2 py-1 text-xs rounded #{if @view_mode == :grid, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300"}"}
            phx-click="set_view_mode" 
            phx-value-mode="grid"
            phx-target={@myself}
          >
            Grid
          </button>
          <button 
            class={"px-2 py-1 text-xs rounded #{if @view_mode == :list, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300"}"}
            phx-click="set_view_mode" 
            phx-value-mode="list"
            phx-target={@myself}
          >
            List
          </button>
        </div>
      </div>

      <!-- Toolbar -->
      <div class="file-manager-toolbar bg-gray-850 border-b border-gray-700 px-4 py-2 flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <!-- Navigation -->
          <button class="p-1 hover:bg-gray-700 rounded" phx-click="navigate_back" phx-target={@myself}>
            <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"></path>
            </svg>
          </button>
          <button class="p-1 hover:bg-gray-700 rounded" phx-click="navigate_forward" phx-target={@myself}>
            <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
            </svg>
          </button>
          <button class="p-1 hover:bg-gray-700 rounded" phx-click="navigate_up" phx-target={@myself}>
            <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 10l7-7m0 0l7 7m-7-7v18"></path>
            </svg>
          </button>
        </div>

        <!-- Current Path -->
        <div class="flex-1 mx-4">
          <div class="glass-dark px-3 py-1 rounded text-sm text-gray-300 font-mono">
            <%= @current_path %>
          </div>
        </div>

        <!-- Actions -->
        <div class="flex items-center space-x-2">
          <button 
            class="px-3 py-1 bg-blue-600 hover:bg-blue-700 text-white text-xs rounded"
            phx-click="new_folder" 
            phx-target={@myself}
          >
            New Folder
          </button>
          <input 
            type="file" 
            id={"file-input-#{@id}"} 
            class="hidden" 
            multiple 
            phx-hook="FileUpload"
            phx-target={@myself}
          />
          <button 
            class="px-3 py-1 bg-green-600 hover:bg-green-700 text-white text-xs rounded"
            onclick={"document.getElementById('file-input-#{@id}').click()"}
          >
            Upload Files
          </button>
        </div>
      </div>

      <!-- Sidebar -->
      <div class="flex h-full">
        <div class="file-manager-sidebar w-48 bg-gray-850 border-r border-gray-700 p-3">
          <div class="space-y-2">
            <!-- Quick Access -->
            <div class="text-xs font-semibold text-gray-400 uppercase tracking-wide">Quick Access</div>
            <div class="space-y-1">
              <button 
                class={"w-full text-left px-2 py-1 text-sm rounded hover:bg-gray-700 #{if @current_location == :user_files, do: "bg-gray-700 text-blue-400", else: "text-gray-300"}"}
                phx-click="navigate_to" 
                phx-value-location="user_files"
                phx-target={@myself}
              >
                📁 My Files
              </button>
              <%= if @user_role in [:admin, :gm, :editor] do %>
                <button 
                  class={"w-full text-left px-2 py-1 text-sm rounded hover:bg-gray-700 #{if @current_location == :public_files, do: "bg-gray-700 text-blue-400", else: "text-gray-300"}"}
                  phx-click="navigate_to" 
                  phx-value-location="public_files"
                  phx-target={@myself}
                >
                  🌐 Public Files
                </button>
              <% end %>
            </div>

            <!-- File Type Filters -->
            <div class="mt-4">
              <div class="text-xs font-semibold text-gray-400 uppercase tracking-wide">Filter by Type</div>
              <div class="space-y-1 mt-2">
                <button 
                  class={"w-full text-left px-2 py-1 text-xs rounded hover:bg-gray-700 #{if @filter_type == :all, do: "bg-gray-700 text-blue-400", else: "text-gray-300"}"}
                  phx-click="set_filter" 
                  phx-value-type="all"
                  phx-target={@myself}
                >
                  All Files (<%= @stats.total_files %>)
                </button>
                <button 
                  class={"w-full text-left px-2 py-1 text-xs rounded hover:bg-gray-700 #{if @filter_type == :images, do: "bg-gray-700 text-blue-400", else: "text-gray-300"}"}
                  phx-click="set_filter" 
                  phx-value-type="images"
                  phx-target={@myself}
                >
                  🖼️ Images (<%= @stats.images %>)
                </button>
                <button 
                  class={"w-full text-left px-2 py-1 text-xs rounded hover:bg-gray-700 #{if @filter_type == :videos, do: "bg-gray-700 text-blue-400", else: "text-gray-300"}"}
                  phx-click="set_filter" 
                  phx-value-type="videos"
                  phx-target={@myself}
                >
                  🎥 Videos (<%= @stats.videos %>)
                </button>
                <button 
                  class={"w-full text-left px-2 py-1 text-xs rounded hover:bg-gray-700 #{if @filter_type == :audio, do: "bg-gray-700 text-blue-400", else: "text-gray-300"}"}
                  phx-click="set_filter" 
                  phx-value-type="audio"
                  phx-target={@myself}
                >
                  🎵 Audio (<%= @stats.audio %>)
                </button>
                <button 
                  class={"w-full text-left px-2 py-1 text-xs rounded hover:bg-gray-700 #{if @filter_type == :documents, do: "bg-gray-700 text-blue-400", else: "text-gray-300"}"}
                  phx-click="set_filter" 
                  phx-value-type="documents"
                  phx-target={@myself}
                >
                  📄 Documents (<%= @stats.documents %>)
                </button>
              </div>
            </div>

            <!-- Storage Usage -->
            <div class="mt-4">
              <div class="text-xs font-semibold text-gray-400 uppercase tracking-wide">Storage</div>
              <div class="mt-2 p-2 glass-dark rounded">
                <div class="flex justify-between text-xs text-gray-300 mb-1">
                  <span><%= Files.format_file_size(@usage.total_size_bytes) %> used</span>
                  <span><%= Files.format_file_size(@usage.limit) %></span>
                </div>
                <div class="w-full bg-gray-700 rounded-full h-1.5">
                  <div class="bg-blue-600 h-1.5 rounded-full transition-all duration-500" style={"width: #{min((@usage.total_size_bytes / @usage.limit) * 100, 100)}%"}></div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Main Content Area -->
        <div class="flex-1 flex flex-col">
          <!-- Search Bar -->
          <div class="p-3 border-b border-gray-700">
            <form phx-submit="search" phx-target={@myself} class="relative">
              <input 
                type="text" 
                name="query"
                value={@search_query}
                placeholder="Search files..."
                class="w-full glass-dark border border-gray-600 rounded px-3 py-2 text-sm text-gray-200 pr-8"
                phx-debounce="300"
              />
              <svg class="absolute right-2 top-2.5 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
            </form>
          </div>

          <!-- Drop Zone -->
          <div 
            class="flex-1 p-4 relative"
            id={"drop-zone-#{@id}"}
            phx-hook="FileDragDrop"
            phx-target={@myself}
          >
            <%= if @files == [] do %>
              <div class="flex flex-col items-center justify-center h-full text-gray-500">
                <svg class="w-16 h-16 mb-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 48 48">
                  <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
                <p class="text-lg font-medium mb-2">No files found</p>
                <p class="text-sm">Drag and drop files here or click Upload Files</p>
              </div>
            <% else %>
              <%= if @view_mode == :grid do %>
                <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                  <%= for file <- @files do %>
                    <.file_grid_item file={file} myself={@myself} />
                  <% end %>
                </div>
              <% else %>
                <div class="space-y-1">
                  <%= for file <- @files do %>
                    <.file_list_item file={file} myself={@myself} />
                  <% end %>
                </div>
              <% end %>
            <% end %>

            <!-- Drop overlay -->
            <div 
              id={"drop-overlay-#{@id}"} 
              class="absolute inset-0 bg-blue-900/20 border-2 border-dashed border-blue-500 rounded-lg hidden items-center justify-center"
            >
              <div class="text-center text-blue-400">
                <svg class="w-16 h-16 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 48 48">
                  <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
                <p class="text-lg font-medium">Drop files here to upload</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # File grid item component
  defp file_grid_item(assigns) do
    ~H"""
    <div class="file-item glass-dark hover:bg-gray-750 p-3 rounded-lg cursor-pointer group">
      <div class="text-center">
        <div class="mb-2">
          <%= if Files.is_image?(@file) do %>
            <img 
              src={@file.url} 
              class="w-12 h-12 mx-auto rounded object-cover"
              alt={@file.filename}
            />
          <% else %>
            <div class="w-12 h-12 mx-auto bg-gray-700 rounded flex items-center justify-center">
              <span class="text-2xl">
                <%= file_icon(@file) %>
              </span>
            </div>
          <% end %>
        </div>
        <div class="text-xs text-gray-300 truncate" title={@file.filename}>
          <%= @file.filename %>
        </div>
        <div class="text-xs text-gray-500 mt-1">
          <%= Files.format_file_size(@file.size) %>
        </div>
      </div>
      
      <!-- Actions (hidden by default, shown on hover) -->
      <div class="mt-2 flex justify-center space-x-1 opacity-0 group-hover:opacity-100 transition-opacity">
        <button 
          class="p-1 bg-blue-600 hover:bg-blue-700 rounded text-xs"
          phx-click="download_file" 
          phx-value-id={@file.id}
          phx-value-type={@file.type}
          phx-target={@myself}
          title="Download"
        >
          ⬇
        </button>
        <button 
          class="p-1 bg-red-600 hover:bg-red-700 rounded text-xs"
          phx-click="delete_file" 
          phx-value-id={@file.id}
          phx-value-type={@file.type}
          phx-target={@myself}
          data-confirm="Are you sure you want to delete this file?"
          title="Delete"
        >
          🗑
        </button>
      </div>
    </div>
    """
  end

  # File list item component
  defp file_list_item(assigns) do
    ~H"""
    <div class="file-item flex items-center p-2 hover:glass-dark rounded cursor-pointer group">
      <div class="flex-shrink-0 mr-3">
        <%= if Files.is_image?(@file) do %>
          <img 
            src={@file.url} 
            class="w-8 h-8 rounded object-cover"
            alt={@file.filename}
          />
        <% else %>
          <div class="w-8 h-8 bg-gray-700 rounded flex items-center justify-center">
            <span class="text-sm">
              <%= file_icon(@file) %>
            </span>
          </div>
        <% end %>
      </div>
      
      <div class="flex-1 min-w-0">
        <div class="text-sm text-gray-200 truncate" title={@file.filename}>
          <%= @file.filename %>
        </div>
        <div class="text-xs text-gray-500">
          <%= Files.format_file_size(@file.size) %> • <%= Calendar.strftime(@file.inserted_at, "%b %d, %Y") %>
        </div>
      </div>
      
      <!-- Actions -->
      <div class="flex-shrink-0 ml-4 flex space-x-1 opacity-0 group-hover:opacity-100 transition-opacity">
        <button 
          class="p-1 bg-blue-600 hover:bg-blue-700 rounded text-xs"
          phx-click="download_file" 
          phx-value-id={@file.id}
          phx-value-type={@file.type}
          phx-target={@myself}
          title="Download"
        >
          ⬇
        </button>
        <button 
          class="p-1 bg-red-600 hover:bg-red-700 rounded text-xs"
          phx-click="delete_file" 
          phx-value-id={@file.id}
          phx-value-type={@file.type}
          phx-target={@myself}
          data-confirm="Are you sure you want to delete this file?"
          title="Delete"
        >
          🗑
        </button>
      </div>
    </div>
    """
  end

  # File icon helper
  defp file_icon(file) do
    cond do
      Files.is_image?(file) -> "🖼️"
      Files.is_video?(file) -> "🎥"
      Files.is_audio?(file) -> "🎵"
      Files.is_document?(file) -> "📄"
      true -> "📁"
    end
  end

  # Event handlers
  @impl true
  def handle_event("file_drop", %{"files" => files}, socket) do
    user = socket.assigns.user
    
    # Process each dropped file
    Enum.each(files, fn file_data ->
      Files.create_user_file(user, file_data)
    end)
    
    socket = 
      socket
      |> put_flash(:info, "Files uploaded successfully!")
      |> load_files()
    
    {:noreply, socket}
  end

  def handle_event("file_selected", file_data, socket) do
    user = socket.assigns.user
    
    case Files.create_user_file(user, file_data) do
      {:ok, _file} ->
        socket = 
          socket
          |> put_flash(:info, "File uploaded successfully!")
          |> load_files()
        
        {:noreply, socket}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to upload file")}
    end
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_atom(mode))}
  end

  def handle_event("set_filter", %{"type" => type}, socket) do
    socket = 
      socket
      |> assign(:filter_type, String.to_atom(type))
      |> load_files()
    
    {:noreply, socket}
  end

  def handle_event("navigate_to", %{"location" => location}, socket) do
    socket = 
      socket
      |> assign(:current_location, String.to_atom(location))
      |> update_current_path()
      |> load_files()
    
    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket = 
      socket
      |> assign(:search_query, query)
      |> load_files()
    
    {:noreply, socket}
  end

  def handle_event("delete_file", %{"id" => _file_id, "type" => "media"}, socket) do
    {:noreply, put_flash(socket, :error, "Cannot delete media files from here")}
  end

  def handle_event("delete_file", %{"id" => file_id}, socket) do
    user = socket.assigns.user
    
    try do
      file = Files.get_user_file!(user, file_id)
      Files.delete_user_file(file)
      
      socket = 
        socket
        |> put_flash(:info, "File deleted successfully")
        |> load_files()
      
      {:noreply, socket}
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "File not found")}
    end
  end

  def handle_event("close_window", _params, socket) do
    send(self(), {:close_file_manager, socket.assigns.id})
    {:noreply, socket}
  end

  def handle_event(event, params, socket) do
    # Handle other events like minimize, maximize, etc.
    send(self(), {:file_manager_event, event, params, socket.assigns.id})
    {:noreply, socket}
  end

  # Private helper functions
  defp assign_defaults(socket) do
    socket
    |> assign_new(:width, fn -> 800 end)
    |> assign_new(:height, fn -> 600 end)
    |> assign_new(:view_mode, fn -> :grid end)
    |> assign_new(:filter_type, fn -> :all end)
    |> assign_new(:current_location, fn -> :user_files end)
    |> assign_new(:current_path, fn -> "/My Files" end)
    |> assign_new(:search_query, fn -> "" end)
    |> assign_new(:user_role, fn -> get_user_role(socket.assigns.user) end)
  end

  defp load_files(socket) do
    user = socket.assigns.user
    filter_type = socket.assigns.filter_type
    search_query = socket.assigns.search_query
    current_location = socket.assigns.current_location
    user_role = socket.assigns.user_role

    files = case {current_location, String.trim(search_query)} do
      {:user_files, ""} -> Files.list_all_user_content(user)
      {:user_files, query} -> 
        Files.list_all_user_content(user)
        |> Enum.filter(fn file -> String.contains?(String.downcase(file.filename), String.downcase(query)) end)
      {:public_files, ""} -> 
        Files.list_public_files(user_role) |> normalize_files()
      {:public_files, query} -> 
        Files.list_public_files(user_role)
        |> normalize_files()
        |> Enum.filter(fn file -> String.contains?(String.downcase(file.filename), String.downcase(query)) end)
    end

    # Apply filter
    filtered_files = case filter_type do
      :all -> files
      :images -> Enum.filter(files, &Files.is_image?/1)
      :videos -> Enum.filter(files, &Files.is_video?/1)
      :audio -> Enum.filter(files, &Files.is_audio?/1)
      :documents -> Enum.filter(files, &Files.is_document?/1)
    end

    stats = case current_location do
      :user_files -> Files.get_file_stats(user)
      :public_files -> 
        all_files = Files.list_public_files(user_role) |> normalize_files()
        %{
          total_files: length(all_files),
          total_size: Enum.sum(Enum.map(all_files, & &1.size)),
          images: Enum.count(all_files, &Files.is_image?/1),
          videos: Enum.count(all_files, &Files.is_video?/1),  
          audio: Enum.count(all_files, &Files.is_audio?/1),
          documents: Enum.count(all_files, &Files.is_document?/1)
        }
    end

    usage = Files.get_user_data_usage(user.id)

    socket
    |> assign(:files, filtered_files)
    |> assign(:stats, stats)
    |> assign(:usage, usage)
  end

  defp normalize_files(files) do
    Enum.map(files, fn file ->
      %{
        id: file.id,
        filename: file.filename,
        content_type: file.content_type,
        size: file.file_size,
        inserted_at: file.inserted_at,
        url: Bacon8.UserFileUpload.url({file.file, file}, :original),
        type: :file,
        source: file
      }
    end)
  end

  defp update_current_path(socket) do
    path = case socket.assigns.current_location do
      :user_files -> "/My Files"
      :public_files -> "/Public Files"
    end
    
    assign(socket, :current_path, path)
  end

  defp get_user_role(user) do
    # This should be determined based on your user role system
    # For now, defaulting to :user, but you should implement this based on your auth system
    cond do
      user.email == "admin@example.com" -> :admin  # Replace with actual admin check
      true -> :user
    end
  end
end