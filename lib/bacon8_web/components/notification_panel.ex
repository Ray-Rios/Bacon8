defmodule Bacon8Web.Components.NotificationPanel do
  @moduledoc """
  Notification panel component: the hub's notifications (mentions, invites, ... from any plugin)
  """
  use Bacon8Web, :html

  @doc """
  Renders a notification panel that pops up from the taskbar
  """
  attr :show, :boolean, default: false
  attr :mention_notifications, :list, default: []
  attr :current_user, :map, required: true
  attr :target, :any, default: nil

  def notification_panel(assigns) do
    all_notifications = Enum.sort_by(assigns.mention_notifications, & &1.inserted_at, {:desc, DateTime})
    
    assigns = assign(assigns, :all_notifications, all_notifications)
    
    ~H"""
    <%= if @show do %>
      <div 
        id="notification-panel"
        class="fixed bottom-14 right-4 w-96 max-h-[32rem] glass-menu rounded-lg shadow-2xl overflow-hidden z-50 animate-slide-up"
      >
        <div class="p-4 border-b border-gray-600 flex items-center justify-between">
          <h3 class="text-white font-semibold text-lg">Notifications</h3>
          <div class="flex items-center gap-2">
            <%= if length(@all_notifications) > 0 do %>
              <button
                phx-click="mark_all_notifications_read"
                phx-target={@target}
                class="text-xs text-cyan-400 hover:text-cyan-300 transition-colors"
              >
                Mark all read
              </button>
            <% end %>
            <button
              phx-click="toggle_notifications"
              phx-target={@target}
              class="text-gray-400 hover:text-white transition-colors"
            >
              ✕
            </button>
          </div>
        </div>

        <div class="overflow-y-auto max-h-96">
          <%= if Enum.empty?(@all_notifications) do %>
            <div class="p-8 text-center text-gray-400">
              <div class="text-4xl mb-2">📭</div>
              <p>No pending notifications</p>
            </div>
          <% else %>
            <div class="divide-y divide-gray-700">
              <%= for notification <- @all_notifications do %>
                <.mention_notification notification={notification} target={@target} />
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if !Enum.empty?(@all_notifications) do %>
          <div class="p-3 border-t border-gray-600 bg-gray-900/50">
            <div class="text-xs text-gray-400 text-center">
              💡 Tip: Click a notification to open it
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :notification, :map, required: true
  attr :target, :any, default: nil
  
  defp mention_notification(assigns) do
    ~H"""
    <div 
      class={"p-4 hover:bg-gray-800/50 transition-colors cursor-pointer #{unless @notification.read, do: "bg-blue-900/20 border-l-2 border-blue-500"}"}
      phx-click="open_notification"
      phx-value-notification_id={@notification.id}
      phx-value-path={@notification.metadata["path"]}
      phx-target={@target}
    >
      <div class="flex items-start gap-3">
        <div class="text-xl">💬</div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1">
            <span class="text-white font-medium text-sm">
              <%= @notification.title %>
            </span>
            <%= unless @notification.read do %>
              <span class="w-2 h-2 rounded-full bg-blue-500"></span>
            <% end %>
          </div>
          
          <div :if={@notification.metadata["source_name"] || @notification.metadata["channel_name"]} class="text-gray-400 text-sm mb-1 truncate">
            in <span class="text-purple-400">#<%= @notification.metadata["source_name"] || @notification.metadata["channel_name"] %></span>
          </div>
          
          <div class="text-gray-500 text-xs line-clamp-2">
            "<%= @notification.content %>"
          </div>
          
          <div class="text-xs text-gray-500 mt-1">
            <%= format_relative_time(@notification.inserted_at) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
