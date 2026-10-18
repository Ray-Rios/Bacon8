defmodule Bacon8.Settings do
  @moduledoc """
  The Settings context for application configuration.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Settings.Option

  @doc """
  Sets a site option.
  """
  def set_option(name, value, autoload \\ true) do
    # Convert boolean to string for database storage (database expects "yes"/"no")
    autoload_str = if autoload, do: "yes", else: "no"
    
    case Repo.get_by(Option, option_name: name) do
      nil ->
        %Option{}
        |> Option.changeset(%{option_name: name, option_value: value, autoload: autoload_str})
        |> Repo.insert()
      
      option ->
        option
        |> Option.changeset(%{option_value: value, autoload: autoload_str})
        |> Repo.update()
    end
  end

  @doc """
  Gets a site option value.
  """
  def get_option(name, default \\ nil) do
    case Repo.get_by(Option, option_name: name) do
      nil -> default
      option -> option.option_value
    end
  end

  @doc """
  Gets all options.
  """
  def list_options do
    Repo.all(Option)
  end

  @doc """
  Deletes an option.
  """
  def delete_option(name) do
    case Repo.get_by(Option, option_name: name) do
      nil -> {:error, :not_found}
      option -> Repo.delete(option)
    end
  end

  @doc """
  Get the default user role for new registrations.
  """
  def get_default_user_role do
    get_option("default_user_role", "member")
  end

  @doc """
  Set the default user role for new registrations.
  """
  def set_default_user_role(role) when is_binary(role) do
    if role in ["admin", "gm", "editor", "moderator", "member", "guest", "banned"] do
      set_option("default_user_role", role)
    else
      {:error, :invalid_role}
    end
  end
  
  def set_default_user_role(_invalid_role), do: {:error, :invalid_role}

  @doc """
  Seeds default application settings.
  """
  def seed_default_settings do
    set_option("site_name", "My Game CMS")
    set_option("site_description", "A modern game content management system")
    set_option("posts_per_page", "10")
    set_option("comments_enabled", "true")
    set_option("registration_enabled", "true")
    set_option("default_user_role", "member")
  end
end