defmodule Bacon8Web.Api.AdminController do
  use Bacon8Web, :controller

  alias Bacon8.Accounts
  alias Bacon8.Auth.Guardian

  plug :ensure_admin

  # GET /api/admin/actions - list available admin actions (for the toolbox)
  def actions(conn, _params) do
    actions = [
      %{
        id: "list_users",
        method: "GET",
        path: "/api/admin/users",
        description: "List all users with basic account details"
      },
      %{
        id: "delete_user",
        method: "DELETE",
        path: "/api/admin/users/:id",
        description: "Delete a user account and cascade related records"
      },
      %{
        id: "enable_user",
        method: "POST",
        path: "/api/admin/users/:id/enable",
        description: "Enable a disabled user account"
      },
      %{
        id: "disable_user",
        method: "POST",
        path: "/api/admin/users/:id/disable",
        description: "Disable a user account"
      },
      %{
        id: "update_role",
        method: "POST",
        path: "/api/admin/users/:id/role",
        description: "Update a user's role"
      }
    ]

    conn
    |> put_status(:ok)
    |> json(%{success: true, actions: actions})
  end

  # GET /api/admin/users
  def list_users(conn, _params) do
    users =
      Accounts.list_users()
      |> Enum.map(fn u -> %{
        id: u.id,
        email: u.email,
        name: u.name,
        role: u.role,
        is_admin: u.is_admin,
        status: u.status || "active",
        inserted_at: u.inserted_at
      } end)

    conn
    |> put_status(:ok)
    |> json(%{success: true, users: users})
  end

  # DELETE /api/admin/users/:id
  def delete_user(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    cond do
      is_nil(current_user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Unauthenticated"})

      current_user.id == id ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: "You cannot delete your own account"})

      true ->
        case Accounts.get_user(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{success: false, error: "User not found"})

          user ->
            case Accounts.delete_user(user) do
              {:ok, _deleted_user} ->
                conn
                |> put_status(:ok)
                |> json(%{success: true, message: "User deleted", user_id: id})

              {:error, %Ecto.Changeset{} = changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{success: false, error: "Failed to delete user", details: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})

              {:error, reason} ->
                conn
                |> put_status(:internal_server_error)
                |> json(%{success: false, error: "Failed to delete user", reason: inspect(reason)})
            end
        end
    end
  end

  # POST /api/admin/users/:id/role  body: {"role":"..."}
  def update_role(conn, %{"id" => id, "role" => role}) do
    case Accounts.get_user(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{success: false, error: "User not found"})

      user ->
        case Accounts.update_user_role(user, role) do
          {:ok, updated} -> json(conn, %{success: true, user: %{id: updated.id, role: updated.role, is_admin: updated.is_admin}})
          {:error, %Ecto.Changeset{} = cs} -> conn |> put_status(:unprocessable_entity) |> json(%{success: false, error: "Role update failed", details: Ecto.Changeset.traverse_errors(cs, &translate_error/1)})
          {:error, reason} -> conn |> put_status(:internal_server_error) |> json(%{success: false, error: inspect(reason)})
        end
    end
  end

  # POST /api/admin/users/:id/enable
  def enable_user(conn, %{"id" => id}) do
    case Accounts.get_user(id) do
      nil -> conn |> put_status(:not_found) |> json(%{success: false, error: "User not found"})
      user ->
        case Accounts.enable_user(user) do
          {:ok, updated} -> json(conn, %{success: true, message: "User enabled", user: %{id: updated.id, status: updated.status}})
          {:error, %Ecto.Changeset{} = cs} -> conn |> put_status(:unprocessable_entity) |> json(%{success: false, error: "Enable failed", details: Ecto.Changeset.traverse_errors(cs, &translate_error/1)})
          {:error, reason} -> conn |> put_status(:internal_server_error) |> json(%{success: false, error: inspect(reason)})
        end
    end
  end

  # POST /api/admin/users/:id/disable
  def disable_user(conn, %{"id" => id}) do
    case Accounts.get_user(id) do
      nil -> conn |> put_status(:not_found) |> json(%{success: false, error: "User not found"})
      user ->
        case Accounts.disable_user(user) do
          {:ok, updated} -> json(conn, %{success: true, message: "User disabled", user: %{id: updated.id, status: updated.status}})
          {:error, %Ecto.Changeset{} = cs} -> conn |> put_status(:unprocessable_entity) |> json(%{success: false, error: "Disable failed", details: Ecto.Changeset.traverse_errors(cs, &translate_error/1)})
          {:error, reason} -> conn |> put_status(:internal_server_error) |> json(%{success: false, error: inspect(reason)})
        end
    end
  end

  # Admin guard
  defp ensure_admin(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      %Accounts.User{is_admin: true} -> conn
      _ -> conn |> put_status(:forbidden) |> json(%{success: false, error: "Admin access required"}) |> halt()
    end
  end

  # translate changeset errors
  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
  end
end
