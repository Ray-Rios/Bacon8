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

  alias Bacon8.Content.InlineMedia

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
    case InlineMedia.store(context, params) do
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
end
