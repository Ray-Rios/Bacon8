defmodule Bacon8Web.PageLive do
  @moduledoc """
  A page at `/pages/:slug`. Staff edit it right here (`Bacon8Web.InPlaceEditing`): "Edit Page"
  opens the block editor and the settings panel; `?edit=1` opens them straight away.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8Web.Components.BlockEditor
  alias Bacon8Web.Components.ContentSettings
  alias Bacon8Web.Components.SocialShare
  alias Bacon8Web.InPlaceEditing

  # Note: on_mount :default is handled by router's live_session

  @editing_events InPlaceEditing.events()

  def mount(%{"slug" => slug} = params, _session, socket) do
    page = Content.get_page_by_slug(slug)

    # Drafts are for staff (admins, GMs and editors: whoever may edit the page)
    if page && (page.is_published or InPlaceEditing.can_edit?(socket.assigns)) do
      {:ok,
       socket
       |> assign(Bacon8Web.Seo.for_page(page))
       |> assign(page: page, page_title: page.title)
       |> InPlaceEditing.init(:page, page, params["edit"] == "1")}
    else
      {:ok, socket |> put_flash(:error, "Page not found") |> push_navigate(to: "/")}
    end
  end

  defp can_edit?(assigns), do: InPlaceEditing.can_edit?(assigns)

  # Everything about editing (settings, saving, publishing, pictures, versions) is in one place
  def handle_event(event, params, socket) when event in @editing_events,
    do: InPlaceEditing.handle(event, params, socket, :page)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

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
                  value={@pending_title || @page.title}
                  phx-blur="update_title"
                  phx-keyup="update_title"
                  phx-key="Enter"
                  class="text-4xl font-bold text-white bg-transparent border-b-2 border-blue-500 focus:outline-none focus:border-blue-400 w-full"
                  placeholder="Page title..."
                />
              <% else %>
                <h1 class="text-4xl font-bold text-white"><%= @page.title %></h1>
              <% end %>

              <ContentSettings.toolbar :if={can_edit?(assigns)} kind={:page} record={@page} editing={@editing} saving={@saving} last_saved={@last_saved} dirty={InPlaceEditing.dirty?(assigns)} />
            </div>

            <ContentSettings.settings :if={@editing && @form} kind={:page} record={@page} form={@form} revisions={@revisions} uploads={@uploads} featured_library={@featured_library} />

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
