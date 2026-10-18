defmodule Bacon8Web.ProfileUploadsLive do
  @moduledoc """
  "My Uploads" - every file in the user's drive (`Bacon8.Drive`), across all
  folders, with filtering, sorting, sharing and bulk delete. Folders are
  managed in the desktop File Explorer (My Files).

  Media attached to blog posts, pages and chat (`Content.UserMedia`) is not
  listed here; it is managed with the content it belongs to (BACON8.md §7).
  """
  use Bacon8Web, :live_view

  alias Bacon8.Drive
  alias Bacon8.Drive.Sniff

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "My Uploads",
       filter: "all",
       sort_by: "date_desc",
       selected_ids: MapSet.new(),
       show_delete_confirm: false
     )
     |> load()}
  end

  # Re-reads files and usage. Locked drives (guest/banned) show a notice instead.
  defp load(socket) do
    user = socket.assigns.current_user
    summary = Drive.summary(user)

    {uploads, locked?} =
      case Drive.list_all_files(user, socket.assigns.filter) do
        {:ok, files} -> {sort_uploads(files, socket.assigns.sort_by), false}
        {:error, _} -> {[], true}
      end

    assign(socket, uploads: uploads, summary: summary, locked?: locked? or summary.locked?)
  end

  @impl true
  def handle_event("filter", %{"type" => filter}, socket) do
    {:noreply, socket |> assign(filter: filter, selected_ids: MapSet.new()) |> load()}
  end

  def handle_event("sort", %{"by" => sort_by}, socket) do
    {:noreply, assign(socket, sort_by: sort_by, uploads: sort_uploads(socket.assigns.uploads, sort_by))}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id), do: MapSet.delete(selected, id), else: MapSet.put(selected, id)

    {:noreply, assign(socket, selected_ids: selected)}
  end

  def handle_event("select_all", _, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new(socket.assigns.uploads, & &1.id))}
  end

  def handle_event("deselect_all", _, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new())}
  end

  def handle_event("show_delete_confirm", _, socket) do
    if MapSet.size(socket.assigns.selected_ids) > 0 do
      {:noreply, assign(socket, show_delete_confirm: true)}
    else
      {:noreply, put_flash(socket, :error, "No files selected")}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, show_delete_confirm: false)}
  end

  def handle_event("stop_propagation", _, socket), do: {:noreply, socket}

  def handle_event("confirm_delete", _, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    socket = assign(socket, show_delete_confirm: false, selected_ids: MapSet.new())

    case Drive.delete_files(socket.assigns.current_user, ids) do
      {:ok, count} ->
        {:noreply, socket |> put_flash(:info, "Deleted #{count} file(s)") |> load()}

      {:error, :locked} ->
        {:noreply, socket |> put_flash(:error, "Your files are locked while your account is restricted.") |> load()}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Those files couldn't be deleted.") |> load()}
    end
  end

  def handle_event("set_visibility", %{"file_id" => id, "visibility" => visibility}, socket) do
    case Drive.set_visibility(socket.assigns.current_user, id, visibility) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, _} -> {:noreply, socket |> put_flash(:error, "Sharing couldn't be changed.") |> load()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-responsive-content class="min-h-screen pointer-events-none" style="padding-top: 30px; padding-bottom: 48px;">
      <div class="max-w-7xl mx-auto px-4 py-8 pointer-events-auto">
        <div class="auth-glass-panel p-8 rounded-xl">
          <!-- Header -->
          <div class="mb-8">
            <h1 class="text-3xl font-bold text-white mb-2">My Uploads</h1>
            <p class="text-gray-400">
              Every file in your drive. Organise folders and upload from <span class="text-gray-300">File Explorer &rarr; My Files</span>.
            </p>
          </div>

          <%= if @locked? do %>
            <div class="mb-6 p-4 rounded-lg bg-red-900/40 border border-red-700 text-red-200">
              Your files are locked while your account is restricted.
              <%= if @summary.purge_after do %>
                They will be permanently deleted on <%= Calendar.strftime(@summary.purge_after, "%b %d, %Y") %>
                unless your account is restored before then.
              <% end %>
            </div>
          <% end %>

          <!-- Storage Info -->
          <div class="mb-6 p-4 bg-gray-700/50 rounded-lg">
            <div class="flex items-center justify-between mb-2">
              <span class="text-sm text-gray-300">Storage Used</span>
              <span class="text-sm font-medium text-white">
                <%= format_storage_size(@summary.bytes_used) %> / <%= format_quota(@summary.quota_bytes) %>
              </span>
            </div>
            <div class="w-full bg-gray-600 rounded-full h-2">
              <div class={"h-2 rounded-full transition-all #{if @summary.over_quota?, do: "bg-red-500", else: "bg-blue-500"}"} style={"width: #{storage_percentage(@summary)}%"}></div>
            </div>
            <%= if @summary.over_quota? do %>
              <p class="text-xs text-red-300 mt-2">
                You're over your storage limit. Your files are safe, but new uploads are paused until you free up space or choose a larger tier.
              </p>
            <% end %>
          </div>

          <!-- Controls -->
          <div class="flex flex-wrap items-center justify-between gap-4 mb-6">
            <!-- Filters -->
            <div class="flex items-center space-x-2">
              <%= for {value, label} <- [{"all", "All"}, {"image", "Images"}, {"video", "Videos"}, {"audio", "Audio"}, {"other", "Other"}] do %>
                <button phx-click="filter" phx-value-type={value} class={"px-4 py-2 rounded transition-colors #{if @filter == value, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600"}"}>
                  <%= label %>
                </button>
              <% end %>
            </div>

            <!-- Sort and Actions -->
            <div class="flex items-center space-x-2">
              <form phx-change="sort">
                <select name="by" class="bg-gray-700 text-white px-4 py-2 rounded border border-gray-600 focus:border-blue-500 focus:outline-none">
                  <option value="date_desc" selected={@sort_by == "date_desc"}>Newest First</option>
                  <option value="date_asc" selected={@sort_by == "date_asc"}>Oldest First</option>
                  <option value="size_desc" selected={@sort_by == "size_desc"}>Largest First</option>
                  <option value="size_asc" selected={@sort_by == "size_asc"}>Smallest First</option>
                  <option value="name_asc" selected={@sort_by == "name_asc"}>Name A-Z</option>
                </select>
              </form>

              <%= if MapSet.size(@selected_ids) > 0 do %>
                <button phx-click="show_delete_confirm" class="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded transition-colors">
                  Delete Selected (<%= MapSet.size(@selected_ids) %>)
                </button>
                <button phx-click="deselect_all" class="bg-gray-600 hover:bg-gray-500 text-white px-4 py-2 rounded transition-colors">
                  Deselect All
                </button>
              <% else %>
                <button phx-click="select_all" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded transition-colors">
                  Select All
                </button>
              <% end %>
            </div>
          </div>

          <!-- Uploads Grid -->
          <%= if @uploads == [] do %>
            <div class="text-center py-12">
              <svg class="mx-auto h-12 w-12 text-gray-500 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path>
              </svg>
              <p class="text-gray-400 text-lg">No files yet</p>
              <p class="text-gray-500 text-sm mt-2">Upload files from File Explorer &rarr; My Files and they will appear here</p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              <%= for upload <- @uploads do %>
                <div class={"relative group bg-gray-700/50 rounded-lg overflow-hidden border-2 transition-all #{if MapSet.member?(@selected_ids, upload.id), do: "border-blue-500", else: "border-transparent hover:border-gray-500"}"}>
                  <!-- Checkbox -->
                  <div class="absolute top-2 left-2 z-10">
                    <input
                      type="checkbox"
                      checked={MapSet.member?(@selected_ids, upload.id)}
                      phx-click="toggle_select"
                      phx-value-id={upload.id}
                      class="w-5 h-5 rounded border-gray-300 text-blue-600 focus:ring-blue-500 cursor-pointer"
                    />
                  </div>

                  <!-- Preview -->
                  <div class="aspect-square bg-gray-800 flex items-center justify-center p-4">
                    <%= case detect_type(upload) do %>
                      <% :image -> %>
                        <img src={"/files/" <> upload.id} alt={upload.name} loading="lazy" class="max-w-full max-h-full object-contain" />
                      <% :video -> %>
                        <svg class="w-16 h-16 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
                        </svg>
                      <% :audio -> %>
                        <svg class="w-16 h-16 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"></path>
                        </svg>
                      <% _ -> %>
                        <svg class="w-16 h-16 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                        </svg>
                    <% end %>
                  </div>

                  <!-- Info -->
                  <div class="p-3">
                    <p class="text-sm text-white font-medium truncate mb-1" title={upload.name}>
                      <%= upload.name %>
                    </p>
                    <div class="flex items-center justify-between text-xs text-gray-400 mb-2">
                      <span><%= format_file_size(upload.size) %></span>
                      <span title={folder_label(upload)}><%= relative_time(upload.inserted_at) %></span>
                    </div>
                    <form phx-change="set_visibility" class="relative z-10">
                      <input type="hidden" name="file_id" value={upload.id} />
                      <select name="visibility" class="w-full bg-gray-800 border border-gray-600 text-xs text-gray-200 rounded px-2 py-1" title="Who can open this file">
                        <option value="private" selected={upload.visibility == "private"}>Only me</option>
                        <option value="link" selected={upload.visibility == "link"}>Anyone with the link</option>
                        <option value="public" selected={upload.visibility == "public"}>Public</option>
                      </select>
                    </form>
                    <%= if share_url(upload) do %>
                      <input
                        readonly
                        value={share_url(upload)}
                        onclick="this.select(); if (navigator.clipboard) navigator.clipboard.writeText(this.value);"
                        class="relative z-10 mt-1 w-full bg-gray-900 border border-gray-700 text-xs text-gray-300 rounded px-2 py-1"
                        title="Click to copy the link"
                      />
                    <% end %>
                  </div>

                  <!-- Actions (on hover, over the preview) -->
                  <div class="absolute inset-x-0 top-0 aspect-square bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center space-x-2">
                    <a href={"/files/" <> upload.id} target="_blank" rel="noopener" class="bg-blue-600 hover:bg-blue-700 text-white p-2 rounded" title="Open">
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"></path>
                      </svg>
                    </a>
                    <a href={"/files/" <> upload.id <> "?download=1"} class="bg-green-600 hover:bg-green-700 text-white p-2 rounded" title="Download">
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>
                      </svg>
                    </a>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <%!-- Delete Confirmation Modal --%>
    <%= if @show_delete_confirm do %>
      <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50" phx-click="cancel_delete">
        <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4" phx-click="stop_propagation">
          <h3 class="text-xl font-bold text-white mb-4">Confirm Deletion</h3>
          <p class="text-gray-300 mb-6">
            Are you sure you want to delete <%= MapSet.size(@selected_ids) %> file(s)? This action cannot be undone.
          </p>
          <div class="flex justify-end space-x-3">
            <button phx-click="cancel_delete" class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors">
              Cancel
            </button>
            <button phx-click="confirm_delete" class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded transition-colors">
              Delete
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------

  defp sort_uploads(uploads, "date_asc"), do: Enum.sort_by(uploads, & &1.inserted_at, DateTime)
  defp sort_uploads(uploads, "date_desc"), do: Enum.sort_by(uploads, & &1.inserted_at, {:desc, DateTime})
  defp sort_uploads(uploads, "size_asc"), do: Enum.sort_by(uploads, & &1.size)
  defp sort_uploads(uploads, "size_desc"), do: Enum.sort_by(uploads, & &1.size, :desc)
  defp sort_uploads(uploads, "name_asc"), do: Enum.sort_by(uploads, &String.downcase(&1.name))
  defp sort_uploads(uploads, _), do: uploads

  defp detect_type(%{content_type: type}) do
    cond do
      # Only previewed inline when the bytes were recognised as an image.
      String.starts_with?(type, "image/") and Sniff.inline?(type) -> :image
      String.starts_with?(type, "video/") -> :video
      String.starts_with?(type, "audio/") -> :audio
      true -> :file
    end
  end

  defp folder_label(%{folder: %{name: name}}), do: "In folder: #{name}"
  defp folder_label(_), do: "In My Files"

  defp share_url(%{visibility: "link", share_token: token}) when is_binary(token),
    do: Bacon8Web.Endpoint.url() <> "/s/" <> token

  defp share_url(%{visibility: "public", id: id}), do: Bacon8Web.Endpoint.url() <> "/files/" <> id
  defp share_url(_), do: nil

  defp storage_percentage(%{quota_bytes: :unlimited}), do: 0
  defp storage_percentage(%{quota_bytes: 0}), do: 100

  defp storage_percentage(%{bytes_used: used, quota_bytes: quota}),
    do: min(round(used / quota * 100), 100)

  defp format_quota(:unlimited), do: "No limit"
  defp format_quota(bytes), do: format_storage_size(bytes)

  defp format_storage_size(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_file_size(_), do: "Unknown"

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
