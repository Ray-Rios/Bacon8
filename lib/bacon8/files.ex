defmodule Bacon8.Files do
  @moduledoc """
  A user's storage usage across the upload paths that count against their allowance (the profile's usage
  bar and the chat's storage check). The drive (`Bacon8.Drive`) is the storage system for files; this
  adds up the blog and editor media and the chat attachments.

  The legacy `user_files` / `user_folders` tables, their schemas and the folder, upload and admin code
  around them were removed on 2026-10-29.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo

  # Chat attachments belong to the chat_channels plugin, which a site may not install: the
  # schema is looked up when needed, and without it there are none.
  defp attachment_schema do
    schema = Module.concat([ChatChannels, MessageAttachment])
    if Code.ensure_loaded?(schema), do: schema, else: nil
  end

  def get_user_data_usage(user_id) do
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
    user_media_count = from(m in Bacon8.Content.UserMedia, where: m.user_id == ^user_id, select: count()) |> Repo.one() || 0
    message_attachments_count = (if schema = attachment_schema(), do: from(m in schema, where: m.user_id == ^user_id, select: count()) |> Repo.one()) || 0

    total_size = user_media_size + message_attachments_size
    total_count = user_media_count + message_attachments_count

    %{
      total_size_bytes: total_size,
      total_files: total_count,
      user_media_size: user_media_size,
      message_attachments_size: message_attachments_size,
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
end
