defmodule Bacon8Web.MediaPickerComponent do
  @moduledoc "Modal component for selecting media from user's library"
  use Bacon8Web, :live_component
  
  alias Bacon8.Content.Media

  @impl true
  def update(assigns, socket) do
    user_id = assigns.current_user.id
    media_list = Media.list_media_for_user(user_id)
    
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       media_list: media_list,
       filter: assigns[:filter] || "all",
       search_query: ""
     )}
  end

  @impl true
  def handle_event("filter", %{"type" => type}, socket) do
    {:noreply, assign(socket, filter: type)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  @impl true
  def handle_event("select_media", %{"url" => url, "filename" => filename}, socket) do
    # Send selection back to parent LiveView
    send(self(), {:media_selected, url, filename})
    {:noreply, socket}
  end

  @impl true
  def handle_event("close_picker", _params, socket) do
    send(self(), :close_media_picker)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 overflow-y-auto pointer-events-auto" phx-click="close_picker" phx-target={@myself}>
      <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
        <!-- Background overlay -->
        <div class="fixed inset-0 transition-opacity bg-gray-900 bg-opacity-75"></div>

        <!-- Modal panel -->
        <div 
          class="inline-block w-full max-w-5xl overflow-hidden text-left align-middle transition-all transform glass-dark shadow-xl rounded-2xl"
          phx-click-away="close_picker"
          phx-target={@myself}
          onclick="event.stopPropagation()"
        >
          <!-- Header -->
          <div class="flex items-center justify-between px-6 py-4 border-b border-gray-700">
            <h3 class="text-2xl font-bold text-white">Select Media</h3>
            <button 
              phx-click="close_picker" 
              phx-target={@myself}
              class="text-gray-400 hover:text-white transition-colors"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Filter Tabs -->
          <div class="flex space-x-2 px-6 pt-4">
            <%= for {label, type} <- [{"All", "all"}, {"Images", "image"}, {"Videos", "video"}, {"Audio", "audio"}] do %>
              <button 
                phx-click="filter" 
                phx-value-type={type}
                phx-target={@myself}
                class={"px-4 py-2 rounded-lg transition-colors text-sm " <> if @filter == type, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600"}
              >
                <%= label %>
              </button>
            <% end %>
          </div>

          <!-- Media Grid -->
          <div class="p-6 max-h-96 overflow-y-auto">
            <%= if length(filtered_media(@media_list, @filter)) > 0 do %>
              <div class="grid grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
                <%= for media <- filtered_media(@media_list, @filter) do %>
                  <button
                    phx-click="select_media"
                    phx-value-url={media.url}
                    phx-value-filename={media.original_filename}
                    phx-target={@myself}
                    class="bg-gray-700 rounded-lg overflow-hidden hover:ring-2 hover:ring-blue-500 transition-all group"
                  >
                    <!-- Preview -->
                    <div class="aspect-square bg-gray-600 flex items-center justify-center overflow-hidden">
                      <%= if media.file_type == "image" do %>
                        <img src={media.url} alt={media.alt_text || media.filename} class="w-full h-full object-cover" />
                      <% else %>
                        <div class="text-3xl">
                          <%= file_type_icon(media.file_type) %>
                        </div>
                      <% end %>
                    </div>

                    <!-- Filename -->
                    <div class="p-2">
                      <p class="text-white text-xs truncate"><%= media.original_filename %></p>
                    </div>
                  </button>
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-12">
                <p class="text-gray-400">No media files found</p>
                <p class="text-gray-500 text-sm mt-1">Upload files in the Media Library</p>
              </div>
            <% end %>
          </div>

          <!-- Footer -->
          <div class="flex justify-end px-6 py-4 border-t border-gray-700 space-x-2">
            <button 
              phx-click="close_picker" 
              phx-target={@myself}
              class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg transition-colors"
            >
              Cancel
            </button>
            <%!-- TODO: Create admin uploads route
            <.link 
              navigate={~p"/admin/files"} 
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
            >
              Open Media Library
            </.link>
            --%>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp filtered_media(media_list, "all"), do: media_list
  defp filtered_media(media_list, filter), do: Enum.filter(media_list, &(&1.file_type == filter))

  defp file_type_icon("image"), do: "🖼️"
  defp file_type_icon("video"), do: "🎥"
  defp file_type_icon("audio"), do: "🎵"
  defp file_type_icon("3d"), do: "🎲"
  defp file_type_icon("document"), do: "📄"
  defp file_type_icon(_), do: "📁"
end
