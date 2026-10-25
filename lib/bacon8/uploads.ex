defmodule Bacon8.Uploads do
  @moduledoc """
  Centralized upload handling for all file uploads in the application.
  
  Provides consistent path generation, URL generation, and file operations
  for user uploads across different contexts (blog, forum, avatars, etc.).
  
  ## File Structure
  
  All uploads are stored under `priv/static/uploads/` with the following structure:
  - User-specific: `uploads/{user_id}/{context}/{filename}`
  - Public: `uploads/public/{context}/{filename}`
  
  ## Examples
  
      # Upload a blog featured image
      {:ok, url} = Uploads.upload_file(user, temp_path, entry, context: "blog")
      
      # Upload a forum attachment
      {:ok, url} = Uploads.upload_file(user, temp_path, entry, context: "forum")
      
      # Upload an avatar
      {:ok, url} = Uploads.upload_file(user, temp_path, entry, context: "avatar")
      
      # Upload to public directory
      {:ok, url} = Uploads.upload_file(nil, temp_path, entry, context: "public/images", public: true)
  """
  
  require Logger

  @doc """
  Get the base upload directory path (filesystem path).
  Returns absolute path like "/app/uploads" in production (mounted PVC)
  or relative path in development.
  """
  def base_dir do
    # Use /app/uploads in production (PVC mount)
    # Use local uploads directory in development
    if System.get_env("MIX_ENV") == "prod" || File.exists?("/app/uploads") do
      "/app/uploads"
    else
      Path.expand("uploads", File.cwd!())
    end
  end

  @doc """
  Get the public uploads directory path (filesystem path).
  Returns: "priv/static/uploads/public"
  """
  def public_dir do
    Path.join([base_dir(), "public"])
  end

  @doc """
  Build upload directory path for a user.
  
  ## Options
  - `:context` - Upload context (e.g., "avatar", "blog", "forum")
  - `:public` - If true, uses public directory instead of user directory
  
  ## Examples
      iex> Bacon8.Uploads.user_dir(123, context: "blog")
      "priv/static/uploads/123/blog"
      
      iex> Bacon8.Uploads.user_dir(nil, public: true, context: "images")
      "priv/static/uploads/public/images"
  """
  def user_dir(user_id, opts \\ []) do
    context = Keyword.get(opts, :context)
    public = Keyword.get(opts, :public, false)
    
    if public do
      case context do
        nil -> public_dir()
        ctx -> Path.join([public_dir(), ctx])
      end
    else
      parts = [base_dir(), to_string(user_id)]
      parts = if context, do: parts ++ [context], else: parts
      
      Path.join(parts)
    end
  end

  @doc """
  Build URL path for serving uploaded files.
  
  ## Examples
      iex> Bacon8.Uploads.url_path(123, "blog", "image.png")
      "/uploads/123/blog/image.png"
      
      iex> Bacon8.Uploads.url_path(nil, "images", "logo.png", public: true)
      "/uploads/public/images/logo.png"
  """
  def url_path(user_id, context, filename, opts \\ []) do
    public = Keyword.get(opts, :public, false)
    
    if public do
      case context do
        nil -> "/uploads/public/#{filename}"
        ctx -> "/uploads/public/#{ctx}/#{filename}"
      end
    else
      parts = ["/uploads", to_string(user_id)]
      parts = if context, do: parts ++ [context], else: parts
      parts = parts ++ [filename]
      
      Path.join(parts)
    end
  end

  @doc """
  Ensure upload directory exists, creating it if necessary.
  Returns :ok or {:error, reason}
  """
  def ensure_dir(path) do
    File.mkdir_p(path)
  end

  @doc """
  Generate a unique filename with the given extension.
  
  ## Example
      iex> Bacon8.Uploads.unique_filename(".jpg")
      "a1b2c3d4e5f6g7h8.jpg"
  """
  def unique_filename(extension) do
    random = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    "#{random}#{extension}"
  end

  @doc """
  Uploads a file from a LiveView upload entry.
  
  This is the main high-level function that combines path generation,
  directory creation, and file copying into a single operation.
  
  ## Parameters
  - `user` - The user uploading the file (or nil for public uploads)
  - `temp_path` - Temporary file path from LiveView upload (e.g., entry.path)
  - `entry` - The upload entry struct with client metadata
  - `opts` - Options:
    - `:context` - Upload context (e.g., "blog", "forum", "avatar")
    - `:public` - If true, upload to public directory
    - `:filename` - Optional custom filename (defaults to random hash + extension)
  
  ## Returns
  - `{:ok, url}` - Success with the public URL path
  - `{:error, reason}` - Failure with error reason
  
  ## Examples
      # User upload
      {:ok, url} = upload_file(user, temp_path, entry, context: "blog")
      
      # Public upload
      {:ok, url} = upload_file(nil, temp_path, entry, context: "images", public: true)
  """
  def upload_file(user, temp_path, entry, opts \\ []) do
    context = Keyword.get(opts, :context, "general")
    public = Keyword.get(opts, :public, false)
    custom_filename = Keyword.get(opts, :filename)
    
    # Generate filename
    filename = custom_filename || unique_filename(Path.extname(entry.client_name))
    
    # Generate paths
    {dest_dir, url} = if public do
      dir = user_dir(nil, public: true, context: context)
      url_path = url_path(nil, context, filename, public: true)
      {dir, url_path}
    else
      dir = user_dir(user.id, context: context)
      url_path = url_path(user.id, context, filename)
      {dir, url_path}
    end
    
    # Log for debugging
    Logger.info("Uploading file: #{entry.client_name} (#{entry.client_size} bytes) to #{dest_dir}")
    
    # Create directory
    case ensure_dir(dest_dir) do
      :ok ->
        # Copy file
        dest_file = Path.join(dest_dir, filename)
        case File.cp(temp_path, dest_file) do
          :ok ->
            Logger.info("File uploaded successfully: #{url}")

            # Best-effort background processing (thumbnail generation, transcode)
            # Skip for single-image contexts like channel icons, where only the
            # original file is ever referenced and a leftover thumbnail would
            # never get cleaned up.
            unless String.starts_with?(context, "channel_icons") do
              Task.start(fn ->
                case get_file_type(entry.client_type) do
                  "image" ->
                    thumb = Path.join(dest_dir, "thumb_#{filename}.png")
                    Bacon8.MediaProcessor.generate_thumbnail(Path.join(dest_dir, filename), thumb)
                  "video" ->
                    out = Path.join(dest_dir, "transcoded_#{filename}")
                    Bacon8.MediaProcessor.transcode_video(Path.join(dest_dir, filename), out)
                  _ -> :ok
                end
              end)
            end
              # Best-effort moderation scan
              Task.start(fn -> Bacon8.Moderation.scan_file(Path.join(dest_dir, filename)) end)

            {:ok, url}
          
          {:error, reason} ->
            Logger.error("File copy failed: #{inspect(reason)}")
            {:error, "file_copy_failed: #{inspect(reason)}"}
        end
      
      {:error, reason} ->
        Logger.error("Directory creation failed: #{inspect(reason)}")
        {:error, "mkdir_failed: #{inspect(reason)}"}
    end
  end

  @doc "Generate a signed URL for secure access to an uploaded file. Local fallback uses Phoenix.Token with a default TTL."
  def signed_url_for(url_path, opts \\ []) when is_binary(url_path) do
    # Capped at one day so a signed link can never be effectively permanent.
    expires_in = opts |> Keyword.get(:expires_in, 3600) |> min(86_400)

    # The lifetime is signed INTO the token. It used to travel as a separate
    # `expires_in` query param that the controller trusted, so anyone could
    # extend a link indefinitely by editing the URL.
    token = Phoenix.Token.sign(Bacon8Web.Endpoint, "uploads", url_path, max_age: expires_in)

    # Use URI.encode_www_form/1 so token characters are safely encoded for query params.
    "/uploads/signed?token=" <> URI.encode_www_form(token)
  end

  @doc """
  Gets the MIME type category from a MIME type string.
  
  Returns one of: "image", "video", "audio", "document", "archive", or "other"
  """
  def get_file_type(mime_type) when is_binary(mime_type) do
    cond do
      String.starts_with?(mime_type, "image/") -> "image"
      String.starts_with?(mime_type, "video/") -> "video"
      String.starts_with?(mime_type, "audio/") -> "audio"
      String.contains?(mime_type, "pdf") -> "document"
      String.contains?(mime_type, "document") -> "document"
      String.contains?(mime_type, "text") -> "document"
      String.contains?(mime_type, "zip") -> "archive"
      String.contains?(mime_type, "compressed") -> "archive"
      true -> "other"
    end
  end

  def get_file_type(_), do: "other"

  @doc """
  Formats file size in bytes to human-readable format.
  """
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes >= 1_099_511_627_776 -> "#{Float.round(bytes / 1_099_511_627_776, 2)} TB"
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_bytes(_), do: "0 B"

  @doc """
  Deletes an uploaded file given its URL path.
  
  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def delete_file(url_path) when is_binary(url_path) do
    # Convert URL path to filesystem path, confined to base_dir(): nil when it climbs out
    file_path = url_to_path(url_path)

    case (if file_path, do: File.rm(file_path), else: {:error, :invalid_path}) do
      :ok ->
        Logger.info("Deleted file: #{url_path}")

        # Attempt to remove parent directory if empty
        parent_dir = Path.dirname(file_path)
        case File.ls(parent_dir) do
          {:ok, []} -> 
            case File.rmdir(parent_dir) do
              :ok -> Logger.info("Removed empty directory: #{parent_dir}")
              {:error, reason} -> Logger.warning("Failed to remove empty directory #{parent_dir}: #{inspect(reason)}")
            end
          _ -> :ok # Directory not empty or error listing it
        end

        :ok
      
      {:error, reason} ->
        Logger.error("Failed to delete file #{url_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def delete_file(_), do: {:error, :invalid_path}

  @doc """
  Checks if a file exists at the given URL path.
  """
  def file_exists?(url_path) when is_binary(url_path) do
    file_path = url_to_path(url_path)

    file_path != nil and File.exists?(file_path)
  end

  def file_exists?(_), do: false

  @doc """
  Gets the absolute filesystem path from a URL path.
  """
  def url_to_path(url_path) when is_binary(url_path) do
    # Confined to base_dir(): "/uploads/../config/x" must not resolve outside it.
    Bacon8.SafePath.resolve!(base_dir(), String.replace_prefix(url_path, "/uploads/", ""))
  end

  def url_to_path(_), do: nil

  @doc """
  Delete all uploaded files for a blog post or page.
  Removes the entire upload directory for the given content type and ID.
  
  ## Parameters
  - `content_type` - Either "blog" or "pages"
  - `content_id` - The ID of the blog post or page
  
  ## Returns
  - `:ok` - Directory deleted or didn't exist
  - `{:error, reason}` - Failure with error reason
  
  ## Examples
      delete_content_uploads("blog", 123)
      delete_content_uploads("pages", 456)
  """
  def delete_content_uploads(content_type, content_id) when content_type in ["blog", "pages"] do
    dir = Path.join([public_dir(), content_type, to_string(content_id)])
    
    if File.exists?(dir) do
      case File.rm_rf(dir) do
        {:ok, _files} -> 
          Logger.info("Deleted uploads directory: #{dir}")
          :ok
        {:error, reason, file} -> 
          Logger.error("Failed to delete uploads: #{inspect(reason)} - #{file}")
          {:error, reason}
      end
    else
      :ok
    end
  end

  @doc """
  Lists all uploaded files for a user in a specific context.
  Returns a list of maps with file details.
  """
  def list_user_uploads(user_id, context) do
    dir = user_dir(user_id, context: context)
    
    if File.exists?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(fn file -> 
        # Filter out thumbnails if they exist in the same dir
        !String.starts_with?(file, "thumb_") && 
        !String.starts_with?(file, "transcoded_")
      end)
      |> Enum.map(fn filename ->
        path = Path.join(dir, filename)
        stat = File.stat!(path)
        url = url_path(user_id, context, filename)
        
        %{
          filename: filename,
          url: url,
          size: stat.size,
          updated_at: stat.mtime
        }
      end)
      |> Enum.sort_by(&(&1.updated_at), :desc)
    else
      []
    end
  end
end
