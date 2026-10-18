defmodule Bacon8Web.BlogLive do
  use Bacon8Web, :live_view
  alias Bacon8.Content
  import Bacon8Web.Components.PageContainer
  alias Bacon8Web.Components.BlockEditor
  alias Bacon8Web.Components.SocialShare

  # Note: on_mount :default is handled by router's live_session

  @allowed_roles ["admin", "gm", "editor"]

  def mount(_params, _session, socket) do
    posts = Content.list_published_posts()
    recent_posts = Content.get_recent_posts(5)

    {:ok,
     assign(socket,
       posts: posts,
       recent_posts: recent_posts,
       current_slide: 0,
       page_title: "Blog",
       view: :post_list,
       editing: false,
       saving: false,
       last_saved: nil
     )}
  end

  def handle_params(%{"slug" => slug}, _uri, socket) do
    post = Content.get_post_by_slug!(slug)

    {:noreply,
     assign(socket,
       post: post,
       page_title: post.title,
       view: :post_detail,
       editing: false,
       saving: false,
       last_saved: nil,
       pending_content: nil
     )}
  end

  def handle_params(_params, _uri, socket) do
    # Back to blog list view
    {:noreply,
     assign(socket,
       page_title: "Blog",
       view: :post_list,
       editing: false
     )}
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
      post = socket.assigns.post
      case Content.update_post(post, %{title: title}) do
        {:ok, updated_post} ->
          {:noreply, assign(socket, post: updated_post, last_saved: DateTime.utc_now())}
        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle block editor content changes (real-time save)
  def handle_event("editor-change", params, socket) do
    if can_edit?(socket.assigns) and socket.assigns.editing do
      # Store the content (prefer JSON block format, fallback to HTML)
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
      post = socket.assigns.post
      # Prefer JSON block format, fallback to HTML
      content = Map.get(params, "content") || Map.get(params, "html", "")
      
      case Content.update_post(post, %{content: content}) do
        {:ok, updated_post} ->
          {:noreply, 
           socket
           |> assign(post: updated_post, saving: false, last_saved: DateTime.utc_now())
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
    # Reload the post to discard any unsaved changes
    post = Content.get_post!(socket.assigns.post.id)
    {:noreply, 
     socket
     |> assign(editing: false, post: post, pending_content: nil)
     |> push_event("update-editor-content", %{content: post.content})
     |> put_flash(:info, "Changes discarded")}
  end

  def handle_event("next_slide", _params, socket) do
    recent_posts = socket.assigns.recent_posts
    current = socket.assigns.current_slide
    next_slide = if current >= length(recent_posts) - 1, do: 0, else: current + 1
    {:noreply, assign(socket, current_slide: next_slide)}
  end

  def handle_event("prev_slide", _params, socket) do
    recent_posts = socket.assigns.recent_posts
    current = socket.assigns.current_slide
    prev_slide = if current == 0, do: length(recent_posts) - 1, else: current - 1
    {:noreply, assign(socket, current_slide: prev_slide)}
  end
  def handle_event("go_to_slide", %{"slide" => slide_str}, socket) do
    slide = String.to_integer(slide_str)
    {:noreply, assign(socket, current_slide: slide)}
  end

  # Desktop UI sometimes pushes update_window_position globally; ignore in BlogLive
  def handle_event("update_window_position", _params, socket) do
    {:noreply, socket}
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
      # Convert to new format and process
      handle_media_upload(Map.put(params, "mediaType", "image"), socket)
    else
      {:noreply, socket}
    end
  end

  defp handle_media_upload(%{"blockId" => block_id, "mediaType" => media_type, "data" => base64_data} = params, socket) do
    post = socket.assigns.post
    filename = params["filename"] || "upload_#{System.unique_integer([:positive])}"
    mime_type = params["mimeType"] || "application/octet-stream"
    file_size = params["size"] || 0
    original_filename = params["filename"] || filename
    
    # Use post ID for the upload path: /uploads/public/blog/{post_id}/
    upload_context = "blog/#{post.id}"
    
    # Decode base64 data
    case Base.decode64(base64_data) do
      {:ok, file_data} ->
        # Create temp file
        temp_dir = System.tmp_dir!()
        temp_path = Path.join(temp_dir, filename)
        
        case File.write(temp_path, file_data) do
          :ok ->
            # Upload to /uploads/public/blog/{post_id}/ using Uploads module
            case Bacon8.Uploads.upload_file(
              nil,
              temp_path,
              %{client_name: filename, client_type: mime_type, client_size: file_size},
              context: upload_context,
              public: true
            ) do
              {:ok, url} ->
                # Clean up temp file
                File.rm(temp_path)
                
                # Push success event to client
                {:noreply, push_event(socket, "block-media-uploaded", %{
                  blockId: block_id,
                  url: url,
                  mediaType: media_type,
                  filename: original_filename,
                  mediaId: nil
                })}
              
              {:error, reason} ->
                File.rm(temp_path)
                {:noreply, push_event(socket, "block-media-error", %{
                  blockId: block_id,
                  error: "Upload failed: #{inspect(reason)}"
                })}
            end
          
          {:error, reason} ->
            {:noreply, push_event(socket, "block-media-error", %{
              blockId: block_id,
              error: "Failed to write temp file: #{inspect(reason)}"
            })}
        end
      
      :error ->
        {:noreply, push_event(socket, "block-media-error", %{
          blockId: block_id,
          error: "Invalid file data"
        })}
    end
  end

  defp handle_media_remove(%{"url" => url}, socket) when is_binary(url) do
    # Delete the file directly from filesystem
    # URL format: /uploads/public/blog/{post_id}/filename.ext
    if String.starts_with?(url, "/uploads/public/") do
      # Convert URL path to filesystem path
      relative_path = String.replace_prefix(url, "/uploads/", "")
      file_path = Path.join(Bacon8.Uploads.base_dir(), relative_path)
      
      # Delete the file if it exists
      if File.exists?(file_path) do
        File.rm(file_path)
      end
    end
    
    {:noreply, socket}
  end

  defp handle_media_remove(%{"itemId" => _item_id}, socket) do
    # For gallery items, deletion is handled by the URL-based removal
    # since we're not storing them in the database
    {:noreply, socket}
  end

  defp handle_media_remove(_params, socket), do: {:noreply, socket}

  # Helper to get featured image URL - handles both Arc files and plain URLs
  defp get_featured_image_url(post, _version) do
    cond do
      # If featured_image is nil or empty, use default
      is_nil(post.featured_image) or post.featured_image == "" ->
        "/images/default-blog.jpg"
      
      # If featured_image starts with /uploads/, use it directly
      is_binary(post.featured_image) and String.starts_with?(post.featured_image, "/uploads/") ->
        post.featured_image
      
      # If featured_image starts with /, it's already a URL path
      is_binary(post.featured_image) and String.starts_with?(post.featured_image, "/") ->
        post.featured_image
      
      # If featured_image starts with http, it's an external URL
      is_binary(post.featured_image) and String.starts_with?(post.featured_image, "http") ->
        post.featured_image
      
      # Otherwise treat as hash filename - construct full path with user ID
      is_binary(post.featured_image) and post.user ->
        "/uploads/#{post.user.id}/blog/#{post.featured_image}"
      
      # Fallback
      true ->
        "/images/default-blog.jpg"
    end
  end

  

  def render(assigns) do
    ~H"""
    <.page_container glass={false}>
      <!-- Blog List View -->
      <div :if={@view != :post_detail}>
        <h1 class="text-4xl font-bold text-white mb-8 text-center">Our Blog</h1>

        <!-- Featured Posts Carousel -->
        <div :if={@recent_posts != []} class="mb-12">
            <h2 class="text-2xl font-bold text-white mb-6">Featured Posts</h2>

            <div class="relative glass-dark rounded-lg overflow-hidden">
              <div class="relative h-96 overflow-hidden">
                <%= for {post, index} <- Enum.with_index(@recent_posts) do %>
                  <div
                    class={[
                      "absolute inset-0 transition-transform duration-500 ease-in-out",
                      if(index == @current_slide, do: "translate-x-0",
                        else: if(index < @current_slide, do: "-translate-x-full", else: "translate-x-full")
                      )
                    ]}
                  >
                    <div class="flex h-full">
                      <!-- Image -->
                      <div class="w-1/2 relative">
                        <img src={get_featured_image_url(post, :large)}
                             alt={post.title} class="w-full h-full object-cover" />
                        <div class="absolute inset-0 bg-gradient-to-r from-transparent to-gray-800"></div>
                      </div>

                      <!-- Content -->
                      <div class="w-1/2 p-8 flex flex-col justify-center">
                        <div class="text-blue-400 text-sm mb-2">
                          <%= Calendar.strftime(post.published_at, "%B %d, %Y") %>
                        </div>
                        <h3 class="text-2xl font-bold text-white mb-4"><%= post.title %></h3>
                        <p class="text-gray-300 mb-6 line-clamp-3"><%= post.excerpt || String.slice(post.content, 0, 200) <> "..." %></p>
                        <div class="flex items-center space-x-4">
                          <.link navigate={"/blog/#{post.slug}"}
                                 class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg transition-colors">
                            Read More
                          </.link>
                          <div class="flex items-center text-gray-400 text-sm">
                            <%= if post.user.avatar_url do %>
                              <img src={post.user.avatar_url} alt={post.user.name || post.user.email} class="w-6 h-6 rounded-full mr-2 object-cover" />
                            <% else %>
                              <div class="w-6 h-6 rounded-full mr-2" style={"background-color: #{post.user.avatar_color};";}>
                                <span class="text-xs text-white flex items-center justify-center h-full">
                                  <%= String.first(post.user.name || post.user.email) %>
                                </span>
                              </div>
                            <% end %>
                            <span class="mr-4"><%= post.user.name || post.user.email %></span>
                            <span><%= Calendar.strftime(post.published_at, "%b %d, %Y") %></span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Navigation Arrows -->
              <button phx-click="prev_slide"
                      class="absolute left-4 top-1/2 transform -translate-y-1/2 bg-black bg-opacity-50 hover:bg-opacity-75 text-white p-2 rounded-full transition-all">
                ←
              </button>
              <button phx-click="next_slide"
                      class="absolute right-4 top-1/2 transform -translate-y-1/2 bg-black bg-opacity-50 hover:bg-opacity-75 text-white p-2 rounded-full transition-all">
                →
              </button>

              <!-- Dots Indicator -->
              <div class="absolute bottom-4 left-1/2 transform -translate-x-1/2 flex space-x-2">
                <%= for {_post, index} <- Enum.with_index(@recent_posts) do %>
                  <button phx-click="go_to_slide" phx-value-slide={index}
                          class={["w-3 h-3 rounded-full transition-all",
                                  if(index == @current_slide, do: "bg-blue-500", else: "bg-gray-500 hover:bg-gray-400")]} />
                <% end %>
              </div>
            </div>
        </div>

        <!-- All Posts Grid -->
        <div class="mb-8">
            <h2 class="text-2xl font-bold text-white mb-6">All Posts</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
              <%= for post <- @posts do %>
                <article class="glass-dark rounded-lg overflow-hidden hover:transform hover:scale-105 transition-all duration-300">
                  <.link navigate={"/blog/#{post.slug}"}>
                    <img src={get_featured_image_url(post, :thumb)}
                         alt={post.title} class="w-full h-48 object-cover" />
                  </.link>

                  <div class="p-6">
                    <div class="flex items-center text-gray-400 text-sm mb-3">
                      <%= if post.user.avatar_url do %>
                        <img src={post.user.avatar_url} alt={post.user.name || post.user.email} class="w-6 h-6 rounded-full mr-2 object-cover" />
                      <% else %>
                        <div class="w-6 h-6 rounded-full mr-2" style={"background-color: #{post.user.avatar_color};";}>
                          <span class="text-xs text-white flex items-center justify-center h-full">
                            <%= String.first(post.user.name || post.user.email) %>
                          </span>
                        </div>
                      <% end %>
                      <span class="mr-4"><%= post.user.name || post.user.email %></span>
                      <span><%= Calendar.strftime(post.published_at, "%b %d, %Y") %></span>
                    </div>

                    <h3 class="text-xl font-bold text-white mb-3 hover:text-blue-400 transition-colors">
                      <.link navigate={"/blog/#{post.slug}"}><%= post.title %></.link>
                    </h3>

                    <p class="text-gray-300 mb-4 line-clamp-3">
                      <%= post.excerpt || String.slice(post.content, 0, 150) <> "..." %>
                    </p>

                    <div class="flex items-center justify-between">
                      <.link navigate={"/blog/#{post.slug}"}
                             class="text-blue-400 hover:text-blue-300 font-medium transition-colors">
                        Read More →
                      </.link>

                      <div :if={post.tags != []} class="flex flex-wrap gap-1">
                        <%= for tag <- Enum.take(post.tags, 2) do %>
                          <span class="bg-gray-700 text-gray-300 px-2 py-1 rounded text-xs">
                            #<%= tag %>
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </article>
              <% end %>
            </div>
          </div>
        </div>

      <!-- Blog Post Detail View -->
      <div :if={@view == :post_detail}>
        <div class="auth-glass-panel rounded-xl p-8 mb-6">
          <!-- Back button -->
          <.link navigate={~p"/blog"} class="text-blue-400 hover:text-blue-300 mb-6 inline-block">
            ← Back to Blog
          </.link>

          <!-- Featured Image -->
          <div :if={@post.featured_image} class="mb-8 rounded-lg overflow-hidden">
            <img src={get_featured_image_url(@post, :large)}
                 alt={@post.title} class="w-full h-96 object-cover" />
          </div>

          <!-- Post Header -->
          <article class="prose prose-invert max-w-none">
            <div class="flex items-center justify-between mb-4">
              <!-- Title: Editable or Read-only -->
              <%= if @editing do %>
                <input
                  type="text"
                  value={@post.title}
                  phx-blur="update_title"
                  phx-keyup="update_title"
                  phx-key="Enter"
                  class="text-4xl font-bold text-white bg-transparent border-b-2 border-blue-500 focus:outline-none focus:border-blue-400 w-full"
                  placeholder="Post title..."
                />
              <% else %>
                <h1 class="text-4xl font-bold text-white"><%= @post.title %></h1>
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
                    Edit Post
                  </button>
                <% end %>
              <% end %>
            </div>

            <div class="flex items-center text-gray-400 text-sm mb-8">
              <%= if @post.user.avatar_url do %>
                <img src={@post.user.avatar_url} alt={@post.user.name || @post.user.email} class="w-8 h-8 rounded-full mr-3 object-cover" />
              <% else %>
                <div class="w-8 h-8 rounded-full mr-3" style={"background-color: #{@post.user.avatar_color};";}>
                  <span class="text-sm text-white flex items-center justify-center h-full">
                    <%= String.first(@post.user.name || @post.user.email) %>
                  </span>
                </div>
              <% end %>
              <span class="mr-4"><%= @post.user.name || @post.user.email %></span>
              <span><%= Calendar.strftime(@post.published_at, "%B %d, %Y") %></span>
            </div>

            <!-- Tags -->
            <div :if={@post.tags != []} class="flex flex-wrap gap-2 mb-8">
              <%= for tag <- @post.tags do %>
                <span class="bg-gray-700 text-gray-300 px-3 py-1 rounded-full text-sm">
                  #<%= tag %>
                </span>
              <% end %>
            </div>

            <!-- Post Content: WYSIWYG Editor or Rendered View -->
            <%= if @editing do %>
              <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
                <BlockEditor.block_editor
                  id={"blog-editor-#{@post.id}"}
                  content={@post.content}
                  placeholder="Write your blog post content..."
                  min_height="500px"
                  autosave_delay={5000}
                />
              </div>
            <% else %>
              <div class="text-gray-200 leading-relaxed text-lg prose prose-invert max-w-none">
                <%= BlockEditor.render_blocks(@post.content) %>
              </div>
              
              <!-- Social Share Buttons -->
              <div class="mt-8 pt-6 border-t border-gray-700">
                <SocialShare.social_share
                  url={Bacon8Web.Endpoint.url() <> "/blog/#{@post.slug}"}
                  title={@post.title}
                  description={@post.excerpt || @post.meta_description}
                  image_url={get_featured_image_url(@post, :large)}
                  platforms={@post.share_platforms || ["twitter", "facebook", "linkedin", "reddit", "email"]}
                  show={Map.get(@post, :show_share_buttons, true)}
                  colored={Map.get(@post, :share_buttons_colored, false)}
                />
              </div>
            <% end %>
          </article>
        </div>
      </div>

      <script>
        setInterval(() => {
          if (window.location.pathname === '/blog') {
            const nextButton = document.querySelector('[phx-click="next_slide"]');
            if (nextButton) nextButton.click();
          }
        }, 5000);
      </script>
    </.page_container>
    """
  end
end
