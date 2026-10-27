defmodule Bacon8Web.AdminLive.Pages do
  @moduledoc """
  The list of pages: browse, start a new one, publish or unpublish, schedule, delete. Editing a page
  happens on the page itself (`Bacon8Web.InPlaceEditing`); "Edit" and "New page" open it there.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8Web.Components.AdminSidebar
  alias Bacon8Web.Components.ContentExtras

  on_mount {Bacon8Web.UserAuth, {:require_area, :content}}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, pages: Content.list_pages(), page_title: "Pages")}
  end

  # A new page starts as a saved draft, so the editor has a record to autosave to and to attach
  # uploads to (Bacon8.Content.create_draft/2), and opens on the page itself.
  def handle_event("new_page", _params, socket) do
    case Content.create_draft(:page, socket.assigns.current_user) do
      {:ok, page} -> {:noreply, push_navigate(socket, to: "/pages/#{page.slug}?edit=1")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't start a new page")}
    end
  end

  def handle_event("delete_page", %{"id" => id}, socket) do
    with {:ok, page} <- fetch(id),
         {:ok, _} <- Content.delete_page(page) do
      # Delete uploaded files for this page
      Bacon8.Uploads.delete_content_uploads("pages", page.id)
      {:noreply, socket |> assign(pages: Content.list_pages()) |> put_flash(:info, "Page deleted")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to delete page")}
    end
  end

  def handle_event("toggle_publish", %{"id" => id}, socket) do
    with {:ok, page} <- fetch(id),
         {:ok, _} <- Content.update_page(page, %{is_published: !page.is_published}) do
      {:noreply, assign(socket, pages: Content.list_pages())}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to update publish status")}
    end
  end

  def handle_event("set_schedule", %{"record_id" => id, "scheduled_at" => value}, socket) do
    with {:ok, page} <- fetch(id) do
      case Content.schedule(page, value) do
        {:ok, _} -> {:noreply, socket |> assign(pages: Content.list_pages()) |> put_flash(:info, "Schedule saved")}
        {:error, :past} -> {:noreply, put_flash(socket, :error, "That time has passed. Use Publish to publish now.")}
        {:error, :published} -> {:noreply, put_flash(socket, :error, "It is published already")}
        _ -> {:noreply, put_flash(socket, :error, "That isn't a time")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "That page is gone")}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp fetch(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id), %Content.Page{} = page <- Bacon8.Repo.get(Content.Page, uuid) do
      {:ok, page}
    else
      _ -> :error
    end
  end

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/pages" current_user={@current_user}>
      <div class="max-w-6xl mx-auto">
        <div class="auth-glass-panel p-8 rounded-xl">
          <div class="flex justify-between items-center mb-8">
            <h1 class="text-3xl font-bold text-white">Pages</h1>
            <button phx-click="new_page" id="new-page" class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg transition-colors">➕ New Page</button>
          </div>

          <div class="glass-dark rounded-lg overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-700">
              <h2 class="text-lg font-semibold text-white">All Pages (<%= length(@pages) %>)</h2>
            </div>
            <%= if @pages == [] do %>
              <div class="p-8 text-center text-gray-400">No pages yet</div>
            <% else %>
              <div class="divide-y divide-gray-700">
                <div :for={page <- @pages} id={"page-#{page.id}"} class="p-6 hover:bg-gray-750 transition-colors">
                  <div class="flex items-start justify-between">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center flex-wrap gap-2 mb-2">
                        <h3 class="text-lg font-medium text-white truncate"><%= page.title %></h3>
                        <span class={["px-2 py-1 text-xs rounded-full", if(page.is_published, do: "bg-green-600 text-white", else: "bg-gray-600 text-gray-300")]}>
                          <%= if page.is_published, do: "✓ Published", else: "📝 Draft" %>
                        </span>
                        <span :if={page.scheduled_at && !page.is_published} class="px-2 py-1 text-xs rounded-full bg-blue-600 text-white">
                          ⏰ Goes live <%= Calendar.strftime(page.scheduled_at, "%b %d, %Y %H:%M") %> UTC
                        </span>
                        <% missing_alt = Bacon8.Content.Audit.images_missing_alt(page.content) %>
                        <span :if={missing_alt > 0} class="alt-warning px-2 py-1 text-xs rounded-full bg-amber-600 text-white" title="Open the page and describe these pictures in the alt text field under each">
                          ⚠ <%= missing_alt %> <%= if missing_alt == 1, do: "image", else: "images" %> without alt text
                        </span>
                        <span :if={page.template_type != "default"} class="px-2 py-1 text-xs rounded-full bg-purple-600 text-white">
                          <%= String.capitalize(page.template_type) %>
                        </span>
                        <span :if={page.category} class="px-2 py-1 text-xs rounded-full bg-blue-600 text-white"><%= page.category %></span>
                      </div>

                      <p :if={page.excerpt} class="text-sm text-gray-400 mb-2 line-clamp-2"><%= page.excerpt %></p>

                      <div class="flex items-center space-x-4 text-xs text-gray-500">
                        <div>Slug: /<%= page.slug %></div>
                        <div :if={page.published_at}>Published: <%= Calendar.strftime(page.published_at, "%b %d, %Y") %></div>
                        <div :if={page.order != 0}>Order: <%= page.order %></div>
                        <div>Updated: <%= Calendar.strftime(page.updated_at, "%b %d, %Y") %></div>
                      </div>

                      <ContentExtras.schedule_row :if={!page.is_published} id={page.id} value={page.scheduled_at} />
                    </div>

                    <div class="flex space-x-2 ml-4">
                      <.link href={"/pages/#{page.slug}"} target="_blank" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1 text-sm rounded transition-colors">
                        <%= if page.is_published, do: "👁 View", else: "👁 Preview" %>
                      </.link>
                      <button type="button" phx-click="toggle_publish" phx-value-id={page.id} class={["px-3 py-1 text-sm rounded transition-colors", if(page.is_published, do: "bg-orange-600 hover:bg-orange-700 text-white", else: "bg-green-600 hover:bg-green-700 text-white")]}>
                        <%= if page.is_published, do: "📤 Unpublish", else: "🚀 Publish" %>
                      </button>
                      <.link navigate={"/pages/#{page.slug}?edit=1"} class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 text-sm rounded transition-colors">
                        ✏️ Edit
                      </.link>
                      <button type="button" phx-click="delete_page" phx-value-id={page.id} data-confirm="Delete this page?" class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 text-sm rounded transition-colors">
                        🗑 Delete
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
