defmodule Bacon8Web.AdminLive.Users do
  use Bacon8Web, :live_view
  alias Bacon8.Accounts

  def mount(_params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      users = Accounts.list_users()
      
      {:ok, assign(socket,
        users: users,
        page_title: "Admin - Users"
      )}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  def handle_event("toggle_admin", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)
    
    result = if user.is_admin do
      Accounts.remove_admin(user)
    else
      Accounts.make_admin(user)
    end
    
    case result do
      {:ok, _updated_user} ->
        users = Accounts.list_users()
        {:noreply, assign(socket, users: users)
         |> put_flash(:info, "User updated successfully")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update user")}
    end
  end

  def render(assigns) do
    ~H"""
    <div data-responsive-content class="min-h-screen" style="padding-top: 30px; padding-bottom: 48px;">
      <div class="flex relative z-10">
        <!-- Admin Sidebar -->
        <div class="w-64 bg-gray-900 min-h-screen">
          <div class="p-6">
            <h2 class="text-xl font-bold text-white mb-6">Admin Panel</h2>
            <nav class="space-y-2">
              <.link navigate="/admin" class="admin-nav-link">📊 Dashboard</.link>
              <.link navigate="/admin/user-management" class="admin-nav-link active">👥 Users</.link>
              <.link navigate="/admin/products" class="admin-nav-link">🛍️ Products</.link>
              <.link navigate="/admin/orders" class="admin-nav-link">📦 Orders</.link>
              <.link navigate="/admin/posts" class="admin-nav-link">📝 Blog Posts</.link>
              <.link navigate="/admin/channels" class="admin-nav-link">💬 Chat Channels</.link>
              <.link navigate="/admin/sql" class="admin-nav-link">🗄️ SQL Console</.link>
            </nav>
          </div>
        </div>

        <!-- Main Content -->
        <div class="flex-1 p-8">
          <h1 class="text-3xl font-bold text-white mb-8">User Management</h1>
          
          <div class="glass-dark rounded-lg overflow-hidden">
            <table class="w-full">
              <thead class="bg-gray-700">
                <tr>
                  <th class="px-6 py-3 text-left text-white">User</th>
                  <th class="px-6 py-3 text-left text-white">Email</th>
                  <th class="px-6 py-3 text-left text-white">Admin</th>
                  <th class="px-6 py-3 text-left text-white">2FA</th>
                  <th class="px-6 py-3 text-left text-white">Joined</th>
                  <th class="px-6 py-3 text-left text-white">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for user <- @users do %>
                  <tr class="border-b border-gray-700 hover:bg-gray-700">
                    <td class="px-6 py-4">
                      <div class="flex items-center space-x-3">
                        <div class="w-8 h-8 rounded-full flex items-center justify-center text-white text-sm"
                             style={"background-color: #{user.avatar_color}"}>
                          <%= String.first(user.name || user.email) %>
                        </div>
                        <span class="text-white"><%= user.name || "No name" %></span>
                      </div>
                    </td>
                    <td class="px-6 py-4 text-gray-300"><%= user.email %></td>
                    <td class="px-6 py-4">
                      <span class={["px-2 py-1 rounded text-xs",
                                   if(user.is_admin, do: "bg-green-600 text-green-100", else: "bg-gray-600 text-gray-300")]}>
                        <%= if user.is_admin, do: "Admin", else: "User" %>
                      </span>
                    </td>
                    <td class="px-6 py-4">
                      <span class={["px-2 py-1 rounded text-xs",
                                   if(user.two_factor_enabled, do: "bg-blue-600 text-blue-100", else: "bg-gray-600 text-gray-300")]}>
                        <%= if user.two_factor_enabled, do: "Enabled", else: "Disabled" %>
                      </span>
                    </td>
                    <td class="px-6 py-4 text-gray-300">
                      <%= Calendar.strftime(user.inserted_at, "%m/%d/%Y") %>
                    </td>
                    <td class="px-6 py-4">
                      <button phx-click="toggle_admin" phx-value-user_id={user.id}
                              class={["px-3 py-1 rounded text-sm transition-colors",
                                     if(user.is_admin, do: "bg-red-600 hover:bg-red-700 text-white", else: "bg-green-600 hover:bg-green-700 text-white")]}>
                        <%= if user.is_admin, do: "Remove Admin", else: "Make Admin" %>
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>

    <style>
      .admin-nav-link {
        @apply block w-full text-left px-4 py-2 text-gray-300 hover:glass-dark hover:text-white rounded transition-colors;
      }
      .admin-nav-link.active {
        @apply bg-blue-600 text-white;
      }
    </style>
    """
  end
end