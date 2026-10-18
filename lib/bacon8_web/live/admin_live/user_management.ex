defmodule Bacon8Web.AdminLive.UserManagementLive do
  use Bacon8Web, :live_view
  alias Bacon8.Accounts
  alias Bacon8Web.Components.AdminSidebar
  require Logger

  # Ensure current_user is loaded and authenticated
  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    # Force recompile to ensure sidebar is rendered
    # Check if current_user exists and is admin
    current_user = socket.assigns[:current_user]

    cond do
      current_user == nil ->
        # Redirect if no user is logged in
        {:ok, redirect(socket, to: "/login")}

      not current_user.is_admin ->
        # Redirect if user is not admin
        {:ok, redirect(socket, to: "/dashboard")}

      true ->
        # Load users for admin
        users = Accounts.list_users()
        default_role = Bacon8.Settings.get_option("default_user_role", "member")
        
        {:ok, assign(socket, 
          users: users, 
          page_title: "User Management", 
          confirm_delete_user_id: nil, 
          default_role: default_role
        )}
    end
  end

  @impl true
  def handle_event("change_default_role", %{"default_role" => role}, socket) do
    require Logger
    Logger.info("Changing default role to: #{inspect(role)}")
    
    case Bacon8.Settings.set_option("default_user_role", role) do
      {:ok, option} ->
        Logger.info("Successfully updated default role: #{inspect(option)}")
        {:noreply, assign(socket, default_role: role) |> put_flash(:info, "Default role updated to #{role}")}
      {:error, changeset} ->
        Logger.error("Failed to set default role: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Failed to update default role")}
    end
  end

  @impl true
  def handle_event("change_role", %{"role" => role, "user_id" => user_id}, socket) do
    require Logger
    Logger.info("Changing user role. User ID: #{user_id}, New Role: #{role}")
    
    user = Accounts.get_user!(user_id)
    
    case Accounts.update_user_role(user, role) do
      {:ok, updated_user} ->
        Logger.info("Successfully updated user role: #{inspect(updated_user)}")
        users = Accounts.list_users()
        {:noreply, assign(socket, users: users) |> put_flash(:info, "User role updated successfully")}

      {:error, changeset} ->
        Logger.error("Failed to update user role: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Failed to update user role")}
    end
  end

  @impl true
  def handle_event("toggle_status", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    result =
      if user.status == "active" do
        Accounts.disable_user(user)
      else
        Accounts.enable_user(user)
      end

    case result do
      {:ok, _updated_user} ->
        users = Accounts.list_users()
        {:noreply, assign(socket, users: users) |> put_flash(:info, "User status updated successfully")}

      {:error, changeset} ->
        Logger.error("Failed to update user status: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Failed to update user status")}
    end
  end

  @impl true
  def handle_event("delete_user", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    case Accounts.delete_user(user) do
      {:ok, _deleted_user} ->
        users = Accounts.list_users()
        {:noreply, assign(socket, users: users) |> put_flash(:info, "User deleted successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete user")}
    end
  end

  @impl true
  def handle_event("confirm_delete", %{"user_id" => user_id}, socket) do
    {:noreply, assign(socket, confirm_delete_user_id: user_id)}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete_user_id: nil)}
  end

  @impl true
  def handle_event("prevent_submit", _params, socket) do
    {:noreply, socket}
  end

  # Helper function to determine user role
  defp get_user_role(user) do
    cond do
      user.is_admin -> "admin"
      user.role && user.role != "subscriber" -> user.role
      true -> "member"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/user-management">
      <div class="max-w-7xl mx-auto">
          <h1 class="text-3xl font-bold text-white mb-8">User Management</h1>
          
          <!-- Default Role Setting -->
          <div class="auth-glass-panel rounded-lg p-6 mb-6">
            <h2 class="text-lg font-semibold text-white mb-4">Default Role Settings</h2>
            <form phx-change="change_default_role" phx-submit="prevent_submit">
              <div class="flex items-center space-x-4">
                <label class="text-sm font-medium text-gray-300">Default role for new users:</label>
                <select 
                  name="default_role"
                  class="glass-dark text-white px-3 py-2 rounded border border-gray-600 focus:border-blue-500"
                >
                  <option value="guest" selected={@default_role == "guest"}>Guest</option>
                  <option value="member" selected={@default_role == "member"}>Member</option>
                  <option value="moderator" selected={@default_role == "moderator"}>Moderator</option>
                  <option value="editor" selected={@default_role == "editor"}>Editor</option>
                  <option value="gm" selected={@default_role == "gm"}>GM</option>
                  <option value="admin" selected={@default_role == "admin"}>Admin</option>
                </select>
                <span class="text-xs text-gray-400">Currently set to: <strong><%= String.capitalize(@default_role) %></strong></span>
              </div>
            </form>
          </div>
          
          <div class="auth-glass-panel rounded-lg shadow-lg">
            <div class="p-6 border-b border-gray-700">
              <h2 class="text-lg font-semibold text-white">Users (<%= length(@users) %>)</h2>
            </div>
            <div class="overflow-x-auto">
              <div class="min-w-full inline-block align-middle">
                <table class="min-w-full">
                <thead class="glass-dark">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">User</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Email</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Status</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Role</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Joined</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for user <- @users do %>
                    <tr class="hover:bg-gray-700 transition-colors">
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-white">
                        <div class="flex items-center">
                          <div class="flex-shrink-0 h-8 w-8">
                            <div class="h-8 w-8 rounded-full bg-blue-500 flex items-center justify-center text-white text-sm font-medium">
                              <%= String.first(user.name || user.email) |> String.upcase() %>
                            </div>
                          </div>
                          <div class="ml-3">
                            <div class="text-sm font-medium text-white"><%= user.name || "No name" %></div>
                          </div>
                        </div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-300"><%= user.email %></td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{case user.status do
                          "active" -> "bg-green-100 text-green-800"
                          "pending" -> "bg-yellow-100 text-yellow-800"
                          "disabled" -> "bg-red-100 text-red-800"
                          _ -> "bg-gray-100 text-gray-800"
                        end}"}>
                          <%= String.capitalize(user.status || "pending") %>
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= case get_user_role(user) do %>
                          <% "admin" -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-red-100 text-red-800">Admin</span>
                          <% "gm" -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-purple-100 text-purple-800">GM</span>
                          <% "editor" -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-blue-100 text-blue-800">Editor</span>
                          <% "moderator" -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-yellow-100 text-yellow-800">Moderator</span>
                          <% "member" -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800">Member</span>
                          <% "guest" -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-gray-100 text-gray-800">Guest</span>
                          <% "banned" -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-black text-white">BANNED</span>
                          <% _ -> %>
                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-gray-100 text-gray-800">Member</span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-300"><%= Calendar.strftime(user.inserted_at, "%b %d, %Y") %></td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm">
                        <%= if user.id != @current_user.id do %>
                          <div class="flex flex-col lg:flex-row gap-2">
                            <form phx-change="change_role" phx-submit="prevent_submit" class="inline-block">
                              <input type="hidden" name="user_id" value={user.id} />
                              <select 
                                name="role"
                                class="bg-gray-700 text-white text-xs px-2 py-1 rounded border border-gray-600 focus:border-blue-500"
                              >
                                <option value="banned" selected={get_user_role(user) == "banned"}>BANNED</option>
                                <option value="guest" selected={get_user_role(user) == "guest"}>Guest</option>
                                <option value="member" selected={get_user_role(user) == "member"}>Member</option>
                                <option value="moderator" selected={get_user_role(user) == "moderator"}>Moderator</option>
                                <option value="editor" selected={get_user_role(user) == "editor"}>Editor</option>
                                <option value="gm" selected={get_user_role(user) == "gm"}>GM</option>
                                <option value="admin" selected={get_user_role(user) == "admin"}>Admin</option>
                              </select>
                            </form>
                            
                            <button 
                              phx-click="toggle_status" 
                              phx-value-user_id={user.id}
                              class={"px-3 py-1 text-xs font-medium rounded-md transition-colors #{if user.status == "active", do: "bg-yellow-600 hover:bg-yellow-700 text-white", else: "bg-green-600 hover:bg-green-700 text-white"}"}
                              title={if user.status == "pending", do: "Manually activate this user (bypasses email verification)", else: nil}
                            >
                              <%= case user.status do %>
                                <% "active" -> %>Disable
                                <% "pending" -> %>Activate
                                <% _ -> %>Enable
                              <% end %>
                            </button>
                            
                            <%= if @confirm_delete_user_id == user.id do %>
                              <div class="flex space-x-1">
                                <button 
                                  phx-click="delete_user" 
                                  phx-value-user_id={user.id}
                                  class="px-3 py-1 text-xs font-medium bg-red-700 hover:bg-red-800 text-white rounded-md transition-colors"
                                >
                                  Confirm
                                </button>
                                <button 
                                  phx-click="cancel_delete"
                                  class="px-3 py-1 text-xs font-medium bg-gray-600 hover:bg-gray-700 text-white rounded-md transition-colors"
                                >
                                  Cancel
                                </button>
                              </div>
                            <% else %>
                              <button 
                                phx-click="confirm_delete" 
                                phx-value-user_id={user.id}
                                class="px-3 py-1 text-xs font-medium bg-red-600 hover:bg-red-700 text-white rounded-md transition-colors"
                              >
                                Delete
                              </button>
                            <% end %>
                          </div>
                        <% else %>
                          <span class="text-gray-400 text-xs">Current User</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
                </table>
              </div>
            </div>
          </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
