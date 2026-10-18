defmodule Bacon8Web.Components.BlockEditor do
  @moduledoc """
  Block-based WYSIWYG editor component for LiveView.
  
  Provides a comprehensive content editing experience with:
  - Row/Column layouts for flexible content grids
  - Multiple content block types (text, image, video, code, etc.)
  - Drag-and-drop block reordering
  - Rich text editing with Quill.js
  - Real-time auto-save
  
  ## Usage
  
      <.block_editor
        id="blog-content"
        value={@content}
        placeholder="Start writing..."
        on_change="content-changed"
        autosave_delay={5000}
      />
  """
  use Phoenix.Component

  @doc """
  Renders a block-based WYSIWYG editor.
  
  ## Attributes
  
  * `:id` (required) - Unique identifier for the editor instance
  * `:value` - Initial content (JSON block format or HTML string)
  * `:content` - Alias for value (for convenience)
  * `:field` - Phoenix.HTML.Form field (alternative to value)
  * `:placeholder` - Placeholder text
  * `:autosave_delay` - Delay in milliseconds before autosave (default: 5000)
  * `:readonly` - Whether editor is read-only (default: false)
  * `:min_height` - Minimum height of the editor (default: "400px")
  * `:class` - Additional CSS classes
  """
  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :content, :string, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :placeholder, :string, default: "Click to add content..."
  attr :autosave_delay, :integer, default: 5000
  attr :readonly, :boolean, default: false
  attr :min_height, :string, default: "400px"
  attr :class, :string, default: ""

  def block_editor(assigns) do
    # Support both :value and :content attribute names
    assigns = 
      if assigns.content do
        assign(assigns, :value, assigns.content)
      else
        assigns
      end
    
    # If field is provided, use it; otherwise use value
    assigns = 
      if assigns.field do
        assign(assigns, :value, Phoenix.HTML.Form.input_value(assigns.field.form, assigns.field.field))
      else
        assigns
      end

    ~H"""
    <div class={"block-editor-wrapper #{@class}"}>
      <!-- Hidden input to store content for form submission -->
      <%= if @field do %>
        <input 
          type="hidden" 
          id={"#{@id}-input"}
          name={Phoenix.HTML.Form.input_name(@field.form, @field.field)}
          value={@value}
        />
      <% else %>
        <input 
          type="hidden" 
          id={"#{@id}-input"}
          name="content"
          value={@value}
        />
      <% end %>
      
      <!-- Block editor container -->
      <div 
        id={@id}
        phx-hook="BlockEditor"
        phx-update="ignore"
        data-placeholder={@placeholder}
        data-autosave-delay={@autosave_delay}
        data-readonly={to_string(@readonly)}
        data-initial-content={@value}
        style={"min-height: #{@min_height};"}
        class="block-editor-container"
      >
        <!-- BlockEditor hook will render content here -->
        <div class="block-editor-loading">
          <div class="flex items-center justify-center py-12 text-gray-500">
            <svg class="animate-spin -ml-1 mr-3 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Loading editor...
          </div>
        </div>
      </div>
      
      <!-- Save status indicators -->
      <div class="flex items-center justify-between mt-2 text-sm">
        <div id={"#{@id}-loading"} class="hidden text-yellow-500">
          <span class="inline-flex items-center">
            <svg class="animate-spin -ml-1 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Saving...
          </span>
        </div>
        
        <div id={"#{@id}-saved"} class="hidden text-green-500">
          ✓ Saved
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders content from block editor format to HTML for display.
  
  This function parses the JSON block format and converts it to
  displayable HTML. Handles backward compatibility with plain HTML content.
  """
  def render_blocks(nil), do: ""
  def render_blocks(""), do: ""
  
  def render_blocks(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"rows" => rows}} ->
        render_rows(rows)
      {:ok, _} ->
        # JSON but not block format, return as-is
        Phoenix.HTML.raw(content)
      {:error, _} ->
        # Not JSON, assume HTML content
        Phoenix.HTML.raw(content)
    end
  end

  defp render_rows(rows) when is_list(rows) do
    html = Enum.map_join(rows, "", &render_row/1)
    Phoenix.HTML.raw(html)
  end

  defp render_row(%{"columns" => columns} = _row) when is_list(columns) do
    column_count = length(columns)
    
    if column_count > 1 do
      inner = Enum.map_join(columns, "", &render_column/1)
      ~s(<div class="content-row columns-#{column_count}">#{inner}</div>)
    else
      Enum.map_join(columns, "", &render_column/1)
    end
  end
  defp render_row(_), do: ""

  defp render_column(%{"blocks" => blocks, "width" => width}) when is_list(blocks) and is_binary(width) do
    inner = Enum.map_join(blocks, "", &render_block/1)
    # Handle percentage widths (e.g., "33.33%") and legacy fraction widths (e.g., "1/2")
    # Use flex-basis with flex-shrink to allow columns to shrink for gaps
    style = cond do
      String.ends_with?(width, "%") ->
        width_val = String.replace(width, "%", "")
        ~s| style="flex: 1 1 #{width_val}%;"|
      width == "full" ->
        ""
      String.contains?(width, "/") ->
        # Legacy fraction format - convert to percentage
        [num, denom] = String.split(width, "/") |> Enum.map(&String.to_integer/1)
        percent = Float.round(num / denom * 100, 2)
        ~s| style="flex: 1 1 #{percent}%;"|
      true ->
        ""
    end
    ~s(<div class="content-column"#{style}>#{inner}</div>)
  end
  defp render_column(%{"blocks" => blocks}) when is_list(blocks) do
    inner = Enum.map_join(blocks, "", &render_block/1)
    ~s(<div class="content-column">#{inner}</div>)
  end
  defp render_column(_), do: ""

  defp render_block(%{"type" => "text", "content" => content}) do
    content || ""
  end
  
  defp render_block(%{"type" => "heading", "content" => content, "settings" => settings}) do
    level = settings["level"] || 2
    ~s(<h#{level}>#{escape_html(content || "")}</h#{level}>)
  end
  defp render_block(%{"type" => "heading", "content" => content}) do
    ~s(<h2>#{escape_html(content || "")}</h2>)
  end
  
  defp render_block(%{"type" => "image", "content" => url, "settings" => settings}) do
    alt = settings["alt"] || ""
    caption = settings["caption"] || ""
    ~s(<figure><img src="#{escape_html(url || "")}" alt="#{escape_html(alt)}" loading="lazy"><figcaption>#{escape_html(caption)}</figcaption></figure>)
  end
  defp render_block(%{"type" => "image", "content" => url}) do
    ~s(<figure><img src="#{escape_html(url || "")}" alt="" loading="lazy"></figure>)
  end
  
  defp render_block(%{"type" => "video", "content" => url}) do
    render_video_embed(url)
  end
  
  defp render_block(%{"type" => "gallery", "media" => media, "settings" => settings}) when is_list(media) do
    display_mode = settings["displayMode"] || "carousel"
    
    if length(media) > 0 do
      items = Enum.with_index(media) |> Enum.map_join("", fn {item, idx} ->
        url = item["url"] || ""
        alt = item["alt"] || ""
        caption = item["caption"] || ""
        
        active_class = if idx == 0 and display_mode == "carousel", do: " active", else: ""
        caption_html = if caption != "", do: ~s(<figcaption>#{escape_html(caption)}</figcaption>), else: ""
        ~s(<figure class="gallery-item#{active_class}" data-index="#{idx}"><img src="#{escape_html(url)}" alt="#{escape_html(alt)}" loading="lazy">#{caption_html}</figure>)
      end)
      
      nav_html = if display_mode == "carousel" and length(media) > 1 do
        dots = Enum.with_index(media) |> Enum.map_join("", fn {_, idx} ->
          active = if idx == 0, do: " active", else: ""
          ~s(<button class="gallery-dot#{active}" data-index="#{idx}"></button>)
        end)
        ~s(<button class="gallery-nav gallery-prev"><svg width="24" height="24" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg></button><button class="gallery-nav gallery-next"><svg width="24" height="24" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg></button><div class="gallery-dots">#{dots}</div>)
      else
        ""
      end
      
      ~s(<div class="gallery gallery-#{escape_html(display_mode)}"><div class="gallery-items">#{items}</div>#{nav_html}</div>)
    else
      ""
    end
  end
  defp render_block(%{"type" => "gallery"}), do: ""
  
  defp render_block(%{"type" => "audio", "content" => url, "settings" => settings}) do
    filename = settings["filename"] || "Audio file"
    if url && url != "" do
      ~s(<div class="audio-block-display"><audio controls src="#{escape_html(url)}" preload="metadata"></audio><span class="audio-filename">#{escape_html(filename)}</span></div>)
    else
      ""
    end
  end
  defp render_block(%{"type" => "audio", "content" => url}) when is_binary(url) and url != "" do
    ~s(<div class="audio-block-display"><audio controls src="#{escape_html(url)}" preload="metadata"></audio></div>)
  end
  defp render_block(%{"type" => "audio"}), do: ""
  
  defp render_block(%{"type" => "file", "content" => url, "settings" => settings}) do
    filename = settings["filename"] || "Download file"
    file_size = settings["fileSize"] || ""
    file_type = settings["fileType"] || "document"
    _mime_type = settings["mimeType"] || ""
    
    if url && url != "" do
      size_html = if file_size != "", do: ~s| <span class="file-size">(#{escape_html(file_size)})</span>|, else: ""
      icon = get_file_icon(file_type, url)
      
      # Simple file display with icon and download link
      # No iframes - they cause cross-origin security issues
      ~s|<div class="file-block-display">
        <div class="file-card">
          <div class="file-icon-large">#{icon}</div>
          <div class="file-details">
            <a href="#{escape_html(url)}" target="_blank" class="file-name-link">#{escape_html(filename)}</a>
            #{size_html}
          </div>
          <a href="#{escape_html(url)}" download="#{escape_html(filename)}" class="file-download-btn" title="Download">
            <svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/>
            </svg>
          </a>
        </div>
      </div>|
    else
      ""
    end
  end
  defp render_block(%{"type" => "file", "content" => url}) when is_binary(url) and url != "" do
    # Extract filename from URL
    filename = url |> String.split("/") |> List.last() |> URI.decode()
    icon = get_file_icon("document", url)
    
    ~s|<div class="file-block-display">
      <div class="file-card">
        <div class="file-icon-large">#{icon}</div>
        <div class="file-details">
          <a href="#{escape_html(url)}" target="_blank" class="file-name-link">#{escape_html(filename)}</a>
        </div>
        <a href="#{escape_html(url)}" download="#{escape_html(filename)}" class="file-download-btn" title="Download">
          <svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/>
          </svg>
        </a>
      </div>
    </div>|
  end
  defp render_block(%{"type" => "file"}), do: ""
  
  defp render_block(%{"type" => "code", "content" => content, "settings" => settings}) do
    language = settings["language"] || ""
    language_label = if language != "", do: language, else: "code"
    ~s|<div class="code-block-display" data-language="#{escape_html(language)}">
      <div class="code-block-header">
        <span class="code-language-label">#{escape_html(language_label)}</span>
        <button type="button" class="code-copy-btn" onclick="navigator.clipboard.writeText(this.closest('.code-block-display').querySelector('code').textContent).then(() => { this.textContent = 'Copied!'; setTimeout(() => this.textContent = 'Copy', 2000); })" title="Copy code">Copy</button>
      </div>
      <pre class="code-pre"><code class="language-#{escape_html(language)}">#{escape_html(content || "")}</code></pre>
    </div>|
  end
  defp render_block(%{"type" => "code", "content" => content}) do
    ~s|<div class="code-block-display">
      <div class="code-block-header">
        <span class="code-language-label">code</span>
        <button type="button" class="code-copy-btn" onclick="navigator.clipboard.writeText(this.closest('.code-block-display').querySelector('code').textContent).then(() => { this.textContent = 'Copied!'; setTimeout(() => this.textContent = 'Copy', 2000); })" title="Copy code">Copy</button>
      </div>
      <pre class="code-pre"><code>#{escape_html(content || "")}</code></pre>
    </div>|
  end
  
  defp render_block(%{"type" => "quote", "content" => content, "settings" => settings}) do
    author = settings["author"] || ""
    ~s(<blockquote>#{escape_html(content || "")}<cite>#{escape_html(author)}</cite></blockquote>)
  end
  defp render_block(%{"type" => "quote", "content" => content}) do
    ~s(<blockquote>#{escape_html(content || "")}</blockquote>)
  end
  
  defp render_block(%{"type" => "callout", "content" => content, "settings" => settings}) do
    callout_type = settings["calloutType"] || "info"
    ~s(<div class="callout callout-#{escape_html(callout_type)}">#{escape_html(content || "")}</div>)
  end
  defp render_block(%{"type" => "callout", "content" => content}) do
    ~s(<div class="callout callout-info">#{escape_html(content || "")}</div>)
  end
  
  defp render_block(%{"type" => "divider"}) do
    ~s(<hr class="content-divider">)
  end
  
  defp render_block(%{"type" => "embed", "content" => content}) do
    content || ""
  end
  
  # HTML embed block - renders raw HTML content
  defp render_block(%{"type" => "html", "content" => content}) when is_binary(content) and content != "" do
    # Note: This renders raw HTML - content should be trusted/sanitized before storage
    ~s(<div class="html-embed-display">#{content}</div>)
  end
  defp render_block(%{"type" => "html"}), do: ""
  
  # API data block - renders the last fetched result or a placeholder
  defp render_block(%{"type" => "api", "settings" => settings}) do
    last_result = settings["lastResult"] || ""
    last_fetched = settings["lastFetched"] || ""
    
    if last_result != "" do
      time_html = if last_fetched != "", do: ~s(<div class="api-fetch-time">Last updated: #{escape_html(last_fetched)}</div>), else: ""
      ~s(<div class="api-data-display">#{last_result}#{time_html}</div>)
    else
      ~s(<div class="api-data-display api-placeholder"><p class="text-gray-500">API data not loaded</p></div>)
    end
  end
  defp render_block(%{"type" => "api", "content" => _url}) do
    ~s(<div class="api-data-display api-placeholder"><p class="text-gray-500">API data not loaded</p></div>)
  end
  defp render_block(%{"type" => "api"}), do: ""
  
  defp render_block(_), do: ""

  defp render_video_embed(nil), do: ""
  defp render_video_embed(""), do: ""
  defp render_video_embed(url) when is_binary(url) do
    cond do
      # YouTube
      String.contains?(url, "youtube.com") or String.contains?(url, "youtu.be") ->
        case Regex.run(~r/(?:youtube\.com\/(?:watch\?v=|embed\/)|youtu\.be\/)([^&\s]+)/, url) do
          [_, video_id] ->
            ~s(<div class="video-embed"><iframe src="https://www.youtube.com/embed/#{video_id}" frameborder="0" allowfullscreen loading="lazy"></iframe></div>)
          _ ->
            ~s(<a href="#{escape_html(url)}" target="_blank">#{escape_html(url)}</a>)
        end
      
      # Vimeo
      String.contains?(url, "vimeo.com") ->
        case Regex.run(~r/vimeo\.com\/(\d+)/, url) do
          [_, video_id] ->
            ~s(<div class="video-embed"><iframe src="https://player.vimeo.com/video/#{video_id}" frameborder="0" allowfullscreen loading="lazy"></iframe></div>)
          _ ->
            ~s(<a href="#{escape_html(url)}" target="_blank">#{escape_html(url)}</a>)
        end
      
      # Uploaded video files (mp4, webm, ogg, mov)
      String.starts_with?(url, "/uploads") or 
      String.ends_with?(url, ".mp4") or
      String.ends_with?(url, ".webm") or
      String.ends_with?(url, ".ogg") or
      String.ends_with?(url, ".mov") ->
        ~s(<div class="video-player-container"><video controls src="#{escape_html(url)}" preload="metadata" class="block-video"></video></div>)
      
      true ->
        ~s(<a href="#{escape_html(url)}" target="_blank">#{escape_html(url)}</a>)
    end
  end

  defp escape_html(nil), do: ""
  defp escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  # Helper to get file icon based on type
  defp get_file_icon(file_type, url) do
    ext = url |> String.downcase() |> Path.extname()
    
    case {file_type, ext} do
      {_, ".pdf"} -> "📄"
      {_, ".doc"} -> "📝"
      {_, ".docx"} -> "📝"
      {_, ".xls"} -> "📊"
      {_, ".xlsx"} -> "📊"
      {_, ".ppt"} -> "📽️"
      {_, ".pptx"} -> "📽️"
      {_, ".txt"} -> "📝"
      {_, ".zip"} -> "📦"
      {_, ".rar"} -> "📦"
      {_, ".7z"} -> "📦"
      {"document", _} -> "📄"
      {"spreadsheet", _} -> "📊"
      {"presentation", _} -> "📽️"
      {"archive", _} -> "📦"
      _ -> "📎"
    end
  end
end
