defmodule Bacon8.Files do
  @moduledoc """
  What a user has stored across the older upload paths, for the desktop's "user://" view, the profile's
  usage bar and the chat's storage check.

  The drive (`Bacon8.Drive`) is the storage system now. `user_files` (the Arc uploads this module's
  `UserFile` maps) is empty in production and is only read, never written; the folder, rename, move and
  upload functions, the admin page and the file controller that used it were deleted on 2026-10-29.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Files.UserFile

  # Chat attachments belong to the chat_channels plugin, which a site may not install: the
  # schema is looked up when needed, and without it there are none.
  defp attachment_schema do
    schema = Module.concat([ChatChannels, MessageAttachment])
    if Code.ensure_loaded?(schema), do: schema, else: nil
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

  def format_file_size(size_bytes) when is_integer(size_bytes) do
    cond do
      size_bytes >= 1_073_741_824 -> "#{Float.round(size_bytes / 1_073_741_824, 2)} GB"
      size_bytes >= 1_048_576 -> "#{Float.round(size_bytes / 1_048_576, 2)} MB"
      size_bytes >= 1024 -> "#{Float.round(size_bytes / 1024, 2)} KB"
      true -> "#{size_bytes} B"
    end
  end
  def format_file_size(_), do: "0 B"

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
end
