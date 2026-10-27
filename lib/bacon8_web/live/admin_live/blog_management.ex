defmodule Bacon8Web.AdminLive.BlogManagement do
  @moduledoc """
  The list of blog posts: browse, start a new one, publish or unpublish, schedule, delete. Editing a
  post happens on the post itself (`Bacon8Web.InPlaceEditing`); "Edit" and "New post" open it there.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Content
  alias Bacon8Web.Components.AdminSidebar
  alias Bacon8Web.Components.ContentExtras

  on_mount {Bacon8Web.UserAuth, {:require_area, :content}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, posts: Content.list_posts(), page_title: "Blog Management")}
  end

  # A new post starts as a saved draft, so the editor has a record to autosave to and to attach
  # uploads to (Bacon8.Content.create_draft/2), and opens on the post itself.
  @impl true
  def handle_event("new_post", _params, socket) do
    case Content.create_draft(:post, socket.assigns.current_user) do
      {:ok, post} -> {:noreply, push_navigate(socket, to: "/blog/#{post.slug}?edit=1")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't start a new post")}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    with {:ok, post} <- fetch(id),
         {:ok, _} <- Content.delete_post(post) do
      Bacon8.Uploads.delete_content_uploads("blog", post.id)
      {:noreply, socket |> assign(posts: Content.list_posts()) |> put_flash(:info, "Post deleted successfully!")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to delete post")}
    end
  end

  def handle_event("toggle_publish", %{"id" => id}, socket) do
    case fetch(id) do
      {:ok, post} ->
        publish? = !post.is_published

        # A post needs a title and words before it can go live
        if publish? and (blank?(post.title) or blank?(post.content)) do
          {:noreply, put_flash(socket, :error, "Cannot publish: Post must have a title and content")}
        else
          case Content.update_post(post, %{is_published: publish?}) do
            {:ok, _} ->
              {:noreply, socket |> assign(posts: Content.list_posts()) |> put_flash(:info, "Post #{if publish?, do: "published", else: "unpublished"} successfully!")}

            {:error, changeset} ->
              error_msg = Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
              {:noreply, put_flash(socket, :error, "Failed to update post: #{error_msg}")}
          end
        end

      :error ->
        {:noreply, put_flash(socket, :error, "That post is gone")}
    end
  end

  def handle_event("set_schedule", %{"record_id" => id, "scheduled_at" => value}, socket) do
    with {:ok, post} <- fetch(id) do
      case Content.schedule(post, value) do
        {:ok, _} -> {:noreply, socket |> assign(posts: Content.list_posts()) |> put_flash(:info, "Schedule saved")}
        {:error, :past} -> {:noreply, put_flash(socket, :error, "That time has passed. Use Publish to publish now.")}
        {:error, :published} -> {:noreply, put_flash(socket, :error, "It is published already")}
        _ -> {:noreply, put_flash(socket, :error, "That isn't a time")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "That post is gone")}
    end
  end

  # Catch-all for client events meant for other LiveViews (window position, desktop widgets).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp fetch(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id), %Content.Post{} = post <- Bacon8.Repo.get(Content.Post, uuid) do
      {:ok, Bacon8.Repo.preload(post, :user)}
    else
      _ -> :error
    end
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/blog-management" current_user={@current_user}>
      <div class="max-w-6xl mx-auto">
        <div class="auth-glass-panel p-8 rounded-xl">
          <div class="flex justify-between items-center mb-8">
            <h1 class="text-3xl font-bold text-white">Blog Management</h1>
            <button phx-click="new_post" id="new-post" class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg transition-colors">➕ New Post</button>
          </div>

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
                <div :for={post <- @posts} id={"post-#{post.id}"} class="p-6 hover:bg-gray-750 transition-colors">
                  <div class="flex justify-between items-start">
                    <div class="flex-1">
                      <div class="flex items-center flex-wrap gap-2 mb-2">
                        <h3 class="text-lg font-medium text-white"><%= post.title %></h3>
                        <span class={["px-2 py-1 text-xs rounded-full", if(post.is_published, do: "bg-green-600 text-white", else: "bg-gray-600 text-gray-300")]}>
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

                      <p :if={post.excerpt} class="text-gray-300 text-sm mb-3"><%= post.excerpt %></p>

                      <div :if={post.tags && length(post.tags) > 0} class="flex flex-wrap gap-1 mb-3">
                        <span :for={tag <- post.tags} class="bg-blue-600 text-white px-2 py-1 text-xs rounded"><%= tag %></span>
                      </div>

                      <div class="text-xs text-gray-500">Slug: /<%= post.slug %></div>

                      <ContentExtras.schedule_row :if={!post.is_published} id={post.id} value={post.scheduled_at} />
                    </div>

                    <div class="flex space-x-2 ml-4">
                      <.link href={"/blog/#{post.slug}"} target="_blank" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1 text-sm rounded transition-colors">
                        <%= if post.is_published, do: "View", else: "Preview" %>
                      </.link>
                      <button type="button" phx-click="toggle_publish" phx-value-id={post.id}
                              class={["px-3 py-1 text-sm rounded transition-colors", if(post.is_published, do: "bg-orange-600 hover:bg-orange-700 text-white", else: "bg-green-600 hover:bg-green-700 text-white")]}>
                        <%= if post.is_published, do: "Unpublish", else: "Publish" %>
                      </button>
                      <.link navigate={"/blog/#{post.slug}?edit=1"} class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 text-sm rounded transition-colors">
                        Edit
                      </.link>
                      <button type="button" phx-click="delete_post" phx-value-id={post.id}
                              data-confirm="Are you sure you want to delete this post?"
                              class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 text-sm rounded transition-colors">
                        Delete
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
