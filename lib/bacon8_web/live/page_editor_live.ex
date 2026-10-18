defmodule Bacon8Web.PageEditorLive do
  @moduledoc """
  Real-time page editor with block-based WYSIWYG functionality.
  Only accessible by admins, GMs, and editors.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8.Content.Page
  alias Bacon8Web.Components.BlockEditor

  on_mount {Bacon8Web.UserAuth, :ensure_authenticated}

  @allowed_roles ["admin", "gm", "editor"]
  @template_types [
    {"Default", "default"},
    {"Landing Page", "landing"},
    {"Full Width", "full-width"},
    {"With Sidebar", "sidebar"},
    {"Custom", "custom"}
  ]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    
    # Check if user has permission to edit content
    if user.role in @allowed_roles or Map.get(user, :is_admin, false) do
      {:ok,
       assign(socket,
         page_title: "Page Editor",
         pages: Content.list_pages(),
         editing_page: nil,
         form: nil,
         view: :list,
         saving: false,
         last_saved: nil,
         template_types: @template_types,
         pending_content: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to access the page editor.")
       |> redirect(to: ~p"/")}
    end
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    page = Content.get_page!(id)
    changeset = Page.changeset(page, %{})
    
    {:noreply,
     assign(socket,
       page_title: "Edit: #{page.title}",
       editing_page: page,
       form: to_form(changeset),
       view: :edit
     )}
  end

  def handle_params(%{"action" => "new"}, _uri, socket) do
    user = socket.assigns.current_user
    changeset = Page.changeset(%Page{author_id: user.id}, %{})
    
    {:noreply,
     assign(socket,
       page_title: "New Page",
       editing_page: %Page{author_id: user.id},
       form: to_form(changeset),
       view: :new
     )}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       page_title: "Page Editor",
       pages: Content.list_pages(),
       editing_page: nil,
       form: nil,
       view: :list
     )}
  end

  # Handle form validation
  def handle_event("validate", %{"page" => page_params}, socket) do
    changeset =
      (socket.assigns.editing_page || %Page{})
      |> Page.changeset(page_params)
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
    save_page_content(socket, content)
  end

  # Handle manual save
  def handle_event("save_page", %{"page" => page_params}, socket) do
    socket = assign(socket, saving: true)
    
    # Use pending_content if available (from editor-change events)
    page_params = 
      if socket.assigns[:pending_content] do
        Map.put(page_params, "content", socket.assigns.pending_content)
      else
        page_params
      end
    
    case socket.assigns.view do
      :new ->
        user = socket.assigns.current_user
        page_params = Map.put(page_params, "author_id", user.id)
        
        case Content.create_page(page_params) do
          {:ok, page} ->
            {:noreply,
             socket
             |> assign(saving: false, last_saved: DateTime.utc_now())
             |> put_flash(:info, "Page created successfully!")
             |> push_navigate(to: ~p"/admin/pages/#{page.id}")}
          
          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(saving: false, form: to_form(changeset))
             |> put_flash(:error, "Failed to create page.")}
        end
      
      :edit ->
        case Content.update_page(socket.assigns.editing_page, page_params) do
          {:ok, page} ->
            {:noreply,
             socket
             |> assign(saving: false, editing_page: page, last_saved: DateTime.utc_now())
             |> put_flash(:info, "Page saved successfully!")}
          
          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(saving: false, form: to_form(changeset))
             |> put_flash(:error, "Failed to save page.")}
        end
      
      _ ->
        {:noreply, assign(socket, saving: false)}
    end
  end

  # Save as draft
  def handle_event("save_draft", %{"page" => page_params}, socket) do
    page_params = Map.put(page_params, "is_published", false)
    handle_event("save_page", %{"page" => page_params}, socket)
  end

  # Publish page
  def handle_event("publish", %{"page" => page_params}, socket) do
    page_params = 
      page_params
      |> Map.put("is_published", true)
      |> Map.put("published_at", DateTime.utc_now())
    
    handle_event("save_page", %{"page" => page_params}, socket)
  end

  # Unpublish page
  def handle_event("unpublish", _params, socket) do
    case Content.update_page(socket.assigns.editing_page, %{is_published: false}) do
      {:ok, page} ->
        changeset = Page.changeset(page, %{})
        {:noreply,
         socket
         |> assign(editing_page: page, form: to_form(changeset))
         |> put_flash(:info, "Page unpublished.")}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unpublish page.")}
    end
  end

  # Delete page
  def handle_event("delete_page", %{"id" => id}, socket) do
    page = Content.get_page!(id)
    
    case Content.delete_page(page) do
      {:ok, _} ->
        # Delete uploaded files for this page
        Bacon8.Uploads.delete_content_uploads("pages", id)
        
        {:noreply,
         socket
         |> assign(pages: Content.list_pages())
         |> put_flash(:info, "Page deleted.")
         |> push_navigate(to: ~p"/admin/pages")}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete page.")}
    end
  end

  # Navigate back to list
  def handle_event("back_to_list", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/pages")}
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
    # For new pages without an ID, we need to save the page first
    page = socket.assigns.editing_page
    
    # If it's a new page without an ID, save it first
    {socket, page} = 
      if page.id == nil do
        user = socket.assigns.current_user
        case Content.create_page(%{
          title: "Untitled Page",
          content: "",
          author_id: user.id,
          is_published: false
        }) do
          {:ok, new_page} ->
            changeset = Page.changeset(new_page, %{})
            {assign(socket, editing_page: new_page, form: to_form(changeset), view: :edit), new_page}
          {:error, _} ->
            {socket, page}
        end
      else
        {socket, page}
      end
    
    if page.id == nil do
      {:noreply, push_event(socket, "block-media-error", %{
        blockId: block_id,
        error: "Please save the page first before uploading media"
      })}
    else
      filename = params["filename"] || "upload_#{System.unique_integer([:positive])}"
      mime_type = params["mimeType"] || "application/octet-stream"
      file_size = params["size"] || 0
      original_filename = params["filename"] || filename
      
      # Use page ID for the upload path: /uploads/public/pages/{page_id}/
      upload_context = "pages/#{page.id}"
      
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

  defp save_page_content(socket, html) do
    case socket.assigns.view do
      :edit ->
        page = socket.assigns.editing_page
        case Content.update_page(page, %{content: html}) do
          {:ok, updated_page} ->
            {:noreply, assign(socket, editing_page: updated_page, last_saved: DateTime.utc_now())}
          
          {:error, _} ->
            {:noreply, socket}
        end
      
      _ ->
        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-indigo-900">
      <!-- Header -->
      <div class="bg-black/50 border-b border-gray-700 sticky top-0 z-50">
        <div class="container mx-auto px-4">
          <div class="flex items-center justify-between h-14">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/games"} class="text-gray-400 hover:text-white">
                ← Back to World
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
              <h2 class="text-2xl font-bold text-white">Manage Pages</h2>
              <.link navigate={~p"/admin/pages?action=new"} class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg">
                + New Page
              </.link>
            </div>
            
            <div class="bg-white/10 backdrop-blur-sm rounded-xl overflow-hidden">
              <table class="w-full">
                <thead class="bg-black/30">
                  <tr>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Title</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Slug</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Template</th>
                    <th class="text-left text-gray-300 px-4 py-3 text-sm font-medium">Status</th>
                    <th class="text-right text-gray-300 px-4 py-3 text-sm font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for page <- @pages do %>
                    <tr class="hover:bg-white/5">
                      <td class="px-4 py-3">
                        <.link navigate={~p"/admin/pages/#{page.id}"} class="text-white hover:text-blue-400 font-medium">
                          <%= page.title || "(Untitled)" %>
                        </.link>
                      </td>
                      <td class="px-4 py-3 text-gray-400 text-sm">
                        /<%= page.slug %>
                      </td>
                      <td class="px-4 py-3 text-gray-400 text-sm">
                        <%= page.template_type || "default" %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if page.is_published do %>
                          <span class="inline-block px-2 py-1 bg-green-600/50 text-green-200 text-xs rounded">Published</span>
                        <% else %>
                          <span class="inline-block px-2 py-1 bg-yellow-600/50 text-yellow-200 text-xs rounded">Draft</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-right">
                        <.link navigate={~p"/admin/pages/#{page.id}"} class="text-blue-400 hover:text-blue-300 text-sm mr-3">
                          Edit
                        </.link>
                        <%= if page.is_published do %>
                          <.link navigate={~p"/pages/#{page.slug}"} target="_blank" class="text-gray-400 hover:text-gray-300 text-sm mr-3">
                            View
                          </.link>
                        <% end %>
                        <button 
                          phx-click="delete_page" 
                          phx-value-id={page.id}
                          data-confirm="Are you sure you want to delete this page?"
                          class="text-red-400 hover:text-red-300 text-sm"
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
              
              <%= if @pages == [] do %>
                <div class="text-center text-gray-400 py-12">
                  <p class="mb-4">No pages yet.</p>
                  <.link navigate={~p"/admin/pages?action=new"} class="text-blue-400 hover:text-blue-300">
                    Create your first page →
                  </.link>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Edit/New View -->
        <%= if @view in [:edit, :new] do %>
          <div class="max-w-6xl mx-auto">
            <.form for={@form} phx-change="validate" phx-submit="save_page" class="space-y-6">
              <!-- Top Controls -->
              <div class="flex items-center justify-between bg-white/10 backdrop-blur-sm rounded-xl p-4">
                <button type="button" phx-click="back_to_list" class="text-gray-400 hover:text-white">
                  ← Back to List
                </button>
                
                <div class="flex items-center gap-3">
                  <%= if @view == :edit && @editing_page.is_published do %>
                    <button type="button" phx-click="unpublish" class="bg-yellow-600 hover:bg-yellow-700 text-white px-4 py-2 rounded-lg text-sm">
                      Unpublish
                    </button>
                  <% end %>
                  
                  <button type="submit" name="action" value="draft" phx-disable-with="Saving..." class="bg-gray-600 hover:bg-gray-700 text-white px-4 py-2 rounded-lg text-sm">
                    Save Draft
                  </button>
                  
                  <button type="submit" name="action" value="publish" phx-disable-with="Publishing..." class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm">
                    <%= if @view == :edit && @editing_page.is_published, do: "Update", else: "Publish" %>
                  </button>
                </div>
              </div>

              <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <!-- Main Editor -->
                <div class="lg:col-span-2 space-y-6">
                  <!-- Title -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Page Title</label>
                    <input 
                      type="text" 
                      name="page[title]" 
                      value={@form[:title].value}
                      placeholder="Enter page title..."
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-3 text-white text-xl placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <%= if @form[:title].errors != [] do %>
                      <p class="mt-1 text-sm text-red-400"><%= Enum.join(Enum.map(@form[:title].errors, fn {msg, _} -> msg end), ", ") %></p>
                    <% end %>
                  </div>

                  <!-- Content Editor -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Content</label>
                    <input type="hidden" name="page[content]" id="page-content-hidden" value={@form[:content].value || ""} />
                    <BlockEditor.block_editor
                      id="page-content"
                      value={@form[:content].value || ""}
                      placeholder="Build your page content..."
                      autosave_delay={5000}
                    />
                  </div>
                </div>

                <!-- Sidebar -->
                <div class="space-y-6">
                  <!-- Slug -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">URL Slug</label>
                    <input 
                      type="text" 
                      name="page[slug]" 
                      value={@form[:slug].value}
                      placeholder="auto-generated-from-title"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <p class="mt-1 text-xs text-gray-500">Leave blank to auto-generate from title</p>
                  </div>

                  <!-- Template Type -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Template</label>
                    <select 
                      name="page[template_type]"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    >
                      <%= for {label, value} <- @template_types do %>
                        <option value={value} selected={@form[:template_type].value == value}><%= label %></option>
                      <% end %>
                    </select>
                  </div>

                  <!-- Category -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Category</label>
                    <input 
                      type="text" 
                      name="page[category]" 
                      value={@form[:category].value}
                      placeholder="e.g., About, Services, Contact"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                  </div>

                  <!-- Excerpt -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Excerpt</label>
                    <textarea 
                      name="page[excerpt]"
                      rows="3"
                      placeholder="Brief summary of the page..."
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
                    ><%= @form[:excerpt].value %></textarea>
                  </div>

                  <!-- Featured Image -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Featured Image URL</label>
                    <input 
                      type="text" 
                      name="page[featured_image]" 
                      value={@form[:featured_image].value}
                      placeholder="/uploads/image.jpg or https://..."
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <%= if @form[:featured_image].value && @form[:featured_image].value != "" do %>
                      <img src={@form[:featured_image].value} alt="Preview" class="mt-3 rounded-lg max-h-32 object-cover" />
                    <% end %>
                  </div>

                  <!-- Meta Description -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Meta Description</label>
                    <textarea 
                      name="page[meta_description]"
                      rows="2"
                      maxlength="160"
                      placeholder="SEO description (max 160 chars)"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
                    ><%= @form[:meta_description].value %></textarea>
                    <p class="mt-1 text-xs text-gray-500">
                      <%= String.length(@form[:meta_description].value || "") %>/160 characters
                    </p>
                  </div>

                  <!-- Meta Keywords -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Meta Keywords</label>
                    <input 
                      type="text" 
                      name="page[meta_keywords]" 
                      value={@form[:meta_keywords].value}
                      placeholder="keyword1, keyword2, keyword3"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <p class="mt-1 text-xs text-gray-500">Comma-separated</p>
                  </div>

                  <!-- Display Order -->
                  <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                    <label class="block text-sm font-medium text-gray-300 mb-2">Display Order</label>
                    <input 
                      type="number" 
                      name="page[order]" 
                      value={@form[:order].value || 0}
                      min="0"
                      class="w-full bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm placeholder-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <p class="mt-1 text-xs text-gray-500">Lower numbers appear first</p>
                  </div>

                  <!-- Page Info (for existing pages) -->
                  <%= if @view == :edit && @editing_page do %>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6">
                      <h3 class="text-sm font-medium text-gray-300 mb-3">Page Info</h3>
                      <dl class="space-y-2 text-sm">
                        <div class="flex justify-between">
                          <dt class="text-gray-500">Created</dt>
                          <dd class="text-gray-300"><%= Calendar.strftime(@editing_page.inserted_at, "%b %d, %Y") %></dd>
                        </div>
                        <%= if @editing_page.published_at do %>
                          <div class="flex justify-between">
                            <dt class="text-gray-500">Published</dt>
                            <dd class="text-gray-300"><%= Calendar.strftime(@editing_page.published_at, "%b %d, %Y") %></dd>
                          </div>
                        <% end %>
                        <div class="flex justify-between">
                          <dt class="text-gray-500">Status</dt>
                          <dd>
                            <%= if @editing_page.is_published do %>
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
