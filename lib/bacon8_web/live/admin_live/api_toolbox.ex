defmodule Bacon8Web.AdminLive.ApiToolbox do
  use Bacon8Web, :live_view

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  alias Bacon8.Accounts
  alias Bacon8.Content
  alias Bacon8Web.Components.AdminSidebar

  @impl true
  def mount(_params, _session, socket) do
    # Core actions, then active plugins' (BACON8.md §9; e.g. the store's orders).
    actions = api_actions() ++ Bacon8.Plugins.admin_tools()

    {:ok,
     socket
     |> assign(:api_actions, actions)
     |> assign(:execution_results, %{})
     |> assign(:selected_category, "all")
     |> assign(:page_title, "Admin API Toolbox")}
  end

  @impl true
  def handle_event("execute_action", %{"action_id" => action_id} = params, socket) do
    current_user = socket.assigns.current_user

    # A plugin's action carries its own `run`; core actions are matched below.
    outcome =
      case Enum.find(socket.assigns.api_actions, &(&1.id == action_id)) do
        %{run: run} when is_function(run, 2) -> run.(params, current_user)
        _ -> execute_action(action_id, params, current_user)
      end

    result =
      case outcome do
        {:ok, payload} ->
          %{status: :ok, payload: payload, timestamp: DateTime.utc_now()}

        {:error, message, details} ->
          %{status: :error, payload: %{message: message, details: details}, timestamp: DateTime.utc_now()}
      end

    {:noreply,
     socket
     |> assign(:execution_results, Map.put(socket.assigns.execution_results, action_id, result))}
  end

  @impl true
  def handle_event("clear_result", %{"action_id" => action_id}, socket) do
    {:noreply,
     socket
     |> assign(:execution_results, Map.delete(socket.assigns.execution_results, action_id))}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, :selected_category, category)}
  end

  # Filter buttons: the core categories, then any a plugin's actions add.
  defp category_filters(actions) do
    core = [{"All", "all"}, {"Users", "users"}, {"Content", "content"}, {"Files", "files"}]

    plugin =
      for %{category: category} = action <- actions,
          category not in ["users", "content", "files"],
          uniq: true,
          do: {Map.get(action, :category_label, String.capitalize(category)), category}

    core ++ plugin
  end

  # ============================================================================
  # ACTION EXECUTORS
  # ============================================================================

  defp execute_action("list_users", _params, _current_user) do
    users =
      Accounts.list_users()
      |> Enum.map(fn user ->
        %{
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          is_admin: user.is_admin,
          status: user.status || "active",
          email_verified: !is_nil(user.email_verified_at),
          last_login: user.last_login_at,
          inserted_at: user.inserted_at
        }
      end)

    {:ok, %{message: "Fetched #{length(users)} users", data: users, count: length(users)}}
  end

  defp execute_action("get_user", %{"user_id" => user_id}, _current_user) do
    user_id = String.trim(user_id || "")

    if user_id == "" do
      {:error, "User ID is required", nil}
    else
      case Accounts.get_user(user_id) do
        nil ->
          {:error, "User not found", nil}

        user ->
          {:ok,
           %{
             message: "User found",
             data: %{
               id: user.id,
               email: user.email,
               name: user.name,
               role: user.role,
               is_admin: user.is_admin,
               status: user.status,
               email_verified: !is_nil(user.email_verified_at),
               last_login: user.last_login_at,
               inserted_at: user.inserted_at,
               updated_at: user.updated_at
             }
           }}
      end
    end
  end

  defp execute_action("delete_user", %{"user_id" => user_id}, current_user) do
    user_id = String.trim(user_id || "")

    cond do
      user_id == "" ->
        {:error, "User ID is required", nil}

      is_nil(current_user) ->
        {:error, "Current user missing from session", nil}

      current_user.id == user_id ->
        {:error, "You cannot delete your own account", nil}

      true ->
        case Accounts.get_user(user_id) do
          nil ->
            {:error, "User not found", nil}

          user ->
            case Accounts.delete_user(user) do
              {:ok, deleted_user} ->
                {:ok,
                 %{
                   message: "User deleted successfully with cascading deletes",
                   user_id: deleted_user.id,
                   email: deleted_user.email
                 }}

              {:error, %Ecto.Changeset{} = changeset} ->
                {:error, "Failed to delete user", format_changeset_errors(changeset)}

              {:error, reason} ->
                {:error, "Failed to delete user", inspect(reason)}
            end
        end
    end
  end

  defp execute_action("update_user_role", %{"user_id" => user_id, "role" => role}, current_user) do
    user_id = String.trim(user_id || "")
    role = String.trim(role || "")

    cond do
      user_id == "" ->
        {:error, "User ID is required", nil}

      role == "" ->
        {:error, "Role is required", nil}

      role not in ["admin", "gm", "editor", "moderator", "member", "guest", "banned"] ->
        {:error, "Invalid role. Must be one of: admin, gm, editor, moderator, member, guest, banned", nil}

      current_user.id == user_id and role == "banned" ->
        {:error, "You cannot ban yourself", nil}

      true ->
        case Accounts.get_user(user_id) do
          nil ->
            {:error, "User not found", nil}

          user ->
            case Accounts.update_user_role(user, role) do
              {:ok, updated_user} ->
                {:ok,
                 %{
                   message: "User role updated successfully",
                   user_id: updated_user.id,
                   email: updated_user.email,
                   new_role: updated_user.role,
                   is_admin: updated_user.is_admin
                 }}

              {:error, changeset} ->
                {:error, "Failed to update role", format_changeset_errors(changeset)}
            end
        end
    end
  end

  defp execute_action("count_users", _params, _current_user) do
    total = Accounts.count_users()
    admin_count = Accounts.count_admin_users()
    active_count = Accounts.count_active_users()

    {:ok,
     %{
       message: "User counts retrieved",
       data: %{
         total: total,
         admins: admin_count,
         active: active_count,
         inactive: total - active_count
       }
     }}
  end

  defp execute_action("list_posts", _params, _current_user) do
    posts = Content.list_posts() |> Enum.take(50)

    {:ok,
     %{
       message: "Fetched #{length(posts)} posts (limited to 50)",
       data:
         Enum.map(posts, fn post ->
           %{
             id: post.id,
             title: post.title,
             slug: post.slug,
             status: post.status,
             author: post.user && post.user.name,
             inserted_at: post.inserted_at
           }
         end),
       count: length(posts)
     }}
  end

  defp execute_action(_unknown, _params, _current_user) do
    {:error, "Unsupported action", nil}
  end

  # ============================================================================
  # API ACTIONS CONFIGURATION
  # ============================================================================

  defp api_actions do
    [
      # User Management
      %{
        id: "list_users",
        name: "List All Users",
        category: "users",
        method: "GET",
        path: "/api/admin/users",
        description: "Retrieve all users with complete profile information including roles, status, and authentication details.",
        fields: []
      },
      %{
        id: "get_user",
        name: "Get User by ID",
        category: "users",
        method: "GET",
        path: "/api/admin/users/:id",
        description: "Retrieve detailed information for a specific user by their UUID.",
        fields: [
          %{name: "user_id", label: "User ID", placeholder: "Enter UUID", required: true}
        ]
      },
      %{
        id: "delete_user",
        name: "Delete User",
        category: "users",
        method: "DELETE",
        path: "/api/admin/users/:id",
        description: "Permanently delete a user and all associated data (cascading delete). You cannot delete your own account.",
        fields: [
          %{name: "user_id", label: "User ID", placeholder: "Enter UUID", required: true}
        ]
      },
      %{
        id: "update_user_role",
        name: "Update User Role",
        category: "users",
        method: "PATCH",
        path: "/api/admin/users/:id/role",
        description: "Change a user's role and permissions. Roles: admin, gm, editor, moderator, member, guest, banned.",
        fields: [
          %{name: "user_id", label: "User ID", placeholder: "Enter UUID", required: true},
          %{name: "role", label: "New Role", placeholder: "admin|gm|editor|moderator|member|guest|banned", required: true}
        ]
      },
      %{
        id: "count_users",
        name: "User Statistics",
        category: "users",
        method: "GET",
        path: "/api/admin/users/stats",
        description: "Get aggregate statistics: total users, admin count, active users (last 30 days).",
        fields: []
      },

      # Content Management
      %{
        id: "list_posts",
        name: "List Blog Posts",
        category: "content",
        method: "GET",
        path: "/api/admin/posts",
        description: "Retrieve up to 50 most recent blog posts with titles, slugs, and author info.",
        fields: []
      }
    ]
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/api-toolbox">
      <div class="max-w-7xl mx-auto">
          <!-- Header -->
          <div class="mb-8">
            <h1 class="text-4xl font-bold text-white mb-3 flex items-center gap-3">
              <span class="text-blue-400">⚡</span>
              Admin API Toolbox
            </h1>
            <p class="text-base text-gray-300 max-w-4xl leading-relaxed">
              Professional-grade administrative tools for direct system manipulation. Each function mirrors production API endpoints 
              with full validation, error handling, and real-time feedback. Test integrations, manage users, and inspect system state 
              without leaving the dashboard.
            </p>
          </div>

          <!-- Category Filter -->
          <div class="flex flex-wrap gap-2 mb-6">
            <%= for {label, value} <- category_filters(@api_actions) do %>
              <button
                phx-click="filter_category"
                phx-value-category={value}
                class={[
                  "px-4 py-2 rounded-lg text-sm font-medium transition-all",
                  if(@selected_category == value,
                    do: "bg-blue-600 text-white shadow-lg shadow-blue-500/50",
                    else: "glass-dark text-gray-300 hover:bg-gray-700 border border-gray-700"
                  )
                ]}
              >
                <%= label %>
              </button>
            <% end %>
          </div>

          <!-- API Actions Grid -->
          <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
            <%= for action <- filter_actions(@api_actions, @selected_category) do %>
              <div class="glass-dark/90 backdrop-blur border border-gray-700 rounded-xl shadow-2xl overflow-hidden hover:border-gray-600 transition-all">
                <!-- Action Header -->
                <div class="bg-gradient-to-r from-gray-900 to-gray-800 px-6 py-4 border-b border-gray-700">
                  <div class="flex items-start justify-between gap-4">
                    <div class="flex-1 min-w-0">
                      <h2 class="text-xl font-bold text-white mb-1 truncate"><%= action.name %></h2>
                      <code class="text-xs text-blue-400 font-mono"><%= action.path %></code>
                    </div>
                    <div class="flex items-center gap-2 flex-shrink-0">
                      <span class={[
                        "px-2.5 py-1 text-xs font-bold rounded uppercase tracking-wide",
                        method_color_class(action.method)
                      ]}>
                        <%= action.method %>
                      </span>
                    </div>
                  </div>
                </div>

                <!-- Action Body -->
                <div class="p-6">
                  <p class="text-sm text-gray-300 mb-5 leading-relaxed"><%= action.description %></p>

                  <!-- Form -->
                  <.form for={%{}} phx-submit="execute_action" class="space-y-4">
                    <input type="hidden" name="action_id" value={action.id} />
                    
                    <%= if length(action.fields) > 0 do %>
                      <div class="space-y-3">
                        <%= for field <- action.fields do %>
                          <div class="flex flex-col">
                            <label class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1.5">
                              <%= field.label %> <%= if field[:required], do: "*", else: "" %>
                            </label>
                            <input
                              type="text"
                              name={field.name}
                              placeholder={field[:placeholder]}
                              required={field[:required]}
                              class="bg-gray-900 border border-gray-600 text-white text-sm rounded-lg px-4 py-2.5 focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 focus:outline-none transition-all placeholder-gray-500"
                            />
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                    <button
                      type="submit"
                      class="w-full bg-gradient-to-r from-blue-600 to-blue-500 hover:from-blue-700 hover:to-blue-600 text-white text-sm font-bold rounded-lg py-3 transition-all shadow-lg hover:shadow-xl transform hover:scale-[1.02] active:scale-[0.98]"
                    >
                      <span class="flex items-center justify-center gap-2">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                        </svg>
                        Execute <%= action.name %>
                      </span>
                    </button>
                  </.form>

                  <!-- Results Panel -->
                  <%= if result = @execution_results[action.id] do %>
                    <div class="mt-5 relative">
                      <button
                        phx-click="clear_result"
                        phx-value-action_id={action.id}
                        class="absolute top-3 right-3 text-gray-400 hover:text-white transition-colors z-10"
                        title="Clear result"
                      >
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>

                      <div class={[
                        "rounded-lg border-2 overflow-hidden",
                        if(result.status == :ok,
                          do: "border-green-500 bg-green-950/40",
                          else: "border-red-500 bg-red-950/40"
                        )
                      ]}>
                        <!-- Result Header -->
                        <div class={[
                          "px-4 py-2 border-b flex items-center justify-between",
                          if(result.status == :ok,
                            do: "bg-green-900/50 border-green-700",
                            else: "bg-red-900/50 border-red-700"
                          )
                        ]}>
                          <div class="flex items-center gap-2">
                            <%= if result.status == :ok do %>
                              <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                              </svg>
                              <span class="font-bold text-green-200">Success</span>
                            <% else %>
                              <svg class="w-5 h-5 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                              </svg>
                              <span class="font-bold text-red-200">Error</span>
                            <% end %>
                          </div>
                          <span class="text-xs text-gray-400">
                            <%= Calendar.strftime(result.timestamp, "%H:%M:%S") %>
                          </span>
                        </div>

                        <!-- Result Body -->
                        <div class="p-4 max-h-96 overflow-y-auto custom-scrollbar">
                          <%= if result.status == :ok do %>
                            <div class="text-sm text-green-200 font-medium mb-3">
                              <%= result.payload[:message] || "Operation completed successfully" %>
                            </div>
                            
                            <%= if count = result.payload[:count] do %>
                              <div class="text-xs text-green-300 mb-2">
                                <span class="font-semibold">Records:</span> <%= count %>
                              </div>
                            <% end %>

                            <%= if user_id = result.payload[:user_id] do %>
                              <div class="text-xs text-green-300 mb-2">
                                <span class="font-semibold">User ID:</span> 
                                <code class="bg-green-900/30 px-2 py-0.5 rounded"><%= user_id %></code>
                              </div>
                            <% end %>

                            <%= if email = result.payload[:email] do %>
                              <div class="text-xs text-green-300 mb-2">
                                <span class="font-semibold">Email:</span> <%= email %>
                              </div>
                            <% end %>

                            <%= if data = result.payload[:data] do %>
                              <div class="mt-3">
                                <div class="text-xs font-semibold text-green-300 mb-2 uppercase tracking-wide">Response Data:</div>
                                <pre class="bg-gray-950 text-green-100 p-3 rounded text-xs overflow-x-auto font-mono leading-relaxed border border-green-700/30"><%= Jason.encode!(data, pretty: true) %></pre>
                              </div>
                            <% end %>
                          <% else %>
                            <div class="text-sm text-red-200 font-medium mb-3">
                              <%= result.payload[:message] || "Operation failed" %>
                            </div>
                            
                            <%= if details = result.payload[:details] do %>
                              <div class="mt-3">
                                <div class="text-xs font-semibold text-red-300 mb-2 uppercase tracking-wide">Error Details:</div>
                                <pre class="bg-gray-950 text-red-100 p-3 rounded text-xs overflow-x-auto font-mono leading-relaxed border border-red-700/30"><%= inspect(details, pretty: true) %></pre>
                              </div>
                            <% end %>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
      </div>

      <style>
        .custom-scrollbar::-webkit-scrollbar {
          width: 8px;
          height: 8px;
        }
        .custom-scrollbar::-webkit-scrollbar-track {
          background: rgba(0, 0, 0, 0.3);
          border-radius: 4px;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb {
          background: rgba(96, 165, 250, 0.5);
          border-radius: 4px;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb:hover {
          background: rgba(96, 165, 250, 0.7);
        }
      </style>
    </AdminSidebar.admin_layout>
    """
  end

  defp filter_actions(actions, "all"), do: actions
  defp filter_actions(actions, category) do
    Enum.filter(actions, fn action -> action.category == category end)
  end

  defp method_color_class("GET"), do: "bg-green-600 text-white"
  defp method_color_class("POST"), do: "bg-blue-600 text-white"
  defp method_color_class("PATCH"), do: "bg-yellow-600 text-white"
  defp method_color_class("PUT"), do: "bg-orange-600 text-white"
  defp method_color_class("DELETE"), do: "bg-red-600 text-white"
  defp method_color_class(_), do: "bg-gray-600 text-white"
end
