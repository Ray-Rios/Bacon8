defmodule Bacon8Web.Components.NotificationPanel do
  @moduledoc """
  Notification panel component for displaying pending invites and other notifications
  """
  use Bacon8Web, :html

  @doc """
  Renders a notification panel that pops up from the taskbar
  """
  attr :show, :boolean, default: false
  attr :pending_invites, :list, default: []
  attr :mention_notifications, :list, default: []
  attr :current_user, :map, required: true
  attr :target, :any, default: nil

  def notification_panel(assigns) do
    # Combine invites and mentions, sort by time
    all_notifications = 
      (Enum.map(assigns.pending_invites, &Map.put(&1, :notification_type, :invite)) ++
       Enum.map(assigns.mention_notifications, &Map.put(&1, :notification_type, :mention)))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    
    assigns = assign(assigns, :all_notifications, all_notifications)
    
    ~H"""
    <%= if @show do %>
      <div 
        id="notification-panel"
        class="fixed bottom-14 right-4 w-96 max-h-[32rem] glass-dark rounded-lg shadow-2xl border border-gray-600 overflow-hidden z-50 animate-slide-up"
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
                <%= case notification.notification_type do %>
                  <% :invite -> %>
                    <.invite_notification invite={notification} target={@target} />
                  <% :mention -> %>
                    <.mention_notification notification={notification} target={@target} />
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if !Enum.empty?(@all_notifications) do %>
          <div class="p-3 border-t border-gray-600 bg-gray-900/50">
            <div class="text-xs text-gray-400 text-center">
              💡 Tip: Click on a mention to go to the message
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :invite, :map, required: true
  attr :target, :any, default: nil
  
  defp invite_notification(assigns) do
    ~H"""
    <div class="p-4 hover:bg-gray-800/50 transition-colors">
      <div class="flex items-start justify-between mb-2">
        <div class="flex-1">
          <div class="text-white font-medium mb-1">
            📨 Channel Invite
          </div>
          <div class="text-gray-300 text-sm mb-2">
            <span class="font-semibold text-cyan-400"><%= @invite.inviter.name || @invite.inviter.email %></span>
            invited you to
            <span class="font-semibold text-purple-400">#<%= @invite.channel.name %></span>
          </div>
          <%= if @invite.channel.description do %>
            <div class="text-gray-400 text-xs mb-2 italic">
              "<%= @invite.channel.description %>"
            </div>
          <% end %>
          <div class="text-xs text-gray-500">
            <%= format_relative_time(@invite.inserted_at) %>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <button
          type="button"
          phx-click="accept_invite"
          phx-value-invite_id={@invite.id}
          phx-target={@target}
          class="flex-1 px-3 py-2 bg-green-600 hover:bg-green-700 text-white text-sm font-medium rounded transition-colors"
        >
          ✓ Accept
        </button>
        <button
          type="button"
          phx-click="decline_invite"
          phx-value-invite_id={@invite.id}
          phx-target={@target}
          class="flex-1 px-3 py-2 bg-gray-600 hover:bg-gray-700 text-white text-sm font-medium rounded transition-colors"
        >
          ✕ Decline
        </button>
      </div>
    </div>
    """
  end

  attr :notification, :map, required: true
  attr :target, :any, default: nil
  
  defp mention_notification(assigns) do
    ~H"""
    <div 
      class={"p-4 hover:bg-gray-800/50 transition-colors cursor-pointer #{unless @notification.read, do: "bg-blue-900/20 border-l-2 border-blue-500"}"}
      phx-click="open_mention"
      phx-value-notification_id={@notification.id}
      phx-value-channel_id={@notification.channel_id}
      phx-value-message_id={@notification.resource_id}
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
          
          <div class="text-gray-400 text-sm mb-1 truncate">
            in <span class="text-purple-400">#<%= @notification.metadata["channel_name"] || "channel" %></span>
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
