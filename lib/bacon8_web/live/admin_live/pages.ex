defmodule Bacon8Web.AdminLive.Pages do
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8.Content.Page
  alias Bacon8Web.Components.AdminSidebar
  alias Bacon8Web.Components.BlockEditor
  alias Bacon8Web.Components.SocialShare

  on_mount {Bacon8Web.UserAuth, {:require_area, :content}}

  @default_platforms ["twitter", "facebook", "linkedin", "reddit", "email"]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       pages: Content.list_pages(),
       page_title: "Pages",
       show_form: false,
       editing_page: nil,
       new_draft_id: nil,
       form: to_form(Page.changeset(%Page{}, %{})),
       show_share_buttons: true,
       share_platforms: @default_platforms,
       share_buttons_colored: false
     )}
  end

  # A new page starts as a saved draft, so the editor has a record to autosave to and to attach
  # uploads to (Bacon8.Content.create_draft/2).
  def handle_event("new_page", _params, socket) do
    case Content.create_draft(:page, socket.assigns.current_user) do
      {:ok, page} ->
        {:noreply,
         assign(socket,
           pages: Content.list_pages(),
           show_form: true,
           editing_page: page,
           new_draft_id: page.id,
           form: to_form(Page.changeset(page, %{})),
           show_share_buttons: true,
           share_platforms: @default_platforms,
           share_buttons_colored: false
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't start a new page")}
    end
  end

  def handle_event("edit_page", %{"id" => id}, socket) do
    page = Content.get_page!(id)
    {:noreply, assign(socket, 
      show_form: true, 
      editing_page: page, 
      form: to_form(Page.changeset(page, %{})),
      show_share_buttons: Map.get(page, :show_share_buttons, true),
      share_platforms: Map.get(page, :share_platforms) || @default_platforms,
      share_buttons_colored: Map.get(page, :share_buttons_colored, false)
    )}
  end

  def handle_event("cancel_form", _params, socket) do
    # A draft nobody wrote anything in goes away, so "New page" then "Cancel" leaves nothing behind
    page = socket.assigns.editing_page

    if page && page.id == socket.assigns.new_draft_id && Content.untouched_draft?(Content.get_page!(page.id)),
      do: Content.delete_page(page)

    {:noreply, assign(socket, pages: Content.list_pages(), show_form: false, editing_page: nil, form: to_form(Page.changeset(%Page{}, %{})))}
  end

  # The editor reports every change, and saves a draft's body now and then (ContentEditing.autosave/4);
  # the form's own hidden field carries the body on Save and Publish.
  def handle_event("editor-change", _params, socket), do: {:noreply, socket}

  def handle_event("editor-autosave", params, socket) do
    {:noreply, Bacon8Web.ContentEditing.autosave(socket, :page, :editing_page, params)}
  end

  # The block editor's media events (shared with the other editing screens)
  def handle_event(event, params, socket) when event in ["block-media-upload", "block-media-remove", "block-image-upload"] do
    context = Bacon8Web.ContentEditing.context(:page, socket.assigns.editing_page)
    {:noreply, Bacon8Web.ContentEditing.media(event, params, socket, context)}
  end

  def handle_event("validate", %{"page" => params}, socket) do
    changeset = (socket.assigns.editing_page || %Page{}) |> Page.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"page" => params, "action_type" => action_type}, socket) do
    should_publish = action_type == "publish"
    params = params 
             |> Map.put("is_published", should_publish)
             |> Map.put("published_at", if(should_publish, do: DateTime.utc_now(), else: nil))
             |> Map.put("show_share_buttons", socket.assigns.show_share_buttons)
             |> Map.put("share_platforms", socket.assigns.share_platforms)
             |> Map.put("share_buttons_colored", socket.assigns.share_buttons_colored)

    case socket.assigns.editing_page do
      nil ->
        case Content.create_page(params) do
          {:ok, page} ->
            {:noreply,
             socket
             |> assign(pages: Content.list_pages(), show_form: false, editing_page: nil, form: to_form(Page.changeset(%Page{}, %{})))
             |> put_flash(:info, if(should_publish, do: "Page '#{page.title}' published successfully!", else: "Draft '#{page.title}' saved"))}
          {:error, ch} -> 
            {:noreply, assign(socket, form: to_form(ch)) |> put_flash(:error, "Failed to save page")}
        end
      page ->
        case Content.update_page(page, Content.slug_for_save(:page, page, params)) do
          {:ok, updated_page} ->
            {:noreply,
             socket
             |> assign(pages: Content.list_pages(), show_form: false, editing_page: nil, form: to_form(Page.changeset(%Page{}, %{})))
             |> put_flash(:info, if(should_publish, do: "Page '#{updated_page.title}' updated & published!", else: "Draft '#{updated_page.title}' updated"))}
          {:error, ch} -> 
            {:noreply, assign(socket, form: to_form(ch)) |> put_flash(:error, "Failed to update page")}
        end
    end
  end

  def handle_event("delete_page", %{"id" => id}, socket) do
    page = Content.get_page!(id)
    case Content.delete_page(page) do
      {:ok, _} -> 
        # Delete uploaded files for this page
        Bacon8.Uploads.delete_content_uploads("pages", id)
        
        {:noreply, assign(socket, pages: Content.list_pages()) |> put_flash(:info, "Page deleted")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete page")}
    end
  end

  def handle_event("toggle_publish", %{"id" => id}, socket) do
    page = Content.get_page!(id)
    case Content.update_page(page, %{is_published: !page.is_published}) do
      {:ok, _} -> {:noreply, assign(socket, pages: Content.list_pages())}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update publish status")}
    end
  end

  # Handle toggle for share buttons visibility
  def handle_event("toggle_share_buttons", _params, socket) do
    {:noreply, assign(socket, show_share_buttons: !socket.assigns.show_share_buttons)}
  end

  # Handle toggle for colored share buttons
  def handle_event("toggle_share_colored", _params, socket) do
    {:noreply, assign(socket, share_buttons_colored: !socket.assigns.share_buttons_colored)}
  end

  # Handle toggle for individual share platforms
  def handle_event("toggle_share_platform", %{"platform" => platform}, socket) do
    current_platforms = socket.assigns.share_platforms
    
    new_platforms = if platform in current_platforms do
      List.delete(current_platforms, platform)
    else
      current_platforms ++ [platform]
    end
    
    {:noreply, assign(socket, share_platforms: new_platforms)}
  end

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/pages" current_user={@current_user}>
      <div class="max-w-6xl mx-auto">
          <div class="auth-glass-panel p-8 rounded-xl">
            <div class="flex justify-between items-center mb-8">
              <h1 class="text-3xl font-bold text-white">Pages</h1>
              <button phx-click="new_page" class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg transition-colors">➕ New Page</button>
            </div>

            <%= if @show_form do %>
              <.form for={@form} phx-submit="save" phx-change="validate" id="page-form" autocomplete="off" class="space-y-6">
                <!-- Basic Info Section -->
                <div class="glass-dark p-6 rounded-lg space-y-4">
                  <h3 class="text-lg font-semibold text-white mb-4">Basic Information</h3>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <.input field={@form[:title]} label="Title" placeholder="Enter page title..." autocomplete="off" />
                    </div>
                    <div>
                      <.input field={@form[:slug]} label="Slug (URL)" placeholder="auto-generated-from-title" autocomplete="off" />
                    </div>
                  </div>
                  <div>
                    <.input field={@form[:excerpt]} type="textarea" label="Excerpt (Optional)" placeholder="Short summary (max 500 chars)" rows="2" autocomplete="off" />
                  </div>
                </div>

                <!-- Content Section -->
                <div class="glass-dark p-6 rounded-lg space-y-4">
                  <h3 class="text-lg font-semibold text-white mb-4">Content</h3>
                  <BlockEditor.block_editor
                    id="page-content-editor"
                    value={Phoenix.HTML.Form.input_value(@form, :content)}
                    field={@form[:content]}
                    placeholder="Build your page content..."
                    min_height="500px"
                    autosave_delay={5000}
                  />
                  <%= for {msg, _} <- @form[:content].errors do %>
                    <.error><%= msg %></.error>
                  <% end %>
                </div>

                <!-- Layout & Design Section -->
                <div class="glass-dark p-6 rounded-lg space-y-4">
                  <h3 class="text-lg font-semibold text-white mb-4">Layout & Design</h3>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <.input field={@form[:template_type]} type="select" label="Template" options={[
                        {"Default", "default"},
                        {"Landing Page", "landing"},
                        {"Full Width", "full-width"},
                        {"With Sidebar", "sidebar"},
                        {"Custom", "custom"}
                      ]} />
                    </div>
                    <div>
                      <.input field={@form[:category]} label="Category (Optional)" placeholder="e.g., About, Legal, Help" autocomplete="off" />
                    </div>
                  </div>
                  <div>
                    <.input field={@form[:featured_image]} label="Featured Image URL (Optional)" placeholder="https://example.com/image.jpg" autocomplete="off" />
                  </div>
                  <div>
                    <.input field={@form[:order]} type="number" label="Order (for navigation sorting)" placeholder="0" />
                  </div>
                </div>

                <!-- SEO Section -->
                <div class="glass-dark p-6 rounded-lg space-y-4">
                  <h3 class="text-lg font-semibold text-white mb-4">SEO Settings</h3>
                  <div>
                    <.input field={@form[:meta_description]} label="Meta Description" placeholder="SEO description (max 160 characters)" autocomplete="off" />
                  </div>
                  <div>
                    <.input field={@form[:meta_keywords]} label="Meta Keywords (Optional)" placeholder="keyword1, keyword2, keyword3" autocomplete="off" />
                  </div>
                </div>

                <!-- Social Share Settings Section -->
                <div class="glass-dark p-6 rounded-lg space-y-4">
                  <h3 class="text-lg font-semibold text-white mb-4">Social Share Settings</h3>
                  <SocialShare.share_settings
                    show_share_buttons={@show_share_buttons}
                    share_platforms={@share_platforms}
                    share_buttons_colored={@share_buttons_colored}
                    on_toggle="toggle_share_buttons"
                    on_platform_toggle="toggle_share_platform"
                    on_colored_toggle="toggle_share_colored"
                  />
                </div>

                <input type="hidden" name="action_type" value="draft" id="page-action-type" />
                <div class="flex space-x-4">
                  <button type="submit" onclick="document.getElementById('page-action-type').value='draft'" class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg transition-colors font-medium">💾 Save Draft</button>
                  <button type="submit" onclick="document.getElementById('page-action-type').value='publish'" class="bg-green-600 hover:bg-green-700 text-white px-6 py-2 rounded-lg transition-colors font-medium">🚀 Publish</button>
                  <button type="button" phx-click="cancel_form" class="bg-gray-600 hover:bg-gray-700 text-white px-6 py-2 rounded-lg transition-colors font-medium">✖ Cancel</button>
                </div>
              </.form>
            <% end %>

            <div class="glass-dark rounded-lg overflow-hidden mt-6">
              <div class="px-6 py-4 border-b border-gray-700">
                <h2 class="text-lg font-semibold text-white">All Pages (<%= length(@pages) %>)</h2>
              </div>
              <%= if @pages == [] do %>
                <div class="p-8 text-center text-gray-400">No pages yet</div>
              <% else %>
                <div class="divide-y divide-gray-700">
                  <%= for page <- @pages do %>
                    <div class="p-6 hover:bg-gray-750 transition-colors">
                      <div class="flex items-start justify-between">
                        <div class="flex-1 min-w-0">
                          <!-- Title & Status -->
                          <div class="flex items-center space-x-3 mb-2">
                            <h3 class="text-lg font-medium text-white truncate"><%= page.title %></h3>
                            <span class={["px-2 py-1 text-xs rounded-full", if(page.is_published, do: "bg-green-600 text-white", else: "bg-gray-600 text-gray-300")]}>
                              <%= if page.is_published, do: "✓ Published", else: "📝 Draft" %>
                            </span>
                            <%= if page.template_type != "default" do %>
                              <span class="px-2 py-1 text-xs rounded-full bg-purple-600 text-white">
                                <%= String.capitalize(page.template_type) %>
                              </span>
                            <% end %>
                            <%= if page.category do %>
                              <span class="px-2 py-1 text-xs rounded-full bg-blue-600 text-white">
                                <%= page.category %>
                              </span>
                            <% end %>
                          </div>
                          
                          <!-- Excerpt -->
                          <%= if page.excerpt do %>
                            <p class="text-sm text-gray-400 mb-2 line-clamp-2"><%= page.excerpt %></p>
                          <% end %>
                          
                          <!-- Meta Info -->
                          <div class="flex items-center space-x-4 text-xs text-gray-500">
                            <div>Slug: /<%= page.slug %></div>
                            <%= if page.published_at do %>
                              <div>Published: <%= Calendar.strftime(page.published_at, "%b %d, %Y") %></div>
                            <% end %>
                            <%= if page.order != 0 do %>
                              <div>Order: <%= page.order %></div>
                            <% end %>
                            <div>Updated: <%= Calendar.strftime(page.updated_at, "%b %d, %Y") %></div>
                          </div>
                        </div>
                        
                        <!-- Actions -->
                        <div class="flex space-x-2 ml-4">
                          <.link href={"/pages/#{page.slug}"} target="_blank" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1 text-sm rounded transition-colors">
                            👁 View
                          </.link>
                          <button type="button" phx-click="toggle_publish" phx-value-id={page.id} class={["px-3 py-1 text-sm rounded transition-colors", if(page.is_published, do: "bg-orange-600 hover:bg-orange-700 text-white", else: "bg-green-600 hover:bg-green-700 text-white")]}>
                            <%= if page.is_published, do: "📤 Unpublish", else: "🚀 Publish" %>
                          </button>
                          <button type="button" phx-click="edit_page" phx-value-id={page.id} class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 text-sm rounded transition-colors">
                            ✏️ Edit
                          </button>
                          <button type="button" phx-click="delete_page" phx-value-id={page.id} data-confirm="Delete this page?" class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 text-sm rounded transition-colors">
                            🗑 Delete
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
