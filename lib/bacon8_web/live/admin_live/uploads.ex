defmodule Bacon8Web.AdminLive.Uploads do
  use Bacon8Web, :live_view
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  def mount(_params, _session, socket) do
    uploads_info = get_uploads_info()
    
    {:ok,
     assign(socket,
       page_title: "Admin - Uploads",
       uploads_info: uploads_info,
       files: list_uploads(),
       selected_folder: nil
     )}
  end

  defp get_uploads_info do
    uploads_path = Path.join(:code.priv_dir(:bacon8), "static/uploads")
    
    if File.exists?(uploads_path) do
      {size, count} = calculate_dir_size(uploads_path)
      %{
        bytes: size,
        formatted: format_bytes(size),
        file_count: count,
        path: uploads_path
      }
    else
      %{bytes: 0, formatted: "0 KB", file_count: 0, path: uploads_path}
    end
  end

  defp list_uploads do
    uploads_path = Path.join(:code.priv_dir(:bacon8), "static/uploads")
    
    if File.exists?(uploads_path) do
      list_directory(uploads_path, "")
    else
      []
    end
  end

  defp list_directory(base_path, relative_path) do
    full_path = Path.join(base_path, relative_path)
    
    case File.ls(full_path) do
      {:ok, entries} ->
        entries
        |> Enum.map(fn entry ->
          entry_path = Path.join(full_path, entry)
          rel_path = if relative_path == "", do: entry, else: Path.join(relative_path, entry)
          
          case File.stat(entry_path) do
            {:ok, %{type: :directory, mtime: mtime}} ->
              {size, count} = calculate_dir_size(entry_path)
              %{
                name: entry,
                path: rel_path,
                type: :directory,
                size: size,
                formatted_size: format_bytes(size),
                file_count: count,
                modified: mtime
              }
            {:ok, %{type: :regular, size: size, mtime: mtime}} ->
              %{
                name: entry,
                path: rel_path,
                type: :file,
                size: size,
                formatted_size: format_bytes(size),
                extension: Path.extname(entry) |> String.downcase(),
                modified: mtime
              }
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(fn f -> {f.type != :directory, f.name} end)
      _ -> []
    end
  end

  defp calculate_dir_size(path) do
    case File.ls(path) do
      {:ok, entries} ->
        Enum.reduce(entries, {0, 0}, fn item, {total_size, total_count} ->
          full_path = Path.join(path, item)
          case File.stat(full_path) do
            {:ok, %{type: :directory}} ->
              {sub_size, sub_count} = calculate_dir_size(full_path)
              {total_size + sub_size, total_count + sub_count}
            {:ok, %{size: size, type: :regular}} ->
              {total_size + size, total_count + 1}
            _ ->
              {total_size, total_count}
          end
        end)
      _ -> {0, 0}
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"

  def handle_event("delete_file", %{"path" => path}, socket) do
    uploads_path = Path.join(:code.priv_dir(:bacon8), "static/uploads")
    # Security: confine to the uploads directory, and never rm_rf the root itself.
    full_path = Bacon8.SafePath.resolve!(uploads_path, path)

    if full_path && full_path != Path.expand(uploads_path) do
      case File.rm_rf(full_path) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(uploads_info: get_uploads_info(), files: list_uploads())
           |> put_flash(:info, "Deleted successfully")}
        {:error, _, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid path")}
    end
  end

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/uploads">
      <div class="max-w-6xl mx-auto">
          <div class="auth-glass-panel p-8 rounded-xl">
            <!-- Header -->
            <div class="flex justify-between items-center mb-8">
              <div>
                <h1 class="text-3xl font-bold text-white">Uploads Management</h1>
                <p class="text-gray-400 mt-1">Manage uploaded files and media</p>
              </div>
              <div class="text-right">
                <p class="text-2xl font-bold text-blue-400"><%= @uploads_info.formatted %></p>
                <p class="text-gray-500 text-sm"><%= @uploads_info.file_count %> files total</p>
              </div>
            </div>

            <!-- Files List -->
            <div class="bg-gray-800/50 rounded-lg border border-gray-700 overflow-hidden">
              <table class="w-full">
                <thead class="bg-black/30">
                  <tr>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Name</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Type</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Size</th>
                    <th class="text-right text-gray-300 px-4 py-3 text-sm font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= if @files == [] do %>
                    <tr>
                      <td colspan="4" class="px-4 py-8 text-center text-gray-500">
                        No uploaded files yet
                      </td>
                    </tr>
                  <% else %>
                    <%= for file <- @files do %>
                      <tr class="hover:bg-white/5">
                        <td class="px-4 py-3">
                          <div class="flex items-center gap-3">
                            <span class="text-xl">
                              <%= if file.type == :directory do %>
                                📁
                              <% else %>
                                <%= case file.extension do
                                  ".jpg" -> "🖼️"
                                  ".jpeg" -> "🖼️"
                                  ".png" -> "🖼️"
                                  ".gif" -> "🖼️"
                                  ".webp" -> "🖼️"
                                  ".pdf" -> "📄"
                                  ".doc" -> "📝"
                                  ".docx" -> "📝"
                                  ".mp4" -> "🎬"
                                  ".mp3" -> "🎵"
                                  _ -> "📎"
                                end %>
                              <% end %>
                            </span>
                            <span class="text-white font-medium"><%= file.name %></span>
                          </div>
                        </td>
                        <td class="px-4 py-3 text-gray-400 text-sm">
                          <%= if file.type == :directory, do: "Folder", else: String.upcase(String.trim_leading(file.extension || "", ".")) %>
                        </td>
                        <td class="px-4 py-3 text-gray-400 text-sm">
                          <%= file.formatted_size %>
                          <%= if file.type == :directory do %>
                            <span class="text-gray-500">(<%= file.file_count %> files)</span>
                          <% end %>
                        </td>
                        <td class="px-4 py-3 text-right">
                          <%= if file.type == :file do %>
                            <a href={"/uploads/#{file.path}"} target="_blank" class="text-blue-400 hover:text-blue-300 text-sm mr-3">
                              View
                            </a>
                          <% end %>
                          <button
                            phx-click="delete_file"
                            phx-value-path={file.path}
                            data-confirm={"Are you sure you want to delete #{file.name}?"}
                            class="text-red-400 hover:text-red-300 text-sm"
                          >
                            Delete
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
