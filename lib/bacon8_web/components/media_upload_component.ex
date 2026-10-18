defmodule Bacon8Web.MediaUploadComponent do
  @moduledoc "Reusable media upload component with drag-drop support"
  use Bacon8Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="media-upload-component">
      <div class="mb-4">
        <label class="block text-sm font-medium text-gray-300 mb-2">
          <%= @label %>
        </label>
        
        <div 
          class="border-2 border-dashed border-gray-600 rounded-lg p-6 text-center hover:border-blue-500 transition-colors"
          phx-drop-target={@uploads.media_file.ref}
        >
          <.live_file_input upload={@uploads.media_file} class="hidden" id={"media-upload-#{@id}"} />
          
          <div class="space-y-2">
            <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
              <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
            
            <div class="text-sm text-gray-400">
              <label for={"media-upload-#{@id}"} class="cursor-pointer text-blue-500 hover:text-blue-400">
                Click to upload
              </label>
              or drag and drop
            </div>
            
            <p class="text-xs text-gray-500">
              <%= @accept_text %>
            </p>
          </div>
        </div>
      </div>

      <!-- Upload Progress -->
      <%= for entry <- @uploads.media_file.entries do %>
        <div class="mt-2 bg-gray-700 rounded-lg p-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm text-white"><%= entry.client_name %></span>
            <span class="text-xs text-gray-400"><%= format_bytes(entry.client_size) %></span>
          </div>
          
          <div class="w-full bg-gray-600 rounded-full h-2">
            <div class="bg-blue-500 h-2 rounded-full transition-all" style={"width: #{entry.progress}%"}></div>
          </div>

          <!-- Preview for images -->
          <%= if String.starts_with?(entry.client_type, "image/") do %>
            <div class="mt-2">
              <.live_img_preview entry={entry} class="max-w-xs rounded" />
            </div>
          <% end %>

          <!-- Error messages -->
          <%= for err <- upload_errors(@uploads.media_file, entry) do %>
            <p class="mt-2 text-sm text-red-400"><%= error_to_string(err) %></p>
          <% end %>
        </div>
      <% end %>

      <!-- Uploaded files list -->
      <%= if @uploaded_files && length(@uploaded_files) > 0 do %>
        <div class="mt-4">
          <h4 class="text-sm font-medium text-gray-300 mb-2">Recently Uploaded</h4>
          <div class="grid grid-cols-3 gap-2">
            <%= for file <- @uploaded_files do %>
              <div class="relative group">
                <img src={file.url} class="w-full h-24 object-cover rounded" />
                <div class="absolute inset-0 bg-black bg-opacity-50 opacity-0 group-hover:opacity-100 transition-opacity rounded flex items-center justify-center">
                  <button 
                    phx-click="copy_url" 
                    phx-value-url={file.url}
                    phx-target={@myself}
                    class="text-white text-xs px-2 py-1 bg-blue-600 rounded hover:bg-blue-700"
                  >
                    Copy URL
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uploaded_files, assigns[:uploaded_files] || [])
     |> allow_upload(:media_file,
       accept: assigns[:accept] || ~w(.jpg .jpeg .png .gif .webp .pdf .mp4 .mp3),
       max_entries: assigns[:max_entries] || 5,
       max_file_size: assigns[:max_file_size] || 10_000_000,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("copy_url", %{"url" => url}, socket) do
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: url})}
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp error_to_string(:too_large), do: "File is too large"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(err), do: "Error: #{inspect(err)}"
end
