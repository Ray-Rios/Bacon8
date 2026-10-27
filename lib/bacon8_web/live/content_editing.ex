defmodule Bacon8Web.ContentEditing do
  @moduledoc """
  What every place that edits a page or a post with the block editor shares: the public pages
  and blog posts (editing in place) and the two admin screens. One implementation of the
  editor's events, so a fix or a safety rule is made once.

  The block editor (`assets/js/block_editor_hook.ts`) pushes `editor-change`, `editor-autosave`,
  `block-media-upload`, `block-media-remove` and the older `block-image-upload` to whichever
  LiveView renders it. Each of those LiveViews decides *whether* the event is allowed (who may
  edit) and *which record* it is for; the work is here.

  A record's uploads live in `uploads/public/<context>/`, where the context is `"pages/<id>"` or
  `"blog/<id>"` (`context/2`). Nothing here accepts an upload for a record that doesn't exist yet:
  new pages and posts are created as drafts first (`Bacon8.Content.create_draft/2`), so there is
  always an id.
  """
  import Phoenix.LiveView, only: [push_event: 3]

  alias Bacon8.Content.{InlineMedia, Library}

  @doc "The uploads context of a record: `context(:page, page)` is `\"pages/<id>\"`."
  def context(:page, %{id: id}) when is_binary(id), do: "pages/#{id}"
  def context(:post, %{id: id}) when is_binary(id), do: "blog/#{id}"
  def context(_kind, _record), do: nil

  @doc "The body the editor sent: its block JSON, else its HTML, else an empty string."
  def content(params), do: Map.get(params, "content") || Map.get(params, "html", "")

  @doc """
  The editor's periodic autosave on an admin screen. Only a record that isn't published is saved
  (a published page changes when its editor presses Save or Publish, not behind their back; the
  in-place editors on the public pages do autosave live, because that is what they are for).
  Returns the socket, with the saved record under `assign_key` and the editor told it is saved.
  """
  def autosave(socket, kind, assign_key, params) do
    record = socket.assigns[assign_key]

    with %{is_published: false} <- record,
         {:ok, saved} <- save_content(kind, record, content(params)) do
      socket
      |> Phoenix.Component.assign(assign_key, saved)
      |> push_event("content-saved", %{})
    else
      _ -> socket
    end
  end

  defp save_content(:page, record, content), do: Bacon8.Content.update_page(record, %{content: content})
  defp save_content(:post, record, content), do: Bacon8.Content.update_post(record, %{content: content})

  @doc """
  Handles `block-media-upload`, `block-image-upload` (the older name) and `block-media-remove`
  for the record whose uploads context is `context`. Returns the socket; a nil context (no record
  yet) answers the editor with an error instead of storing anything.
  """
  def media(event, params, socket, context)

  def media("block-image-upload", params, socket, context),
    do: media("block-media-upload", Map.put(params, "mediaType", "image"), socket, context)

  def media("block-media-upload", %{"blockId" => block_id}, socket, nil),
    do: push_event(socket, "block-media-error", %{blockId: block_id, error: "Save a draft first"})

  def media("block-media-upload", %{"blockId" => block_id, "mediaType" => media_type} = params, socket, context) do
    case InlineMedia.store(context, params, user_id: user_id(socket)) do
      {:ok, %{url: url, filename: filename}} ->
        push_event(socket, "block-media-uploaded", %{
          blockId: block_id,
          url: url,
          mediaType: media_type,
          filename: filename,
          mediaId: nil
        })

      {:error, message} ->
        push_event(socket, "block-media-error", %{blockId: block_id, error: message})
    end
  end

  # Only this record's own uploads can be removed (InlineMedia.remove/2 checks the folder).
  def media("block-media-remove", %{"url" => url}, socket, context) when is_binary(url) and is_binary(context) do
    InlineMedia.remove(context, url)
    socket
  end

  def media(_event, _params, socket, _context), do: socket

  @doc """
  The image library for the editor's picker (`library-list`): one page of pictures as plain maps
  (`%{images: [%{url, filename}], more: boolean}`), filtered by the file name in `"query"`.
  """
  def library(params) do
    offset = params |> Map.get("offset", 0) |> to_int()
    %{images: images, more: more} = Library.list(query: Map.get(params, "query", ""), offset: offset)
    %{images: Enum.map(images, &%{url: &1.url, filename: &1.filename}), more: more}
  end

  @doc """
  `library-use`: puts the library picture `"url"` into block `"blockId"` (an image block, or a
  gallery with `"mediaType" => "gallery"`). The picture is copied into this record's own uploads
  (`Library.use_image/3`); the editor answers like an upload.
  """
  def library_use(%{"blockId" => block_id, "url" => url} = params, socket, context) when is_binary(context) do
    case Library.use_image(context, url, user_id(socket)) do
      {:ok, %{url: new_url, filename: filename}} ->
        push_event(socket, "block-media-uploaded", %{
          blockId: block_id,
          url: new_url,
          mediaType: if(params["mediaType"] == "gallery", do: "gallery", else: "image"),
          filename: filename,
          mediaId: nil
        })

      {:error, message} ->
        push_event(socket, "block-media-error", %{blockId: block_id, error: message})
    end
  end

  def library_use(%{"blockId" => block_id}, socket, _context),
    do: push_event(socket, "block-media-error", %{blockId: block_id, error: "Save a draft first"})

  def library_use(_params, socket, _context), do: socket

  @doc "Pictures already shown, then `more` without the ones shown twice."
  def merge_images(shown, more), do: shown ++ Enum.reject(more, fn image -> Enum.any?(shown, &(&1.url == image.url)) end)

  @common_settings ~w(title slug excerpt meta_description scheduled_at show_share_buttons share_buttons_colored share_platforms)
  @page_settings ~w(template_type category)
  @post_settings ~w(tags)

  @doc """
  The attributes to save from the settings form of an in-place editor (`params` has string
  keys, as the form sends them): only the fields the form has, tags as a list, no empty share
  platforms, and a new draft's slug following its title (`Content.slug_for_save/3`).
  Returns a map with atom keys.
  """
  def settings_attrs(kind, record, params) do
    keys = @common_settings ++ if(kind == :page, do: @page_settings, else: @post_settings)

    params
    |> Map.take(keys)
    |> normalise_settings()
    |> then(&Bacon8.Content.slug_for_save(kind, record, &1))
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp normalise_settings(params) do
    params
    |> then(fn p -> if is_list(p["share_platforms"]), do: Map.put(p, "share_platforms", Enum.reject(p["share_platforms"], &(&1 in ["", nil]))), else: p end)
    |> then(fn p ->
      case p["tags"] do
        tags when is_binary(tags) -> Map.put(p, "tags", tags |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")))
        _ -> p
      end
    end)
  end

  @doc """
  Stores the featured image picked in the settings form's file field (the upload `:featured_image`)
  in the record's own uploads, and returns its URL, or nil when none was chosen or it was refused.
  """
  def consume_featured(socket, context, user_id) when is_binary(context) do
    if Map.has_key?(socket.assigns[:uploads] || %{}, :featured_image) do
      Phoenix.LiveView.consume_uploaded_entries(socket, :featured_image, fn %{path: path}, entry ->
        with {:ok, bytes} <- File.read(path),
             {:ok, %{url: url}} <-
               InlineMedia.store(context, %{"data" => Base.encode64(bytes), "filename" => entry.client_name, "mimeType" => entry.client_type}, user_id: user_id) do
          {:ok, url}
        else
          _ -> {:ok, nil}
        end
      end)
      |> Enum.find(& &1)
    end
  end

  def consume_featured(_socket, _context, _user_id), do: nil

  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  defp user_id(socket), do: socket.assigns[:current_user] && socket.assigns.current_user.id
end
