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

  @doc """
  Starts a new page or post as an empty draft titled "Untitled" with a free slug, so the editor
  always has a record to autosave and attach uploads to. Returns `{:ok, record}`.
  """
  def create_draft(:page, user) do
    create_page(%{title: "Untitled", slug: Bacon8.Content.Slugs.free(:page, "untitled"), author_id: user.id})
  end

  def create_draft(:post, user) do
    create_post(user, %{title: "Untitled", slug: Bacon8.Content.Slugs.free(:post, "untitled")})
  end

  @doc """
  When a draft still has the slug `create_draft/2` gave it ("untitled", "untitled-2"...) and the
  form leaves it alone, the slug follows the title it was just given. Anything the editor typed
  into the slug field, or a slug a published page already lives at, is never touched.
  `params` has string keys; returns them, with a new "slug" when it applies.
  """
  def slug_for_save(kind, record, params) do
    title = String.trim(to_string(params["title"] || ""))
    current = record && record.slug

    if is_binary(current) and Regex.match?(~r/^untitled(-\d+)?$/, current) and params["slug"] in [nil, "", current] and title != "" and
         not record.is_published do
      Map.put(params, "slug", Bacon8.Content.Slugs.free(kind, title))
    else
      params
    end
  end

  @doc "True for a record still exactly as `create_draft/2` made it (nothing worth keeping)."
  def untouched_draft?(%{title: "Untitled", content: content, is_published: false}), do: content in [nil, ""]
  def untouched_draft?(_), do: false

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
      where: c.post_id == ^post_id and c.is_approved == true and c.is_spam == false,
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

  # A comment is approved (shown), pending (waiting for a moderator) or spam (kept on record,
  # shown nowhere): is_approved and is_spam say which.
  def approve_comment(%Comment{} = comment) do
    newly? = not comment.is_approved

    with {:ok, approved} <- update_comment(comment, %{is_approved: true, is_spam: false}) do
      # (a reply tells the person it answers, when it first becomes visible)
      if newly?, do: Bacon8.Content.CommentNotices.reply(approved)
      {:ok, approved}
    end
  end

  def mark_spam(%Comment{} = comment) do
    update_comment(comment, %{is_approved: false, is_spam: true})
  end

  @doc """
  A signed-in member's comment on a post, held for approval or shown at once by the rules in
  `Bacon8.Content.Moderation`. Returns `{:ok, comment}` (check `comment.is_approved`), or
  `{:error, :not_allowed}` (no verified email), `{:error, :rate_limited}`, `{:error, :duplicate}`,
  `{:error, changeset}`.
  """
  def submit_comment(user, post, text, parent_id \\ nil)

  def submit_comment(user, %Post{id: post_id, is_published: true}, text, parent_id) do
    text = String.trim(to_string(text))
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    hour_ago = DateTime.add(now, -3600, :second)

    cond do
      is_nil(user) or is_nil(user.email_verified_at) ->
        {:error, :not_allowed}

      Repo.aggregate(from(c in Comment, where: c.user_id == ^user.id and c.inserted_at > ^hour_ago), :count) >=
          Bacon8.Content.Moderation.rate_limit() ->
        {:error, :rate_limited}

      Repo.exists?(from c in Comment, where: c.user_id == ^user.id and c.post_id == ^post_id and c.content == ^text and c.inserted_at > ^hour_ago) ->
        {:error, :duplicate}

      true ->
        approved_before = Repo.aggregate(from(c in Comment, where: c.user_id == ^user.id and c.is_approved == true and c.is_spam == false), :count)
        approved? = Bacon8.Content.Moderation.decide(user, text, approved_before) == :approved

        with {:ok, parent} <- reply_target(parent_id, post_id),
             {:ok, comment} <-
               create_comment(%{content: text, post_id: post_id, user_id: user.id, is_approved: approved?, parent_id: parent && parent.id}) do
          if approved?,
            do: Bacon8.Content.CommentNotices.reply(comment),
            else: Bacon8.Content.CommentNotices.pending(comment)

          {:ok, comment}
        end
    end
  end

  def submit_comment(_user, _post, _text, _parent_id), do: {:error, :not_allowed}

  # A reply answers a visible comment of the same post. Replies are one level deep: answering a
  # reply answers the comment it hangs from.
  defp reply_target(nil, _post_id), do: {:ok, nil}

  defp reply_target(parent_id, post_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(parent_id),
         %Comment{} = parent <-
           Repo.one(from c in Comment, where: c.id == ^uuid and c.post_id == ^post_id and c.is_approved == true and c.is_spam == false) do
      {:ok, if(parent.parent_id, do: Repo.get!(Comment, parent.parent_id), else: parent)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  A member changes their own comment. Staff comments stay shown; anyone else's goes through the
  rules again (an edit can't smuggle in links after approval) and may go back to waiting.
  `{:error, :not_found}` when the comment isn't theirs (or is spam).
  """
  def edit_own_comment(user, comment_id, text) do
    text = String.trim(to_string(text))

    with %Comment{} = comment <- own_comment(user, comment_id),
         false <- comment.is_spam do
      approved_before =
        Repo.aggregate(from(c in Comment, where: c.user_id == ^user.id and c.is_approved == true and c.is_spam == false), :count)

      approved? = Bacon8.Content.Moderation.decide(user, text, approved_before) == :approved

      with {:ok, updated} <-
             update_comment(comment, %{content: text, is_approved: approved?, edited_at: DateTime.utc_now() |> DateTime.truncate(:second)}) do
        if comment.is_approved and not approved?, do: Bacon8.Content.CommentNotices.pending(updated)
        {:ok, updated}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "A member deletes their own comment (replies to it go with it)."
  def delete_own_comment(user, comment_id) do
    case own_comment(user, comment_id) do
      %Comment{} = comment -> delete_comment(comment)
      nil -> {:error, :not_found}
    end
  end

  defp own_comment(nil, _id), do: nil

  defp own_comment(user, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.one(from c in Comment, where: c.id == ^uuid and c.user_id == ^user.id)
      :error -> nil
    end
  end

  @doc "Comments for the moderation screen: `:pending`, `:approved` or `:spam`, newest first."
  def list_comments_by_status(status) when status in [:pending, :approved, :spam] do
    from(c in Comment, where: ^status_filter(status), order_by: [desc: c.inserted_at], limit: 200)
    |> Repo.all()
    |> Repo.preload([:user, :post])
  end

  defp status_filter(:pending), do: dynamic([c], c.is_approved == false and c.is_spam == false)
  defp status_filter(:approved), do: dynamic([c], c.is_approved == true and c.is_spam == false)
  defp status_filter(:spam), do: dynamic([c], c.is_spam == true)

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

  def count_comments_by_status(status) when status in [:approved, :pending, :spam] do
    from(c in Comment, where: ^status_filter(status))
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