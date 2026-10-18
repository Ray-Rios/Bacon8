defmodule Bacon8.Desktop do
  @moduledoc """
  Desktop context for managing window layouts and state persistence
  """
  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Desktop.WindowLayout

  @doc """
  Get saved window layout for a user and app
  """
  def get_window_layout(user_id, app) when is_binary(user_id) and is_binary(app) do
    Repo.get_by(WindowLayout, user_id: user_id, app: app)
  end

  @doc """
  Save or update window layout for a user and app
  """
  def save_window_layout(user_id, app, attrs) when is_binary(user_id) and is_binary(app) do
    case get_window_layout(user_id, app) do
      nil ->
        %WindowLayout{user_id: user_id, app: app}
        |> WindowLayout.changeset(attrs)
        |> Repo.insert()

      layout ->
        layout
        |> WindowLayout.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Delete window layout
  """
  def delete_window_layout(user_id, app) do
    case get_window_layout(user_id, app) do
      nil -> {:ok, nil}
      layout -> Repo.delete(layout)
    end
  end

  @doc """
  Get all saved layouts for a user
  """
  def list_user_layouts(user_id) do
    from(w in WindowLayout, where: w.user_id == ^user_id)
    |> Repo.all()
  end
end
