defmodule Bacon8Web.FileController do
  use Bacon8Web, :controller

  def upload(conn, %{"file" => file_params}) do
    user = conn.assigns.current_user
    
    if user do
      case Bacon8.Files.create_user_file(user, file_params) do
        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_changeset_errors(changeset)})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Authentication required"})
    end
  end

  def delete(conn, %{"id" => file_id}) do
    user = conn.assigns.current_user
    
    if user do
      try do
        Bacon8.Files.get_user_file!(user, file_id)
      rescue
        RuntimeError ->
          conn
          |> put_status(:not_implemented)
          |> json(%{error: "File deletion not implemented yet"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Authentication required"})
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end