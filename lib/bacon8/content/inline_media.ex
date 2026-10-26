defmodule Bacon8.Content.InlineMedia do
  @moduledoc """
  Pictures and files a staff member drops into a page or post while editing it in place:
  the block editor sends the bytes over the LiveView socket as base64, with a file name
  the browser chose, and later sends back a URL to delete.

  Both ends take client input, so both go through `Bacon8.SafePath`. Before this module
  (the same code sat in `PageLive` and `BlogLive`) the temp file was named from the client's
  file name, so `../../x` wrote, and afterwards deleted, a file outside the temp directory,
  and "remove" joined any `/uploads/public/...` URL onto the uploads directory without
  resolving `..`, so it could delete files anywhere the app could write.

  A `context` is `"pages/<id>"` or `"blog/<id>"`: files live in `uploads/public/<context>/`,
  and a page can only remove its own.

  File types a browser would run (HTML, SVG, XML, JavaScript; `SafePath.active_content?/1`) are
  refused, as BACON8.md invariant 4 requires of every upload (reviewed 2026-10-25: this module
  used to accept them and rely on `UploadsGuard` alone).
  """
  alias Bacon8.{SafePath, Uploads}

  # What the Drive allows a member to upload at once; a block editor has no business with more.
  @max_bytes 25 * 1024 * 1024

  # Base64 spends 4 bytes for every 3. Anything longer than this cannot decode to @max_bytes or
  # less, so it is refused before decoding (which would hold both copies in memory).
  @max_encoded div(@max_bytes + 2, 3) * 4

  @doc """
  Stores an upload from the block editor's event (`"data"` is base64, `"filename"` and
  `"mimeType"` are the browser's). Returns `{:ok, %{url: url, filename: name}}`, where `name`
  is the cleaned file name, or `{:error, message}` fit to show the editor.
  """
  def store(context, %{"data" => data} = params) when is_binary(data) do
    with {:ok, bytes} <- decode(data),
         {:ok, name} <- clean_name(params["filename"]),
         :ok <- allowed_type(name) do
      temp = Path.join(System.tmp_dir!(), "b8_inline_#{System.unique_integer([:positive])}#{Path.extname(name)}")

      try do
        entry = %{
          client_name: name,
          client_type: mime(params["mimeType"]),
          client_size: byte_size(bytes)
        }

        with :ok <- File.write(temp, bytes),
             {:ok, url} <- Uploads.upload_file(nil, temp, entry, context: context, public: true) do
          {:ok, %{url: url, filename: name}}
        else
          {:error, reason} -> {:error, "Upload failed: #{inspect(reason)}"}
        end
      after
        File.rm(temp)
      end
    end
  end

  def store(_context, _params), do: {:error, "Invalid file data"}

  @doc """
  Deletes the file at `url` if it is one of this context's own uploads
  (`/uploads/public/<context>/<file>`). Anything else, including a URL that climbs out with
  `..`, a directory, or another page's file, is ignored. Returns `:ok` or `:ignored`.
  """
  def remove(context, "/uploads/public/" <> rest) do
    root = Path.join(Uploads.public_dir(), context)

    with {:ok, path} <- SafePath.resolve(Uploads.public_dir(), rest),
         true <- path != Path.expand(root) and SafePath.inside?(path, root),
         true <- File.regular?(path),
         :ok <- File.rm(path) do
      :ok
    else
      _ -> :ignored
    end
  end

  def remove(_context, _url), do: :ignored

  defp decode(data) when byte_size(data) > @max_encoded, do: {:error, "File too large"}

  defp decode(data) do
    case Base.decode64(data) do
      {:ok, bytes} when byte_size(bytes) > @max_bytes -> {:error, "File too large"}
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, "Invalid file data"}
    end
  end

  defp clean_name(nil), do: {:ok, "upload_#{System.unique_integer([:positive])}"}

  defp clean_name(name) do
    case SafePath.filename(name) do
      nil -> {:error, "Invalid file name"}
      clean -> {:ok, clean}
    end
  end

  # BACON8.md invariant 4: a type a browser would run is never accepted from a client.
  defp allowed_type(name) do
    if SafePath.active_content?(name), do: {:error, "That type of file can't be added here"}, else: :ok
  end

  defp mime(type) when is_binary(type) and type != "", do: type
  defp mime(_), do: "application/octet-stream"
end
