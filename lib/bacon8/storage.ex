defmodule Bacon8.Storage do
  @moduledoc """
  Where file bodies live. Bodies are content-addressed: the key is the
  lowercase hex SHA-256 of the bytes, so identical uploads are stored once and
  a key can never be made to point at different content.

  Metadata (names, folders, owners, visibility) lives only in the database
  (`Bacon8.Drive`); an adapter knows nothing but keys and bytes.

  Configure with:

      config :bacon8, Bacon8.Storage,
        adapter: Bacon8.Storage.Local,
        root: "/app/uploads/_drive"

  An S3-compatible adapter can implement the same behaviour later; nothing
  outside this module names the adapter.
  """

  @type sha :: String.t()

  @doc """
  Stores the file at `src_path` under `sha` if not already present. Must be
  safe to call concurrently for the same sha. Returns `:created` or `:exists`.
  """
  @callback put_new(sha, src_path :: Path.t()) :: {:ok, :created | :exists} | {:error, term}

  @doc "A local filesystem path for `sha`, for `send_file`. Adapters without local files return `:error`."
  @callback local_path(sha) :: {:ok, Path.t()} | :error

  @callback exists?(sha) :: boolean
  @callback delete(sha) :: :ok | {:error, term}

  def adapter, do: Keyword.get(config(), :adapter, Bacon8.Storage.Local)
  def config, do: Application.get_env(:bacon8, __MODULE__, [])

  def put_new(sha, src), do: valid!(sha) && adapter().put_new(sha, src)
  def local_path(sha), do: valid!(sha) && adapter().local_path(sha)
  def exists?(sha), do: valid!(sha) && adapter().exists?(sha)
  def delete(sha), do: valid!(sha) && adapter().delete(sha)

  @doc "SHA-256 (lowercase hex) of a file, streamed so large files are fine."
  def sha256_file(path) do
    path
    |> File.stream!(2_097_152, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc "True for a well-formed key. Keys become path segments, so this is a security check."
  def valid_sha?(sha), do: is_binary(sha) and String.match?(sha, ~r/\A[0-9a-f]{64}\z/)

  defp valid!(sha) do
    valid_sha?(sha) || raise ArgumentError, "invalid storage key: #{inspect(sha)}"
  end
end
