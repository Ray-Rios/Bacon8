defmodule Bacon8Web.PageLive do
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8Web.Components.BlockEditor
  alias Bacon8Web.Components.SocialShare

  # Note: on_mount :default is handled by router's live_session

  @allowed_roles ["admin", "gm", "editor"]

  def mount(%{"slug" => slug}, _session, socket) do
    page = Content.get_page_by_slug(slug)
    
    case page do
      nil ->
        {:ok, socket
         |> put_flash(:error, "Page not found")
         |> push_navigate(to: "/")}
      
      page ->
        # Drafts are for staff (admins, GMs and editors: whoever may edit the page)
        if page.is_published or can_edit?(socket.assigns) do
          {:ok, assign(socket,
            page: page,
            page_title: page.title,
            editing: false,
            saving: false,
            last_saved: nil,
            pending_content: nil
          )}
        else
          {:ok, socket
           |> put_flash(:error, "Page not found")
           |> push_navigate(to: "/")}
        end
    end
  end

  # Check if user can edit content
  defp can_edit?(%{current_user: nil}), do: false
  defp can_edit?(%{current_user: user}) do
    user.role in @allowed_roles or Map.get(user, :is_admin, false)
  end
  defp can_edit?(_), do: false

  # Toggle edit mode
  def handle_event("toggle_edit", _params, socket) do
    if can_edit?(socket.assigns) do
      {:noreply, assign(socket, editing: !socket.assigns.editing)}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to edit.")}
    end
  end

  # Handle inline title edit
  def handle_event("update_title", %{"value" => title}, socket) do
    if can_edit?(socket.assigns) do
      page = socket.assigns.page
      case Content.update_page(page, %{title: title}) do
        {:ok, updated_page} ->
          {:noreply, assign(socket, page: updated_page, last_saved: DateTime.utc_now())}
        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle block editor content changes
  def handle_event("editor-change", params, socket) do
    if can_edit?(socket.assigns) and socket.assigns.editing do
      # Prefer JSON block format, fallback to HTML
      content = Map.get(params, "content") || Map.get(params, "html", "")
      {:noreply, assign(socket, pending_content: content)}
    else
      {:noreply, socket}
    end
  end

  # Handle auto-save from editor
  def handle_event("editor-autosave", params, socket) do
    if can_edit?(socket.assigns) and socket.assigns.editing do
      socket = assign(socket, saving: true)
      page = socket.assigns.page
      # Prefer JSON block format, fallback to HTML
      content = Map.get(params, "content") || Map.get(params, "html", "")
      
      case Content.update_page(page, %{content: content}) do
        {:ok, updated_page} ->
          {:noreply, 
           socket
           |> assign(page: updated_page, saving: false, last_saved: DateTime.utc_now())
           |> push_event("content-saved", %{})}
        {:error, _} ->
          {:noreply, assign(socket, saving: false)}
      end
    else
      {:noreply, socket}
    end
  end

  # Manual save
  def handle_event("save_content", _params, socket) do
    if can_edit?(socket.assigns) and socket.assigns.editing do
      # The autosave has already saved the content, just exit editing mode
      {:noreply, 
       socket
       |> assign(editing: false, pending_content: nil)
       |> put_flash(:info, "Content saved!")}
    else
      {:noreply, socket}
    end
  end

  # Cancel editing
  def handle_event("cancel_edit", _params, socket) do
    # Reload the page to discard any unsaved changes
    page = Content.get_page!(socket.assigns.page.id)
    {:noreply, 
     socket
     |> assign(editing: false, page: page, pending_content: nil)
     |> push_event("update-editor-content", %{content: page.content})
     |> put_flash(:info, "Changes discarded")}
  end

  # Handle media uploads from block editor
  def handle_event("block-media-upload", params, socket) do
    if can_edit?(socket.assigns) do
      handle_media_upload(params, socket)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to upload.")}
    end
  end

  # Handle media removal from block editor
  def handle_event("block-media-remove", %{"blockId" => _block_id} = params, socket) do
    if can_edit?(socket.assigns) do
      handle_media_remove(params, socket)
    else
      {:noreply, socket}
    end
  end

  # Legacy handler for older block-image-upload events
  def handle_event("block-image-upload", params, socket) do
    if can_edit?(socket.assigns) do
      handle_media_upload(Map.put(params, "mediaType", "image"), socket)
    else
      {:noreply, socket}
    end
  end

  defp handle_media_upload(%{"blockId" => block_id, "mediaType" => media_type} = params, socket) do
    case Bacon8.Content.InlineMedia.store("pages/#{socket.assigns.page.id}", params) do
      {:ok, %{url: url, filename: filename}} ->
        {:noreply,
         push_event(socket, "block-media-uploaded", %{
           blockId: block_id,
           url: url,
           mediaType: media_type,
           filename: filename,
           mediaId: nil
         })}

      {:error, message} ->
        {:noreply, push_event(socket, "block-media-error", %{blockId: block_id, error: message})}
    end
  end

  defp handle_media_upload(_params, socket), do: {:noreply, socket}

  # Only this page's own uploads can be removed (Bacon8.Content.InlineMedia)
  defp handle_media_remove(%{"url" => url}, socket) when is_binary(url) do
    Bacon8.Content.InlineMedia.remove("pages/#{socket.assigns.page.id}", url)
    {:noreply, socket}
  end

  defp handle_media_remove(%{"itemId" => _item_id}, socket) do
    # For gallery items, deletion is handled by the URL-based removal
    {:noreply, socket}
  end

  defp handle_media_remove(_params, socket), do: {:noreply, socket}

  def render(assigns) do
    # Determine max width based on template type
    max_width = case assigns.page.template_type do
      "full-width" -> "max-w-full"
      "landing" -> "max-w-7xl"
      "sidebar" -> "max-w-6xl"
      _ -> "max-w-[85%]"
    end

    assigns = assign(assigns, :max_width, max_width)

    ~H"""
    <div data-responsive-content class="min-h-screen pointer-events-none" style="padding-top: 30px; padding-bottom: 48px;">
      <div class={"w-full #{@max_width} mx-auto px-4 py-8 relative z-10 pointer-events-auto"}>
        <div class="auth-glass-panel p-8 rounded-xl">
          <!-- Featured Image -->
          <%= if @page.featured_image do %>
            <div class="mb-8 rounded-lg overflow-hidden -mx-8 -mt-8">
              <img src={@page.featured_image} alt={@page.title} class="w-full h-96 object-cover" />
            </div>
          <% end %>

          <article class="prose prose-invert max-w-none">
            <!-- Category Badge -->
            <%= if @page.category do %>
              <div class="mb-4">
                <span class="inline-block px-3 py-1 text-sm rounded-full bg-blue-600 text-white">
                  <%= @page.category %>
                </span>
              </div>
            <% end %>

            <!-- Title with Edit Button -->
            <div class="flex items-center justify-between mb-6">
              <%= if @editing do %>
                <input
                  type="text"
                  value={@page.title}
                  phx-blur="update_title"
                  phx-keyup="update_title"
                  phx-key="Enter"
                  class="text-4xl font-bold text-white bg-transparent border-b-2 border-blue-500 focus:outline-none focus:border-blue-400 w-full"
                  placeholder="Page title..."
                />
              <% else %>
                <h1 class="text-4xl font-bold text-white"><%= @page.title %></h1>
              <% end %>
              
              <!-- Edit/Save/Cancel Buttons for Authorized Users -->
              <%= if can_edit?(assigns) do %>
                <%= if @editing do %>
                  <div class="flex items-center gap-2 ml-4">
                    <!-- Save Status Indicator -->
                    <span :if={@saving} class="text-yellow-400 text-sm animate-pulse">Saving...</span>
                    <span :if={@last_saved && !@saving} class="text-green-400 text-sm">
                      Saved <%= Calendar.strftime(@last_saved, "%H:%M:%S") %>
                    </span>
                    
                    <button
                      type="button"
                      phx-click="save_content"
                      class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm flex items-center gap-2"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                      </svg>
                      Save & Exit
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_edit"
                      class="bg-gray-600 hover:bg-gray-700 text-white px-4 py-2 rounded-lg text-sm"
                    >
                      Cancel
                    </button>
                  </div>
                <% else %>
                  <button
                    type="button"
                    phx-click="toggle_edit"
                    class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm flex items-center gap-2"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
                    </svg>
                    Edit Page
                  </button>
                <% end %>
              <% end %>
            </div>
            
            <!-- Excerpt or Meta Description -->
            <%= if @page.excerpt do %>
              <p class="text-xl text-gray-300 mb-8 font-medium"><%= @page.excerpt %></p>
            <% else %>
              <%= if @page.meta_description do %>
                <p class="text-xl text-gray-300 mb-8"><%= @page.meta_description %></p>
              <% end %>
            <% end %>

            <!-- Publish Date -->
            <%= if @page.published_at do %>
              <div class="text-sm text-gray-400 mb-8 flex items-center space-x-4">
                <span>Published: <%= Calendar.strftime(@page.published_at, "%B %d, %Y") %></span>
                <%= if @page.updated_at != @page.inserted_at do %>
                  <span>• Updated: <%= Calendar.strftime(@page.updated_at, "%B %d, %Y") %></span>
                <% end %>
              </div>
            <% end %>

            <hr class="border-gray-700 mb-8" />
            
            <!-- Content: WYSIWYG Editor or Rendered View -->
            <%= if @editing do %>
              <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
                <BlockEditor.block_editor
                  id={"page-editor-#{@page.id}"}
                  content={@page.content}
                  placeholder="Build your page content..."
                  min_height="500px"
                  autosave_delay={5000}
                />
              </div>
            <% else %>
              <div class="text-gray-200 leading-relaxed text-lg prose prose-invert max-w-none">
                <%= BlockEditor.render_blocks(@page.content) %>
              </div>
              
              <!-- Social Share Buttons -->
              <div class="mt-8 pt-6 border-t border-gray-700">
                <SocialShare.social_share
                  url={Bacon8Web.Endpoint.url() <> "/pages/#{@page.slug}"}
                  title={@page.title}
                  description={@page.excerpt || @page.meta_description}
                  image_url={@page.featured_image}
                  platforms={@page.share_platforms || ["twitter", "facebook", "linkedin", "reddit", "email"]}
                  show={Map.get(@page, :show_share_buttons, true)}
                  colored={Map.get(@page, :share_buttons_colored, false)}
                />
              </div>
            <% end %>
          </article>
        </div>
      </div>
    </div>
    """
  end
end
