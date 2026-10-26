defmodule Bacon8Web.AdminLive.BlogManagement do
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8.Content.Post
  alias Bacon8.Content.Media
  alias Bacon8Web.Components.AdminSidebar
  alias Bacon8Web.Components.BlockEditor
  alias Bacon8Web.Components.ContentExtras
  alias Bacon8Web.Components.SocialShare

  on_mount {Bacon8Web.UserAuth, {:require_area, :content}}

  @default_platforms ["twitter", "facebook", "linkedin", "reddit", "email"]

  @impl true
  def mount(_params, _session, socket) do
    posts = Content.list_posts()
    
    {:ok, 
     socket
     |> assign(
       posts: posts,
       page_title: "Blog Management",
       show_form: false,
       editing_post: nil,
       new_draft_id: nil,
       revisions: [],
       editor_key: 0,
       uploaded_media: [],
       show_media_picker: false,
       form: to_form(Post.changeset(%Post{}, %{})),
       show_share_buttons: true,
       share_platforms: @default_platforms
     )
     |> allow_upload(:featured_image,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  # A new post starts as a saved draft, so the editor has a record to autosave to and to attach
  # uploads to (Bacon8.Content.create_draft/2).
  def handle_event("new_post", _params, socket) do
    case Content.create_draft(:post, socket.assigns.current_user) do
      {:ok, post} ->
        {:noreply,
         assign(socket,
           posts: Content.list_posts(),
           show_form: true,
           editing_post: post,
           new_draft_id: post.id,
           revisions: [],
           form: to_form(Post.changeset(post, %{})),
           show_share_buttons: true,
           share_platforms: @default_platforms
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't start a new post")}
    end
  end

  def handle_event("edit_post", %{"id" => id}, socket) do
    post = Content.get_post!(id)
    changeset = Post.changeset(post, %{})
    
    {:noreply, assign(socket,
      show_form: true,
      editing_post: post,
      revisions: Bacon8.Content.Revisions.list(:post, post.id),
      form: to_form(changeset),
      show_share_buttons: Map.get(post, :show_share_buttons, true),
      share_platforms: Map.get(post, :share_platforms) || @default_platforms
    )}
  end

  # Puts an earlier version back; the editor is rebuilt (a new id) so it shows the restored body
  def handle_event("restore_revision", %{"id" => id}, socket) do
    post = socket.assigns.editing_post

    case post && Bacon8.Content.Revisions.restore(post, id, socket.assigns.current_user.id) do
      {:ok, restored} ->
        {:noreply,
         socket
         |> assign(
           editing_post: restored,
           form: to_form(Post.changeset(restored, %{})),
           revisions: Bacon8.Content.Revisions.list(:post, restored.id),
           editor_key: socket.assigns.editor_key + 1
         )
         |> put_flash(:info, "Earlier version restored")}

      _ ->
        {:noreply, put_flash(socket, :error, "That version is no longer there")}
    end
  end

  def handle_event("cancel_form", _params, socket) do
    # A draft nobody wrote anything in goes away, so "New post" then "Cancel" leaves nothing behind
    post = socket.assigns.editing_post

    if post && post.id == socket.assigns.new_draft_id && Content.untouched_draft?(Content.get_post!(post.id)),
      do: Content.delete_post(post)

    {:noreply, assign(socket,
      posts: Content.list_posts(),
      show_form: false,
      editing_post: nil,
      form: to_form(Post.changeset(%Post{}, %{}))
    )}
  end

  # The editor reports every change, and saves a draft's body now and then (ContentEditing.autosave/4);
  # the form's own hidden field carries the body on Save and Publish.
  def handle_event("editor-change", _params, socket), do: {:noreply, socket}

  def handle_event("editor-autosave", params, socket) do
    {:noreply, Bacon8Web.ContentEditing.autosave(socket, :post, :editing_post, params)}
  end

  # The block editor's media events (shared with the other editing screens)
  def handle_event(event, params, socket) when event in ["block-media-upload", "block-media-remove", "block-image-upload"] do
    context = Bacon8Web.ContentEditing.context(:post, socket.assigns.editing_post)
    {:noreply, Bacon8Web.ContentEditing.media(event, params, socket, context)}
  end

  def handle_event("validate", %{"post" => post_params}, socket) do
    post = socket.assigns.editing_post || %Post{}
    changeset = Post.changeset(post, post_params)
    
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end



  def handle_event("autosave_draft", %{"post" => post_params}, socket) do
    # Save as draft, but do not publish
    draft_params = Map.put(post_params, "is_published", false)
    case socket.assigns.editing_post do
      nil ->
        # Create new draft
        case Content.create_post(socket.assigns.current_user, draft_params) do
          {:ok, draft_post} ->
            {:noreply, assign(socket, editing_post: draft_post, form: to_form(Post.changeset(draft_post, %{})))}
          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
      post ->
        # Update existing draft
        case Content.update_post(post, draft_params) do
          {:ok, draft_post} ->
            {:noreply, assign(socket, editing_post: draft_post, form: to_form(Post.changeset(draft_post, %{})))}
          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
    end
  end

  def handle_event("save", %{"post" => post_params, "action_type" => action_type}, socket) do
    # Determine if we should publish based on the action_type
    should_publish = action_type == "publish"
    
    # Validate required fields if publishing
    if should_publish and (is_nil(post_params["title"]) or String.trim(post_params["title"]) == "" or 
       is_nil(post_params["content"]) or String.trim(post_params["content"]) == "") do
      {:noreply, put_flash(socket, :error, "Cannot publish: Post must have a title and content")}
    else
      # Process uploads first
      uploaded_files = consume_uploaded_entries(socket, :featured_image, fn %{path: path}, entry ->
        user = socket.assigns.current_user

        case Bacon8.Uploads.upload_file(user, path, entry, context: "blog") do
          {:ok, url_path} ->
            # Store in Media table and return the stored URL
            case Media.create_media(user, %{
              "filename" => Path.basename(url_path),
              "original_filename" => entry.client_name,
              "file_type" => "image",
              "mime_type" => entry.client_type,
              "file_size" => entry.client_size,
              "file_path" => Bacon8.Uploads.url_to_path(url_path),
              "url" => url_path,
              "usage_context" => "blog_featured"
            }) do
              {:ok, media} -> {:ok, media.url}
              {:error, _changeset} -> {:postpone, :error}
            end

          {:error, _reason} ->
            {:postpone, :error}
        end
      end)
      
      # Extract URLs from {:ok, url} tuples and reject errors
      uploaded_urls = uploaded_files
      |> Enum.filter(fn 
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, url} -> url end)
      
      # Process params and set publication status
      processed_params = 
        post_params
        |> process_post_params()
        |> maybe_add_featured_image(uploaded_urls)
        |> Map.put("is_published", should_publish)
        |> Map.put("show_share_buttons", socket.assigns.show_share_buttons)
        |> Map.put("share_platforms", socket.assigns.share_platforms)
      
      # Set published_at if publishing
      processed_params = if should_publish do
        Map.put_new(processed_params, "published_at", DateTime.utc_now())
      else
        processed_params
      end
      
      case socket.assigns.editing_post do
        nil ->
          # Create new post
          case Content.create_post(socket.assigns.current_user, processed_params) do
            {:ok, _post} ->
              posts = Content.list_posts()
              success_msg = if should_publish, do: "Post published successfully!", else: "Draft saved successfully!"
              {:noreply, assign(socket,
                posts: posts,
                show_form: false,
                editing_post: nil,
                form: to_form(Post.changeset(%Post{}, %{}))
              ) |> put_flash(:info, success_msg)}
            
            {:error, changeset} ->
              {:noreply, assign(socket, form: to_form(changeset))}
          end
        
        post ->
          # Update existing post
          case Content.update_post(post, Content.slug_for_save(:post, post, processed_params)) do
            {:ok, _post} ->
              posts = Content.list_posts()
              success_msg = if should_publish, do: "Post updated and published successfully!", else: "Draft updated successfully!"
              {:noreply, assign(socket,
                posts: posts,
                show_form: false,
                editing_post: nil,
                form: to_form(Post.changeset(%Post{}, %{}))
              ) |> put_flash(:info, success_msg)}
            
            {:error, changeset} ->
              {:noreply, assign(socket, form: to_form(changeset))}
          end
      end
    end
  end

  # Fallback for old save handler (in case action_type is missing)
  @impl true
  def handle_event("save", %{"post" => post_params}, socket) do
    # Default to draft if no action_type specified
    handle_event("save", %{"post" => post_params, "action_type" => "draft"}, socket)
  end

  @impl true
  def handle_event("delete_post", %{"id" => id}, socket) do
    post = Content.get_post!(id)
    
    case Content.delete_post(post) do
      {:ok, _post} ->
        # Delete uploaded files for this blog post
        Bacon8.Uploads.delete_content_uploads("blog", id)
        
        posts = Content.list_posts()
        {:noreply, assign(socket, posts: posts) |> put_flash(:info, "Post deleted successfully!")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete post")}
    end
  end

  @impl true
  def handle_event("toggle_publish", %{"id" => id}, socket) do
    post = Content.get_post!(id)
    new_published_status = !post.is_published
    
    # Validate post has required fields before publishing
    if new_published_status and (is_nil(post.title) or String.trim(post.title) == "" or is_nil(post.content) or String.trim(post.content) == "") do
      {:noreply, put_flash(socket, :error, "Cannot publish: Post must have a title and content")}
    else
      case Content.update_post(post, %{is_published: new_published_status}) do
        {:ok, _updated_post} ->
          posts = Content.list_posts()
          status_text = if new_published_status, do: "published", else: "unpublished"
          
          {:noreply, 
            socket
            |> assign(posts: posts)
            |> put_flash(:info, "Post #{status_text} successfully!")}
        
        {:error, changeset} ->
          error_msg = changeset.errors
            |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
            |> Enum.join(", ")
          
          {:noreply, put_flash(socket, :error, "Failed to update post: #{error_msg}")}
      end
    end
  end

  @impl true
  def handle_event("open_media_picker", _params, socket) do
    {:noreply, assign(socket, show_media_picker: true)}
  end

  # Handle toggle for share buttons visibility
  @impl true
  def handle_event("toggle_share_buttons", _params, socket) do
    {:noreply, assign(socket, show_share_buttons: !socket.assigns.show_share_buttons)}
  end

  # Handle toggle for individual share platforms
  @impl true
  def handle_event("toggle_share_platform", %{"platform" => platform}, socket) do
    current_platforms = socket.assigns.share_platforms
    
    new_platforms = if platform in current_platforms do
      List.delete(current_platforms, platform)
    else
      current_platforms ++ [platform]
    end
    
    {:noreply, assign(socket, share_platforms: new_platforms)}
  end

  # Catch-all handler for any client events we don't explicitly handle.
  # Some frontend hooks (window position, desktop widgets, etc.) emit events
  # that are intended for other LiveViews. If those arrive here, ignore them
  # instead of crashing the LiveView process.
  @impl true
  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:close_media_picker, socket) do
    {:noreply, assign(socket, show_media_picker: false)}
  end

  @impl true
  def handle_info({:media_selected, url, filename}, socket) do
    # Get current content from the form
    current_changeset = socket.assigns.form.source
    current_content = case current_changeset.changes[:content] do
      nil -> current_changeset.data.content || ""
      content -> content
    end
    
    # Create appropriate markdown based on file type
    media_markdown = if String.contains?(String.downcase(filename), [".jpg", ".jpeg", ".png", ".gif", ".webp"]) do
      "\n![#{filename}](#{url})\n"
    else
      "\n[#{filename}](#{url})\n"
    end
    
    new_content = current_content <> media_markdown
    
    # Update the changeset with the new content
    updated_changeset = Ecto.Changeset.put_change(current_changeset, :content, new_content)
    
    {:noreply, 
     socket
     |> assign(show_media_picker: false, form: to_form(updated_changeset))
     |> put_flash(:info, "Media inserted: #{filename}")}
  end

  # Helper function to process post parameters
  defp process_post_params(post_params) do
    params_with_tags = case Map.get(post_params, "tags") do
      nil -> post_params
      "" -> Map.put(post_params, "tags", [])
      tags_string when is_binary(tags_string) ->
        tags_list = 
          tags_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
        Map.put(post_params, "tags", tags_list)
      tags_list when is_list(tags_list) -> post_params
    end
    
    # Convert is_published string to boolean
    case Map.get(params_with_tags, "is_published") do
      "true" -> Map.put(params_with_tags, "is_published", true)
      "false" -> Map.put(params_with_tags, "is_published", false)
      true -> params_with_tags
      false -> params_with_tags
      nil -> Map.put(params_with_tags, "is_published", false)
      _ -> Map.put(params_with_tags, "is_published", false)
    end
  end

  defp maybe_add_featured_image(params, []), do: params
  defp maybe_add_featured_image(params, [url | _]), do: Map.put(params, "featured_image", url)

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/blog-management" current_user={@current_user}>
      <div class="max-w-6xl mx-auto">
          <div class="auth-glass-panel p-8 rounded-xl">
            <div class="flex justify-between items-center mb-8">
              <h1 class="text-3xl font-bold text-white">Blog Management</h1>
              <button phx-click="new_post" class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg transition-colors">
                ✍️ New Post
              </button>
            </div>

          <!-- Blog Post Form -->
          <%= if @show_form do %>
            <div class="glass-dark rounded-lg p-6 mb-8">
              <div class="flex justify-between items-center mb-4">
                <h2 class="text-xl font-semibold text-white">
                  <%= if @editing_post, do: "Edit Post", else: "Create New Post" %>
                </h2>
                <button phx-click="cancel_form" class="text-gray-400 hover:text-white">
                  ✕
                </button>
              </div>

              <.form for={@form} phx-submit="save" phx-change="validate" phx-debounce="500" id="blog-post-form" autocomplete="off" class="space-y-4"
                phx-hook="BlogAutosave">
                <style>
                  #blog-post-form input, #blog-post-form textarea, #blog-post-form select {
                    background-color: #374151 !important;
                    color: #ffffff !important;
                    border-color: #4b5563 !important;
                  }
                  #blog-post-form input:focus, #blog-post-form textarea:focus, #blog-post-form select:focus {
                    border-color: #3b82f6 !important;
                    box-shadow: 0 0 0 1px #3b82f6 !important;
                  }
                  #blog-post-form label {
                    color: #d1d5db !important;
                  }
                </style>
                
                <div>
                  <.input field={@form[:title]} label="Title" placeholder="Enter post title..." autocomplete="off" />
                </div>

                <div>
                  <.input field={@form[:slug]} label="Slug (URL)" placeholder="auto-generated-from-title" autocomplete="off" />
                </div>

                <div>
                  <.input field={@form[:excerpt]} type="textarea" label="Excerpt" placeholder="Brief description of the post..." rows="3" autocomplete="off" />
                </div>

                <div>
                  <div class="flex justify-between items-center mb-2">
                    <label class="text-sm font-medium text-gray-300">Content</label>
                    <button 
                      type="button"
                      phx-click="open_media_picker"
                      class="text-xs bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded transition-colors"
                    >
                      📷 Insert Media
                    </button>
                  </div>
                  
                  <BlockEditor.block_editor
                    id={"blog-post-editor-#{@editor_key}"}
                    value={Phoenix.HTML.Form.input_value(@form, :content)}
                    field={@form[:content]}
                    placeholder="Build your blog post content..."
                    min_height="500px"
                    autosave_delay={5000}
                  />
                  <%= for {msg, _} <- @form[:content].errors do %>
                    <.error><%= msg %></.error>
                  <% end %>
                </div>

                <div>
                  <.input field={@form[:meta_description]} label="Meta Description" placeholder="SEO description (max 160 characters)" autocomplete="off" />
                </div>

                <div>
                  <.input field={@form[:tags]} label="Tags" placeholder="tag1, tag2, tag3" autocomplete="off" />
                  <div class="text-xs text-gray-400 mt-1">Separate tags with commas</div>
                </div>

                <!-- Featured Image Upload -->
                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-2">Featured Image</label>
                  
                  <%= if @editing_post && @editing_post.featured_image && Enum.empty?(@uploads.featured_image.entries) do %>
                    <div class="mb-4">
                      <div class="relative inline-block">
                        <img src={@editing_post.featured_image} alt="Current featured image" class="max-w-xs rounded border-2 border-gray-600" />
                        <div class="text-xs text-gray-400 text-center mt-1">Current featured image</div>
                      </div>
                    </div>
                  <% end %>
                  
                  <div class="border-2 border-dashed border-gray-600 rounded-lg p-4 hover:border-blue-500 transition-colors"
                       phx-drop-target={@uploads.featured_image.ref}>
                    <.live_file_input upload={@uploads.featured_image} class="hidden" id="featured-image-upload" />
                    
                    <div class="text-center">
                      <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                        <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                      </svg>
                      <label for="featured-image-upload" class="cursor-pointer text-blue-500 hover:text-blue-400 text-sm">
                        <%= if @editing_post && @editing_post.featured_image, do: "Replace image", else: "Click to upload or drag and drop" %>
                      </label>
                      <p class="text-xs text-gray-500 mt-1">PNG, JPG, GIF up to 5MB</p>
                    </div>

                    <%= for entry <- @uploads.featured_image.entries do %>
                      <div class="mt-2">
                        <.live_img_preview entry={entry} class="max-w-xs rounded mx-auto" />
                        <div class="text-xs text-gray-400 text-center mt-1"><%= entry.client_name %></div>
                      </div>
                    <% end %>
                  </div>
                </div>

                <!-- Social Share Settings -->
                <div class="border border-gray-600 rounded-lg p-4">
                  <h3 class="text-sm font-medium text-gray-300 mb-4">Social Share Settings</h3>
                  <SocialShare.share_settings
                    show_share_buttons={@show_share_buttons}
                    share_platforms={@share_platforms}
                    on_toggle="toggle_share_buttons"
                    on_platform_toggle="toggle_share_platform"
                  />
                </div>

                <ContentExtras.schedule_input name="post[scheduled_at]" value={@form[:scheduled_at].value} />
                <ContentExtras.history revisions={@revisions} />

                <div class="mt-6">
                  <input type="hidden" name="action_type" value="draft" id="blog-action-type" />
                  
                  <div class="flex space-x-4">
                    <button 
                      type="submit"
                      onclick="document.getElementById('blog-action-type').value='draft'"
                      class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg transition-colors font-medium">
                      <%= if @editing_post, do: "Save Changes", else: "Save Draft" %>
                    </button>
                    <button 
                      type="submit"
                      onclick="document.getElementById('blog-action-type').value='publish'"
                      class="bg-green-600 hover:bg-green-700 text-white px-6 py-2 rounded-lg transition-colors font-medium">
                      <%= if @editing_post, do: "Update & Publish", else: "Publish Now" %>
                    </button>
                    <.link :if={@editing_post} id="preview-link" href={"/blog/#{@editing_post.slug}"} target="_blank" class="bg-gray-700 hover:bg-gray-600 text-white px-6 py-2 rounded-lg transition-colors font-medium" title="Opens the saved version; staff can see drafts, nobody else can">
                      Preview saved version
                    </.link>
                    <button type="button" phx-click="cancel_form" class="bg-gray-600 hover:bg-gray-700 text-white px-6 py-2 rounded-lg transition-colors font-medium">
                      Cancel
                    </button>
                  </div>
                  <div class="mt-2 text-xs text-gray-400">
                    Click "Save Draft" to save without publishing, or "Publish Now" to make the post publicly visible.
                  </div>
                </div>
              </.form>
            </div>
          <% end %>

          <!-- Posts List -->
          <div class="glass-dark rounded-lg overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-700">
              <h2 class="text-lg font-semibold text-white">All Posts (<%= length(@posts) %>)</h2>
            </div>

            <%= if @posts == [] do %>
              <div class="p-8 text-center text-gray-400">
                <div class="text-4xl mb-4">📝</div>
                <div class="text-lg mb-2">No posts yet</div>
                <div class="text-sm">Create your first blog post to get started!</div>
              </div>
            <% else %>
              <div class="divide-y divide-gray-700">
                <%= for post <- @posts do %>
                  <div class="p-6 hover:bg-gray-750 transition-colors">
                    <div class="flex justify-between items-start">
                      <div class="flex-1">
                        <div class="flex items-center space-x-3 mb-2">
                          <h3 class="text-lg font-medium text-white"><%= post.title %></h3>
                          <span class={["px-2 py-1 text-xs rounded-full",
                                       if post.is_published do
                                         "bg-green-600 text-white"
                                       else
                                         "bg-gray-600 text-gray-300"
                                       end]}>
                            <%= if post.is_published, do: "Published", else: "Draft" %>
                          </span>
                          <% missing_alt = Bacon8.Content.Audit.images_missing_alt(post.content) %>
                          <span :if={missing_alt > 0} class="alt-warning px-2 py-1 text-xs rounded-full bg-amber-600 text-white" title="Open the post and describe these pictures in the alt text field under each">
                            ⚠ <%= missing_alt %> <%= if missing_alt == 1, do: "image", else: "images" %> without alt text
                          </span>
                        </div>
                        
                        <div class="text-sm text-gray-400 mb-2">
                          By <%= post.user.name || post.user.email %> • 
                          <%= Calendar.strftime(post.inserted_at, "%B %d, %Y") %>
                          <%= if post.published_at do %>
                            • Published <%= Calendar.strftime(post.published_at, "%B %d, %Y") %>
                          <% end %>
                          <%= if post.scheduled_at && !post.is_published do %>
                            • <span class="text-blue-300">⏰ Goes live <%= Calendar.strftime(post.scheduled_at, "%b %d, %Y %H:%M") %> UTC</span>
                          <% end %>
                        </div>

                        <%= if post.excerpt do %>
                          <p class="text-gray-300 text-sm mb-3"><%= post.excerpt %></p>
                        <% end %>

                        <%= if post.tags && length(post.tags) > 0 do %>
                          <div class="flex flex-wrap gap-1 mb-3">
                            <%= for tag <- post.tags do %>
                              <span class="bg-blue-600 text-white px-2 py-1 text-xs rounded">
                                <%= tag %>
                              </span>
                            <% end %>
                          </div>
                        <% end %>

                        <div class="text-xs text-gray-500">
                          Slug: /<%= post.slug %>
                        </div>
                      </div>

                      <div class="flex space-x-2 ml-4">
                        <.link href={"/blog/#{post.slug}"} target="_blank" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1 text-sm rounded transition-colors">
                          <%= if post.is_published, do: "View", else: "Preview" %>
                        </.link>
                        <button type="button" phx-click="toggle_publish" phx-value-id={post.id}
                                class={["px-3 py-1 text-sm rounded transition-colors",
                                       if(post.is_published, do: "bg-orange-600 hover:bg-orange-700 text-white", else: "bg-green-600 hover:bg-green-700 text-white")]}>
                          <%= if post.is_published, do: "Unpublish", else: "Publish" %>
                        </button>
                        
                        <button type="button" phx-click="edit_post" phx-value-id={post.id}
                                class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 text-sm rounded transition-colors">
                          Edit
                        </button>
                        
                        <button type="button" phx-click="delete_post" phx-value-id={post.id}
                                data-confirm="Are you sure you want to delete this post?"
                                class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 text-sm rounded transition-colors">
                          Delete
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
          
          <!-- Media Picker Modal -->
          <%= if @show_media_picker do %>
            <.live_component 
              module={Bacon8Web.MediaPickerComponent} 
              id="media-picker" 
              current_user={@current_user}
            />
          <% end %>
          </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end