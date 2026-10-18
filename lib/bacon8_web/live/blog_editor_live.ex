defmodule Bacon8Web.BlogEditorLive do
  @moduledoc """
  Real-time blog post editor with block-based WYSIWYG functionality.
  Only accessible by admins, GMs, and editors.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8.Content.Post
  alias Bacon8Web.Components.BlockEditor

  on_mount {Bacon8Web.UserAuth, :ensure_authenticated}

  @allowed_roles ["admin", "gm", "editor"]

  @default_platforms ["twitter", "facebook", "linkedin", "reddit", "email"]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    
    # Check if user has permission to edit content
    if user.role in @allowed_roles or Map.get(user, :is_admin, false) do
      {:ok,
       assign(socket,
         page_title: "Blog Editor",
         posts: Content.list_posts(),
         editing_post: nil,
         form: nil,
         view: :list,
         saving: false,
         last_saved: nil,
         pending_content: nil,
         show_share_buttons: true,
         share_platforms: @default_platforms,
         share_buttons_colored: false
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to access the blog editor.")
       |> redirect(to: ~p"/blog")}
    end
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    post = Content.get_post!(id)
    changeset = Post.changeset(post, %{})
    
    {:noreply,
     assign(socket,
       page_title: "Edit: #{post.title}",
       editing_post: post,
       form: to_form(changeset),
       view: :edit,
       show_share_buttons: Map.get(post, :show_share_buttons, true),
       share_platforms: Map.get(post, :share_platforms) || @default_platforms,
       share_buttons_colored: Map.get(post, :share_buttons_colored, false)
     )}
  end

  def handle_params(%{"action" => "new"}, _uri, socket) do
    user = socket.assigns.current_user
    changeset = Post.changeset(%Post{user_id: user.id}, %{})
    
    {:noreply,
     assign(socket,
       page_title: "New Post",
       editing_post: %Post{user_id: user.id},
       form: to_form(changeset),
       view: :new,
       show_share_buttons: true,
       share_platforms: @default_platforms,
       share_buttons_colored: false
     )}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       page_title: "Blog Editor",
       posts: Content.list_posts(),
       editing_post: nil,
       form: nil,
       view: :list
     )}
  end

  # Handle form validation
  def handle_event("validate", %{"post" => post_params}, socket) do
    changeset =
      (socket.assigns.editing_post || %Post{})
      |> Post.changeset(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  # Handle block editor content changes
  def handle_event("editor-change", params, socket) do
    # Prefer JSON block format, fallback to HTML
    content = Map.get(params, "content") || Map.get(params, "html", "")
    # Store pending content without updating the form (to avoid re-rendering the editor)
    {:noreply, assign(socket, pending_content: content)}
  end

  # Handle auto-save from editor
  def handle_event("editor-autosave", params, socket) do
    # Prefer JSON block format, fallback to HTML
    content = Map.get(params, "content") || Map.get(params, "html", "")
    save_post_content(socket, content)
  end

  # Handle manual save
  def handle_event("save_post", %{"post" => post_params}, socket) do
    socket = assign(socket, saving: true)
    
    # Use pending_content if available (from editor-change events)
    post_params = 
      if socket.assigns[:pending_content] do
        Map.put(post_params, "content", socket.assigns.pending_content)
      else
        post_params
      end
    
    # Parse tags from string to list
    post_params = Map.update(post_params, "tags", [], &parse_tags/1)
    
    case socket.assigns.view do
      :new ->
        user = socket.assigns.current_user
        case Content.create_post(user, post_params) do
          {:ok, post} ->
            {:noreply,
             socket
             |> assign(saving: false, last_saved: DateTime.utc_now())
             |> put_flash(:info, "Post created successfully!")
             |> push_navigate(to: ~p"/admin/blog-management/#{post.id}")}
          
          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(saving: false, form: to_form(changeset))
             |> put_flash(:error, "Failed to create post.")}
        end
      
      :edit ->
        case Content.update_post(socket.assigns.editing_post, post_params) do
          {:ok, post} ->
            {:noreply,
             socket
             |> assign(saving: false, editing_post: post, last_saved: DateTime.utc_now())
             |> put_flash(:info, "Post saved successfully!")}
          
          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(saving: false, form: to_form(changeset))
             |> put_flash(:error, "Failed to save post.")}
        end
      
      _ ->
        {:noreply, assign(socket, saving: false)}
    end
  end

  # Save as draft
  def handle_event("save_draft", %{"post" => post_params}, socket) do
    post_params = Map.put(post_params, "is_published", false)
    handle_event("save_post", %{"post" => post_params}, socket)
  end

  # Publish post
  def handle_event("publish", %{"post" => post_params}, socket) do
    post_params = 
      post_params
      |> Map.put("is_published", true)
      |> Map.put("published_at", DateTime.utc_now())
    
    handle_event("save_post", %{"post" => post_params}, socket)
  end

  # Unpublish post
  def handle_event("unpublish", _params, socket) do
    case Content.update_post(socket.assigns.editing_post, %{is_published: false}) do
      {:ok, post} ->
        changeset = Post.changeset(post, %{})
        {:noreply,
         socket
         |> assign(editing_post: post, form: to_form(changeset))
         |> put_flash(:info, "Post unpublished.")}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unpublish post.")}
    end
  end

  # Delete post
  def handle_event("delete_post", %{"id" => id}, socket) do
    post = Content.get_post!(id)
    
    case Content.delete_post(post) do
      {:ok, _} ->
        # Delete uploaded files for this blog post
        Bacon8.Uploads.delete_content_uploads("blog", id)
        
        {:noreply,
         socket
         |> assign(posts: Content.list_posts())
         |> put_flash(:info, "Post deleted.")
         |> push_navigate(to: ~p"/admin/blog-management")}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete post.")}
    end
  end

  # Navigate back to list
  def handle_event("back_to_list", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/blog-management")}
  end

  # Toggle share buttons on/off
  def handle_event("toggle_share_buttons", _params, socket) do
    {:noreply, assign(socket, show_share_buttons: !socket.assigns.show_share_buttons)}
  end

  # Toggle colored share buttons
  def handle_event("toggle_share_colored", _params, socket) do
    {:noreply, assign(socket, share_buttons_colored: !socket.assigns.share_buttons_colored)}
  end

  # Toggle individual share platform
  def handle_event("toggle_share_platform", %{"platform" => platform}, socket) do
    platforms = socket.assigns.share_platforms
    updated_platforms = 
      if platform in platforms do
        List.delete(platforms, platform)
      else
        platforms ++ [platform]
      end
    {:noreply, assign(socket, share_platforms: updated_platforms)}
  end

  # Handle media uploads from block editor
  def handle_event("block-media-upload", params, socket) do
    handle_media_upload(params, socket)
  end

  # Handle media removal from block editor
  def handle_event("block-media-remove", %{"blockId" => _block_id} = params, socket) do
    handle_media_remove(params, socket)
  end

  defp handle_media_upload(%{"blockId" => block_id, "mediaType" => media_type, "data" => base64_data} = params, socket) do
    # For new posts without an ID, we need to save the post first
    post = socket.assigns.editing_post
    user = socket.assigns.current_user
    
    # If it's a new post without an ID, save it first
    {socket, post} = 
      if post.id == nil do
        case Content.create_post(user, %{
          "title" => "Untitled Post",
          "content" => "",
          "is_published" => false
        }) do
          {:ok, new_post} ->
            changeset = Post.changeset(new_post, %{})
            {assign(socket, editing_post: new_post, form: to_form(changeset), view: :edit), new_post}
          {:error, _} ->
            {socket, post}
        end
      else
        {socket, post}
      end
    
    if post.id == nil do
      {:noreply, push_event(socket, "block-media-error", %{
        blockId: block_id,
        error: "Please save the post first before uploading media"
      })}
    else
      filename = params["filename"] || "upload_#{System.unique_integer([:positive])}"
      mime_type = params["mimeType"] || "application/octet-stream"
      file_size = params["size"] || 0
      original_filename = params["filename"] || filename
      
      # Use post ID for the upload path: /uploads/public/blog/{post_id}/
      upload_context = "blog/#{post.id}"
      
      case Base.decode64(base64_data) do
        {:ok, file_data} ->
          temp_dir = System.tmp_dir!()
          temp_path = Path.join(temp_dir, filename)
          
          case File.write(temp_path, file_data) do
            :ok ->
              case Bacon8.Uploads.upload_file(
                nil,
                temp_path,
                %{client_name: filename, client_type: mime_type, client_size: file_size},
                context: upload_context,
                public: true
              ) do
                {:ok, url} ->
                  File.rm(temp_path)
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
  end

  defp handle_media_remove(%{"url" => url}, socket) when is_binary(url) do
    if String.starts_with?(url, "/uploads/public/") do
      priv_path = Path.join(["priv/static", url])
      File.rm(priv_path)
    end
    {:noreply, socket}
  end

  defp handle_media_remove(_params, socket), do: {:noreply, socket}

  defp save_post_content(socket, html) do
    case socket.assigns.view do
      :edit ->
        post = socket.assigns.editing_post
        case Content.update_post(post, %{content: html}) do
          {:ok, updated_post} ->
            {:noreply, assign(socket, editing_post: updated_post, last_saved: DateTime.utc_now())}
          
          {:error, _} ->
            {:noreply, socket}
        end
      
      _ ->
        {:noreply, socket}
    end
  end

  # Parse tags from comma-separated string
  defp parse_tags(nil), do: []
  defp parse_tags(tags) when is_list(tags), do: tags
  defp parse_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-indigo-900">
      <!-- Header -->
      <div class="bg-black/50 border-b border-gray-700 sticky top-0 z-50">
        <div class="container mx-auto px-4">
          <div class="flex items-center justify-between h-14">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/blog"} class="text-gray-400 hover:text-white">
                ← Back to Blog
              </.link>
              <h1 class="text-xl font-bold text-white"><%= @page_title %></h1>
            </div>
            
            <div class="flex items-center gap-3">
              <%= if @last_saved do %>
                <span class="text-xs text-green-400">
                  ✓ Last saved: <%= Calendar.strftime(@last_saved, "%I:%M %p") %>
                </span>
              <% end %>
              
              <%= if @saving do %>
                <span class="text-xs text-yellow-400 animate-pulse">Saving...</span>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="container mx-auto px-4 py-8">
        <!-- List View -->
        <%= if @view == :list do %>
          <div class="max-w-6xl mx-auto">
            <div class="flex items-center justify-between mb-6">
              <h2 class="text-2xl font-bold text-white">Manage Posts</h2>
              <.link navigate={~p"/admin/blog-management?action=new"} class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg">
                + New Post
              </.link>
            </div>
            
            <div class="bg-white/10 backdrop-blur-sm rounded-xl overflow-hidden">
              <table class="w-full">
                <thead class="bg-black/30">
                  <tr>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Title</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Author</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Status</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Date</th>
                    <th class="text-right text-gray-300 px-4 py-3 text-sm font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for post <- @posts do %>
                    <tr class="hover:bg-white/5">
                      <td class="px-4 py-3">
                        <.link navigate={~p"/admin/blog-management/#{post.id}"} class="text-white hover:text-blue-400 font-medium">
                          <%= post.title || "(Untitled)" %>
                        </.link>
                      </td>
                      <td class="px-4 py-3 text-gray-400 text-sm">
                        <%= if post.user, do: post.user.name || post.user.email, else: "Unknown" %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if post.is_published do %>
                          <span class="inline-block px-2 py-1 bg-green-600/50 text-green-200 text-xs rounded">Published</span>
                        <% else %>
                          <span class="inline-block px-2 py-1 bg-yellow-600/50 text-yellow-200 text-xs rounded">Draft</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-gray-400 text-sm">
                        <%= Calendar.strftime(post.inserted_at, "%b %d, %Y") %>
                      </td>
                      <td class="px-4 py-3 text-right">
                        <.link navigate={~p"/admin/blog-management/#{post.id}"} class="text-blue-400 hover:text-blue-300 text-sm mr-3">
                          Edit
                        </.link>
                        <.link navigate={~p"/blog/#{post.slug}"} target="_blank" class="text-gray-400 hover:text-gray-300 text-sm mr-3">
                          View
                        </.link>
                        <button 
                          phx-click="delete_post" 
                          phx-value-id={post.id}
                          data-confirm="Are you sure you want to delete this post?"
                          class="text-red-400 hover:text-red-300 text-sm"
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
              
              <%= if @posts == [] do %>
                <div class="text-center text-gray-400 py-12">
                  <p class="mb-4">No posts yet.</p>
                  <.link navigate={~p"/admin/blog-management?action=new"} class="text-blue-400 hover:text-blue-300">
                    Create your first post →
                  </.link>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Edit/New View -->
        <%= if @view in [:edit, :new] do %>
          <div class="max-w-6xl mx-auto">
            <.form for={@form} phx-change="validate" phx-submit="save_post" class="space-y-6">
              <!-- Top Controls -->
              <div class="flex items-center justify-between bg-white/10 backdrop-blur-sm rounded-xl p-4">
                <button type="button" phx-click="back_to_list" class="text-gray-400 hover:text-white">
                  ← Back to List
                </button>
                
                <div class="flex items-center gap-3">
                  <%= if @view == :edit && @editing_post.is_published do %>
                    <button type="button" phx-click="unpublish" class="bg-yellow-600 hover:bg-yellow-700 text-white px-4 py-2 rounded-lg text-sm">
                      Unpublish
                    </button>
                  <% end %>
                  
                  <button type="submit" name="action" value="draft" phx-disable-with="Saving..." class="bg-gray-600 hover:bg-gray-700 text-white px-4 py-2 rounded-lg text-sm">
                    Save Draft
                  </button>
                  
                  <button type="submit" name="action" value="publish" phx-disable-with="Publishing..." class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm">
                    <%= if @view == :edit && @editing_post.is_published, do: "Update", else: "Publish" %>
                  </button>
                </div>
              </div>

              <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <!-- Main Editor -->
                <div class="lg:col-span-2 space-y-6">
                  <!-- Title -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Title</label>
                    <input 
                      type="text" 
                      name="post[title]" 
                      value={@form[:title].value}
                      placeholder="Enter post title..."
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-3 text-white text-xl placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <%= if @form[:title].errors != [] do %>
                      <p class="mt-1 text-sm text-red-400"><%= Enum.join(Enum.map(@form[:title].errors, fn {msg, _} -> msg end), ", ") %></p>
                    <% end %>
                  </div>

                  <!-- Content Editor -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Content</label>
                    <input type="hidden" name="post[content]" id="post-content-hidden" value={@form[:content].value || ""} />
                    <BlockEditor.block_editor 
                      id="post-content"
                      value={@form[:content].value || ""}
                      placeholder="Start building your post content..."
                      autosave_delay={5000}
                    />
                  </div>
                </div>

                <!-- Sidebar -->
                <div class="space-y-6 lg:sticky lg:top-20 lg:max-h-[calc(100vh-6rem)] lg:overflow-y-auto">
                  <!-- Slug -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">URL Slug</label>
                    <input 
                      type="text" 
                      name="post[slug]" 
                      value={@form[:slug].value}
                      placeholder="auto-generated-from-title"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <p class="mt-1 text-xs text-gray-500">Leave blank to auto-generate from title</p>
                  </div>

                  <!-- Excerpt -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Excerpt</label>
                    <textarea 
                      name="post[excerpt]"
                      rows="3"
                      placeholder="Brief summary of the post..."
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
                    ><%= @form[:excerpt].value %></textarea>
                  </div>

                  <!-- Featured Image -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Featured Image URL</label>
                    <input 
                      type="text" 
                      name="post[featured_image]" 
                      value={@form[:featured_image].value}
                      placeholder="/uploads/image.jpg or https://..."
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <%= if @form[:featured_image].value && @form[:featured_image].value != "" do %>
                      <img src={@form[:featured_image].value} alt="Preview" class="mt-3 rounded-lg max-h-32 object-cover" />
                    <% end %>
                  </div>

                  <!-- Tags -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Tags</label>
                    <input 
                      type="text" 
                      name="post[tags]" 
                      value={if is_list(@form[:tags].value), do: Enum.join(@form[:tags].value, ", "), else: @form[:tags].value}
                      placeholder="tag1, tag2, tag3"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <p class="mt-1 text-xs text-gray-500">Comma-separated</p>
                  </div>

                  <!-- Meta Description -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Meta Description</label>
                    <textarea 
                      name="post[meta_description]"
                      rows="2"
                      maxlength="160"
                      placeholder="SEO description (max 160 chars)"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
                    ><%= @form[:meta_description].value %></textarea>
                    <p class="mt-1 text-xs text-gray-500">
                      <%= String.length(@form[:meta_description].value || "") %>/160 characters
                    </p>
                  </div>

                  <!-- Social Sharing Settings -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <h3 class="text-sm font-medium text-gray-300 mb-3">Social Sharing</h3>
                    <Bacon8Web.Components.SocialShare.share_settings
                      show_share_buttons={@show_share_buttons}
                      share_platforms={@share_platforms}
                      share_buttons_colored={@share_buttons_colored}
                      on_toggle="toggle_share_buttons"
                      on_platform_toggle="toggle_share_platform"
                      on_colored_toggle="toggle_share_colored"
                    />
                    <!-- Hidden fields for form submission -->
                    <input type="hidden" name="post[show_share_buttons]" value={to_string(@show_share_buttons)} />
                    <input type="hidden" name="post[share_buttons_colored]" value={to_string(@share_buttons_colored)} />
                    <%= for platform <- @share_platforms do %>
                      <input type="hidden" name="post[share_platforms][]" value={platform} />
                    <% end %>
                  </div>

                  <!-- Post Info (for existing posts) -->
                  <%= if @view == :edit && @editing_post do %>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                      <h3 class="text-sm font-medium text-gray-300 mb-3">Post Info</h3>
                      <dl class="space-y-2 text-sm">
                        <div class="flex justify-between">
                          <dt class="text-gray-500">Created</dt>
                          <dd class="text-gray-300"><%= Calendar.strftime(@editing_post.inserted_at, "%b %d, %Y") %></dd>
                        </div>
                        <%= if @editing_post.published_at do %>
                          <div class="flex justify-between">
                            <dt class="text-gray-500">Published</dt>
                            <dd class="text-gray-300"><%= Calendar.strftime(@editing_post.published_at, "%b %d, %Y") %></dd>
                          </div>
                        <% end %>
                        <div class="flex justify-between">
                          <dt class="text-gray-500">Status</dt>
                          <dd>
                            <%= if @editing_post.is_published do %>
                              <span class="text-green-400">Published</span>
                            <% else %>
                              <span class="text-yellow-400">Draft</span>
                            <% end %>
                          </dd>
                        </div>
                      </dl>
                    </div>
                  <% end %>
                </div>
              </div>
            </.form>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
