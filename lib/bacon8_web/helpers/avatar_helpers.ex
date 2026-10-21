defmodule Bacon8Web.AvatarHelpers do
  @moduledoc """
  Helpers for displaying user avatars with proper precedence:
  1. Custom uploaded avatar (highest priority)
  2. Generated color/shape avatar  
  3. Default avatar image (fallback)
  """
  
  use Phoenix.Component

  @doc """
  Returns the avatar HTML for a user.
  
  Precedence:
  1. If user.avatar_url is set -> show uploaded image
  2. Else if user.avatar_color is set -> show generated avatar with first letter
  3. Else -> show default avatar image
  """
  def avatar_tag(user, opts \\ []) do
    size_class = Keyword.get(opts, :size_class, "w-10 h-10")
    
    # Safely get values whether user is a struct or a map
    shape = Map.get(user, :avatar_shape) || "circle"
    color = Map.get(user, :avatar_color) || "#3B82F6"
    opacity = (Map.get(user, :avatar_opacity) || 100) / 100
    avatar_url = Map.get(user, :avatar_url)
    name = Map.get(user, :name)
    
    # Convert hex color to rgba with opacity
    rgba_color = hex_to_rgba(color, opacity)
    
    shape_classes = case shape do
      "circle" -> "rounded-full"
      "square" -> "rounded-none"
      "rounded" -> "rounded-lg"
      _ -> "rounded-full"
    end

    assigns = %{
      user: user,
      size_class: size_class,
      shape_classes: shape_classes,
      color: color,
      rgba_color: rgba_color,
      initial: get_user_initial(user),
      avatar_url: avatar_url,
      name: name
    }

    cond do
      # Priority 1: Custom uploaded avatar
      avatar_url && String.trim(avatar_url) != "" ->
        ~H"""
        <img src={@avatar_url} alt={@name || "Avatar"} class={"#{@size_class} object-cover border #{@shape_classes}"} style={"border-color: #{@rgba_color}; box-shadow: 0 0 15px #{@rgba_color}"} />
        """

      # Priority 2: Generated color/shape avatar
      Map.get(user, :avatar_color) || Map.get(user, :avatar_shape) ->
        ~H"""
        <div class={"#{@size_class} flex items-center justify-center text-white font-bold #{@shape_classes} border"} style={"background-color: #{@color}; border-color: #{@rgba_color}; box-shadow: 0 0 15px #{@rgba_color}"}>
          <%= @initial %>
        </div>
        """

      # Priority 3: Default avatar image
      true ->
        ~H"""
        <img src="/images/default-avatar.png" alt="Default Avatar" class={"#{@size_class} object-cover #{@shape_classes}"} />
        """
    end
  end

  @doc """
  Converts a hex color to rgba string with given opacity.
  """
  def hex_to_rgba(hex, opacity) when is_binary(hex) do
    hex = String.trim_leading(hex, "#")
    
    {r, g, b} = case String.length(hex) do
      3 ->
        <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> = hex
        {
          String.to_integer(r <> r, 16),
          String.to_integer(g <> g, 16),
          String.to_integer(b <> b, 16)
        }
      6 ->
        <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex
        {
          String.to_integer(r, 16),
          String.to_integer(g, 16),
          String.to_integer(b, 16)
        }
      _ ->
        {59, 130, 246}  # Default blue if invalid
    end
    
    "rgba(#{r}, #{g}, #{b}, #{opacity})"
  end
  
  def hex_to_rgba(_, opacity), do: "rgba(59, 130, 246, #{opacity})"

  @doc """
  Gets the user's initial for generated avatars.
  """
  def get_user_initial(user) do
    name = Map.get(user, :name)
    email = Map.get(user, :email)
    
    cond do
      name && String.trim(name) != "" ->
        name |> String.first() |> String.upcase()
      email && String.trim(email) != "" ->
        email |> String.first() |> String.upcase()
      true ->
        "?"
    end
  end

  @doc """
  Returns just the avatar URL string (for APIs or direct URL access).
  """
  def avatar_url(user) do
    avatar_url = Map.get(user, :avatar_url)
    cond do
      avatar_url && String.trim(avatar_url) != "" ->
        avatar_url
      true ->
        "/images/default-avatar.png"
    end
  end

  @doc """
  Checks if user has a custom uploaded avatar.
  """
  def has_custom_avatar?(user) do
    avatar_url = Map.get(user, :avatar_url)
    avatar_url && String.trim(avatar_url) != ""
  end
end
