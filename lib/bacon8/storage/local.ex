defmodule Bacon8.Storage.Local do
  @moduledoc """
  Stores blobs on a local volume as `<root>/<aa>/<bb>/<sha256>`.

  `root` must NOT be served by `Plug.Static`. The default lives under the
  uploads volume (`/app/uploads/_drive`), which *is* served at `/uploads`, so
  `Bacon8Web.Plugs.UploadsGuard` refuses every `/uploads/_drive/...` request.
  See BACON8.md §6.
  """
  @behaviour Bacon8.Storage

  @impl true
  def put_new(sha, src_path) do
    dest = path_for(sha)

    if File.regular?(dest) do
      {:ok, :exists}
    else
      tmp = dest <> ".tmp-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

      with :ok <- File.mkdir_p(Path.dirname(dest)),
           {:ok, _} <- File.copy(src_path, tmp),
           # rename(2) within one directory is atomic: readers see either no
           # file or the whole file, and two writers of the same sha both win.
           :ok <- File.rename(tmp, dest) do
        {:ok, :created}
      else
        error ->
          File.rm(tmp)
          error
      end
    end
  end

  @impl true
  def local_path(sha) do
    path = path_for(sha)
    if File.regular?(path), do: {:ok, path}, else: :error
  end

  @impl true
  def exists?(sha), do: File.regular?(path_for(sha))

  @impl true
  def delete(sha) do
    case File.rm(path_for(sha)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @doc false
  def path_for(<<a::binary-size(2), b::binary-size(2), _::binary>> = sha),
    do: Path.join([root(), a, b, sha])

  def root do
    Keyword.get(Bacon8.Storage.config(), :root) ||
      if(File.dir?("/app/uploads"), do: "/app/uploads/_drive", else: Path.expand("uploads/_drive"))
  end
end
