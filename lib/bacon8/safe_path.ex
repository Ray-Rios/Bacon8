defmodule Bacon8.SafePath do
  @moduledoc """
  Confines user-supplied paths to a root directory.

  `Path.join/2` does not resolve `..`, so `Path.join("/app/uploads/users/1", "../2/x")`
  is `/app/uploads/users/1/../2/x` - which the OS happily resolves to user 2's file.
  Every place that turns a client-supplied path or filename into a filesystem path
  must go through `resolve/2` (for paths) or `filename/1` (for a single name).

  Note: `Path.expand/1` is lexical - it does not follow symlinks. That is fine as
  long as nothing lets a user create a symlink under an uploads root.
  """

  @doc """
  Joins `subpath` onto `root` and returns `{:ok, absolute_path}` only if the result
  is `root` itself or lies inside it. Returns `:error` for traversal, absolute
  subpaths that escape, NUL bytes, or non-binary input.

      iex> Bacon8.SafePath.resolve("/srv/up", "a/b.png")
      {:ok, "/srv/up/a/b.png"}
      iex> Bacon8.SafePath.resolve("/srv/up", "../etc/passwd")
      :error
  """
  def resolve(root, subpath \\ "")

  def resolve(root, subpath) when is_binary(root) and is_binary(subpath) do
    if String.contains?(root <> subpath, <<0>>) do
      :error
    else
      root = Path.expand(root)
      # Strip leading slashes so an "absolute" subpath is treated as relative to root.
      relative = String.trim_leading(subpath, "/")
      candidate = Path.expand(relative, root)

      if inside?(candidate, root), do: {:ok, candidate}, else: :error
    end
  end

  def resolve(_root, _subpath), do: :error

  @doc "Like `resolve/2` but returns the path or `nil`."
  def resolve!(root, subpath \\ "") do
    case resolve(root, subpath) do
      {:ok, path} -> path
      :error -> nil
    end
  end

  @doc "True when `path` is `root` or a descendant of it (both expanded)."
  def inside?(path, root) when is_binary(path) and is_binary(root) do
    path = Path.expand(path)
    root = Path.expand(root)
    path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")
  end

  def inside?(_, _), do: false

  @doc """
  Reduces a client-supplied filename to a safe single path segment, or `nil`.

  Drops any directory part (both `/` and `\\`), control characters and NUL, and
  rejects empty names, `.` and `..`. Use this for upload `client_name`s and for
  user-typed folder names.
  """
  def filename(name) when is_binary(name) do
    cleaned =
      name
      |> String.replace("\\", "/")
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/[\x00-\x1F\x7F]/u, "")
      |> String.trim()
      |> String.slice(0, 255)

    if cleaned in ["", ".", ".."], do: nil, else: cleaned
  end

  def filename(_), do: nil

  # Extensions a browser will execute as active content if served inline from our
  # origin. Uploads with these are refused; anything already on disk with them is
  # served with a sandbox CSP + attachment disposition by UploadsGuard.
  @active_content_exts ~w(.html .htm .xhtml .shtml .svg .svgz .xml .xsl .xslt .js .mjs .swf .hta .php .phtml)

  @doc "True for file types that run script when rendered by a browser."
  def active_content?(name) when is_binary(name) do
    String.downcase(Path.extname(name)) in @active_content_exts
  end

  def active_content?(_), do: false
end
