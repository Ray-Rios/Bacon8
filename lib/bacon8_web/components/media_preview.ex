defmodule Bacon8Web.Components.MediaPreview do
  use Phoenix.Component

  @doc """
  Renders a media preview based on file type.
  Supports images, video, audio, and generic file downloads.
  """
  attr :attachment, :map, required: true
  attr :class, :string, default: ""
  attr :show_filename, :boolean, default: true

  def media_preview(assigns) do
    # Normalize a few common keys for compatibility with message attachments and media records
    attachment = assigns.attachment
    
    # Handle both maps and structs
    get_field = fn att, field, fallback ->
      cond do
        is_map(att) && Map.has_key?(att, field) -> Map.get(att, field)
        is_struct(att) && Map.has_key?(att, field) -> Map.get(att, field)
        true -> fallback
      end
    end
    
    normalized = %{
      file_name: get_field.(attachment, :file_name, nil) || 
                 get_field.(attachment, :filename, nil) || 
                 (get_field.(attachment, :file, nil) |> to_string() |> Path.basename()),
      file_size: get_field.(attachment, :file_size, nil) || get_field.(attachment, :size, 0),
      file_type: get_field.(attachment, :file_type, nil) || 
                 get_field.(attachment, :content_type, nil) || 
                 get_field.(attachment, :mime_type, nil),
      url_path: get_field.(attachment, :url_path, nil) || 
                get_field.(attachment, :url, nil) || 
                get_field.(attachment, :file, nil) || 
                get_field.(attachment, :path, nil)
    }

    assigns = assigns |> assign(:attachment, normalized) |> assign(:file_type, detect_file_type(normalized))

    ~H"""
    <div class={["media-preview", @class]}>
      <%= case @file_type do %>
        <% :image -> %>
          <.image_preview attachment={@attachment} show_filename={@show_filename} />
        <% :video -> %>
          <.video_preview attachment={@attachment} show_filename={@show_filename} />
        <% :audio -> %>
          <.audio_preview attachment={@attachment} show_filename={@show_filename} />
        <% :pdf -> %>
          <.pdf_preview attachment={@attachment} show_filename={@show_filename} />
        <% _ -> %>
          <.file_preview attachment={@attachment} />
      <% end %>
    </div>
    """
  end

  # Image preview with lightbox support - click to expand
  defp image_preview(assigns) do
    ~H"""
    <div class="image-preview relative group">
      <img 
        src={@attachment.url_path} 
        alt={@attachment.file_name}
        class="max-w-sm max-h-64 rounded-lg object-cover cursor-pointer hover:opacity-90 transition-all !border-0 !bg-transparent shadow-none"
        loading="lazy"
        phx-click="open_image_viewer"
        phx-value-url={@attachment.url_path}
        phx-value-filename={@attachment.file_name}
      />
      <%!-- Quick action buttons on hover --%>
      <div class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
        <a 
          href={@attachment.url_path} 
          download
          class="p-1.5 bg-black/60 hover:bg-black/80 rounded text-white"
          title="Download"
          phx-click="stop_propagation"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>
          </svg>
        </a>
        <%!-- Removed redundant fullscreen button - clicking image already opens fullscreen --%>
      </div>
      <%= if @show_filename do %>
        <p class="text-xs text-gray-500 dark:text-gray-400 mt-1 truncate max-w-sm opacity-0 group-hover:opacity-100 transition-opacity">
          <%= @attachment.file_name %> · <%= format_file_size(@attachment.file_size) %>
        </p>
      <% end %>
    </div>
    """
  end

  # Video preview with HTML5 player - lazy load (preload=none delays download until play)
  defp video_preview(assigns) do
    ~H"""
    <div class="video-preview group">
      <video 
        controls 
        preload="none"
        class="max-w-lg max-h-96 rounded-lg transition-all"
      >
        <source src={@attachment.url_path} type={@attachment.file_type || "video/mp4"} />
        Your browser does not support the video tag.
      </video>
      <%= if @show_filename do %>
        <p class="text-xs text-gray-500 dark:text-gray-400 mt-1 truncate max-w-lg opacity-0 group-hover:opacity-100 transition-opacity">
          <%= @attachment.file_name %> · <%= format_file_size(@attachment.file_size) %>
        </p>
      <% end %>
    </div>
    """
  end

  # Audio preview with HTML5 player and download button
  defp audio_preview(assigns) do
    ~H"""
    <div class="audio-preview w-full min-w-[320px] max-w-xl group">
      <div class="dark-glass rounded-lg p-4 transition-all">
        <div class="flex items-center gap-3 mb-3">
          <svg class="w-6 h-6 text-blue-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"></path>
          </svg>
          <span class="text-sm font-medium text-gray-200 truncate flex-1">
            <%= @attachment.file_name %>
          </span>
          <a 
            href={@attachment.url_path} 
            download
            class="flex-shrink-0 p-2 text-blue-500 hover:text-blue-400 hover:bg-gray-700 rounded transition-colors"
            title="Download audio"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>
            </svg>
          </a>
        </div>
        <audio controls class="w-full h-10" style="min-width: 280px;">
          <source src={@attachment.url_path} type={@attachment.file_type || "audio/mpeg"} />
          Your browser does not support the audio element.
        </audio>
        <%= if @show_filename do %>
          <p class="text-xs text-gray-400 mt-2">
            <%= format_file_size(@attachment.file_size) %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  # PDF preview with embed/download option
  defp pdf_preview(assigns) do
    ~H"""
    <div class="pdf-preview max-w-md group">
      <div class="bg-gray-100 dark:bg-gray-700 rounded-lg p-4 transition-all">
        <div class="flex items-center justify-between">
          <div class="flex items-center flex-1 min-w-0 mr-4">
            <svg class="w-8 h-8 text-red-500 flex-shrink-0 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
            </svg>
            <div class="flex-1 min-w-0 opacity-0 group-hover:opacity-100 transition-opacity">
              <p class="text-sm font-medium text-gray-800 dark:text-gray-200 truncate">
                <%= @attachment.file_name %>
              </p>
              <%= if @show_filename do %>
                <p class="text-xs text-gray-500 dark:text-gray-400">
                  <%= format_file_size(@attachment.file_size) %>
                </p>
              <% end %>
            </div>
          </div>
          <a 
            href={@attachment.url_path} 
            target="_blank"
            download
            class="bg-blue-500 hover:bg-blue-600 text-white px-3 py-1 rounded text-sm flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
          >
            Download
          </a>
        </div>
      </div>
    </div>
    """
  end

  # Generic file preview with download button
  defp file_preview(assigns) do
    ~H"""
    <div class="file-preview max-w-md group">
      <div class="bg-gray-100 dark:bg-gray-700 rounded-lg p-4 transition-all">
        <div class="flex items-center justify-between">
          <div class="flex items-center flex-1 min-w-0 mr-4">
            <svg class="w-8 h-8 text-gray-500 flex-shrink-0 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
            </svg>
            <div class="flex-1 min-w-0 opacity-0 group-hover:opacity-100 transition-opacity">
              <p class="text-sm font-medium text-gray-800 dark:text-gray-200 truncate">
                <%= @attachment.file_name %>
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                <%= format_file_size(@attachment.file_size) %>
              </p>
            </div>
          </div>
          <a 
            href={@attachment.url_path} 
            download
            class="bg-blue-500 hover:bg-blue-600 text-white px-3 py-1 rounded text-sm flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
          >
            Download
          </a>
        </div>
      </div>
    </div>
    """
  end

  # Helper: Detect file type from MIME type or extension
  defp detect_file_type(attachment) do
    file_type = attachment.file_type || ""
    file_name = attachment.file_name || ""
    
    cond do
      String.starts_with?(file_type, "image/") -> :image
      String.starts_with?(file_type, "video/") -> :video
      String.starts_with?(file_type, "audio/") -> :audio
      String.contains?(file_type, "pdf") -> :pdf
      String.ends_with?(file_name, [".jpg", ".jpeg", ".png", ".gif", ".webp"]) -> :image
      String.ends_with?(file_name, [".mp4", ".webm", ".mov", ".avi"]) -> :video
      String.ends_with?(file_name, [".mp3", ".wav", ".ogg", ".m4a", ".flac"]) -> :audio
      String.ends_with?(file_name, ".pdf") -> :pdf
      true -> :file
    end
  end

  # Helper: Format file size for display
  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_file_size(_), do: "Unknown size"
end
