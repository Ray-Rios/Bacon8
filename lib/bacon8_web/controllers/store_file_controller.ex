defmodule Bacon8Web.StoreFileController do
  @moduledoc """
  Store files (BACON8.md §8):

    * `GET /store/media/:id` - a product image. Public while the product is
      on sale; admins can see images of products still off sale. Cached for a
      year: a file id always names the same bytes.
    * `GET /store/download/:id` - a download file, for buyers (and admins).
      Always an attachment, never rendered by the browser.

  Refusals are 404, never 403.
  """
  use Bacon8Web, :controller

  alias Bacon8.Storage
  alias Bacon8.Store.{Catalog, Library}

  def media(conn, %{"id" => id}) do
    with %{role: "image", product: product} = file <- Catalog.get_file(id),
         true <- product.active or admin?(conn.assigns[:current_user]),
         {:ok, path} <- Storage.local_path(file.sha256) do
      conn
      |> put_resp_content_type(file.content_type, nil)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", if(product.active, do: "public, max-age=31536000, immutable", else: "private, no-store"))
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> send_file(200, path)
    else
      _ -> not_found(conn)
    end
  end

  def download(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    with %{role: "download"} = file <- Catalog.get_file(id),
         true <- Library.can_download?(user, file),
         {:ok, path} <- Storage.local_path(file.sha256) do
      conn
      |> put_resp_content_type("application/octet-stream", nil)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-disposition", attachment(file.filename))
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> send_file(200, path)
    else
      _ -> not_found(conn)
    end
  end

  defp admin?(%{} = user), do: Map.get(user, :is_admin) == true or Map.get(user, :role) == "admin"
  defp admin?(_), do: false

  defp attachment(name) do
    ascii = String.replace(name, ~r/[^\x20-\x7E]|["\\]/u, "_")
    ~s(attachment; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(name, &URI.char_unreserved?/1)})
  end

  defp not_found(conn), do: conn |> put_status(404) |> text("Not found")
end
