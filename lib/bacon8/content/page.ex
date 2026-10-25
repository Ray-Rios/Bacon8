defmodule Bacon8.Content.Page do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pages" do
    field :title, :string
    field :slug, :string
    field :content, :string
    field :excerpt, :string
    field :template_type, :string, default: "default"
    field :is_published, :boolean, default: false
    field :published_at, :utc_datetime
    field :meta_description, :string
    field :meta_keywords, :string
    field :featured_image, :string
    field :category, :string
    field :order, :integer, default: 0
    field :show_share_buttons, :boolean, default: true
    field :share_platforms, {:array, :string}, default: ["twitter", "facebook", "linkedin", "reddit", "email"]
    field :share_buttons_colored, :boolean, default: false

    belongs_to :author, Bacon8.Accounts.User, foreign_key: :author_id, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :slug, :content, :excerpt, :template_type, :is_published, :published_at, 
                    :meta_description, :meta_keywords, :featured_image, :category, :order, :author_id,
                    :show_share_buttons, :share_platforms, :share_buttons_colored])
    |> validate_required_if_published()
    |> default_content()
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:excerpt, max: 500)
    |> validate_length(:meta_description, max: 160)
    |> validate_length(:meta_keywords, max: 255)
    |> validate_inclusion(:template_type, ["default", "landing", "full-width", "sidebar", "custom"])
    |> maybe_generate_slug()
    |> maybe_set_published_at()
    |> unique_constraint(:slug)
  end

  defp validate_required_if_published(changeset) do
    case get_field(changeset, :is_published) do
      true -> validate_required(changeset, [:title, :content])
      _ -> changeset
    end
  end

  # The pages table won't take a NULL body, but a draft may not have one yet.
  defp default_content(changeset) do
    if is_nil(get_field(changeset, :content)), do: put_change(changeset, :content, ""), else: changeset
  end

  # A slug is made from the title only while there is none: a page that has a URL
  # keeps it when it is renamed (the old URL is out in links, and the legal pages
  # are linked from the footer), and the editor sends the slug back unchanged, so
  # "no slug change" cannot mean "make a new one".
  defp maybe_generate_slug(changeset) do
    title = get_field(changeset, :title)

    if blank?(get_field(changeset, :slug)) and not blank?(title) do
      slug =
        title
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9\s]/, "")
        |> String.replace(~r/\s+/, "-")

      put_change(changeset, :slug, slug)
    else
      changeset
    end
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp maybe_set_published_at(changeset) do
    is_published = get_change(changeset, :is_published)
    current_published_at = get_field(changeset, :published_at)
    explicit_published_at = get_change(changeset, :published_at)
    
    cond do
      # If published_at was explicitly set in params, use that
      not is_nil(explicit_published_at) ->
        changeset
      
      # Set published_at when publishing for the first time
      is_published == true && is_nil(current_published_at) ->
        put_change(changeset, :published_at, DateTime.truncate(DateTime.utc_now(), :second))
      
      # Clear published_at when unpublishing
      is_published == false ->
        put_change(changeset, :published_at, nil)
      
      true ->
        changeset
    end
  end
end