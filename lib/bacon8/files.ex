defmodule Bacon8.Files do
  @moduledoc """
  The Files context for comprehensive file management operations.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Files.UserFile
  alias Bacon8.Files.UserFolder

  # ==================== FOLDER OPERATIONS ====================

  @doc "List all folders for a user"
  def list_user_folders(user) do
    try do
      from(f in UserFolder, where: f.user_id == ^user.id, order_by: [asc: f.path])
      |> Repo.all()
    rescue
      # Table doesn't exist yet (migration not run) or any other error
      _ -> []
    end
  end

  @doc "List folders at a specific path (direct children)"
  def list_folders_at_path(user, parent_path \\ "/") do
    try do
      from(f in UserFolder, 
        where: f.user_id == ^user.id and f.parent_path == ^parent_path,
        order_by: [asc: f.name]
      )
      |> Repo.all()
    rescue
      # Table doesn't exist yet (migration not run) or any other error
      _ -> []
    end
  end

  @doc "Get a folder by path"
  def get_folder_by_path(user, path) do
    try do
      from(f in UserFolder, where: f.user_id == ^user.id and f.path == ^path)
      |> Repo.one()
    rescue
      _ -> nil
    end
  end

  @doc "Create a new folder"
  def create_folder(user, name, parent_path \\ "/") do
    try do
      # Normalize parent path
      parent_path = normalize_path(parent_path)
      
      # Build full path
      full_path = if parent_path == "/" do
        "/" <> name
      else
        parent_path <> "/" <> name
      end

      %UserFolder{}
      |> UserFolder.changeset(%{
        name: name,
        path: full_path,
        parent_path: parent_path,
        user_id: user.id
      })
      |> Repo.insert()
    rescue
      # Table doesn't exist yet
      Postgrex.Error -> {:error, :migration_pending}
    end
  end

  @doc "Delete a folder and optionally its contents"
  def delete_folder(user, path, delete_contents \\ false) do
    case get_folder_by_path(user, path) do
      nil -> 
        {:error, :not_found}
      folder ->
        if delete_contents do
          # Delete all files in this folder and subfolders
          delete_folder_contents(user, path)
        else
          # Check if folder is empty
          if folder_has_contents?(user, path) do
            {:error, :folder_not_empty}
          else
            Repo.delete(folder)
          end
        end
    end
  end

  defp delete_folder_contents(user, path) do
    # Delete all files in this folder path (and subfolders)
    from(f in UserFile, 
      where: f.user_id == ^user.id and (f.folder_path == ^path or like(f.folder_path, ^"#{path}/%"))
    )
    |> Repo.delete_all()

    # Delete all media in this folder path
    from(m in Bacon8.Content.UserMedia, 
      where: m.user_id == ^user.id and (m.folder_path == ^path or like(m.folder_path, ^"#{path}/%"))
    )
    |> Repo.delete_all()

    # Delete subfolders
    from(f in UserFolder, 
      where: f.user_id == ^user.id and like(f.path, ^"#{path}/%")
    )
    |> Repo.delete_all()

    # Delete the folder itself
    from(f in UserFolder, where: f.user_id == ^user.id and f.path == ^path)
    |> Repo.delete_all()

    :ok
  end

  defp folder_has_contents?(user, path) do
    file_count = from(f in UserFile, 
      where: f.user_id == ^user.id and f.folder_path == ^path, 
      select: count()
    ) |> Repo.one() || 0

    media_count = from(m in Bacon8.Content.UserMedia, 
      where: m.user_id == ^user.id and m.folder_path == ^path, 
      select: count()
    ) |> Repo.one() || 0

    subfolder_count = from(f in UserFolder, 
      where: f.user_id == ^user.id and f.parent_path == ^path, 
      select: count()
    ) |> Repo.one() || 0

    file_count > 0 || media_count > 0 || subfolder_count > 0
  end

  @doc "Rename a folder"
  def rename_folder(user, path, new_name) do
    case get_folder_by_path(user, path) do
      nil -> 
        {:error, :not_found}
      folder ->
        new_path = Path.join(folder.parent_path, new_name) |> normalize_path()
        
        # Update folder
        folder
        |> UserFolder.changeset(%{name: new_name, path: new_path})
        |> Repo.update()
        |> case do
          {:ok, updated_folder} ->
            # Update all files and subfolders with the old path
            update_paths_after_rename(user, path, new_path)
            {:ok, updated_folder}
          error -> error
        end
    end
  end

  defp update_paths_after_rename(user, old_path, new_path) do
    # Update files
    from(f in UserFile, 
      where: f.user_id == ^user.id and f.folder_path == ^old_path
    )
    |> Repo.update_all(set: [folder_path: new_path])

    from(f in UserFile, 
      where: f.user_id == ^user.id and like(f.folder_path, ^"#{old_path}/%")
    )
    |> Repo.all()
    |> Enum.each(fn file ->
      new_folder_path = String.replace(file.folder_path, old_path, new_path, global: false)
      file |> Ecto.Changeset.change(%{folder_path: new_folder_path}) |> Repo.update!()
    end)

    # Update media
    from(m in Bacon8.Content.UserMedia, 
      where: m.user_id == ^user.id and m.folder_path == ^old_path
    )
    |> Repo.update_all(set: [folder_path: new_path])

    # Update subfolders
    from(f in UserFolder, 
      where: f.user_id == ^user.id and f.parent_path == ^old_path
    )
    |> Repo.update_all(set: [parent_path: new_path])

    from(f in UserFolder, 
      where: f.user_id == ^user.id and like(f.path, ^"#{old_path}/%")
    )
    |> Repo.all()
    |> Enum.each(fn folder ->
      new_folder_path = String.replace(folder.path, old_path, new_path, global: false)
      new_parent_path = String.replace(folder.parent_path, old_path, new_path, global: false)
      folder |> Ecto.Changeset.change(%{path: new_folder_path, parent_path: new_parent_path}) |> Repo.update!()
    end)
  end

  @doc "Move a file to a different folder"
  def move_file(user, file_id, new_folder_path) do
    new_folder_path = normalize_path(new_folder_path)
    
    case get_user_file(user, file_id) do
      nil -> {:error, :not_found}
      file ->
        file
        |> Ecto.Changeset.change(%{folder_path: new_folder_path})
        |> Repo.update()
    end
  end

  defp get_user_file(user, id) do
    from(f in UserFile, where: f.user_id == ^user.id and f.id == ^id)
    |> Repo.one()
  end

  defp normalize_path(""), do: "/"
  defp normalize_path(nil), do: "/"
  defp normalize_path("/" <> _ = path) do
    case String.trim_trailing(path, "/") do
      "" -> "/"
      p -> p
    end
  end
  defp normalize_path(path), do: "/" <> String.trim_trailing(path, "/")

  # ==================== FILE LISTING WITH FOLDERS ====================

  @doc "List files and folders at a specific path"
  def list_contents_at_path(user, path \\ "/") do
    try do
      path = normalize_path(path)
      
      # Get folders at this path
      folders = list_folders_at_path(user, path)
      |> Enum.map(fn folder ->
        %{
          id: folder.id,
          name: folder.name,
          type: :folder,
          path: folder.path,
          icon: Map.get(folder, :icon) || "📁",
          color: Map.get(folder, :color),
          inserted_at: folder.inserted_at,
          file_size: 0,
          content_type: "folder"
        }
      end)

      # Get files at this path (UserFile + UserMedia)
      files = list_files_at_path(user, path)
      
      # Also include forum attachments (these are actual uploaded working files)
      attachments = list_user_attachments(user, path)
      
      folders ++ files ++ attachments
    rescue
      e ->
        require Logger
        Logger.warning("Error listing contents at path: #{inspect(e)}")
        # Fall back to listing all user files
        list_all_user_content(user)
        |> Enum.map(fn file ->
          %{
            id: file.id,
            name: file.original_filename || file.filename,
            filename: file.filename,
            original_filename: file.original_filename,
            file_size: file.file_size,
            content_type: file.content_type,
            folder_path: "/",
            url: file.url,
            inserted_at: file.inserted_at,
            type: :file,
            source_type: file.type,
            source: file
          }
        end)
    end
  end

  @doc "List files at a specific folder path"
  def list_files_at_path(user, folder_path \\ "/") do
    folder_path = normalize_path(folder_path)
    
    # For root path ("/"), list all files (backwards compatible before folder_path migration)
    # This also handles the case where folder_path column doesn't exist yet
    user_files = try do
      if folder_path == "/" do
        # At root, show files that have no folder_path or folder_path = "/"
        from(f in UserFile, 
          where: f.user_id == ^user.id and (is_nil(f.folder_path) or f.folder_path == "/" or f.folder_path == ""),
          order_by: [desc: f.inserted_at]
        )
        |> Repo.all()
      else
        from(f in UserFile, 
          where: f.user_id == ^user.id and f.folder_path == ^folder_path,
          order_by: [desc: f.inserted_at]
        )
        |> Repo.all()
      end
    rescue
      # If folder_path column doesn't exist or any error, fall back to listing all files at root
      _ ->
        if folder_path == "/" do
          from(f in UserFile, where: f.user_id == ^user.id, order_by: [desc: f.inserted_at])
          |> Repo.all()
        else
          []
        end
    end
    |> Enum.map(fn f -> 
      %{
        id: f.id,
        name: f.original_filename || f.filename,
        filename: f.filename,
        original_filename: f.original_filename,
        file_size: f.file_size,
        content_type: f.content_type,
        folder_path: Map.get(f, :folder_path, "/"),
        url: safe_file_url(f),
        inserted_at: f.inserted_at,
        type: :file,
        source_type: :user_file,
        source: f
      }
    end)

    user_media = try do
      if folder_path == "/" do
        from(m in Bacon8.Content.UserMedia, 
          where: m.user_id == ^user.id and (is_nil(m.folder_path) or m.folder_path == "/" or m.folder_path == ""),
          order_by: [desc: m.inserted_at]
        )
        |> Repo.all()
      else
        from(m in Bacon8.Content.UserMedia, 
          where: m.user_id == ^user.id and m.folder_path == ^folder_path,
          order_by: [desc: m.inserted_at]
        )
        |> Repo.all()
      end
    rescue
      # If folder_path column doesn't exist or any error, fall back to listing all media at root
      _ ->
        if folder_path == "/" do
          from(m in Bacon8.Content.UserMedia, where: m.user_id == ^user.id, order_by: [desc: m.inserted_at])
          |> Repo.all()
        else
          []
        end
    end
    # Note: Stale media filtering disabled to prevent potential issues
    # Old records with broken URLs will show as 404 when accessed
    |> Enum.map(fn m -> 
      %{
        id: m.id,
        name: m.original_filename || m.filename,
        filename: m.filename,
        original_filename: m.original_filename,
        file_size: m.file_size,
        content_type: m.mime_type,
        folder_path: Map.get(m, :folder_path, "/"),
        url: m.url,
        inserted_at: m.inserted_at,
        type: :file,
        source_type: :user_media,
        source: m
      }
    end)

    (user_files ++ user_media)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  # Chat attachments belong to the chat_channels plugin, which a site may not install: the
  # schema is looked up when needed, and without it there are none.
  defp attachment_schema do
    schema = Module.concat([ChatChannels, MessageAttachment])
    if Code.ensure_loaded?(schema), do: schema, else: nil
  end

  @doc "List forum/chat attachments for a user - these are actual uploaded files"
  def list_user_attachments(user, folder_path \\ "/") do
    schema = attachment_schema()

    # Only show at root level for now (these don't have folder structure)
    if folder_path == "/" and schema do
      try do
        from(a in schema, 
          where: a.user_id == ^user.id,
          order_by: [desc: a.inserted_at]
        )
        |> Repo.all()
        |> Enum.map(fn a -> 
          %{
            id: a.id,
            name: a.original_filename || a.filename,
            filename: a.filename,
            original_filename: a.original_filename,
            file_size: a.file_size,
            content_type: a.content_type,
            folder_path: "/",
            url: a.url,
            inserted_at: a.inserted_at,
            type: :file,
            source_type: :message_attachment,
            source: a
          }
        end)
      rescue
        _ -> []
      end
    else
      []
    end
  end
  def list_user_files(user) do
    try do
      from(f in UserFile, where: f.user_id == ^user.id, order_by: [desc: f.inserted_at])
      |> Repo.all()
    rescue
      _ ->
        # Fallback: Select specific fields that we know exist (excluding folder_path if missing)
        from(f in UserFile, 
          where: f.user_id == ^user.id, 
          order_by: [desc: f.inserted_at],
          select: %{
            id: f.id,
            filename: f.filename,
            original_filename: f.original_filename,
            content_type: f.content_type,
            file_size: f.file_size,
            file_path: f.file_path,
            is_public: f.is_public,
            description: f.description,
            tags: f.tags,
            user_id: f.user_id,
            inserted_at: f.inserted_at,
            updated_at: f.updated_at,
            file: f.file
          }
        )
        |> Repo.all()
        |> Enum.map(fn data -> 
          struct(UserFile, Map.put(data, :folder_path, "/"))
        end)
    end
  end

  def list_all_user_content(user) do
    files = list_user_files(user)
    media = Bacon8.Content.list_user_media(user)
    
    # Also include forum message attachments (these are actual working uploads)
    attachments =
      case attachment_schema() do
        nil ->
          []

        schema ->
          try do
            from(a in schema,
              where: a.user_id == ^user.id,
              order_by: [desc: a.inserted_at]
            )
            |> Repo.all()
          rescue
            _ -> []
          end
      end
    
    # Normalize
    normalized_files = Enum.map(files, fn f -> 
      %{
        id: f.id,
        filename: f.filename,
        original_filename: f.original_filename,
        file_size: f.file_size,
        content_type: f.content_type,
        url: safe_file_url(f),
        inserted_at: f.inserted_at,
        type: :file,
        source: f
      }
    end)
    
    normalized_media = Enum.map(media, fn m -> 
      %{
        id: m.id,
        filename: m.filename,
        original_filename: m.original_filename,
        file_size: m.file_size,
        content_type: m.mime_type,
        url: m.url,
        inserted_at: m.inserted_at,
        type: :media,
        source: m
      }
    end)
    
    normalized_attachments = Enum.map(attachments, fn a ->
      %{
        id: a.id,
        filename: a.filename,
        original_filename: a.original_filename,
        file_size: a.file_size,
        content_type: a.content_type,
        url: a.url,
        inserted_at: a.inserted_at,
        type: :attachment,
        source: a
      }
    end)
    
    (normalized_files ++ normalized_media ++ normalized_attachments)
    |> Enum.sort_by(& &1.inserted_at, {:desc, Date})
  end

  def get_user_file!(user, id) do
    from(f in UserFile, where: f.user_id == ^user.id and f.id == ^id)
    |> Repo.one!()
  end

  def create_user_file(user, attrs \\ %{}) do
    # Handle Base64 data from JavaScript
    attrs = prepare_file_attrs(attrs)
    
    # Check storage limit
    file_size = attrs["file_size"] || 0
    case check_storage_limit(user, file_size) do
      :ok ->
        # Ensure uploads directory exists
        ensure_uploads_directory(user)
        
        changeset = %UserFile{}
        |> UserFile.changeset(attrs)
        |> Ecto.Changeset.put_assoc(:user, user)
        
        Repo.insert(changeset)
      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_user_file(%UserFile{} = user_file, attrs) do
    user_file
    |> UserFile.changeset(attrs)
    |> Repo.update()
  end

  def delete_user_file(%UserFile{} = user_file) do
    Repo.delete(user_file)
  end

  def change_user_file(%UserFile{} = user_file, attrs \\ %{}) do
    UserFile.changeset(user_file, attrs)
  end

  def get_file_stats(user) do
    file_query = from f in UserFile, where: f.user_id == ^user.id
    media_query = from m in Bacon8.Content.UserMedia, where: m.user_id == ^user.id
    
    file_stats = %{
      count: Repo.aggregate(file_query, :count) || 0,
      size: Repo.aggregate(file_query, :sum, :file_size) || 0,
      images: Repo.aggregate(from(f in file_query, where: like(f.content_type, "image/%")), :count) || 0,
      videos: Repo.aggregate(from(f in file_query, where: like(f.content_type, "video/%")), :count) || 0,
      audio: Repo.aggregate(from(f in file_query, where: like(f.content_type, "audio/%")), :count) || 0,
      documents: Repo.aggregate(from(f in file_query, where: f.content_type in ["application/pdf", "application/msword", "text/plain"]), :count) || 0
    }

    media_stats = %{
      count: Repo.aggregate(media_query, :count) || 0,
      size: Repo.aggregate(media_query, :sum, :file_size) || 0,
      images: Repo.aggregate(from(m in media_query, where: like(m.mime_type, "image/%")), :count) || 0,
      videos: Repo.aggregate(from(m in media_query, where: like(m.mime_type, "video/%")), :count) || 0,
      audio: Repo.aggregate(from(m in media_query, where: like(m.mime_type, "audio/%")), :count) || 0,
      documents: Repo.aggregate(from(m in media_query, where: m.mime_type in ["application/pdf", "application/msword", "text/plain"]), :count) || 0
    }

    %{
      total_files: file_stats.count + media_stats.count,
      total_size: file_stats.size + media_stats.size,
      images: file_stats.images + media_stats.images,
      videos: file_stats.videos + media_stats.videos,
      audio: file_stats.audio + media_stats.audio,
      documents: file_stats.documents + media_stats.documents
    }
  end

  def search_files(user, query) do
    search_term = "%#{query}%"
    
    from(f in UserFile, 
      where: f.user_id == ^user.id and ilike(f.filename, ^search_term),
      order_by: [desc: f.inserted_at]
    )
    |> Repo.all()
  end

  def count_files do
    Repo.aggregate(UserFile, :count)
  end

  # Admin functions - list all files across all users
  def list_all_user_files do
    from(f in UserFile, order_by: [desc: f.inserted_at], preload: [:user])
    |> Repo.all()
  end

  def get_user_file_by_id!(id) do
    Repo.get!(UserFile, id)
  end

  def delete_user_file_by_id(id) when is_binary(id) do
    case Repo.get(UserFile, id) do
      nil -> {:error, :not_found}
      file -> Repo.delete(file)
    end
  end

  def get_user_data_usage(user_id) do
    # Get total size from UserFile uploads (convert Decimal to integer)
    user_files_size = 
      case from(f in UserFile, where: f.user_id == ^user_id, select: sum(f.file_size)) |> Repo.one() do
        nil -> 0
        %Decimal{} = decimal -> Decimal.to_integer(decimal)
        size -> size
      end

    # Get total size from UserMedia uploads (convert Decimal to integer)
    user_media_size = 
      case from(m in Bacon8.Content.UserMedia, where: m.user_id == ^user_id, select: sum(m.file_size)) |> Repo.one() do
        nil -> 0
        %Decimal{} = decimal -> Decimal.to_integer(decimal)
        size -> size
      end

    # Get total size from MessageAttachment uploads (convert Decimal to integer)
    message_attachments_size = 
      case (if schema = attachment_schema(), do: from(m in schema, where: m.user_id == ^user_id, select: sum(m.file_size)) |> Repo.one()) do
        nil -> 0
        %Decimal{} = decimal -> Decimal.to_integer(decimal)
        size -> size
      end

    # Get count of files
    user_files_count = from(f in UserFile, where: f.user_id == ^user_id, select: count()) |> Repo.one() || 0
    user_media_count = from(m in Bacon8.Content.UserMedia, where: m.user_id == ^user_id, select: count()) |> Repo.one() || 0
    message_attachments_count = (if schema = attachment_schema(), do: from(m in schema, where: m.user_id == ^user_id, select: count()) |> Repo.one()) || 0

    total_size = user_files_size + user_media_size + message_attachments_size
    total_count = user_files_count + user_media_count + message_attachments_count

    %{
      total_size_bytes: total_size,
      total_files: total_count,
      user_files_size: user_files_size,
      user_media_size: user_media_size,
      message_attachments_size: message_attachments_size,
      user_files_count: user_files_count,
      user_media_count: user_media_count,
      message_attachments_count: message_attachments_count,
      limit: get_storage_limit(user_id)
    }
  end

  def get_storage_limit(user_id) do
    user = Bacon8.Accounts.get_user!(user_id)
    case user.role do
      "admin" -> 100 * 1024 * 1024 * 1024 # 100 GB
      "gm" -> 50 * 1024 * 1024 * 1024 # 50 GB
      "editor" -> 10 * 1024 * 1024 * 1024 # 10 GB
      "moderator" -> 5 * 1024 * 1024 * 1024 # 5 GB
      "member" -> 1 * 1024 * 1024 * 1024 # 1 GB
      _ -> 500 * 1024 * 1024 # 500 MB
    end
  end

  def check_storage_limit(user, new_file_size) do
    usage = get_user_data_usage(user.id)
    if usage.total_size_bytes + new_file_size > usage.limit do
      {:error, "Storage limit exceeded"}
    else
      :ok
    end
  end

  def get_all_users_data_usage do
    # Get data usage for all users
    user_files_query = from(f in UserFile,
      select: %{user_id: f.user_id, size: sum(f.file_size), count: count()},
      group_by: f.user_id
    )

    user_media_query = from(m in Bacon8.Content.UserMedia,
      select: %{user_id: m.user_id, size: sum(m.file_size), count: count()},
      group_by: m.user_id
    )

    user_files_data = Repo.all(user_files_query) |> Enum.into(%{}, fn r -> {r.user_id, r} end)
    user_media_data = Repo.all(user_media_query) |> Enum.into(%{}, fn r -> {r.user_id, r} end)

    # Combine data for all users
    all_user_ids = Map.keys(user_files_data) ++ Map.keys(user_media_data) |> Enum.uniq()

    Enum.map(all_user_ids, fn user_id ->
      files_data = Map.get(user_files_data, user_id, %{size: 0, count: 0})
      media_data = Map.get(user_media_data, user_id, %{size: 0, count: 0})

      %{
        user_id: user_id,
        total_size_bytes: files_data.size + media_data.size,
        total_files: files_data.count + media_data.count,
        user_files_size: files_data.size,
        user_media_size: media_data.size,
        user_files_count: files_data.count,
        user_media_count: media_data.count
      }
    end)
    |> Enum.sort_by(& &1.total_size_bytes, :desc)
  end

  # Public/admin file operations
  def list_public_files(role \\ :user) when role in [:admin, :gm, :editor, :user] do
    query = case role do
      :user -> from(f in UserFile, where: f.is_public == true)
      _ -> from(f in UserFile) # Admin/GM/Editor can see all files
    end
    
    query |> order_by([desc: :inserted_at]) |> Repo.all()
  end

  def get_public_file!(id, role \\ :user) do
    query = case role do
      :user -> from(f in UserFile, where: f.id == ^id and f.is_public == true)
      _ -> from(f in UserFile, where: f.id == ^id) # Admin/GM/Editor can access all files
    end
    
    Repo.one!(query)
  end

  # File type helpers
  def is_image?(%{content_type: content_type}), do: String.starts_with?(content_type, "image/")
  def is_video?(%{content_type: content_type}), do: String.starts_with?(content_type, "video/")
  def is_audio?(%{content_type: content_type}), do: String.starts_with?(content_type, "audio/")
  def is_document?(%{content_type: content_type}) do
    content_type in ["application/pdf", "application/msword", "text/plain", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
  end

  def format_file_size(size_bytes) when is_integer(size_bytes) do
    cond do
      size_bytes >= 1_073_741_824 -> "#{Float.round(size_bytes / 1_073_741_824, 2)} GB"
      size_bytes >= 1_048_576 -> "#{Float.round(size_bytes / 1_048_576, 2)} MB"
      size_bytes >= 1024 -> "#{Float.round(size_bytes / 1024, 2)} KB"
      true -> "#{size_bytes} B"
    end
  end
  def format_file_size(_), do: "0 B"

  # Private helper functions
  defp prepare_file_attrs(%{"data" => "data:" <> data_url} = attrs) do
    # Parse Base64 data URL
    [metadata, base64_data] = String.split(data_url, ";base64,", parts: 2)
    content_type = String.replace(metadata, "data:", "")
    
    # Decode Base64 data
    {:ok, file_data} = Base.decode64(base64_data)
    
    # Create a temporary file for Arc to process
    filename = attrs["name"] || "upload"
    temp_path = System.tmp_dir!() |> Path.join("upload_#{System.unique_integer()}_#{filename}")
    File.write!(temp_path, file_data)
    
    # Create Plug.Upload-like struct that Arc can handle
    file_upload = %Plug.Upload{
      filename: filename,
      path: temp_path,
      content_type: content_type
    }
    
    # Schedule temp file cleanup
    Task.start(fn ->
      :timer.sleep(10000) # Wait 10 seconds for Arc to process
      if File.exists?(temp_path), do: File.rm!(temp_path)
    end)
    
    %{
      "file" => file_upload,
      "original_filename" => filename,
      "filename" => Path.basename(filename, Path.extname(filename)),
      "content_type" => content_type,
      "file_size" => byte_size(file_data)
    }
  end
  
  defp prepare_file_attrs(attrs) when is_map(attrs) do
    attrs
  end
  
  defp ensure_uploads_directory(user) do
    # Use Bacon8.Uploads to get the path
    # This ensures consistency with other uploads
    user_dir = Bacon8.Uploads.user_dir(user.id, context: "files")
    File.mkdir_p!(user_dir)
  end

  defp safe_file_url(file) do
    try do
      if file.file do
        Bacon8.UserFileUpload.url({file.file, file}, :original)
      else
        nil
      end
    rescue
      _ -> nil
    end
  end

  @doc """
  Check if a media file actually exists on disk.
  Used to filter out stale database records pointing to deleted files.
  """
  def media_file_exists?(media) do
    try do
      url = media.url || ""
      # Extract relative path from URL
      # URL format: /uploads/{user_id}/{context}/... or /uploads/{user_id}/2025/...
      cond do
        String.starts_with?(url, "/uploads/") ->
          # Convert URL to filesystem path
          relative_path = String.replace_prefix(url, "/uploads/", "")
          base_path = get_uploads_base_path()
          full_path = Path.join(base_path, relative_path)
          File.exists?(full_path)
        true ->
          # Unknown URL format - assume it doesn't exist
          false
      end
    rescue
      _ -> false
    end
  end

  defp get_uploads_base_path do
    cond do
      File.exists?("/app/uploads") -> "/app/uploads"
      File.exists?("uploads") -> Path.join(File.cwd!(), "uploads")
      true -> Path.join(File.cwd!(), "uploads")
    end
  end

  @doc """
  Clean up stale UserMedia records that point to non-existent files.
  Returns the count of records deleted.
  """
  def cleanup_stale_media(user) do
    try do
      media_records = from(m in Bacon8.Content.UserMedia, 
        where: m.user_id == ^user.id
      ) |> Repo.all()

      stale_ids = media_records
      |> Enum.filter(fn m -> not media_file_exists?(m) end)
      |> Enum.map(& &1.id)

      if stale_ids != [] do
        {count, _} = from(m in Bacon8.Content.UserMedia, 
          where: m.id in ^stale_ids
        ) |> Repo.delete_all()
        
        {:ok, count}
      else
        {:ok, 0}
      end
    rescue
      e -> {:error, e}
    end
  end
end