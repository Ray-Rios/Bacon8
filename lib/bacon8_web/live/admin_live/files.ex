defmodule Bacon8Web.AdminLive.Files do
  use Bacon8Web, :live_view
  alias Bacon8.Files
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  def mount(_params, _session, socket) do
    # on_mount already verified admin access
    files = Files.list_all_user_files()

    {:ok, assign(socket,
      files: files,
      page_title: "Media Library",
      selected_file: nil
    )}
  end

  def handle_event("select_file", %{"file_id" => file_id}, socket) do
    file = Files.get_user_file_by_id!(file_id)
    {:noreply, assign(socket, selected_file: file)}
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, selected_file: nil)}
  end

  def handle_event("delete_file", %{"file_id" => file_id}, socket) do
    case Files.delete_user_file_by_id(file_id) do
      {:ok, _} ->
        files = Files.list_all_user_files()
        {:noreply,
         socket
         |> assign(files: files, selected_file: nil)
         |> put_flash(:info, "File deleted successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete file")}
    end
  end

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/files">
      <div class="max-w-7xl mx-auto">
            <h1 class="text-3xl font-bold text-white mb-8">Media Library</h1>
            
            <!-- Files Grid -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
              <%= for file <- @files do %>
                <div class="glass-dark rounded-lg overflow-hidden shadow-lg hover:shadow-xl transition-shadow">
                  <!-- File Preview -->
                  <div class="aspect-square bg-gray-900 flex items-center justify-center p-4">
                    <%= if file.content_type && String.starts_with?(file.content_type, "image/") do %>
                      <img 
                        src={"/uploads/user_files/#{file.user_id}/#{file.id}_#{file.filename}_original"}
                        alt={file.original_filename}
                        class="max-w-full max-h-full object-contain cursor-pointer"
                        phx-click="select_file"
                        phx-value-file_id={file.id}
                      />
                    <% else %>
                      <div class="text-6xl text-gray-600">📄</div>
                    <% end %>
                  </div>
                  
                  <!-- File Info -->
                  <div class="p-4">
                    <h3 class="text-white font-medium truncate mb-2" title={file.original_filename}>
                      <%= file.original_filename %>
                    </h3>
                    <div class="text-sm text-gray-400 space-y-1">
                      <p>Size: <%= format_file_size(file.file_size) %></p>
                      <p>Type: <%= file.content_type %></p>
                      <p class="text-xs">Uploaded: <%= Calendar.strftime(file.inserted_at, "%Y-%m-%d") %></p>
                    </div>
                    
                    <!-- Actions -->
                    <div class="mt-4 flex gap-2">
                      <button
                        phx-click="select_file"
                        phx-value-file_id={file.id}
                        class="flex-1 px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm transition-colors"
                      >
                        View
                      </button>
                      <button
                        phx-click="delete_file"
                        phx-value-file_id={file.id}
                        data-confirm="Are you sure you want to delete this file?"
                        class="px-3 py-2 bg-red-600 hover:bg-red-700 text-white rounded text-sm transition-colors"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

            <%= if Enum.empty?(@files) do %>
              <div class="text-center py-12">
                <div class="text-6xl mb-4">📁</div>
                <p class="text-gray-400 text-lg">No files uploaded yet</p>
              </div>
            <% end %>
      </div>

      <!-- File Preview Modal -->
      <%= if @selected_file do %>
        <div class="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50 p-4" phx-click="close_preview">
          <div class="glass-dark rounded-lg max-w-4xl w-full max-h-[90vh] overflow-auto" phx-click-away="close_preview">
            <div class="p-6">
              <div class="flex justify-between items-start mb-4">
                <h2 class="text-2xl font-bold text-white"><%= @selected_file.original_filename %></h2>
                <button phx-click="close_preview" class="text-gray-400 hover:text-white">
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              </div>
              
              <%= if @selected_file.content_type && String.starts_with?(@selected_file.content_type, "image/") do %>
                <img 
                  src={"/uploads/user_files/#{@selected_file.user_id}/#{@selected_file.id}_#{@selected_file.filename}_original"}
                  alt={@selected_file.original_filename}
                  class="w-full rounded-lg mb-4"
                />
              <% end %>
              
              <div class="grid grid-cols-2 gap-4 text-sm text-gray-300">
                <div>
                  <p class="text-gray-500 mb-1">File Size</p>
                  <p><%= format_file_size(@selected_file.file_size) %></p>
                </div>
                <div>
                  <p class="text-gray-500 mb-1">Content Type</p>
                  <p><%= @selected_file.content_type %></p>
                </div>
                <div>
                  <p class="text-gray-500 mb-1">Uploaded</p>
                  <p><%= Calendar.strftime(@selected_file.inserted_at, "%Y-%m-%d %H:%M:%S") %></p>
                </div>
                <div>
                  <p class="text-gray-500 mb-1">Public</p>
                  <p><%= if @selected_file.is_public, do: "Yes", else: "No" %></p>
                </div>
              </div>
              
              <%= if @selected_file.description do %>
                <div class="mt-4">
                  <p class="text-gray-500 mb-1">Description</p>
                  <p class="text-gray-300"><%= @selected_file.description %></p>
                </div>
              <% end %>
              
              <%= if @selected_file.tags && length(@selected_file.tags) > 0 do %>
                <div class="mt-4">
                  <p class="text-gray-500 mb-2">Tags</p>
                  <div class="flex flex-wrap gap-2">
                    <%= for tag <- @selected_file.tags do %>
                      <span class="px-3 py-1 bg-gray-700 text-gray-300 rounded-full text-sm"><%= tag %></span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </AdminSidebar.admin_layout>
    """
  end

  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_file_size(_), do: "Unknown"
end
