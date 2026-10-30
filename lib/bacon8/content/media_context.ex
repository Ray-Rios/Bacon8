defmodule Bacon8.Content.Media do
  @moduledoc "Context module for user media uploads and management"
  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Content.UserMedia

  def list_media_for_user(user_id) do
    # If the user's role is banned, do not show any media
    user = Bacon8.Repo.get(Bacon8.Accounts.User, user_id)
    if user && user.role == "banned" do
      []
    else
      from(m in UserMedia, where: m.user_id == ^user_id, order_by: [desc: m.inserted_at])
      |> Repo.all()
    end
  end

  def get_media!(id), do: Repo.get!(UserMedia, id)

  def create_media(user, attrs) do
    attrs = Map.put(attrs, "user_id", user.id)
    %UserMedia{}
    |> UserMedia.changeset(attrs)
    |> Repo.insert()
  end

  def link_media_to_post(_media_id, _post_id, _role \\ "inline") do
    # TODO: implement linking via post_media table
    {:error, :not_implemented}
  end

  # Placeholder for generating presigned URLs (S3 or other providers)
  def generate_presigned_upload(_user, _opts \\ %{}) do
    {:ok, %{upload_url: "/temp-upload", key: "temp-key"}}
  end

  def list_all_media do
    # Exclude media uploaded by banned users
    from(m in UserMedia,
      join: u in assoc(m, :user),
      where: is_nil(u.role) or u.role != "banned",
      preload: [:user],
      order_by: [desc: m.inserted_at]
    )
    |> Repo.all()
  end

  def get_media_by_id!(id), do: Repo.get!(UserMedia, id)

  def update_media(%UserMedia{} = media, attrs) do
    media
    |> UserMedia.changeset(attrs)
    |> Repo.update()
  end

  def delete_media(%UserMedia{} = media) do
    Repo.delete(media)
  end

  def toggle_media_public(%UserMedia{} = media) do
    update_media(media, %{is_public: !media.is_public})
  end

  def get_media_stats do
    query = from m in UserMedia

    %{
      total: Repo.aggregate(query, :count),
      images: Repo.aggregate(from(m in query, where: m.file_type == "image"), :count),
      videos: Repo.aggregate(from(m in query, where: m.file_type == "video"), :count),
      audio: Repo.aggregate(from(m in query, where: m.file_type == "audio"), :count),
      documents: Repo.aggregate(from(m in query, where: m.file_type == "document"), :count),
      public: Repo.aggregate(from(m in query, where: m.is_public == true), :count),
      private: Repo.aggregate(from(m in query, where: m.is_public == false), :count)
    }
  end

  def find_posts_using_media(media_id) do
    # Search for posts that contain references to this media file
    # This is a simple implementation - in a real app you'd want a proper many-to-many relationship
    from(p in Bacon8.Content.Post,
      where: ilike(p.content, ^"%#{media_id}%") or ilike(p.title, ^"%#{media_id}%"),
      preload: [:user]
    )
    |> Repo.all()
  end

  def find_media_usage(media_url) do
    # Search for posts that contain this media URL
    from(p in Bacon8.Content.Post,
      where: ilike(p.content, ^"%#{media_url}%"),
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc "Get a single media item by ID, returns nil if not found"
  def get_user_media(id) do
    Repo.get(UserMedia, id)
  end

  @doc "Get media by its URL path"
  def get_media_by_url(url) when is_binary(url) do
    # Try to find media by url field or file_path
    from(m in UserMedia, 
      where: m.url == ^url or m.file_path == ^url,
      limit: 1
    )
    |> Repo.one()
  end
end
