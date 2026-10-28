defmodule Bacon8Web.AdminLive.Security do
  use Bacon8Web, :live_view
  alias Bacon8.Security
  alias Bacon8.RateLimiter
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    # on_mount already verified admin access
    if connected?(socket) do
      # Update stats every 5 seconds
      :timer.send_interval(5000, self(), :update_stats)
    end

    {:ok, load_security_data(socket)}
  end

  @impl true
  def handle_info(:update_stats, socket) do
    {:noreply, load_security_data(socket)}
  end

  @impl true
  def handle_event("block_identifier", %{"identifier" => identifier, "type" => type, "reason" => reason}, socket) do
    case Security.block_identifier(%{
      identifier: identifier,
      identifier_type: type,
      reason: reason,
      blocked_at: DateTime.utc_now(),
      auto_blocked: false,
      blocked_by_user_id: socket.assigns.current_user.id
    }) do
      {:ok, _} ->
        # Also block in rate limiter
        RateLimiter.block(identifier)
        {:noreply, load_security_data(socket) |> put_flash(:info, "Identifier blocked successfully")}
      
      {:error, :not_blockable} ->
        {:noreply, socket |> put_flash(:error, not_blockable_text(identifier))}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Failed to block identifier")}
    end
  end

  @impl true
  def handle_event("unblock_identifier", %{"identifier" => identifier, "type" => type}, socket) do
    case Security.unblock_identifier(identifier, type) do
      {:ok, _} ->
        # Also unblock in rate limiter
        RateLimiter.unblock(identifier)
        {:noreply, load_security_data(socket) |> put_flash(:info, "Identifier unblocked successfully")}
      
      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to unblock identifier")}
    end
  end

  @impl true
  def handle_event("allow_identifier", %{"identifier" => identifier, "type" => type, "reason" => reason}, socket) do
    case Security.allow_identifier(%{
      identifier: identifier,
      identifier_type: type,
      reason: reason,
      added_at: DateTime.utc_now(),
      added_by_user_id: socket.assigns.current_user.id
    }) do
      {:ok, _} ->
        {:noreply, load_security_data(socket) |> put_flash(:info, "Identifier added to allowlist")}
      
      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to add to allowlist")}
    end
  end

  @impl true
  def handle_event("disallow_identifier", %{"identifier" => identifier, "type" => type}, socket) do
    case Security.disallow_identifier(identifier, type) do
      {:ok, _} ->
        {:noreply, load_security_data(socket) |> put_flash(:info, "Identifier removed from allowlist")}
      
      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to remove from allowlist")}
    end
  end

  @impl true
  def handle_event("clear_rate_limiter", %{"identifier" => identifier}, socket) do
    RateLimiter.record_success(identifier)
    {:noreply, load_security_data(socket) |> put_flash(:info, "Rate limiter cleared for #{identifier}")}
  end

  @impl true
  def handle_event("block_ip_quick", %{"ip" => ip}, socket) do
    # (checked here too, before anything is added to the rate limiter or the block table)
    if not Security.blockable_ip?(ip) do
      {:noreply, put_flash(socket, :error, not_blockable_text(ip))}
    else
      block_ip_now(socket, ip)
    end
  end


  @impl true
  def handle_event("fetch_logs", _params, socket) do
    # Fetch actual server logs from the in-memory log buffer
    logs = try do
      entries = Bacon8.LogBuffer.get_entries(100)
      
      if entries == [] do
        "No log entries captured yet.\n\nLogs are captured in real-time from the running application.\nTry refreshing in a few moments or trigger some activity."
      else
        log_lines = entries
        |> Enum.map(fn entry -> entry.message end)
        |> Enum.join("\n")
        
        "=== Application Server Logs (Last #{length(entries)} entries) ===\n\n#{log_lines}\n\n=== End of Logs ==="
      end
    rescue
      e -> "Error fetching logs: #{Exception.message(e)}"
    end
    
    {:noreply, assign(socket, server_logs: logs)}
  end

  defp block_ip_now(socket, ip) do
    case Security.block_identifier(%{
      identifier: ip,
      identifier_type: "ip",
      reason: "Blocked from security dashboard - vulnerability scanning",
      blocked_at: DateTime.utc_now(),
      auto_blocked: false,
      blocked_by_user_id: socket.assigns.current_user.id
    }) do
      {:ok, _} ->
        # Also block in rate limiter and ETS
        RateLimiter.block(ip)
        ensure_ets_table()
        :ets.insert(:blocked_ips, {ip, System.system_time(:second)})
        {:noreply, load_security_data(socket) |> put_flash(:info, "IP #{ip} blocked successfully")}
      
      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Failed to block IP")}
    end
  end

  defp not_blockable_text(ip) do
    "#{ip} is an internal address, not a visitor: behind Docker Desktop every visitor arrives from the server's own gateway, so blocking it would lock everyone out, you included. Real addresses need a proxy in front that passes them on."
  end

  defp ensure_ets_table do
    case :ets.whereis(:blocked_ips) do
      :undefined ->
        :ets.new(:blocked_ips, [:set, :public, :named_table])
      _ ->
        :ok
    end
  end

  defp load_security_data(socket) do
    stats = Security.get_security_stats()
    suspicious_stats = Security.get_suspicious_stats()
    
    socket
    |> assign(:stats, stats)
    |> assign(:suspicious_stats, suspicious_stats)
    |> assign(:suspicious_requests, Security.get_recent_suspicious_requests(50))
    |> assign(:blocked_identifiers, Security.list_blocked_history(90)) # Show 90 days history
    |> assign(:allowed_identifiers, Security.list_allowed_identifiers())
    |> assign(:recent_failures, Security.get_recent_failed_attempts(50))
    |> assign(:rate_limiter_blocked, RateLimiter.list_blocked())
    |> assign(:page_title, "Security Dashboard")
  end

  defp scan_type_color(type) do
    case type do
      "wordpress_scan" -> "bg-red-800 text-red-200"
      "php_probe" -> "bg-orange-800 text-orange-200"
      "shell_probe" -> "bg-red-900 text-red-100"
      "backdoor_probe" -> "bg-red-900 text-red-100"
      "config_probe" -> "bg-yellow-800 text-yellow-200"
      "env_probe" -> "bg-yellow-800 text-yellow-200"
      "git_probe" -> "bg-purple-800 text-purple-200"
      "htaccess_probe" -> "bg-gray-700 text-gray-200"
      "phpmyadmin_probe" -> "bg-orange-800 text-orange-200"
      "mysql_probe" -> "bg-blue-800 text-blue-200"
      "adminer_probe" -> "bg-blue-800 text-blue-200"
      "cgi_probe" -> "bg-gray-700 text-gray-200"
      "sql_injection" -> "bg-red-900 text-red-100"
      "xss_attempt" -> "bg-red-900 text-red-100"
      "lfi_attempt" -> "bg-red-900 text-red-100"
      "path_traversal" -> "bg-red-800 text-red-200"
      _ -> "bg-gray-700 text-gray-200"
    end
  end

  defp humanize_scan_type(type) do
    case type do
      "wordpress_scan" -> "WordPress"
      "php_probe" -> "PHP"
      "shell_probe" -> "Shell"
      "backdoor_probe" -> "Backdoor"
      "config_probe" -> "Config"
      "env_probe" -> ".env"
      "git_probe" -> ".git"
      "htaccess_probe" -> ".htaccess"
      "phpmyadmin_probe" -> "phpMyAdmin"
      "mysql_probe" -> "MySQL"
      "adminer_probe" -> "Adminer"
      "cgi_probe" -> "CGI"
      "sql_injection" -> "SQLi"
      "xss_attempt" -> "XSS"
      "lfi_attempt" -> "LFI"
      "path_traversal" -> "Path Traversal"
      "security_txt" -> "security.txt"
      _ -> type
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/security">
      <div class="mb-8 flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold text-white">Security Dashboard</h1>
          <p class="mt-2 text-sm text-gray-400">Monitor login attempts and manage security controls</p>
        </div>
        <button phx-click="fetch_logs" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium transition-colors">
          View Server Logs
        </button>
      </div>

      <%= if assigns[:server_logs] do %>
        <div class="mb-8 dark-glass shadow rounded-lg overflow-hidden">
          <div class="px-4 py-5 sm:p-6">
            <div class="flex justify-between items-center mb-4">
              <h3 class="text-lg leading-6 font-medium text-white">Server Logs (Last 100 lines)</h3>
              <button phx-click="fetch_logs" class="text-blue-400 hover:text-blue-300 text-sm">Refresh</button>
            </div>
            <pre class="bg-black/50 p-4 rounded text-xs text-gray-300 font-mono overflow-x-auto max-h-96 whitespace-pre-wrap"><%= @server_logs %></pre>
          </div>
        </div>
      <% end %>

      <!-- Statistics Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-6 mb-8">
        <div class="dark-glass overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <svg class="h-6 w-6 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
                </svg>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-400 truncate">
                    Attempts (Last Hour)
                  </dt>
                  <dd class="flex items-baseline">
                    <div class="text-2xl font-semibold text-white">
                      <%= @stats.total_attempts_last_hour %>
                    </div>
                    <div class="ml-2 flex items-baseline text-sm font-semibold text-red-600">
                      <%= @stats.failed_attempts_last_hour %> failed
                    </div>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div class="dark-glass overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <svg class="h-6 w-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-400 truncate">
                    Attempts (Last 24h)
                  </dt>
                  <dd class="flex items-baseline">
                    <div class="text-2xl font-semibold text-white">
                      <%= @stats.total_attempts_last_day %>
                    </div>
                    <div class="ml-2 flex items-baseline text-sm font-semibold text-red-600">
                      <%= @stats.failed_attempts_last_day %> failed
                    </div>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div class="dark-glass overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <svg class="h-6 w-6 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                </svg>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-400 truncate">
                    Blocked Identifiers
                  </dt>
                  <dd class="text-2xl font-semibold text-white">
                    <%= @stats.blocked_identifiers %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div class="dark-glass overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <svg class="h-6 w-6 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 11c0 3.517-1.009 6.799-2.753 9.571m-3.44-2.04l.054-.09A13.916 13.916 0 008 11a4 4 0 118 0c0 1.017-.07 2.019-.203 3m-2.118 6.844A21.88 21.88 0 0015.171 17m3.839 1.132c.645-2.266.99-4.659.99-7.132A8 8 0 008 4.07M3 15.364c.64-1.319 1-2.8 1-4.364 0-1.457.39-2.823 1.07-4" />
                </svg>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-400 truncate">
                    Device Fingerprints
                  </dt>
                  <dd class="text-2xl font-semibold text-white">
                    <%= @stats.unique_fingerprints %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div class="dark-glass overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <svg class="h-6 w-6 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-400 truncate">
                    Suspicious (24h)
                  </dt>
                  <dd class="flex items-baseline">
                    <div class="text-2xl font-semibold text-white">
                      <%= @suspicious_stats.total_last_day %>
                    </div>
                    <div class="ml-2 flex items-baseline text-sm font-semibold text-yellow-500">
                      <%= @suspicious_stats.total_last_hour %>/hr
                    </div>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Rate Limiter Active Blocks -->
      <div class="dark-glass shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-lg leading-6 font-medium text-white mb-4">
            Rate Limiter Active Blocks
          </h3>
          <%= if Enum.empty?(@rate_limiter_blocked) do %>
            <p class="text-sm text-gray-400">No active rate-limited identifiers</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-700">
                <thead>
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Identifier
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Failed Attempts
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for identifier <- @rate_limiter_blocked do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-white">
                        <%= identifier %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        10+ (Auto-blocked)
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <button
                          phx-click="clear_rate_limiter"
                          phx-value-identifier={identifier}
                          class="text-blue-400 hover:text-blue-300"
                        >
                          Clear
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Add to Block/Allow List Forms -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-8 mb-8">
        <!-- Block Form -->
        <div class="dark-glass shadow rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg leading-6 font-medium text-white mb-4">
              Block Identifier
            </h3>
            <form phx-submit="block_identifier">
              <div class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-300">
                    Identifier (IP or Fingerprint)
                  </label>
                  <input
                    type="text"
                    name="identifier"
                    required
                    class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                    placeholder="192.168.1.1 or fingerprint hash"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-300">
                    Type
                  </label>
                  <select
                    name="type"
                    required
                    class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  >
                    <option value="ip">IP Address</option>
                    <option value="fingerprint">Device Fingerprint</option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-300">
                    Reason
                  </label>
                  <input
                    type="text"
                    name="reason"
                    class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                    placeholder="Suspicious activity detected"
                  />
                </div>
                <button
                  type="submit"
                  class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                >
                  Block Identifier
                </button>
              </div>
            </form>
          </div>
        </div>

        <!-- Allow Form -->
        <div class="dark-glass shadow rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg leading-6 font-medium text-white mb-4">
              Add to Allowlist
            </h3>
            <form phx-submit="allow_identifier">
              <div class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-300">
                    Identifier (IP or Fingerprint)
                  </label>
                  <input
                    type="text"
                    name="identifier"
                    required
                    class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                    placeholder="192.168.1.1 or fingerprint hash"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-300">
                    Type
                  </label>
                  <select
                    name="type"
                    required
                    class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  >
                    <option value="ip">IP Address</option>
                    <option value="fingerprint">Device Fingerprint</option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-300">
                    Reason
                  </label>
                  <input
                    type="text"
                    name="reason"
                    class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                    placeholder="Trusted administrator"
                  />
                </div>
                <button
                  type="submit"
                  class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                >
                  Add to Allowlist
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>

      <!-- Blocked Identifiers Table -->
      <div class="dark-glass shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-lg leading-6 font-medium text-white mb-4">
            Blocked Identifiers History (Last 90 Days)
          </h3>
          <%= if Enum.empty?(@blocked_identifiers) do %>
            <p class="text-sm text-gray-400">No blocked identifiers history</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-700">
                <thead>
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Identifier
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Type
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Reason
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Blocked At
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Auto
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for blocked <- @blocked_identifiers do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-white">
                        <%= blocked.identifier %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-gray-700 text-gray-300">
                          <%= blocked.identifier_type %>
                        </span>
                      </td>
                      <td class="px-6 py-4 text-sm text-gray-400">
                        <%= blocked.reason || "N/A" %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        <%= Calendar.strftime(blocked.blocked_at, "%Y-%m-%d %H:%M") %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        <%= if blocked.auto_blocked, do: "Yes", else: "No" %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <button
                          phx-click="unblock_identifier"
                          phx-value-identifier={blocked.identifier}
                          phx-value-type={blocked.identifier_type}
                          class="text-blue-400 hover:text-blue-300"
                        >
                          Unblock
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Allowed Identifiers Table -->
      <div class="dark-glass shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-lg leading-6 font-medium text-white mb-4">
            Allowlist
          </h3>
          <%= if Enum.empty?(@allowed_identifiers) do %>
            <p class="text-sm text-gray-400">No allowed identifiers</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-700">
                <thead>
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Identifier
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Type
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Reason
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Added At
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for allowed <- @allowed_identifiers do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-white">
                        <%= allowed.identifier %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-900 text-green-300">
                          <%= allowed.identifier_type %>
                        </span>
                      </td>
                      <td class="px-6 py-4 text-sm text-gray-400">
                        <%= allowed.reason || "N/A" %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        <%= Calendar.strftime(allowed.added_at, "%Y-%m-%d %H:%M") %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <button
                          phx-click="disallow_identifier"
                          phx-value-identifier={allowed.identifier}
                          phx-value-type={allowed.identifier_type}
                          class="text-red-400 hover:text-red-300"
                        >
                          Remove
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Suspicious Requests (Vulnerability Scans) -->
      <div class="dark-glass shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-lg leading-6 font-medium text-white mb-4">
            Suspicious Requests (Vulnerability Scans)
          </h3>
          
          <!-- Behind Docker Desktop every visitor arrives from one internal address -->
          <%= if Enum.any?(@suspicious_stats.top_offenders, fn {ip, _} -> not Security.blockable_ip?(ip) end) do %>
            <div id="internal-address-note" class="mb-6 p-4 bg-blue-900/20 border border-blue-700 rounded-lg text-sm text-blue-100">
              <strong>These scans are real, but the address is not.</strong>
              An address like 192.168.65.3 is the server's own gateway (Docker Desktop's virtual machine), not a
              hacker's computer and not a compromised container. Every visitor from the internet is rewritten to it
              before reaching this site, so scanners and members look alike here. It can't be blocked (that would
              block everyone), and the sign-in limits use the account instead of the address. To see and block real
              addresses, put a proxy in front that passes them on.
            </div>
          <% end %>

          <!-- Top Offenders Summary -->
          <%= if not Enum.empty?(@suspicious_stats.top_offenders) do %>
            <div class="mb-6 p-4 bg-yellow-900/20 border border-yellow-700 rounded-lg">
              <h4 class="text-sm font-medium text-yellow-400 mb-2">Top Offending IPs (Last 24h)</h4>
              <div class="flex flex-wrap gap-2">
                <%= for {ip, count} <- @suspicious_stats.top_offenders do %>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-800 text-yellow-200">
                    <%= ip %>: <%= count %> requests
                    <button
                      :if={Security.blockable_ip?(ip)}
                      phx-click="block_ip_quick"
                      phx-value-ip={ip}
                      class="ml-2 text-red-400 hover:text-red-300"
                      title="Block this IP"
                    >
                      🚫
                    </button>
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Scan Types Breakdown -->
          <%= if not Enum.empty?(@suspicious_stats.by_type_last_day) do %>
            <div class="mb-6 p-4 bg-gray-800/50 rounded-lg">
              <h4 class="text-sm font-medium text-gray-300 mb-2">Scan Types (Last 24h)</h4>
              <div class="flex flex-wrap gap-2">
                <%= for {type, count} <- @suspicious_stats.by_type_last_day do %>
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{scan_type_color(type)}"}>
                    <%= humanize_scan_type(type) %>: <%= count %>
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if Enum.empty?(@suspicious_requests) do %>
            <p class="text-sm text-gray-400">No suspicious requests detected</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-700">
                <thead>
                  <tr>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Time
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      IP Address
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Type
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Path
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for request <- @suspicious_requests do %>
                    <tr>
                      <td class="px-4 py-3 whitespace-nowrap text-xs text-gray-400">
                        <%= Calendar.strftime(request.inserted_at, "%m-%d %H:%M:%S") %>
                      </td>
                      <td class="px-4 py-3 whitespace-nowrap text-sm font-mono text-white">
                        <%= request.ip_address %>
                      </td>
                      <td class="px-4 py-3 whitespace-nowrap">
                        <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{scan_type_color(request.request_type)}"}>
                          <%= humanize_scan_type(request.request_type) %>
                        </span>
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-400 max-w-xs truncate" title={request.path}>
                        <%= String.slice(request.path, 0..50) %><%= if String.length(request.path) > 50, do: "..." %>
                      </td>
                      <td class="px-4 py-3 whitespace-nowrap text-sm font-medium">
                        <button
                          :if={Security.blockable_ip?(request.ip_address)}
                          phx-click="block_ip_quick"
                          phx-value-ip={request.ip_address}
                          class="text-red-400 hover:text-red-300"
                        >
                          Block
                        </button>
                        <span :if={!Security.blockable_ip?(request.ip_address)} class="text-gray-500 text-xs" title="Internal address: it names no one visitor, so it can't be blocked">can't block</span>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Recent Failed Attempts -->
      <div class="dark-glass shadow rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-lg leading-6 font-medium text-white mb-4">
            Recent Failed Login Attempts
          </h3>
          <%= if Enum.empty?(@recent_failures) do %>
            <p class="text-sm text-gray-400">No recent failed attempts</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-700">
                <thead>
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Identifier
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      IP Address
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      User Agent
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wider">
                      Time
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <%= for attempt <- @recent_failures do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-white">
                        <%= String.slice(attempt.identifier, 0..20) %><%= if String.length(attempt.identifier) > 20, do: "..." %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        <%= attempt.ip_address || "N/A" %>
                      </td>
                      <td class="px-6 py-4 text-sm text-gray-400 max-w-xs truncate">
                        <%= if attempt.user_agent do %>
                          <%= String.slice(attempt.user_agent, 0..50) %><%= if String.length(attempt.user_agent) > 50, do: "..." %>
                        <% else %>
                          N/A
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                        <%= if attempt.last_attempt_at do %>
                          <%= Calendar.strftime(attempt.last_attempt_at, "%Y-%m-%d %H:%M:%S") %>
                        <% else %>
                          N/A
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
