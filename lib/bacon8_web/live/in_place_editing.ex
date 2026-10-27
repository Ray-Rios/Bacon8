defmodule Bacon8Web.InPlaceEditing do
  @moduledoc """
  Editing a page or a post where it is shown (`PageLive` at `/pages/:slug`, `BlogLive` at
  `/blog/:slug`). This is the one place pages and posts are edited; `/admin/pages` and
  `/admin/blog-management` only list, create, publish, schedule and delete them.

  Each LiveView keeps one clause that hands every editing event to `handle/4`:

      @editing_events Bacon8Web.InPlaceEditing.events()
      def handle_event(event, params, socket) when event in @editing_events,
        do: Bacon8Web.InPlaceEditing.handle(event, params, socket, :page)

  and calls `init/4` whenever it shows a record. `kind` is `:page` or `:post`; the record is
  `socket.assigns.page` or `.post`. Only staff (`Bacon8.Permissions`, area `:content`) may use any
  of it; for anyone else every event is ignored.

  ## What is saved when

  * A **draft** saves itself as you type (autosave) and on Save.
  * A **published** page or post is never changed behind the editor's back: what is typed is kept
    in the session (`pending_content`, `pending_title`), the toolbar says "Not saved yet", and
    Save & Exit (or Save settings, or Publish) writes it. Cancel throws it away.
  * Every save that changes the words keeps the version before it (`Bacon8.Content.Revisions`).
  """
  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]
  import Phoenix.LiveView

  alias Bacon8.{Content, Permissions, Uploads}
  alias Bacon8.Content.{Library, Revisions}
  alias Bacon8Web.ContentEditing

  @events ~w(toggle_edit update_title editor-change editor-autosave save_content cancel_edit
             block-media-upload block-media-remove block-image-upload library-list library-use
             save_settings settings_change set_published restore_revision delete_record
             open_featured_library close_featured_library featured_library_search featured_library_more
             pick_featured remove_featured)

  @doc "The event names `handle/4` takes."
  def events, do: @events

  @doc "Whether the signed-in user may edit pages and posts."
  def can_edit?(%{current_user: user}), do: Permissions.can?(user, :content)
  def can_edit?(_), do: false

  @doc """
  Assigns the editing state for `record` (call it whenever the LiveView shows one). `edit?` starts
  the editor open (`?edit=1`), which only works for staff. Also allows the featured image upload.
  """
  def init(socket, kind, record, edit? \\ false) do
    socket =
      if can_edit?(socket.assigns) and not Map.has_key?(socket.assigns[:uploads] || %{}, :featured_image) do
        allow_upload(socket, :featured_image, accept: ~w(.jpg .jpeg .png .gif .webp), max_entries: 1, max_file_size: 10_000_000)
      else
        socket
      end

    socket
    |> assign(
      editing: false,
      saving: false,
      last_saved: nil,
      pending_content: nil,
      pending_title: nil,
      form: nil,
      revisions: [],
      featured_library: nil
    )
    |> then(fn socket ->
      if edit? and can_edit?(socket.assigns), do: open_editor(socket, kind, record), else: socket
    end)
  end

  @doc "True when typed words are waiting to be saved."
  def dirty?(assigns), do: not is_nil(assigns[:pending_content]) or not is_nil(assigns[:pending_title])

  # ------------------------------------------------------------------ events

  def handle(event, params, socket, kind) do
    cond do
      can_edit?(socket.assigns) -> do_handle(event, params, socket, kind)
      event == "library-list" -> {:reply, %{images: [], more: false}, socket}
      event == "toggle_edit" -> {:noreply, put_flash(socket, :error, "You don't have permission to edit.")}
      true -> {:noreply, socket}
    end
  end

  defp do_handle("toggle_edit", _params, socket, kind) do
    if socket.assigns.editing do
      {:noreply, close_editor(socket)}
    else
      {:noreply, open_editor(socket, kind, record(socket, kind))}
    end
  end

  # The title typed in place: a draft keeps it at once, a published record waits for Save.
  defp do_handle("update_title", %{"value" => title}, %{assigns: %{editing: true}} = socket, kind) do
    record = record(socket, kind)

    if record.is_published do
      {:noreply, assign(socket, pending_title: title)}
    else
      case update(kind, record, %{title: title}) do
        {:ok, saved} -> {:noreply, socket |> put_record(kind, saved) |> assign(last_saved: DateTime.utc_now())}
        {:error, _} -> {:noreply, socket}
      end
    end
  end

  defp do_handle("editor-change", params, %{assigns: %{editing: true}} = socket, kind) do
    content = ContentEditing.content(params)
    record = record(socket, kind)

    # (a draft's change is saved by the autosave; remembering it as unsaved would only confuse)
    if record.is_published or content != record.content,
      do: {:noreply, assign(socket, pending_content: content)},
      else: {:noreply, socket}
  end

  defp do_handle("editor-autosave", params, %{assigns: %{editing: true}} = socket, kind) do
    record = record(socket, kind)

    if record.is_published do
      {:noreply, assign(socket, pending_content: ContentEditing.content(params))}
    else
      socket = ContentEditing.autosave(socket, kind, key(kind), params)
      {:noreply, assign(socket, pending_content: nil, last_saved: DateTime.utc_now())}
    end
  end

  defp do_handle("save_content", _params, %{assigns: %{editing: true}} = socket, kind) do
    case save_pending(socket, kind, %{}) do
      {:ok, saved} ->
        {:noreply, socket |> put_record(kind, saved) |> close_editor() |> put_flash(:info, "Saved")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Not saved: " <> errors(changeset))}
    end
  end

  defp do_handle("cancel_edit", _params, %{assigns: %{editing: true}} = socket, kind) do
    record = reload(kind, record(socket, kind).id)

    # A page or post that was just started and never written in goes away.
    if Content.untouched_draft?(record) do
      delete(kind, record)
      {:noreply, socket |> put_flash(:info, "Nothing was written, so nothing was kept") |> push_navigate(to: list_path(kind))}
    else
      {:noreply,
       socket
       |> put_record(kind, record)
       |> close_editor()
       |> push_event("update-editor-content", %{content: record.content})
       |> put_flash(:info, "Changes discarded")}
    end
  end

  defp do_handle(event, params, socket, kind) when event in ["block-media-upload", "block-media-remove", "block-image-upload"] do
    {:noreply, ContentEditing.media(event, params, socket, ContentEditing.context(kind, record(socket, kind)))}
  end

  defp do_handle("library-list", params, socket, _kind), do: {:reply, ContentEditing.library(params), socket}

  defp do_handle("library-use", params, socket, kind) do
    {:noreply, ContentEditing.library_use(params, socket, ContentEditing.context(kind, record(socket, kind)))}
  end

  defp do_handle("settings_change", _params, socket, _kind), do: {:noreply, socket}

  defp do_handle("save_settings", %{"settings" => params}, %{assigns: %{editing: true}} = socket, kind) do
    record = record(socket, kind)
    context = ContentEditing.context(kind, record)

    attrs = ContentEditing.settings_attrs(kind, record, params)

    attrs =
      case ContentEditing.consume_featured(socket, context, socket.assigns.current_user.id) do
        nil -> attrs
        url -> Map.put(attrs, :featured_image, url)
      end

    case save_pending(socket, kind, attrs) do
      {:ok, saved} ->
        if saved.slug != record.slug do
          # the address changed: open the new one, still editing
          {:noreply, socket |> put_flash(:info, "Saved. The address changed.") |> push_navigate(to: path(kind, saved) <> "?edit=1")}
        else
          {:noreply, socket |> put_record(kind, saved) |> refresh_form(kind, saved) |> put_flash(:info, "Settings saved")}
        end

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Not saved: " <> errors(changeset))}
    end
  end

  defp do_handle("set_published", %{"to" => to}, %{assigns: %{editing: true}} = socket, kind) do
    publish? = to == "true"

    case save_pending(socket, kind, %{is_published: publish?}) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_record(kind, saved)
         |> refresh_form(kind, saved)
         |> put_flash(:info, if(publish?, do: "Published", else: "Unpublished: it is a draft again"))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Can't #{if publish?, do: "publish", else: "unpublish"}: " <> errors(changeset))}
    end
  end

  defp do_handle("restore_revision", %{"id" => id}, %{assigns: %{editing: true}} = socket, kind) do
    record = record(socket, kind)

    case Revisions.restore(record, id, socket.assigns.current_user.id) do
      {:ok, restored} ->
        # a fresh page load, so the editor is rebuilt with the restored words
        {:noreply, socket |> put_flash(:info, "Earlier version restored") |> push_navigate(to: path(kind, restored) <> "?edit=1")}

      _ ->
        {:noreply, put_flash(socket, :error, "That version is no longer there")}
    end
  end

  defp do_handle("delete_record", _params, %{assigns: %{editing: true}} = socket, kind) do
    record = record(socket, kind)

    case delete(kind, record) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Deleted") |> push_navigate(to: list_path(kind))}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete it")}
    end
  end

  # ---- the featured image picker (a window over the image library)
  defp do_handle("open_featured_library", _params, %{assigns: %{editing: true}} = socket, _kind),
    do: {:noreply, assign(socket, featured_library: featured_page("", 0))}

  defp do_handle("close_featured_library", _params, socket, _kind), do: {:noreply, assign(socket, featured_library: nil)}

  defp do_handle("featured_library_search", %{"query" => query}, %{assigns: %{featured_library: %{}}} = socket, _kind),
    do: {:noreply, assign(socket, featured_library: featured_page(query, 0))}

  defp do_handle("featured_library_more", _params, %{assigns: %{featured_library: %{} = shown}} = socket, _kind) do
    next = featured_page(shown.query, length(shown.images))
    {:noreply, assign(socket, featured_library: %{next | images: ContentEditing.merge_images(shown.images, next.images)})}
  end

  defp do_handle("pick_featured", %{"url" => url}, %{assigns: %{editing: true}} = socket, kind) do
    record = record(socket, kind)

    with {:ok, %{url: copied}} <- Library.use_image(ContentEditing.context(kind, record), url, socket.assigns.current_user.id),
         {:ok, saved} <- update(kind, record, %{featured_image: copied}) do
      {:noreply, socket |> put_record(kind, saved) |> assign(featured_library: nil) |> put_flash(:info, "Featured image set")}
    else
      {:error, message} when is_binary(message) -> {:noreply, put_flash(socket, :error, message)}
      _ -> {:noreply, put_flash(socket, :error, "Could not set the featured image")}
    end
  end

  defp do_handle("remove_featured", _params, %{assigns: %{editing: true}} = socket, kind) do
    case update(kind, record(socket, kind), %{featured_image: nil}) do
      {:ok, saved} -> {:noreply, put_record(socket, kind, saved)}
      _ -> {:noreply, socket}
    end
  end

  # An event that only makes sense while editing, arriving when not editing (a stale tab).
  defp do_handle(_event, _params, socket, _kind), do: {:noreply, socket}

  # ------------------------------------------------------------------ helpers

  defp open_editor(socket, kind, record) do
    socket
    |> assign(editing: true, pending_content: nil, pending_title: nil)
    |> refresh_form(kind, record)
  end

  defp close_editor(socket),
    do: assign(socket, editing: false, pending_content: nil, pending_title: nil, form: nil, revisions: [], featured_library: nil)

  defp refresh_form(socket, kind, record) do
    assign(socket,
      form: to_form(change(kind, record), as: :settings),
      revisions: Revisions.list(kind, record.id)
    )
  end

  # Writes the title and words typed since the last save, together with `attrs`.
  defp save_pending(socket, kind, attrs) do
    record = record(socket, kind)

    # (a title typed in the settings form wins over one typed in the heading)
    attrs =
      attrs
      |> put_new_unless_nil(:content, socket.assigns[:pending_content])
      |> put_new_unless_nil(:title, socket.assigns[:pending_title])

    update(kind, record, attrs)
  end

  defp put_new_unless_nil(attrs, _key, nil), do: attrs
  defp put_new_unless_nil(attrs, key, value), do: Map.put_new(attrs, key, value)

  defp featured_page(query, offset) do
    %{images: images, more: more} = ContentEditing.library(%{"query" => query, "offset" => offset})
    %{images: images, more: more, query: query}
  end

  defp errors(%Ecto.Changeset{} = changeset) do
    changeset.errors |> Enum.map_join(", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  defp errors(_), do: "something went wrong"

  # ---- kind-specific
  defp key(:page), do: :page
  defp key(:post), do: :post

  defp record(socket, kind), do: Map.fetch!(socket.assigns, key(kind))
  defp put_record(socket, kind, record), do: socket |> assign(key(kind), record) |> assign(pending_content: nil, pending_title: nil, last_saved: DateTime.utc_now())

  defp reload(:page, id), do: Content.get_page!(id)
  defp reload(:post, id), do: Content.get_post!(id)

  defp update(:page, record, attrs), do: Content.update_page(record, attrs)
  defp update(:post, record, attrs), do: Content.update_post(record, attrs)

  defp change(:page, record), do: Bacon8.Content.Page.changeset(record, %{})
  defp change(:post, record), do: Bacon8.Content.Post.changeset(record, %{})

  defp delete(:page, record) do
    with {:ok, _} = ok <- Content.delete_page(record) do
      Uploads.delete_content_uploads("pages", record.id)
      ok
    end
  end

  defp delete(:post, record) do
    with {:ok, _} = ok <- Content.delete_post(record) do
      Uploads.delete_content_uploads("blog", record.id)
      ok
    end
  end

  @doc "The public address of a record."
  def path(:page, record), do: "/pages/#{record.slug}"
  def path(:post, record), do: "/blog/#{record.slug}"

  defp list_path(:page), do: "/admin/pages"
  defp list_path(:post), do: "/admin/blog-management"
end
