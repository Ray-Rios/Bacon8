defmodule Bacon8Web.Components.Taskbar do
  @moduledoc """
  Taskbar component for the desktop environment
  """
  use Bacon8Web, :html
  import Bacon8Web.AvatarHelpers

  @doc """
  Renders the desktop taskbar with start menu and system tray
  """
  attr :current_user, :map, default: nil
  attr :open_windows, :list, default: []
  attr :show_start_menu, :boolean, default: false
  attr :show_notifications, :boolean, default: false
  attr :show_audio_panel, :boolean, default: false
  attr :show_calendar, :boolean, default: false
  attr :unread_notification_count, :integer, default: 0
  attr :taskbar_projects, :list, default: []
  attr :calendar_events, :list, default: []
  attr :selected_date, :string, default: nil
  attr :target, :any, default: nil

  def taskbar(assigns) do
    ~H"""
    <div id="taskbar" class="fixed bottom-0 left-0 w-full h-[35px] auth-glass-panel border-t border-gray-700 z-50 transition-transform duration-300 ease-in-out">
      <div class="flex items-center justify-between h-full px-2">
        <!-- Start Menu Button -->
        <div id="start-menu-wrapper" class="relative h-full flex items-center" phx-click-away={if @show_start_menu, do: "toggle_start_menu", else: nil} phx-target={@target}>
          <button 
            phx-click="toggle_start_menu"
            phx-target={@target}
            aria-label="Start"
            class="start-button p-1 hover:glass-dark hover:bg-white/20 rounded transition-colors duration-200">
            <Bacon8Web.Components.Bacon.bacon size={26} />
          </button>
          
          <!-- Start Menu -->
          <div :if={@show_start_menu} 
               class="absolute bottom-full left-0 mb-2 w-80 glass-menu rounded-lg shadow-2xl overflow-hidden">
            <div class="p-4 border-b border-gray-600">
              <div class="flex items-center space-x-3">
                <%= if @current_user do %>
                  <%= avatar_tag(@current_user, size_class: "w-10 h-10") %>
                  <div class="flex-1 min-w-0">
                    <div class="text-white font-medium truncate"><%= get_user_display_name(@current_user) %></div>
                    <div class="text-gray-400 text-sm truncate"><%= @current_user.email %></div>
                  </div>
                <% else %>
                  <div class="text-white">Guest User</div>
                <% end %>
              </div>
            </div>
            
            <!-- Applications Grid -->
            <div class="p-4">
              <div class="grid grid-cols-3 gap-3">
                <button
                  type="button"
                  phx-click="open_app"
                  phx-value-app="file_manager"
                  phx-target={@target}
                  class="flex flex-col items-center p-3 rounded-lg hover:bg-gray-700 transition-colors group"
                >
                  <div class="text-2xl mb-1 group-hover:scale-110 transition-transform">📁</div>
                  <div class="text-white text-xs text-center">File Manager</div>
                </button>

                <%!-- Apps from active plugins (c:Bacon8.Plugin.desktop_apps/1), e.g. Suggestions & Bugs, which guests don't get --%>
                <.link
                  :for={app <- Bacon8.Plugins.desktop_apps(@current_user)}
                  navigate={app.path}
                  id={"start-app-" <> String.replace(app.path, ~r/[^a-z0-9]+/, "-")}
                  class="flex flex-col items-center p-3 rounded-lg hover:bg-gray-700 transition-colors group"
                >
                  <div class="text-2xl mb-1 group-hover:scale-110 transition-transform"><Bacon8Web.Components.Gem.icon icon={app.icon} /></div>
                  <div class="text-white text-xs text-center"><%= app.label %></div>
                </.link>
              </div>
            </div>
            
            <!-- Quick Access Links -->
            <div class="border-t border-gray-600 p-3">
              <div class="space-y-1">
                <%!-- Links from active plugins (BACON8.md §9), e.g. the store --%>
                <.link :for={item <- Bacon8.Plugins.nav_links(@current_user)} navigate={item.path} class="flex items-center space-x-2 px-3 py-2 rounded hover:bg-gray-700 text-gray-300 hover:text-white transition-colors">
                  <span><Bacon8Web.Components.Gem.icon icon={item.icon} /></span>
                  <span class="text-sm"><%= item.label %></span>
                  <span :if={Map.get(item, :badge)} class="ml-auto rounded-full bg-red-500 px-1.5 text-xs font-bold text-white"><%= item.badge %></span>
                </.link>
                <.link navigate={~p"/blog"} class="flex items-center space-x-2 px-3 py-2 rounded hover:bg-gray-700 text-gray-300 hover:text-white transition-colors">
                  <span>🚬</span>
                  <span class="text-sm">Blog</span>
                </.link>
              </div>
            </div>
            
            <!-- Power Options -->
            <div class="border-t border-gray-600 p-3">
              <div class="flex justify-between">
                <%= if @current_user do %>
                  <.link href={~p"/auth/logout"} method="post" class="flex items-center space-x-2 px-3 py-2 rounded hover:bg-red-700 text-red-300 hover:text-white transition-colors">
                    <span>🚪</span>
                    <span class="text-sm">Logout</span>
                  </.link>
                <% else %>
                  <.link navigate={~p"/login"} class="flex items-center space-x-2 px-3 py-2 rounded hover:bg-blue-700 text-blue-300 hover:text-white transition-colors">
                    <span>🔑</span>
                    <span class="text-sm">Login</span>
                  </.link>
                <% end %>
                <button type="button" class="flex items-center space-x-2 px-3 py-2 rounded hover:bg-gray-700 text-gray-300 hover:text-white transition-colors">
                  <span>🔄</span>
                  <span class="text-sm">Restart</span>
                </button>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Window Buttons (Running Applications) -->
        <div class="flex-1 flex items-center space-x-1 px-4">
          <% max_z_index = Enum.max_by(@open_windows, & &1.z_index, fn -> %{z_index: 0} end).z_index %>
          <%= for window <- @open_windows do %>
            <button 
              phx-click="focus_window" 
              phx-value-window_id={window.id}
              phx-target={@target}
              class={[
                "flex items-center space-x-2 px-3 py-2 rounded text-sm font-medium transition-colors duration-200 max-w-48",
                if(window.z_index == max_z_index, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")
              ]}
            >
              <span class="text-lg"><%= get_app_icon(window.app) %></span>
              <span class="truncate"><%= window.title %></span>
              <%= if window.minimized do %>
                <span class="text-xs opacity-75">(minimized)</span>
              <% end %>
            </button>
          <% end %>
        </div>
        
        <!-- System Tray -->
        <div class="flex items-center space-x-3">
          <!-- Notifications -->
          <div class="relative">
            <button 
              phx-click="toggle_notifications"
              phx-target={@target}
              class="p-2 rounded hover:glass-dark hover:bg-white/20 text-gray-300 hover:text-white transition-colors relative"
            >
              <span class="text-lg">🔔</span>
              <% total_count = @unread_notification_count %>
              <%= if total_count > 0 do %>
                <span class="absolute -top-1 -right-1 bg-red-500 text-white text-xs font-bold rounded-full h-5 w-5 flex items-center justify-center">
                  <%= min(total_count, 9) %><%= if total_count > 9, do: "+" %>
                </span>
              <% end %>
            </button>
          </div>
          
          <!-- Volume -->
          <div class="relative">
            <button 
              phx-click="toggle_audio_panel"
              phx-target={@target}
              class="p-2 rounded hover:glass-dark hover:bg-white/20 text-gray-300 hover:text-white transition-colors"
            >
              <span class="text-lg">🔊</span>
            </button>
            
            <!-- Audio Control Panel -->
            <%= if @show_audio_panel do %>
              <div class="absolute bottom-full right-0 mb-2 w-80 glass-menu rounded-lg shadow-2xl overflow-hidden animate-slide-up">
                <div class="p-4 border-b border-gray-600">
                  <h3 class="text-white font-semibold">Audio & Notifications</h3>
                </div>
                
                <div class="p-4 space-y-4">
                  <!-- Notification Sounds Toggle -->
                  <div class="flex items-center justify-between">
                    <div class="flex-1">
                      <div class="text-white font-medium">Notification sounds</div>
                      <div class="text-gray-400 text-xs">Play sound for invites and alerts</div>
                    </div>
                    <button
                      phx-click="toggle_notification_sound"
                      phx-target={@target}
                      class={[
                        "relative inline-flex h-6 w-11 items-center rounded-full transition-colors",
                        if(@current_user && @current_user.notification_sound_enabled, do: "bg-blue-600", else: "bg-gray-600")
                      ]}
                    >
                      <span class={[
                        "inline-block h-4 w-4 transform rounded-full bg-white transition-transform",
                        if(@current_user && @current_user.notification_sound_enabled, do: "translate-x-6", else: "translate-x-1")
                      ]}></span>
                    </button>
                  </div>
                  
                  <!-- Master Volume -->
                  <div>
                    <div class="flex items-center justify-between mb-2">
                      <div class="text-white font-medium">Master Volume</div>
                      <div class="text-gray-400 text-sm"><%= trunc((@current_user && @current_user.master_volume || 0.5) * 100) %>%</div>
                    </div>
                    <input
                      type="range"
                      min="0"
                      max="100"
                      value={trunc((@current_user && @current_user.master_volume || 0.5) * 100)}
                      phx-change="update_volume"
                      phx-target={@target}
                      name="volume"
                      class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-blue-600"
                    />
                    <div class="flex justify-between text-xs text-gray-500 mt-1">
                      <span>0%</span>
                      <span>50%</span>
                      <span>100%</span>
                    </div>
                  </div>
                  
                  <!-- Test Sound Button -->
                  <button
                    phx-click="test_sound"
                    phx-target={@target}
                    class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded transition-colors flex items-center justify-center gap-2"
                  >
                    <span>🔊</span>
                    <span>Test Sound</span>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
          
          <!-- Clock -->
          <div id="calendar-wrapper" class="relative group h-full flex items-center" phx-click-away={if @show_calendar, do: "toggle_calendar", else: nil} phx-target={@target}>
            <button 
              id="taskbar-clock" 
              phx-click="toggle_calendar"
              phx-target={@target}
              class="px-2 py-[9px] rounded glass-dark hover:bg-white/20 text-gray-300 hover:text-white transition-colors text-sm font-medium"
            >
              <div class="text-center">
                <div class="time">--:--</div>
              </div>
            </button>
            
            <!-- Hover Date Tooltip -->
            <div class="absolute bottom-full right-0 mb-2 px-3 py-1 bg-gray-800 text-white text-xs rounded shadow-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none whitespace-nowrap z-50 border border-gray-600">
              <span class="date-full">--/--/----</span>
            </div>

            <!-- Calendar Popup -->
            <%= if @show_calendar do %>
              <div class="absolute bottom-full right-0 mb-2 w-80 glass-menu rounded-lg shadow-2xl overflow-hidden animate-slide-up z-50">
                <div class="p-4 border-b border-gray-600 flex justify-between items-center">
                  <h3 class="text-white font-semibold date-full-header">Calendar</h3>
                  <button phx-click="toggle_calendar" phx-target={@target} class="text-gray-400 hover:text-white">✕</button>
                </div>
                <div class="p-4">
                  <!-- Simple Calendar Grid Placeholder -->
                  <div class="grid grid-cols-7 gap-1 text-center text-xs mb-4">
                    <div class="text-gray-400 font-bold">Su</div>
                    <div class="text-gray-400 font-bold">Mo</div>
                    <div class="text-gray-400 font-bold">Tu</div>
                    <div class="text-gray-400 font-bold">We</div>
                    <div class="text-gray-400 font-bold">Th</div>
                    <div class="text-gray-400 font-bold">Fr</div>
                    <div class="text-gray-400 font-bold">Sa</div>
                    <!-- Mock days for visual representation -->
                    <%= for day <- calendar_days() do %>
                      <% date_key = get_date_key(day) %>
                      <% has_event = day && has_events_on_date?(@calendar_events, @taskbar_projects, date_key) %>
                      <div 
                        phx-click={if day, do: "select_date", else: nil}
                        phx-value-day={day}
                        phx-target={@target}
                        class={"p-2 rounded transition-colors relative " <> if(day, do: "hover:bg-blue-600 cursor-pointer text-gray-300 hover:text-white", else: "")}
                      >
                        <%= day %>
                        <%= if has_event do %>
                          <span class="absolute bottom-0.5 right-0.5 w-1.5 h-1.5 bg-blue-400 rounded-full"></span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  
                  <!-- Events Section -->
                  <div class="border-t border-gray-600 pt-4">
                    <%= if @selected_date do %>
                      <h4 class="text-white text-sm font-medium mb-2">Events on <%= @selected_date %></h4>
                      <div class="space-y-2 text-sm max-h-48 overflow-y-auto">
                        <% events_for_date = get_events_for_date(@calendar_events, @taskbar_projects, @selected_date) %>
                        <%= if Enum.empty?(events_for_date) do %>
                          <div class="text-gray-400 text-xs">No events on this date</div>
                        <% else %>
                          <%= for event <- events_for_date do %>
                            <div class="p-2 bg-gray-800/50 rounded border border-gray-700">
                              <div class="flex items-center gap-2">
                                <span class={"w-2 h-2 rounded-full " <> event_color(event.type)}></span>
                                <span class="text-gray-200 font-medium text-xs"><%= event.title %></span>
                              </div>
                              <%= if event.description do %>
                                <div class="text-gray-400 text-xs mt-1 pl-4"><%= String.slice(event.description || "", 0, 50) %></div>
                              <% end %>
                              <%= if event.path do %>
                                <div class="mt-1 pl-4">
                                  <a href={event.path} class="text-blue-400 hover:text-blue-300 text-xs">View →</a>
                                </div>
                              <% end %>
                            </div>
                          <% end %>
                        <% end %>
                      </div>
                      <div class="mt-2">
                        <button type="button" phx-click="close_note_input" phx-target={@target} class="text-gray-400 hover:text-white text-xs">← Back</button>
                      </div>
                    <% else %>
                      <h4 class="text-white text-sm font-medium mb-2">Upcoming</h4>
                      <div class="space-y-2 text-sm text-gray-300 max-h-48 overflow-y-auto">
                        <!-- Scheduled Events -->
                        <%= for event <- Enum.take(@calendar_events || [], 3) do %>
                          <div class="flex items-center justify-between p-2 bg-gray-800/50 rounded">
                            <div>
                              <div class="font-medium flex items-center gap-2">
                                <span class={"w-2 h-2 rounded-full " <> event_color(event.type)}></span>
                                <span class="text-gray-200"><%= event.title %></span>
                              </div>
                              <div class="text-xs text-gray-400 pl-4">
                                <%= if event.scheduled_at, do: Calendar.strftime(event.scheduled_at, "%b %d, %H:%M"), else: "Not scheduled" %>
                              </div>
                            </div>
                          </div>
                        <% end %>
                        
                        <!-- Projects -->
                        <%= for p <- Enum.take(@taskbar_projects || [], 3) do %>
                          <div class="flex items-center justify-between p-2 bg-gray-800/50 rounded">
                            <div class="flex-1 min-w-0">
                              <div class="font-medium flex items-center gap-2">
                                <span class="w-2 h-2 rounded-full bg-green-500"></span>
                                <a href={p.path} class="hover:underline text-gray-200 truncate"><%= p.name %></a>
                              </div>
                              <div class="text-xs text-gray-400 pl-4">
                                <%= p.start_date && Calendar.strftime(p.start_date, "%b %d") || "No start" %> — <%= p.status %>
                              </div>
                            </div>
                            <a href={p.path} class="text-blue-400 hover:text-blue-300 text-xs ml-2">Open</a>
                          </div>
                        <% end %>

                        <%= if Enum.empty?(@taskbar_projects || []) && Enum.empty?(@calendar_events || []) do %>
                          <div class="text-gray-400 text-xs">No upcoming events or projects</div>
                        <% end %>
                      </div>
                      
                      <!-- Quick Links -->
                      <div class="mt-3 pt-3 border-t border-gray-700 flex gap-2">
                        <a href="/admin/projects" class="text-xs text-blue-400 hover:text-blue-300">Projects</a>
                        <span class="text-gray-600">•</span>
                        <a href="/admin/scheduler" class="text-xs text-blue-400 hover:text-blue-300">Scheduler</a>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_user_display_name(user) do
    user.name || "User"
  end

  defp get_app_icon(app) do
    case app do
      "file_manager" -> "📁"
      "welcome" -> "👋"
      _ -> "💻"
    end
  end

  defp get_date_key(day) when is_integer(day) do
    today = Date.utc_today()
    "#{today.year}-#{String.pad_leading(to_string(today.month), 2, "0")}-#{String.pad_leading(to_string(day), 2, "0")}"
  end
  
  defp get_date_key(nil), do: nil

  defp calendar_days do
    today = Date.utc_today()
    first_day = Date.beginning_of_month(today)
    last_day = Date.end_of_month(today)
    
    # Elixir: Mon=1, Sun=7.
    # Grid: Su=0, Mon=1...
    start_padding = 
      case Date.day_of_week(first_day) do
        7 -> 0 # Sunday
        n -> n
      end
      
    padding = List.duplicate(nil, start_padding)
    days = Enum.to_list(1..last_day.day)
    
    padding ++ days
  end
  
  defp has_events_on_date?(events, projects, date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        has_event = Enum.any?(events || [], fn e ->
          e.scheduled_at && DateTime.to_date(e.scheduled_at) == date
        end)
        
        has_project = Enum.any?(projects || [], fn p ->
          (p.start_date && DateTime.to_date(p.start_date) == date) ||
          (p.end_date && DateTime.to_date(p.end_date) == date)
        end)
        
        has_event || has_project
      _ -> false
    end
  end
  defp has_events_on_date?(_, _, _), do: false

  defp get_events_for_date(events, projects, date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        event_items = (events || [])
        |> Enum.filter(fn e -> e.scheduled_at && DateTime.to_date(e.scheduled_at) == date end)
        |> Enum.map(fn e ->
          %{
            type: e.event_type || "scheduled",
            title: e.title,
            description: e.description,
            path: nil
          }
        end)
        
        project_items = (projects || [])
        |> Enum.filter(fn p ->
          (p.start_date && DateTime.to_date(p.start_date) == date) ||
          (p.end_date && DateTime.to_date(p.end_date) == date)
        end)
        |> Enum.map(fn p ->
          is_start = p.start_date && DateTime.to_date(p.start_date) == date
          %{
            type: "project",
            title: "#{p.name} #{if is_start, do: "(Start)", else: "(End)"}",
            description: nil,
            path: p.path
          }
        end)
        
        event_items ++ project_items
      _ -> []
    end
  end
  defp get_events_for_date(_, _, _), do: []

  defp event_color(type) do
    case type do
      "project" -> "bg-green-500"
      "scheduled" -> "bg-blue-500"
      "cron" -> "bg-purple-500"
      "webhook" -> "bg-orange-500"
      "trigger" -> "bg-yellow-500"
      _ -> "bg-gray-500"
    end
  end
end