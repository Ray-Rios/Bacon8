defmodule Bacon8Web.Components.FileExplorer do
  @moduledoc """
  Windows-like File Explorer component for the desktop environment.
  Provides a familiar file browsing experience with:
  - Navigation tree (sidebar)
  - File/folder list with sorting
  - Details view, list view, icons view
  - File operations (upload, download, delete, rename)
  """
  use Phoenix.Component

  attr :window, :map, required: true
  attr :current_user, :map, default: nil
  attr :uploads, :map, default: %{}
  attr :target, :any, default: nil

  def file_explorer(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-gray-900 text-white">
      <!-- Toolbar -->
      <div class="flex items-center gap-1 px-2 py-1 bg-gray-800 border-b border-gray-700">
        <!-- Navigation buttons -->
        <button
          type="button"
          phx-click="fm_navigate_back"
          phx-value-window_id={@window.id}
          phx-target={@target}
          disabled={length(@window.history) <= 1}
          class={["p-1.5 rounded hover:bg-gray-700 transition-colors", 
                  if(length(@window.history) <= 1, do: "opacity-40 cursor-not-allowed", else: "")]}
          title="Back"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
          </svg>
        </button>
        
        <button
          type="button"
          phx-click="fm_navigate_forward"
          phx-value-window_id={@window.id}
          phx-target={@target}
          disabled={@window.forward_history == []}
          class={["p-1.5 rounded hover:bg-gray-700 transition-colors",
                  if(@window.forward_history == [], do: "opacity-40 cursor-not-allowed", else: "")]}
          title="Forward"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
          </svg>
        </button>
        
        <button
          type="button"
          phx-click="fm_navigate_up"
          phx-value-window_id={@window.id}
          phx-target={@target}
          disabled={@window.current_path == "/"}
          class={["p-1.5 rounded hover:bg-gray-700 transition-colors",
                  if(@window.current_path == "/", do: "opacity-40 cursor-not-allowed", else: "")]}
          title="Up one level"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7"/>
          </svg>
        </button>
        
        <div class="w-px h-5 bg-gray-600 mx-1"></div>
        
        <button
          type="button"
          phx-click="fm_refresh"
          phx-value-window_id={@window.id}
          phx-target={@target}
          class="p-1.5 rounded hover:bg-gray-700 transition-colors"
          title="Refresh"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
          </svg>
        </button>
        
        <!-- Address bar -->
        <div class="flex-1 flex items-center bg-gray-900 border border-gray-600 rounded px-2 py-1 mx-2">
          <span class="text-gray-400 mr-2">📁</span>
          <div class="flex items-center gap-1 text-sm overflow-x-auto whitespace-nowrap">
            <button
              type="button"
              phx-click="fm_navigate_to"
              phx-value-window_id={@window.id}
              phx-value-path="/"
              phx-target={@target}
              class="hover:text-blue-400 hover:underline"
            >
              My Files
            </button>
            <%= for crumb <- @window.breadcrumbs do %>
              <span class="text-gray-500">›</span>
              <button
                type="button"
                phx-click="fm_navigate_to"
                phx-value-window_id={@window.id}
                phx-value-path={crumb.path}
                phx-target={@target}
                class="hover:text-blue-400 hover:underline"
              >
                <%= crumb.name %>
              </button>
            <% end %>
          </div>
        </div>
        
        <!-- Search -->
        <div class="flex items-center bg-gray-900 border border-gray-600 rounded px-2 py-1 w-48">
          <svg class="w-4 h-4 text-gray-400 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
          </svg>
          <input
            type="text"
            placeholder="Search..."
            value={@window.search_query}
            phx-keyup="fm_search"
            phx-value-window_id={@window.id}
            phx-target={@target}
            phx-debounce="300"
            class="bg-transparent text-sm flex-1 outline-none text-white placeholder-gray-500"
          />
        </div>
      </div>
      
      <!-- View options bar -->
      <div class="flex items-center justify-between px-3 py-1.5 bg-gray-850 border-b border-gray-700 text-xs">
        <div class="flex items-center gap-4">
          <!-- View mode buttons -->
          <div class="flex items-center gap-1">
            <button
              type="button"
              phx-click="fm_set_view"
              phx-value-window_id={@window.id}
              phx-value-view="icons"
              phx-target={@target}
              class={["p-1 rounded", if(@window.view_mode == "icons", do: "bg-blue-600", else: "hover:bg-gray-700")]}
              title="Icons"
            >
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path d="M5 3a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2V5a2 2 0 00-2-2H5zM5 11a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2v-2a2 2 0 00-2-2H5zM11 5a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V5zM11 13a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/>
              </svg>
            </button>
            <button
              type="button"
              phx-click="fm_set_view"
              phx-value-window_id={@window.id}
              phx-value-view="list"
              phx-target={@target}
              class={["p-1 rounded", if(@window.view_mode == "list", do: "bg-blue-600", else: "hover:bg-gray-700")]}
              title="List"
            >
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M3 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clip-rule="evenodd"/>
              </svg>
            </button>
            <button
              type="button"
              phx-click="fm_set_view"
              phx-value-window_id={@window.id}
              phx-value-view="details"
              phx-target={@target}
              class={["p-1 rounded", if(@window.view_mode == "details", do: "bg-blue-600", else: "hover:bg-gray-700")]}
              title="Details"
            >
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M3 3a1 1 0 000 2h14a1 1 0 100-2H3zm0 4a1 1 0 000 2h14a1 1 0 100-2H3zm0 4a1 1 0 000 2h10a1 1 0 100-2H3z" clip-rule="evenodd"/>
              </svg>
            </button>
          </div>
          
          <!-- Sort dropdown -->
          <div class="flex items-center gap-2">
            <span class="text-gray-400">Sort by:</span>
            <select
              phx-change="fm_sort"
              phx-value-window_id={@window.id}
              phx-target={@target}
              name="sort_by"
              class="bg-gray-800 border border-gray-600 rounded px-2 py-0.5 text-xs"
            >
              <option value="name" selected={@window.sort_by == "name"}>Name</option>
              <option value="size" selected={@window.sort_by == "size"}>Size</option>
              <option value="type" selected={@window.sort_by == "type"}>Type</option>
              <option value="modified" selected={@window.sort_by == "modified"}>Date Modified</option>
            </select>
            <button
              type="button"
              phx-click="fm_toggle_sort_order"
              phx-value-window_id={@window.id}
              phx-target={@target}
              class="p-1 rounded hover:bg-gray-700"
              title={if @window.sort_order == "asc", do: "Ascending", else: "Descending"}
            >
              <%= if @window.sort_order == "asc" do %>
                <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z" clip-rule="evenodd"/>
                </svg>
              <% else %>
                <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd"/>
                </svg>
              <% end %>
            </button>
          </div>
        </div>
        
        <!-- New Folder and Upload buttons -->
        <div class="flex items-center gap-2">
          <!-- New Folder button (only in /my-files) -->
          <%= if String.starts_with?(@window.current_path, "/my-files") do %>
            <button
              type="button"
              phx-click="fm_new_folder"
              phx-value-window_id={@window.id}
              phx-target={@target}
              class="flex items-center gap-1 px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded transition-colors"
              title="New Folder"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 13h6m-3-3v6m-9 1V7a2 2 0 012-2h6l2 2h6a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>
              </svg>
              <span class="hidden sm:inline">New Folder</span>
            </button>
          <% end %>
          
          <!-- Upload button -->
          <form phx-change="fm_validate_upload" phx-submit="fm_upload" phx-target={@target} class="flex items-center">
            <input type="hidden" name="window_id" value={@window.id} />
            <label class="flex items-center gap-1 px-2 py-1 bg-blue-600 hover:bg-blue-700 rounded cursor-pointer transition-colors">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"/>
              </svg>
              <span>Upload</span>
              <.live_file_input upload={@uploads.files} class="hidden" />
            </label>
          </form>
        </div>
      </div>
      
      <!-- Main content area -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Sidebar / Navigation Tree -->
        <div class="w-48 bg-gray-850 border-r border-gray-700 overflow-y-auto flex-shrink-0">
          <div class="p-2">
            <div class="text-xs text-gray-400 uppercase tracking-wider mb-2 px-2">Quick Access</div>
            
            <!-- User's Files -->
            <%= if @current_user do %>
              <button
                type="button"
                phx-click="fm_navigate_to"
                phx-value-window_id={@window.id}
                phx-value-path="/my-files"
                phx-target={@target}
                class={["w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm text-left hover:bg-gray-700 transition-colors",
                        if(@window.current_path == "/my-files", do: "bg-gray-700", else: "")]}
              >
                <span>📁</span>
                <span>My Files</span>
              </button>
            <% end %>
            
            <!-- Public Files -->
            <button
              type="button"
              phx-click="fm_navigate_to"
              phx-value-window_id={@window.id}
              phx-value-path="/public"
              phx-target={@target}
              class={["w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm text-left hover:bg-gray-700 transition-colors",
                      if(@window.current_path == "/public" || String.starts_with?(@window.current_path, "/public/"), do: "bg-gray-700", else: "")]}
            >
              <span>🌐</span>
              <span>Public</span>
            </button>
            
            <div class="border-t border-gray-700 my-2"></div>
            
            <div class="text-xs text-gray-400 uppercase tracking-wider mb-2 px-2">Categories</div>
            
            <button
              type="button"
              phx-click="fm_filter_type"
              phx-value-window_id={@window.id}
              phx-value-type="images"
              phx-target={@target}
              class={["w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm text-left hover:bg-gray-700 transition-colors",
                      if(@window.filter_type == "images", do: "bg-gray-700", else: "")]}
            >
              <span>🖼️</span>
              <span>Images</span>
            </button>
            
            <button
              type="button"
              phx-click="fm_filter_type"
              phx-value-window_id={@window.id}
              phx-value-type="documents"
              phx-target={@target}
              class={["w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm text-left hover:bg-gray-700 transition-colors",
                      if(@window.filter_type == "documents", do: "bg-gray-700", else: "")]}
            >
              <span>📄</span>
              <span>Documents</span>
            </button>
            
            <button
              type="button"
              phx-click="fm_filter_type"
              phx-value-window_id={@window.id}
              phx-value-type="audio"
              phx-target={@target}
              class={["w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm text-left hover:bg-gray-700 transition-colors",
                      if(@window.filter_type == "audio", do: "bg-gray-700", else: "")]}
            >
              <span>🎵</span>
              <span>Audio</span>
            </button>
            
            <button
              type="button"
              phx-click="fm_filter_type"
              phx-value-window_id={@window.id}
              phx-value-type="video"
              phx-target={@target}
              class={["w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm text-left hover:bg-gray-700 transition-colors",
                      if(@window.filter_type == "video", do: "bg-gray-700", else: "")]}
            >
              <span>🎬</span>
              <span>Video</span>
            </button>
            
            <button
              type="button"
              phx-click="fm_filter_type"
              phx-value-window_id={@window.id}
              phx-value-type="all"
              phx-target={@target}
              class={["w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm text-left hover:bg-gray-700 transition-colors",
                      if(@window.filter_type == "all", do: "bg-gray-700", else: "")]}
            >
              <span>📂</span>
              <span>All Files</span>
            </button>
          </div>
        </div>
        
        <!-- File listing area -->
        <div class="flex-1 overflow-auto p-2" phx-drop-target={@uploads.files.ref}>
          <%= if @window.current_items == [] do %>
            <div class="flex flex-col items-center justify-center h-full text-gray-500">
              <svg class="w-16 h-16 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/>
              </svg>
              <p class="text-lg">This folder is empty</p>
              <p class="text-sm mt-1">Drop files here or click Upload to add files</p>
            </div>
          <% else %>
            <%= case @window.view_mode do %>
              <% "icons" -> %>
                <.icons_view window={@window} target={@target} />
              <% "list" -> %>
                <.list_view window={@window} target={@target} />
              <% "details" -> %>
                <.details_view window={@window} target={@target} />
              <% _ -> %>
                <.details_view window={@window} target={@target} />
            <% end %>
          <% end %>
          
          <!-- Upload progress overlay -->
          <%= if @uploads.files.entries != [] do %>
            <div class="absolute bottom-4 right-4 bg-gray-800 border border-gray-600 rounded-lg p-3 shadow-lg max-w-xs">
              <div class="text-sm font-medium mb-2">Uploading...</div>
              <%= for entry <- @uploads.files.entries do %>
                <div class="mb-2">
                  <div class="flex justify-between text-xs text-gray-400 mb-1">
                    <span class="truncate max-w-[150px]"><%= entry.client_name %></span>
                    <span><%= entry.progress %>%</span>
                  </div>
                  <div class="w-full h-1.5 bg-gray-700 rounded-full overflow-hidden">
                    <div class="h-full bg-blue-500 transition-all" style={"width: #{entry.progress}%"}></div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Status bar -->
      <div class="flex items-center justify-between px-3 py-1 bg-gray-800 border-t border-gray-700 text-xs text-gray-400">
        <div>
          <%= length(@window.current_items) %> item<%= if length(@window.current_items) != 1, do: "s" %>
          <%= if @window.selected_items != [] do %>
            <span class="ml-2">(<%= length(@window.selected_items) %> selected)</span>
          <% end %>
        </div>
        <div class="flex items-center gap-4">
          <%= if @current_user do %>
            <span>Storage: <%= format_storage(@window.storage_used, @window.storage_quota) %></span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Icons view - large icons in a grid
  defp icons_view(assigns) do
    ~H"""
    <div class="grid grid-cols-6 gap-3">
      <%= for item <- @window.current_items do %>
        <div
          phx-click={if item.type == "folder", do: "fm_navigate_to", else: "fm_preview_file"}
          phx-value-window_id={@window.id}
          phx-value-path={item.path}
          phx-value-item_id={item.id}
          phx-value-url={item.url}
          phx-target={@target}
          class={["flex flex-col items-center p-3 rounded-lg cursor-pointer transition-colors group relative",
                  if(item.id in (@window.selected_items || []), do: "bg-blue-600/30 border border-blue-500", else: "hover:bg-gray-800")]}
        >
          <!-- Thumbnail for images -->
          <%= if is_image?(item) && item.url do %>
            <div class="w-16 h-16 mb-2 rounded overflow-hidden bg-gray-800 flex items-center justify-center">
              <img src={item.url} alt={item.name} class="max-w-full max-h-full object-contain" loading="lazy" />
            </div>
          <% else %>
            <div class="text-4xl mb-2"><%= item.icon %></div>
          <% end %>
          <div class="text-xs text-center truncate w-full" title={item.name}>
            <%= item.name %>
          </div>
          <!-- Play overlay for media -->
          <%= if is_playable?(item) do %>
            <div class="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity bg-black/40 rounded-lg">
              <span class="text-2xl"><%= get_play_icon(item) %></span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # List view - compact list
  defp list_view(assigns) do
    ~H"""
    <div class="space-y-0.5">
      <%= for item <- @window.current_items do %>
        <div
          phx-click={if item.type == "folder", do: "fm_navigate_to", else: "fm_preview_file"}
          phx-value-window_id={@window.id}
          phx-value-path={item.path}
          phx-value-item_id={item.id}
          phx-value-url={item.url}
          phx-target={@target}
          class={["flex items-center gap-3 px-2 py-1.5 rounded cursor-pointer transition-colors",
                  if(item.id in (@window.selected_items || []), do: "bg-blue-600/30", else: "hover:bg-gray-800")]}
        >
          <!-- Thumbnail for images -->
          <%= if is_image?(item) && item.url do %>
            <div class="w-8 h-8 rounded overflow-hidden bg-gray-800 flex items-center justify-center flex-shrink-0">
              <img src={item.url} alt={item.name} class="max-w-full max-h-full object-contain" loading="lazy" />
            </div>
          <% else %>
            <span class="text-xl"><%= item.icon %></span>
          <% end %>
          <span class="flex-1 truncate text-sm"><%= item.name %></span>
          <%= if is_playable?(item) do %>
            <span class="text-gray-500 text-xs"><%= get_play_icon(item) %> Play</span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Details view - table with columns
  defp details_view(assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead class="sticky top-0 bg-gray-900 border-b border-gray-700">
        <tr class="text-left text-gray-400">
          <th class="px-2 py-2 font-medium">
            <button
              type="button"
              phx-click="fm_sort"
              phx-value-window_id={@window.id}
              phx-value-sort_by="name"
              phx-target={@target}
              class="hover:text-white flex items-center gap-1"
            >
              Name
              <%= if @window.sort_by == "name" do %>
                <span class="text-blue-400"><%= if @window.sort_order == "asc", do: "↑", else: "↓" %></span>
              <% end %>
            </button>
          </th>
          <th class="px-2 py-2 font-medium w-24">
            <button
              type="button"
              phx-click="fm_sort"
              phx-value-window_id={@window.id}
              phx-value-sort_by="type"
              phx-target={@target}
              class="hover:text-white flex items-center gap-1"
            >
              Type
              <%= if @window.sort_by == "type" do %>
                <span class="text-blue-400"><%= if @window.sort_order == "asc", do: "↑", else: "↓" %></span>
              <% end %>
            </button>
          </th>
          <th class="px-2 py-2 font-medium w-24 text-right">
            <button
              type="button"
              phx-click="fm_sort"
              phx-value-window_id={@window.id}
              phx-value-sort_by="size"
              phx-target={@target}
              class="hover:text-white flex items-center gap-1 justify-end"
            >
              Size
              <%= if @window.sort_by == "size" do %>
                <span class="text-blue-400"><%= if @window.sort_order == "asc", do: "↑", else: "↓" %></span>
              <% end %>
            </button>
          </th>
          <th class="px-2 py-2 font-medium w-40">
            <button
              type="button"
              phx-click="fm_sort"
              phx-value-window_id={@window.id}
              phx-value-sort_by="modified"
              phx-target={@target}
              class="hover:text-white flex items-center gap-1"
            >
              Modified
              <%= if @window.sort_by == "modified" do %>
                <span class="text-blue-400"><%= if @window.sort_order == "asc", do: "↑", else: "↓" %></span>
              <% end %>
            </button>
          </th>
          <th class="px-2 py-2 font-medium w-28 text-center">Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= for item <- @window.current_items do %>
          <tr
            phx-click={if item.type == "folder", do: "fm_navigate_to", else: "fm_preview_file"}
            phx-value-window_id={@window.id}
            phx-value-path={item.path}
            phx-value-item_id={item.id}
            phx-value-url={item.url}
            phx-target={@target}
            class={["cursor-pointer transition-colors border-b border-gray-800",
                    if(item.id in (@window.selected_items || []), do: "bg-blue-600/30", else: "hover:bg-gray-800")]}
          >
            <td class="px-2 py-2">
              <div class="flex items-center gap-2">
                <!-- Thumbnail for images -->
                <%= if is_image?(item) && item.url do %>
                  <div class="w-6 h-6 rounded overflow-hidden bg-gray-800 flex items-center justify-center flex-shrink-0">
                    <img src={item.url} alt={item.name} class="max-w-full max-h-full object-contain" loading="lazy" />
                  </div>
                <% else %>
                  <span class="text-lg"><%= item.icon %></span>
                <% end %>
                <span class="truncate"><%= item.name %></span>
              </div>
            </td>
            <td class="px-2 py-2 text-gray-400"><%= item.type_label %></td>
            <td class="px-2 py-2 text-right text-gray-400"><%= item.size_formatted %></td>
            <td class="px-2 py-2 text-gray-400"><%= item.modified_formatted %></td>
            <td class="px-2 py-2 text-center">
              <div class="flex items-center justify-center gap-1">
                <!-- Play button for media files -->
                <%= if is_playable?(item) do %>
                  <button
                    type="button"
                    phx-click="fm_preview_file"
                    phx-value-window_id={@window.id}
                    phx-value-item_id={item.id}
                    phx-value-url={item.url}
                    phx-target={@target}
                    onclick="event.stopPropagation();"
                    class="p-1 hover:bg-blue-600/50 rounded text-blue-400"
                    title="Play"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd"/>
                    </svg>
                  </button>
                <% end %>
                <!-- Download button -->
                <%= if item.type != "folder" && item.url do %>
                  <a
                    href={item.url}
                    download={item.name}
                    class="p-1 hover:bg-gray-700 rounded"
                    title="Download"
                    onclick="event.stopPropagation();"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/>
                    </svg>
                  </a>
                <% end %>
                <!-- Sharing (drive files in My Files only) -->
                <%= if item.type == "file" && Map.get(item, :visibility) do %>
                  <form phx-change="fm_set_visibility" phx-target={@target} onclick="event.stopPropagation();" class="inline">
                    <input type="hidden" name="window_id" value={@window.id} />
                    <input type="hidden" name="item_id" value={item.id} />
                    <select name="visibility" class="bg-gray-800 border border-gray-700 text-xs rounded px-1 py-0.5" title="Who can open this file">
                      <option value="private" selected={item.visibility == "private"}>Only me</option>
                      <option value="link" selected={item.visibility == "link"}>Anyone with link</option>
                      <option value="public" selected={item.visibility == "public"}>Public</option>
                    </select>
                  </form>
                  <%= if Map.get(item, :share_url) do %>
                    <input
                      readonly
                      value={item.share_url}
                      onclick="event.stopPropagation(); this.select(); if (navigator.clipboard) navigator.clipboard.writeText(this.value);"
                      class="w-28 bg-gray-900 border border-gray-700 text-xs rounded px-1 py-0.5"
                      title="Click to copy the link"
                    />
                  <% end %>
                <% end %>
                <!-- Delete button -->
                <button
                  type="button"
                  phx-click="fm_delete_item"
                  phx-value-window_id={@window.id}
                  phx-value-path={item.path}
                  phx-value-item_id={item.id}
                  phx-target={@target}
                  onclick="event.stopPropagation(); return confirm('Delete this item?');"
                  class="p-1 hover:bg-red-600/50 rounded text-red-400"
                  title="Delete"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                  </svg>
                </button>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  # Helper functions for media detection
  defp is_image?(item) do
    ext = Map.get(item, :extension, "") |> to_string()
    ext in ~w(.jpg .jpeg .png .gif .webp .svg .bmp .ico)
  end

  defp is_playable?(item) do
    ext = Map.get(item, :extension, "") |> to_string()
    ext in ~w(.mp3 .wav .ogg .flac .aac .m4a .mp4 .webm .mov .avi .mkv .m4v .ogv)
  end

  defp is_audio?(item) do
    ext = Map.get(item, :extension, "") |> to_string()
    ext in ~w(.mp3 .wav .ogg .flac .aac .m4a .wma)
  end

  defp is_video?(item) do
    ext = Map.get(item, :extension, "") |> to_string()
    ext in ~w(.mp4 .webm .mov .avi .mkv .m4v .ogv .wmv)
  end

  defp get_play_icon(item) do
    cond do
      is_audio?(item) -> "🎵"
      is_video?(item) -> "▶️"
      true -> "▶️"
    end
  end

  defp format_storage(used, quota) when is_nil(used) or is_nil(quota), do: "N/A"
  defp format_storage(used, :unlimited) do
    gb = (used || 0) / 1_073_741_824
    if gb >= 1, do: "#{Float.round(gb, 1)} GB used (no limit)", else: "#{Float.round((used || 0) / 1_048_576, 1)} MB used (no limit)"
  end
  defp format_storage(used, quota) do
    used_mb = used / (1024 * 1024)
    quota_mb = quota / (1024 * 1024)
    
    cond do
      quota_mb >= 1024 ->
        "#{Float.round(used_mb / 1024, 1)} / #{Float.round(quota_mb / 1024, 1)} GB"
      true ->
        "#{Float.round(used_mb, 1)} / #{Float.round(quota_mb, 1)} MB"
    end
  end
end
