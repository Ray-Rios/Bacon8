defmodule Bacon8.Resolvers.Content do
  alias Bacon8.Content

  def list_pages(_parent, _args, _resolution) do
    pages = Content.list_pages()
    {:ok, pages}
  end

  def get_page(_parent, %{id: id}, _resolution) do
    page = Content.get_page!(id)
    {:ok, page}
  end

  def create_page(_parent, %{input: input}, %{context: %{current_user: _user}}) do
    case Content.create_page(input) do
      {:ok, page} -> {:ok, page}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_page(_parent, _args, _resolution) do
    {:error, "Not authenticated"}
  end

  def update_page(_parent, %{id: id, input: input}, %{context: %{current_user: _user}}) do
    page = Content.get_page!(id)
    case Content.update_page(page, input) do
      {:ok, page} -> {:ok, page}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def update_page(_parent, _args, _resolution) do
    {:error, "Not authenticated"}
  end

  def delete_page(_parent, %{id: id}, %{context: %{current_user: _user}}) do
    page = Content.get_page!(id)
    case Content.delete_page(page) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end

  def delete_page(_parent, _args, _resolution) do
    {:error, "Not authenticated"}
  end
end