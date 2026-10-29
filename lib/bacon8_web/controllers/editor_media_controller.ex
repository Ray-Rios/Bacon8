defmodule Bacon8Web.EditorMediaController do
  @moduledoc """
  `POST /editor/media`: a picture or file added to a page or post in the page builder
  (`assets/js/page_builder/hook.ts`, 2026-10-29). Multipart: `kind` ("page" or "post"), `id`
  (the record's id), `file`. Answers JSON `{url, filename}` or `{error}`.

  Uploads used to travel as base64 inside a LiveView event. A phone photo made that one
  WebSocket frame several megabytes, the connection dropped, and the picture never arrived;
  on a page opened with the Edit button the remount also closed the editor. An ordinary HTTP
  upload doesn't depend on the live connection at all.

  Who may: staff with the `:content` area (`Bacon8.Permissions`), the same rule as the editor.
  The session cookie signs the request in and the CSRF token (`x-csrf-token`) guards it.
  """
  use Bacon8Web, :controller

  alias Bacon8.{Content, Permissions}
  alias Bacon8.Content.InlineMedia
  alias Bacon8Web.ContentEditing

  def create(conn, %{"kind" => kind, "id" => id, "file" => %Plug.Upload{} = upload}) when kind in ["page", "post"] do
    user = conn.assigns[:current_user]

    with :ok <- allowed(user),
         {:ok, record} <- fetch(kind, id),
         context when is_binary(context) <- ContentEditing.context(String.to_existing_atom(kind), record),
         {:ok, %{url: url, filename: filename}} <-
           InlineMedia.store_file(context, upload.path, upload.filename, upload.content_type, user_id: user.id) do
      json(conn, %{url: url, filename: filename})
    else
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "You can't edit pages and posts."})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "Save a draft first."})
      {:error, message} when is_binary(message) -> conn |> put_status(422) |> json(%{error: message})
      _ -> conn |> put_status(422) |> json(%{error: "The upload failed."})
    end
  end

  def create(conn, _params), do: conn |> put_status(400) |> json(%{error: "No file was sent."})

  defp allowed(user), do: if(user && Permissions.can?(user, :content), do: :ok, else: {:error, :forbidden})

  defp fetch(kind, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %{} = record <- get(kind, uuid) do
      {:ok, record}
    else
      _ -> {:error, :not_found}
    end
  end

  defp get("page", id), do: Bacon8.Repo.get(Content.Page, id)
  defp get("post", id), do: Bacon8.Repo.get(Content.Post, id)
end
