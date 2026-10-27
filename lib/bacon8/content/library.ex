defmodule Bacon8.Content.Library do
  @moduledoc """
  The image library: every picture added to a page or post, ready to be used again.

  Pictures live in `uploads/public/pages/<id>/` and `uploads/public/blog/<id>/` (see
  `Bacon8.Content.InlineMedia`). `InlineMedia.store/3` records each image here. Using a picture
  from the library on another page *copies* it into that page's folder (`use_image/3`), so
  deleting the first page, which deletes its folder, never breaks the second.

  The same picture (same `sha256`) is listed once, whichever page holds it. `sync_from_disk/0`
  adds pictures that were uploaded before the library existed and forgets rows whose file is gone;
  it runs whenever the library is opened (`list/1` with no offset).
  """
  import Ecto.Query, warn: false

  alias Bacon8.{Repo, SafePath, Uploads}
  alias Bacon8.Content.{Image, InlineMedia}

  @extensions ~w(.jpg .jpeg .png .gif .webp .avif)
  @mimes %{".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png", ".gif" => "image/gif", ".webp" => "image/webp", ".avif" => "image/avif"}
  @contexts ~w(pages blog)
  @page_size 40

  @doc "True for a file name the library lists (a picture a browser shows)."
  def image?(name) when is_binary(name), do: String.downcase(Path.extname(name)) in @extensions
  def image?(_), do: false

  @doc "Records a stored picture. Called by `InlineMedia.store/3`; other kinds of file are ignored."
  def record(url, context, filename, bytes, mime, user_id) do
    if image?(filename) do
      Repo.insert(
        %Image{
          url: url,
          filename: filename,
          context: context,
          sha256: sha256(bytes),
          byte_size: byte_size(bytes),
          mime_type: mime,
          user_id: user_id
        },
        on_conflict: :nothing,
        conflict_target: :url
      )
    end

    :ok
  end

  @doc """
  One page of the library, newest first: `%{images: [%Image{}], more: boolean}`.

  Options: `:query` (part of a file name), `:offset`. With no offset the disk is synced first.
  """
  def list(opts \\ []) do
    offset = max(Keyword.get(opts, :offset, 0), 0)
    if offset == 0, do: sync_from_disk()

    query =
      case String.trim(to_string(Keyword.get(opts, :query, ""))) do
        "" -> nil
        text -> "%" <> escape_like(text) <> "%"
      end

    # one row per picture: the newest copy
    newest = from(i in Image, distinct: i.sha256, order_by: [asc: i.sha256, desc: i.inserted_at, desc: i.id])
    newest = if query, do: from(i in newest, where: ilike(i.filename, ^query)), else: newest

    rows =
      from(i in subquery(newest), order_by: [desc: i.inserted_at, desc: i.id], limit: ^(@page_size + 1), offset: ^offset)
      |> Repo.all()

    %{images: Enum.take(rows, @page_size), more: length(rows) > @page_size}
  end

  @doc """
  Puts library picture `url` on the page or post whose uploads context is `context`
  (`"pages/<id>"`): the file is copied into that folder. A picture already in that folder is used
  as it is. Returns `{:ok, %{url: url, filename: name}}` or `{:error, message}`.
  """
  def use_image(context, url, user_id \\ nil) when is_binary(context) do
    with %Image{} = image <- Repo.get_by(Image, url: to_string(url)),
         {:ok, path} <- file_path(image.url),
         true <- File.regular?(path) do
      if image.context == context do
        {:ok, %{url: image.url, filename: image.filename}}
      else
        case File.read(path) do
          {:ok, bytes} ->
            InlineMedia.store(context, %{"data" => Base.encode64(bytes), "filename" => image.filename, "mimeType" => image.mime_type}, user_id: user_id)

          {:error, _} ->
            {:error, "That picture is no longer there"}
        end
      end
    else
      _ -> {:error, "That picture is no longer in the library"}
    end
  end

  @doc """
  Brings the table in step with the disk: adds pictures found in `pages/*/` and `blog/*/` that
  have no row, removes rows whose file is gone. Returns `{added, removed}`.
  """
  def sync_from_disk do
    root = Uploads.public_dir()

    on_disk =
      for kind <- @contexts,
          dir <- ls(Path.join(root, kind)),
          file <- ls(Path.join([root, kind, dir])),
          image?(file),
          not String.starts_with?(file, ["thumb_", "transcoded_"]),
          into: %{} do
        {"/uploads/public/#{kind}/#{dir}/#{file}", {"#{kind}/#{dir}", file}}
      end

    known = Repo.all(from i in Image, select: {i.id, i.url}) |> Map.new(fn {id, url} -> {url, id} end)

    added =
      for {url, {context, file}} <- on_disk, not Map.has_key?(known, url), reduce: 0 do
        count ->
          case File.read(Path.join(root, String.replace_prefix(url, "/uploads/public/", ""))) do
            {:ok, bytes} ->
              record(url, context, file, bytes, Map.get(@mimes, String.downcase(Path.extname(file))), nil)
              count + 1

            _ ->
              count
          end
      end

    gone = for {url, id} <- known, not Map.has_key?(on_disk, url), do: id
    if gone != [], do: Repo.delete_all(from i in Image, where: i.id in ^gone)

    {added, length(gone)}
  end

  defp file_path("/uploads/public/" <> rest), do: SafePath.resolve(Uploads.public_dir(), rest)
  defp file_path(_), do: :error

  defp ls(dir) do
    case File.ls(dir) do
      {:ok, names} -> names
      _ -> []
    end
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp escape_like(text), do: String.replace(text, ["\\", "%", "_"], fn c -> "\\" <> c end)
end
