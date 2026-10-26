defmodule Bacon8.Content do
  @moduledoc """
  The Content context for blog posts and pages.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Content.{Post, Page, UserMedia}

  # Posts
  def list_posts do
    from(p in Post, order_by: [desc: p.inserted_at])
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def count_posts do
    Repo.aggregate(Post, :count, :id)
  end

  def list_published_posts do
    from(p in Post, where: p.is_published == true, order_by: [desc: p.inserted_at])
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def get_recent_posts(limit \\ 5) do
    from(p in Post, 
      where: p.is_published == true, 
      order_by: [desc: p.inserted_at], 
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def get_post!(id) do
    Repo.get!(Post, id) |> Repo.preload(:user)
  end

  def get_post_by_slug!(slug) do
    Repo.get_by!(Post, slug: slug) |> Repo.preload(:user)
  end

  @doc "The post with this slug, published or not, or nil."
  def get_post_by_slug(slug) when is_binary(slug) do
    case Repo.get_by(Post, slug: slug) do
      nil -> nil
      post -> Repo.preload(post, :user)
    end
  end

  def get_post_by_slug(_), do: nil

  def create_post(user, attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:user, user)
    |> Repo.insert()
  end

  @doc """
  A blog post written by a plugin or game, as a draft unless `publish: true`
  (see `Bacon8.Content.PluginPosts`).
  """
  defdelegate post_from_plugin(plugin_slug, attrs, opts \\ []), to: Bacon8.Content.PluginPosts, as: :create

  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  # Pages
  def list_pages do
    Repo.all(Page)
  end

  def get_page!(id), do: Repo.get!(Page, id)
  
  def get_page_by_slug(slug) do
    Repo.get_by(Page, slug: slug)
  end

  def create_page(attrs \\ %{}) do
    %Page{}
    |> Page.changeset(attrs)
    |> Repo.insert()
  end

  def update_page(%Page{} = page, attrs) do
    page
    |> Page.changeset(attrs)
    |> Repo.update()
  end

  def delete_page(%Page{} = page) do
    Repo.delete(page)
  end

  # CMS-style functions
  def list_posts_by_status(status) when status in [:published, :draft] do
    is_published = case status do
      :published -> true
      :draft -> false
    end
    from(p in Post, where: p.is_published == ^is_published, order_by: [desc: p.inserted_at])
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def list_posts_by_type(_post_type) do
    # Post type functionality not implemented in current schema
    # Return all posts for now
    from(p in Post, order_by: [desc: p.inserted_at])
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def list_posts_with_filters(opts \\ []) do
    query = from(p in Post, order_by: [desc: p.inserted_at])
    
    query
    |> maybe_filter_by_status(opts[:status])
    |> maybe_filter_by_type(opts[:post_type])
    |> maybe_filter_by_user(opts[:user_id])
    |> Repo.all()
    |> Repo.preload(:user)
  end

  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status) when status in [:published, :draft] do
    is_published = case status do
      :published -> true
      :draft -> false
    end
    from(p in query, where: p.is_published == ^is_published)
  end

  defp maybe_filter_by_type(query, nil), do: query
  defp maybe_filter_by_type(query, _post_type) do
    # Post type functionality not implemented in current schema
    query
  end

  defp maybe_filter_by_user(query, nil), do: query
  defp maybe_filter_by_user(query, user_id) do
    from(p in query, where: p.user_id == ^user_id)
  end

  # Comments
  alias Bacon8.Content.Comment

  def list_comments(post_id \\ nil) do
    query = from(c in Comment, order_by: [desc: c.inserted_at])
    
    query = if post_id, do: from(c in query, where: c.post_id == ^post_id), else: query
    
    query
    |> Repo.all()
    |> Repo.preload([:user, :post])
  end

  def list_approved_comments(post_id) do
    from(c in Comment, 
      where: c.post_id == ^post_id and c.is_approved == true,
      order_by: [asc: c.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def get_comment!(id) do
    Repo.get!(Comment, id) |> Repo.preload([:user, :post])
  end

  def create_comment(attrs \\ %{}) do
    %Comment{}
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end

  def update_comment(%Comment{} = comment, attrs) do
    comment
    |> Comment.changeset(attrs)
    |> Repo.update()
  end

  def delete_comment(%Comment{} = comment) do
    Repo.delete(comment)
  end

  # Comments have is_approved, not a status. There is no spam state: a "spam" function used to
  # pass a status the schema ignores, so it did nothing and nothing called it.
  def approve_comment(%Comment{} = comment) do
    update_comment(comment, %{is_approved: true})
  end

  # Admin functions

  def count_pages do
    Repo.aggregate(Page, :count, :id)
  end

  def count_posts_by_status(status) when status in [:published, :draft] do
    is_published = case status do
      :published -> true
      :draft -> false
    end
    from(p in Post, where: p.is_published == ^is_published)
    |> Repo.aggregate(:count)
  end

  def count_comments do
    Repo.aggregate(Comment, :count)
  end

  def count_comments_by_status(status) when status in [:approved, :pending] do
    is_approved = case status do
      :approved -> true
      :pending -> false
    end
    from(c in Comment, where: c.is_approved == ^is_approved)
    |> Repo.aggregate(:count)
  end

  # User Media
  def list_user_media(user) do
    try do
      from(m in UserMedia, where: m.user_id == ^user.id, order_by: [desc: m.inserted_at])
      |> Repo.all()
    rescue
      _ ->
        # Fallback: Select specific fields that we know exist (excluding folder_path if missing)
        from(m in UserMedia, 
          where: m.user_id == ^user.id, 
          order_by: [desc: m.inserted_at],
          select: %{
            id: m.id,
            filename: m.filename,
            original_filename: m.original_filename,
            file_type: m.file_type,
            mime_type: m.mime_type,
            file_size: m.file_size,
            file_path: m.file_path,
            url: m.url,
            metadata: m.metadata,
            alt_text: m.alt_text,
            caption: m.caption,
            usage_context: m.usage_context,
            is_public: m.is_public,
            user_id: m.user_id,
            inserted_at: m.inserted_at,
            updated_at: m.updated_at
          }
        )
        |> Repo.all()
        |> Enum.map(fn data -> 
          struct(UserMedia, Map.put(data, :folder_path, "/"))
        end)
    end
  end
end