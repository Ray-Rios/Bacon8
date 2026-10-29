defmodule Bacon8Web.BlogLive do
  use Bacon8Web, :live_view
  alias Bacon8.Content
  import Bacon8Web.Components.PageContainer
  alias Bacon8Web.Components.BlockEditor
  alias Bacon8Web.Components.ContentSettings
  alias Bacon8Web.InPlaceEditing
  alias Bacon8Web.Components.SocialShare

  # Note: on_mount :default is handled by router's live_session

  @editing_events InPlaceEditing.events()

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
       last_saved: nil,
       pending_content: nil,
       pending_title: nil,
       form: nil,
       revisions: [],
       featured_library: nil
     )}
  end

  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    edit? = params["edit"] == "1"

    # A draft is for staff only (it used to be readable by anyone who knew its slug), and a
    # slug nobody has is "not found", not a crash.
    case Content.get_post_by_slug(slug) do
      %{is_published: true} = post ->
        {:noreply, show_post(socket, post, edit?)}

      %{} = post ->
        if can_edit?(socket.assigns), do: {:noreply, show_post(socket, post, edit?)}, else: post_not_found(socket)

      nil ->
        post_not_found(socket)
    end
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

  defp show_post(socket, post, edit?) do
    socket
    |> assign(Bacon8Web.Seo.for_post(post))
    |> assign(
      comments: Content.list_comments_for(post.id, socket.assigns[:current_user]),
      comment_notice: nil,
      comment_reply: nil,
      comment_edit: nil,
      post: post,
      page_title: post.title,
      view: :post_detail
    )
    |> InPlaceEditing.init(:post, post, edit?)
  end

  # A post's date: when it was published, or (a draft, or one published before dates were
  # stamped) when it was written.
  defp post_date(post, format), do: Calendar.strftime(post.published_at || post.inserted_at, format)

  defp post_not_found(socket) do
    {:noreply, socket |> put_flash(:error, "Post not found") |> push_navigate(to: "/blog")}
  end

  defp can_edit?(assigns), do: InPlaceEditing.can_edit?(assigns)

  # Everything about editing (settings, saving, publishing, pictures, versions) is in one place
  def handle_event(event, params, socket) when event in @editing_events,
    do: InPlaceEditing.handle(event, params, socket, :post)

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

  # A member's comment: shown at once or held for a moderator (Bacon8.Content.Moderation)
  def handle_event("post_comment", %{"comment" => text} = params, %{assigns: %{view: :post_detail, post: post}} = socket) do
    parent_id = if params["parent_id"] in [nil, ""], do: nil, else: params["parent_id"]

    notice =
      case Content.submit_comment(socket.assigns[:current_user], post, text, parent_id) do
        {:ok, %{is_approved: true}} -> nil
        {:ok, _held} -> "Thanks. Your comment will appear once a moderator has checked it."
        {:error, :not_found} -> "That comment is no longer there to reply to."
        {:error, :rate_limited} -> "You're commenting too fast. Please wait a little."
        {:error, :duplicate} -> "You already posted that."
        {:error, :not_allowed} -> "Sign in with a verified email to comment."
        {:error, _changeset} -> "That comment can't be posted. Check its length."
      end

    {:noreply, assign(socket, comments: Content.list_comments_for(post.id, socket.assigns[:current_user]), comment_notice: notice, comment_reply: nil)}
  end

  def handle_event("post_comment", _params, socket), do: {:noreply, socket}

  # Replying to, editing and deleting a comment (only the member's own can be edited or deleted)
  def handle_event("reply_to", %{"id" => id}, socket), do: {:noreply, assign(socket, comment_reply: id, comment_edit: nil)}
  def handle_event("cancel_reply", _params, socket), do: {:noreply, assign(socket, comment_reply: nil)}
  def handle_event("edit_comment", %{"id" => id}, socket), do: {:noreply, assign(socket, comment_edit: id, comment_reply: nil)}
  def handle_event("cancel_comment_edit", _params, socket), do: {:noreply, assign(socket, comment_edit: nil)}

  def handle_event("save_comment", %{"comment_id" => id, "comment" => text}, %{assigns: %{view: :post_detail}} = socket) do
    notice =
      case Content.edit_own_comment(socket.assigns[:current_user], id, text) do
        {:ok, %{is_approved: true}} -> nil
        {:ok, _held} -> "Saved. Your comment will appear again once a moderator has checked it."
        {:error, %Ecto.Changeset{}} -> "That comment can't be saved. Check its length."
        {:error, _} -> "That comment can't be changed."
      end

    {:noreply, socket |> assign(comment_edit: nil, comment_notice: notice) |> reload_comments()}
  end

  def handle_event("delete_comment", %{"id" => id}, %{assigns: %{view: :post_detail}} = socket) do
    Content.delete_own_comment(socket.assigns[:current_user], id)
    {:noreply, socket |> assign(comment_notice: nil) |> reload_comments()}
  end

  # Desktop UI sometimes pushes update_window_position globally; ignore in BlogLive
  def handle_event("update_window_position", _params, socket) do
    {:noreply, socket}
  end

  defp reload_comments(socket), do: assign(socket, comments: Content.list_comments_for(socket.assigns.post.id, socket.assigns[:current_user]))

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
                          <%= post_date(post, "%B %d, %Y") %>
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
                            <span><%= post_date(post, "%b %d, %Y") %></span>
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
                      <span><%= post_date(post, "%b %d, %Y") %></span>
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

      <!-- Blog Post Detail View (while editing: the editor, full screen) -->
      <Bacon8Web.Components.EditorShell.shell
        :if={@view == :post_detail && @editing && @form}
        kind={:post}
        record={@post}
        editor_id={"blog-editor-#{@post.id}"}
        form={@form}
        revisions={@revisions}
        uploads={@uploads}
        featured_library={@featured_library}
        saving={@saving}
        last_saved={@last_saved}
        dirty={InPlaceEditing.dirty?(assigns)}
        pending_title={@pending_title}
      />
      <div :if={@view == :post_detail && !(@editing && @form)}>
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
                  value={@pending_title || @post.title}
                  phx-blur="update_title"
                  phx-keyup="update_title"
                  phx-key="Enter"
                  class="text-4xl font-bold text-white bg-transparent border-b-2 border-blue-500 focus:outline-none focus:border-blue-400 w-full"
                  placeholder="Post title..."
                />
              <% else %>
                <h1 class="text-4xl font-bold text-white"><%= @post.title %></h1>
              <% end %>

              <ContentSettings.toolbar :if={can_edit?(assigns)} kind={:post} record={@post} editing={@editing} saving={@saving} last_saved={@last_saved} dirty={InPlaceEditing.dirty?(assigns)} />
            </div>

            <ContentSettings.settings :if={@editing && @form} kind={:post} record={@post} form={@form} revisions={@revisions} uploads={@uploads} featured_library={@featured_library} />

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
              <span><%= if @post.is_published, do: post_date(@post, "%B %d, %Y"), else: "Draft, not published" %></span>
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
              
              <Bacon8Web.Components.Comments.comments comments={@comments} current_user={@current_user} notice={@comment_notice} reply={@comment_reply} edit={@comment_edit} />

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
