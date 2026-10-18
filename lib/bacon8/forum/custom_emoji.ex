defmodule Bacon8.Forum.CustomEmoji do
  @moduledoc """
  Schema for custom emojis that can be added by admins/GMs/editors.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "custom_emojis" do
    field :shortcode, :string
    field :emoji, :string  # Unicode emoji (if aliasing)
    field :image_url, :string  # Custom image URL
    field :category, :string, default: "Custom"
    
    belongs_to :created_by, Bacon8.Accounts.User

    timestamps()
  end

  def changeset(custom_emoji, attrs) do
    custom_emoji
    |> cast(attrs, [:shortcode, :emoji, :image_url, :category, :created_by_id])
    |> validate_required([:shortcode])
    |> validate_format(:shortcode, ~r/^[a-zA-Z0-9_-]+$/, message: "only letters, numbers, underscores and hyphens allowed")
    |> validate_length(:shortcode, min: 2, max: 32)
    |> unique_constraint(:shortcode)
    |> validate_emoji_or_image()
  end

  defp validate_emoji_or_image(changeset) do
    emoji = get_field(changeset, :emoji)
    image_url = get_field(changeset, :image_url)
    
    emoji_blank = is_nil(emoji) or emoji == ""
    image_blank = is_nil(image_url) or image_url == ""
    
    if emoji_blank && image_blank do
      add_error(changeset, :emoji, "either emoji or image_url must be provided")
    else
      changeset
    end
  end
end
