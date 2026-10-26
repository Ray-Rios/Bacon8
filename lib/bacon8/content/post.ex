defmodule Bacon8.Content.Post do
  use Ecto.Schema
  # Removed Arc.Ecto.Schema - using simple string for featured_image
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "posts" do
    field :title, :string
    field :slug, :string
    field :content, :string
    field :excerpt, :string
    field :is_published, :boolean, default: false
    field :published_at, :utc_datetime
    field :scheduled_at, :utc_datetime
    field :featured_image, :string
    field :meta_description, :string
    field :tags, {:array, :string}, default: []
    field :show_share_buttons, :boolean, default: true
    field :share_platforms, {:array, :string}, default: ["twitter", "facebook", "linkedin", "reddit", "email"]
    field :share_buttons_colored, :boolean, default: false

    belongs_to :user, Bacon8.Accounts.User
    # Removed parent/child relationships - not in posts table
    has_many :comments, Bacon8.Content.Comment, foreign_key: :post_id

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :title, :slug, :content, :excerpt, :is_published, :published_at, :scheduled_at, 
      :meta_description, :tags, :featured_image, :show_share_buttons, :share_platforms, :share_buttons_colored
    ])
    |> validate_required_if_published()
    |> default_content()
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:excerpt, max: 500)
    |> validate_length(:meta_description, max: 160)
    |> validate_inclusion(:is_published, [true, false])
    |> maybe_generate_slug()
    |> maybe_set_published_at()
    |> drop_schedule_when_published()
    |> unique_constraint(:slug)
  end

  # Only require title/content when publishing. Allow drafts to save incrementally.
  defp validate_required_if_published(changeset) do
    case get_field(changeset, :is_published) do
      true -> validate_required(changeset, [:title, :content])
      _ -> changeset
    end
  end

  # The posts table won't take a NULL body, but a draft may not have one yet.
  defp default_content(changeset) do
    if is_nil(get_field(changeset, :content)), do: put_change(changeset, :content, ""), else: changeset
  end

  # A slug is made from the title only while there is none: a post that has a URL
  # keeps it when it is renamed (the old URL is out in links), and the editor
  # sends the slug back unchanged, so "no slug change" cannot mean "make a new one".
  defp maybe_generate_slug(changeset) do
    title = get_field(changeset, :title)

    if blank?(get_field(changeset, :slug)) and not blank?(title) do
      slug =
        title
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9\s]/, "")
        |> String.replace(~r/\s+/, "-")
        |> String.slice(0, 100)

      put_change(changeset, :slug, slug)
    else
      changeset
    end
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp maybe_set_published_at(changeset) do
    is_published = get_change(changeset, :is_published)
    current_published_at = get_field(changeset, :published_at)
    
    cond do
      is_published == true and is_nil(current_published_at) ->
        put_change(changeset, :published_at, DateTime.truncate(DateTime.utc_now(), :second))
      is_published == false ->
        put_change(changeset, :published_at, nil)
      true ->
        changeset
    end
  end

  # A published record has nothing left to wait for
  defp drop_schedule_when_published(changeset) do
    if get_field(changeset, :is_published), do: put_change(changeset, :scheduled_at, nil), else: changeset
  end

  # Helper functions
  def published?(post), do: post.is_published == true
  def draft?(post), do: post.is_published == false
end