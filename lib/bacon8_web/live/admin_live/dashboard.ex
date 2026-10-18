defmodule Bacon8Web.AdminLive.Dashboard do
  use Bacon8Web, :live_view
  alias Bacon8.{Accounts, Content, Security, RateLimiter, Store}
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  def mount(_params, _session, socket) do
    # on_mount already verified admin access
    stats = get_dashboard_stats()
    security_stats = get_security_stats()
    server_logs = get_server_logs()

    {:ok, assign(socket,
      stats: stats,
      security_stats: security_stats,
      server_logs: server_logs,
      show_logs_modal: false,
      page_title: "Admin Dashboard",
      active_section: :dashboard
    )}
  end

  def handle_event("toggle_logs_modal", _params, socket) do
    {:noreply, assign(socket, show_logs_modal: !socket.assigns.show_logs_modal)}
  end

  def handle_event("refresh_logs", _params, socket) do
    {:noreply, assign(socket, server_logs: get_server_logs())}
  end

  def handle_event("refresh_security", _params, socket) do
    {:noreply, assign(socket, security_stats: get_security_stats())}
  end

  def handle_event("unblock_ip", %{"ip" => ip}, socket) do
    RateLimiter.unblock(ip)
    Security.unblock_identifier(ip, "ip")
    {:noreply, 
     socket
     |> assign(security_stats: get_security_stats())
     |> put_flash(:info, "IP #{ip} has been unblocked")}
  end

  defp get_dashboard_stats do
    try do
      store = Store.stats()

      %{
        total_users: Accounts.count_users() || 0,
        total_orders: store.orders,
        total_products: store.products,
        total_posts: Content.count_posts() || 0,
        total_pages: Content.count_pages() || 0,
        recent_users: Accounts.list_recent_users(5) || [],
        recent_orders: safe_list_orders() || [],
        revenue_today: Store.format_price(store.revenue_today_cents, "usd"),
        revenue_month: Store.format_price(store.revenue_month_cents, "usd"),
        uploads_size: get_uploads_size()
      }
    rescue
      e -> 
        IO.inspect(e, label: "Dashboard stats error")
        %{
          total_users: 0,
          total_orders: 0,
          total_products: 0,
          total_posts: 0,
          total_pages: 0,
          recent_users: [],
          recent_orders: [],
          revenue_today: "$0.00",
          revenue_month: "$0.00",
          uploads_size: %{bytes: 0, formatted: "0 KB", file_count: 0}
        }
    end
  end

  defp safe_list_orders do
    try do
      Store.list_orders(limit: 5)
    rescue
      _ -> []
    end
  end

  defp get_uploads_size do
    uploads_path = Path.join(:code.priv_dir(:bacon8), "static/uploads")
    
    try do
      if File.exists?(uploads_path) do
        {size, count} = calculate_dir_size(uploads_path)
        %{
          bytes: size,
          formatted: format_bytes(size),
          file_count: count
        }
      else
        %{bytes: 0, formatted: "0 KB", file_count: 0}
      end
    rescue
      _ -> %{bytes: 0, formatted: "0 KB", file_count: 0}
    end
  end

  defp calculate_dir_size(path) do
    File.ls!(path)
    |> Enum.reduce({0, 0}, fn item, {total_size, total_count} ->
      full_path = Path.join(path, item)
      case File.stat(full_path) do
        {:ok, %{type: :directory}} ->
          {sub_size, sub_count} = calculate_dir_size(full_path)
          {total_size + sub_size, total_count + sub_count}
        {:ok, %{size: size, type: :regular}} ->
          {total_size + size, total_count + 1}
        _ ->
          {total_size, total_count}
      end
    end)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"

  defp get_security_stats do
    try do
      base_stats = Security.get_security_stats()
      rate_limiter_blocked = RateLimiter.list_blocked()
      recent_failures = Security.get_recent_failed_attempts(10)
      blocked_identifiers = Security.list_blocked_identifiers()
      
      # Get 404 tracking data from NotFoundTracker
      not_found_stats = get_404_stats()
      
      Map.merge(base_stats, %{
        rate_limiter_blocked: rate_limiter_blocked,
        recent_failures: recent_failures,
        blocked_identifiers: blocked_identifiers,
        not_found_count: not_found_stats.total_count,
        top_404_paths: not_found_stats.top_paths,
        top_offenders: get_top_offenders(recent_failures)
      })
    rescue
      _ -> 
        %{
          total_attempts_last_hour: 0,
          total_attempts_last_day: 0,
          failed_attempts_last_hour: 0,
          failed_attempts_last_day: 0,
          blocked_identifiers: [],
          allowed_identifiers: 0,
          unique_fingerprints: 0,
          rate_limiter_blocked: [],
          recent_failures: [],
          not_found_count: 0,
          top_404_paths: [],
          top_offenders: []
        }
    end
  end

  defp get_404_stats do
    try do
      stats = Bacon8.NotFoundTracker.get_stats()
      top_paths = Bacon8.NotFoundTracker.get_top_paths(5)
      
      Map.put(stats, :top_paths, top_paths)
    rescue
      _ -> %{total_count: 0, last_hour: 0, last_day: 0, unique_ips: 0, unique_paths: 0, top_paths: []}
    end
  end

  defp get_top_offenders(recent_failures) do
    recent_failures
    |> Enum.group_by(fn attempt -> attempt.identifier end)
    |> Enum.map(fn {identifier, attempts} -> 
      %{
        identifier: identifier,
        count: length(attempts),
        last_attempt: List.first(attempts)
      }
    end)
    |> Enum.sort_by(fn %{count: count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp get_server_logs do
    # Try to read from common log locations
    log_paths = [
      Path.join(:code.priv_dir(:bacon8), "../../../logs/bacon8.log"),
      "/var/log/bacon8/bacon8.log",
      Path.join(System.tmp_dir!(), "bacon8.log"),
      "/tmp/bacon8.log"
    ]
    
    # Also try to get from Logger backend if available
    logs = get_logger_memory_logs()
    
    if logs != [] do
      logs
    else
      # Fallback: try file-based logs
      Enum.find_value(log_paths, [], fn path ->
        case File.read(path) do
          {:ok, content} ->
            content
            |> String.split("\n")
            |> Enum.take(-100)
            |> Enum.filter(&(&1 != ""))
          _ -> nil
        end
      end)
    end
  end

  defp get_logger_memory_logs do
    # Get recent log entries from the application's ring logger if available
    try do
      # Check if RingLogger is available and call it dynamically
      case Code.ensure_loaded(:ring_logger) do
        {:module, ring_logger} ->
          ring_logger.get()
          |> Enum.take(-100)
          |> Enum.map(&format_log_entry/1)
        _ ->
          # Fallback: return empty list, logs will be shown from file or "not available"
          []
      end
    rescue
      _ -> []
    end
  end

  defp format_log_entry({level, {Logger, message, timestamp, _metadata}}) do
    {{y, mo, d}, {h, mi, s, _ms}} = timestamp
    time_str = "#{y}-#{pad(mo)}-#{pad(d)} #{pad(h)}:#{pad(mi)}:#{pad(s)}"
    "[#{time_str}] [#{level}] #{message}"
  end
  defp format_log_entry(entry), do: inspect(entry)

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin">
      <!-- Page Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-white">Dashboard</h1>
        <p class="text-gray-400 mt-1">Welcome back! Here's an overview of your site.</p>
      </div>
      
      <!-- Stats Grid -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <.stat_card icon="👥" value={@stats.total_users} label="Users" color="blue" />
        <.stat_card icon="📝" value={@stats.total_posts} label="Blog Posts" color="green" />
        <.stat_card icon="📄" value={@stats.total_pages} label="Pages" color="purple" />
        <.stat_card icon="💎" value={@stats.total_products} label="Products on sale" color="amber" />
      </div>

      <!-- Revenue & Storage Row -->
            <div class="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-8">
              <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-gray-400 text-sm">Revenue Today</p>
                    <p class="text-3xl font-bold text-green-400 mt-1"><%= @stats.revenue_today %></p>
                  </div>
                  <div class="p-3 bg-green-500/10 rounded-lg">
                    <span class="text-2xl">💵</span>
                  </div>
                </div>
              </div>
              
              <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-gray-400 text-sm">Revenue This Month</p>
                    <p class="text-3xl font-bold text-green-400 mt-1"><%= @stats.revenue_month %></p>
                  </div>
                  <div class="p-3 bg-green-500/10 rounded-lg">
                    <span class="text-2xl">📈</span>
                  </div>
                </div>
              </div>
              
              <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-gray-400 text-sm">Uploads Storage</p>
                    <p class="text-3xl font-bold text-blue-400 mt-1"><%= @stats.uploads_size.formatted %></p>
                    <p class="text-gray-500 text-xs mt-1"><%= @stats.uploads_size.file_count %> files</p>
                  </div>
                  <div class="p-3 bg-blue-500/10 rounded-lg">
                    <span class="text-2xl">💾</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Quick Actions & Recent Activity -->
            <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <!-- Quick Actions -->
              <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-white mb-4">Quick Actions</h3>
                <div class="space-y-3">
                  <.link navigate="/admin/user-management" class="flex items-center gap-3 p-3 bg-blue-600/20 hover:bg-blue-600/30 rounded-lg text-blue-400 transition-colors">
                    <span class="text-lg">👥</span>
                    <span>Manage Users</span>
                  </.link>
                  <.link navigate="/admin/blog-management" class="flex items-center gap-3 p-3 bg-green-600/20 hover:bg-green-600/30 rounded-lg text-green-400 transition-colors">
                    <span class="text-lg">📝</span>
                    <span>New Blog Post</span>
                  </.link>
                  <.link navigate="/admin/pages?action=new" class="flex items-center gap-3 p-3 bg-purple-600/20 hover:bg-purple-600/30 rounded-lg text-purple-400 transition-colors">
                    <span class="text-lg">📄</span>
                    <span>New Page</span>
                  </.link>
                  <.link navigate="/admin/sql" class="flex items-center gap-3 p-3 bg-amber-600/20 hover:bg-amber-600/30 rounded-lg text-amber-400 transition-colors">
                    <span class="text-lg">🗄️</span>
                    <span>SQL Console</span>
                  </.link>
                </div>
              </div>

              <!-- Recent Users -->
              <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-white mb-4">Recent Users</h3>
                <div class="space-y-3">
                  <%= if @stats.recent_users == [] do %>
                    <p class="text-gray-500 text-sm">No users yet</p>
                  <% else %>
                    <%= for user <- @stats.recent_users do %>
                      <div class="flex items-center gap-3">
                        <div class="w-8 h-8 rounded-full flex items-center justify-center text-white text-sm font-medium"
                             style={"background-color: #{user.avatar_color || "#3b82f6"}"}>
                          <%= String.first(user.name || user.email || "?") %>
                        </div>
                        <div class="flex-1 min-w-0">
                          <p class="text-white text-sm font-medium truncate"><%= user.name || user.email %></p>
                          <p class="text-gray-500 text-xs truncate"><%= user.email %></p>
                        </div>
                        <span class="text-gray-500 text-xs"><%= Calendar.strftime(user.inserted_at, "%m/%d") %></span>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <!-- Recent Orders -->
              <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-white mb-4">Recent Orders</h3>
                <div class="space-y-3">
                  <%= if @stats.recent_orders == [] do %>
                    <p class="text-gray-500 text-sm">No orders yet</p>
                  <% else %>
                    <%= for order <- @stats.recent_orders do %>
                      <div class="flex items-center justify-between">
                        <div>
                          <.link navigate={~p"/admin/orders/#{order.id}"} class="text-white text-sm font-medium hover:underline"><%= order.product_name %></.link>
                          <p class="text-gray-500 text-xs"><%= order.user && order.user.email %></p>
                        </div>
                        <div class="text-right">
                          <p class="text-green-400 font-bold text-sm"><%= Store.order_price(order) %></p>
                          <span class={["text-xs px-2 py-0.5 rounded",
                                      case order.status do
                                        "awaiting_payment" -> "bg-yellow-600/30 text-yellow-300"
                                        s when s in ["paid", "fulfilled"] -> "bg-green-600/30 text-green-300"
                                        "disputed" -> "bg-orange-600/30 text-orange-300"
                                        s when s in ["failed", "charged_back"] -> "bg-red-600/30 text-red-300"
                                        _ -> "bg-gray-600/30 text-gray-300"
                                      end]}>
                            <%= order.status |> String.replace("_", " ") |> String.capitalize() %>
                          </span>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
            
            <!-- Security Overview Section -->
            <div class="mt-8">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-bold text-white flex items-center gap-2">
                  <span>🛡️</span> Security Overview
                </h2>
                <div class="flex gap-2">
                  <button
                    type="button"
                    phx-click="refresh_security"
                    class="px-3 py-1.5 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm rounded-lg transition-colors"
                  >
                    Refresh
                  </button>
                  <.link navigate="/admin/security" class="px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded-lg transition-colors">
                    Manage Security →
                  </.link>
                </div>
              </div>
              
              <!-- Security Stats Grid -->
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-4 border border-gray-700">
                  <div class="flex items-center gap-3">
                    <div class="p-2 bg-red-500/10 rounded-lg">
                      <span class="text-xl">🚫</span>
                    </div>
                    <div>
                      <p class="text-2xl font-bold text-red-400"><%= length(@security_stats.rate_limiter_blocked) %></p>
                      <p class="text-gray-400 text-xs">Blocked IPs</p>
                    </div>
                  </div>
                </div>
                
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-4 border border-gray-700">
                  <div class="flex items-center gap-3">
                    <div class="p-2 bg-yellow-500/10 rounded-lg">
                      <span class="text-xl">⚠️</span>
                    </div>
                    <div>
                      <p class="text-2xl font-bold text-yellow-400"><%= @security_stats.failed_attempts_last_hour %></p>
                      <p class="text-gray-400 text-xs">Failed Logins (1h)</p>
                    </div>
                  </div>
                </div>
                
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-4 border border-gray-700">
                  <div class="flex items-center gap-3">
                    <div class="p-2 bg-orange-500/10 rounded-lg">
                      <span class="text-xl">🔍</span>
                    </div>
                    <div>
                      <p class="text-2xl font-bold text-orange-400"><%= @security_stats.not_found_count %></p>
                      <p class="text-gray-400 text-xs">404 Errors</p>
                    </div>
                  </div>
                </div>
                
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-4 border border-gray-700">
                  <div class="flex items-center gap-3">
                    <div class="p-2 bg-blue-500/10 rounded-lg">
                      <span class="text-xl">📱</span>
                    </div>
                    <div>
                      <p class="text-2xl font-bold text-blue-400"><%= @security_stats.unique_fingerprints %></p>
                      <p class="text-gray-400 text-xs">Device Fingerprints</p>
                    </div>
                  </div>
                </div>
              </div>
              
              <!-- Security Details Grid -->
              <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <!-- Blocked IPs / Rate Limited -->
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                  <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                    <span class="text-red-400">🚫</span> Blocked IPs
                  </h3>
                  <div class="space-y-2 max-h-48 overflow-y-auto">
                    <%= if @security_stats.rate_limiter_blocked == [] do %>
                      <p class="text-gray-500 text-sm">No blocked IPs</p>
                    <% else %>
                      <%= for ip <- Enum.take(@security_stats.rate_limiter_blocked, 10) do %>
                        <div class="flex items-center justify-between p-2 bg-red-900/20 rounded-lg">
                          <span class="text-red-300 font-mono text-sm"><%= ip %></span>
                          <button
                            type="button"
                            phx-click="unblock_ip"
                            phx-value-ip={ip}
                            class="text-xs text-blue-400 hover:text-blue-300"
                          >
                            Unblock
                          </button>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
                
                <!-- Top Offenders -->
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                  <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                    <span class="text-yellow-400">⚠️</span> Top Offenders
                  </h3>
                  <div class="space-y-2 max-h-48 overflow-y-auto">
                    <%= if @security_stats.top_offenders == [] do %>
                      <p class="text-gray-500 text-sm">No failed login attempts</p>
                    <% else %>
                      <%= for offender <- @security_stats.top_offenders do %>
                        <div class="flex items-center justify-between p-2 bg-yellow-900/20 rounded-lg">
                          <span class="text-yellow-300 font-mono text-sm truncate max-w-[150px]"><%= offender.identifier %></span>
                          <span class="text-yellow-400 font-bold text-sm"><%= offender.count %> fails</span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
                
                <!-- Recent Failed Logins -->
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                  <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                    <span class="text-orange-400">🔐</span> Recent Failures
                  </h3>
                  <div class="space-y-2 max-h-48 overflow-y-auto">
                    <%= if @security_stats.recent_failures == [] do %>
                      <p class="text-gray-500 text-sm">No recent failed attempts</p>
                    <% else %>
                      <%= for attempt <- Enum.take(@security_stats.recent_failures, 5) do %>
                        <div class="p-2 bg-orange-900/20 rounded-lg">
                          <div class="flex items-center justify-between">
                            <span class="text-orange-300 font-mono text-xs truncate max-w-[120px]"><%= attempt.identifier %></span>
                            <span class="text-gray-500 text-xs">
                              <%= if attempt.last_attempt_at do %>
                                <%= Calendar.strftime(attempt.last_attempt_at, "%H:%M") %>
                              <% end %>
                            </span>
                          </div>
                          <p class="text-gray-400 text-xs mt-1">
                            <%= attempt.identifier_type %> • <%= attempt.attempt_count || 1 %> attempts
                          </p>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </div>
              
              <!-- 404 Paths & Additional Security Info -->
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
                <!-- Top 404 Paths -->
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                  <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                    <span class="text-purple-400">🔍</span> Top 404 Paths
                  </h3>
                  <div class="space-y-2 max-h-48 overflow-y-auto">
                    <%= if @security_stats.top_404_paths == [] do %>
                      <p class="text-gray-500 text-sm">No 404 errors recorded</p>
                    <% else %>
                      <%= for entry <- @security_stats.top_404_paths do %>
                        <div class="flex items-center justify-between p-2 bg-purple-900/20 rounded-lg">
                          <span class="text-purple-300 font-mono text-xs truncate max-w-[200px]"><%= entry.path %></span>
                          <span class="text-purple-400 font-bold text-sm"><%= entry.count %> hits</span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
                
                <!-- Persistent Blocklist -->
                <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-6 border border-gray-700">
                  <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                    <span class="text-red-400">🛑</span> Persistent Blocklist
                  </h3>
                  <div class="space-y-2 max-h-48 overflow-y-auto">
                    <%= if @security_stats.blocked_identifiers == [] do %>
                      <p class="text-gray-500 text-sm">No permanently blocked identifiers</p>
                    <% else %>
                      <%= for blocked <- Enum.take(@security_stats.blocked_identifiers, 5) do %>
                        <div class="p-2 bg-red-900/20 rounded-lg">
                          <div class="flex items-center justify-between">
                            <span class="text-red-300 font-mono text-xs truncate max-w-[120px]"><%= blocked.identifier %></span>
                            <span class="text-gray-500 text-xs"><%= blocked.identifier_type %></span>
                          </div>
                          <p class="text-gray-400 text-xs mt-1 truncate"><%= blocked.reason || "No reason" %></p>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Server Logs Section -->
            <div class="mt-8">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-bold text-white flex items-center gap-2">
                  <span>📋</span> Server Logs
                </h2>
                <div class="flex gap-2">
                  <button
                    type="button"
                    phx-click="refresh_logs"
                    class="px-3 py-1.5 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm rounded-lg transition-colors"
                  >
                    Refresh
                  </button>
                  <button
                    type="button"
                    phx-click="toggle_logs_modal"
                    class="px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded-lg transition-colors"
                  >
                    View Full Logs
                  </button>
                </div>
              </div>
              
              <div class="bg-gray-900/80 backdrop-blur-sm rounded-xl p-4 border border-gray-700 font-mono text-xs">
                <div class="max-h-48 overflow-y-auto space-y-1">
                  <%= if @server_logs == [] do %>
                    <p class="text-gray-500">No logs available. Logs may be stored in external log aggregation services in production.</p>
                  <% else %>
                    <%= for log <- Enum.take(@server_logs, 20) do %>
                      <div class={"py-0.5 " <> log_color(log)}>
                        <%= log %>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
    </AdminSidebar.admin_layout>
      
    <!-- Full Logs Modal -->
    <%= if @show_logs_modal do %>
        <div class="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4" phx-click="toggle_logs_modal">
          <div class="bg-gray-900 rounded-xl border border-gray-700 w-full max-w-6xl max-h-[80vh] flex flex-col" phx-click-away="toggle_logs_modal">
            <div class="flex items-center justify-between p-4 border-b border-gray-700">
              <h3 class="text-lg font-bold text-white">Server Logs (Last 100 Lines)</h3>
              <button type="button" phx-click="toggle_logs_modal" class="text-gray-400 hover:text-white">
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <div class="flex-1 overflow-y-auto p-4 font-mono text-xs bg-black/50">
              <%= if @server_logs == [] do %>
                <p class="text-gray-500">No logs available.</p>
              <% else %>
                <%= for log <- @server_logs do %>
                  <div class={"py-0.5 " <> log_color(log)}>
                    <%= log %>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    """
  end
  
  defp log_color(log) do
    cond do
      String.contains?(log, "[error]") or String.contains?(log, "ERROR") -> "text-red-400"
      String.contains?(log, "[warn") or String.contains?(log, "WARNING") -> "text-yellow-400"
      String.contains?(log, "[info]") or String.contains?(log, "INFO") -> "text-blue-400"
      String.contains?(log, "[debug]") or String.contains?(log, "DEBUG") -> "text-gray-500"
      true -> "text-gray-300"
    end
  end
  
  # Stat card component
  attr :icon, :string, required: true
  attr :value, :integer, required: true
  attr :label, :string, required: true
  attr :color, :string, default: "blue"
  
  defp stat_card(assigns) do
    color_classes = case assigns.color do
      "blue" -> "bg-blue-500/10 text-blue-400"
      "green" -> "bg-green-500/10 text-green-400"
      "purple" -> "bg-purple-500/10 text-purple-400"
      "amber" -> "bg-amber-500/10 text-amber-400"
      _ -> "bg-gray-500/10 text-gray-400"
    end
    assigns = assign(assigns, :color_classes, color_classes)
    
    ~H"""
    <div class="bg-gray-800/50 backdrop-blur-sm rounded-xl p-5 border border-gray-700">
      <div class="flex items-center gap-4">
        <div class={"p-3 rounded-lg " <> @color_classes}>
          <span class="text-2xl"><%= @icon %></span>
        </div>
        <div>
          <p class="text-2xl font-bold text-white"><%= @value %></p>
          <p class="text-gray-400 text-sm"><%= @label %></p>
        </div>
      </div>
    </div>
    """
  end
end