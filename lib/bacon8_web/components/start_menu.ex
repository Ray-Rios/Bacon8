defmodule Bacon8Web.Components.StartMenu do
  use Bacon8Web, :html

  attr :show, :boolean, default: false
  attr :current_user, :map, required: true
  attr :target, :any, default: nil

  def start_menu(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        class="fixed bottom-14 left-4 w-80 glass-dark rounded-lg shadow-2xl border border-gray-600 overflow-hidden z-50 animate-slide-up flex flex-col"
        style="height: 500px;"
      >
        <!-- User Profile -->
        <div class="p-4 border-b border-gray-600 bg-gray-800/50 flex items-center space-x-3">
          <div class="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-bold text-lg">
            <%= String.at(@current_user.name || @current_user.email, 0) |> String.upcase() %>
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-white font-medium truncate"><%= @current_user.name || "User" %></div>
            <div class="text-gray-400 text-xs truncate"><%= @current_user.email %></div>
          </div>
          <a href="/users/settings" class="text-gray-400 hover:text-white p-2">
            ⚙️
          </a>
        </div>

        <!-- App Grid -->
        <div class="flex-1 overflow-y-auto p-4">
          <div class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Applications</div>
          
          <div class="grid grid-cols-3 gap-4">
            <.app_icon name="File Manager" icon="📁" app="file_manager" target={@target} />
            <.app_icon name="Terminal" icon="💻" app="terminal" target={@target} />
            <.app_icon name="Calculator" icon="🧮" app="calculator" target={@target} />
            <.app_icon name="Notepad" icon="📝" app="notepad" target={@target} />
            <.app_icon name="Media Player" icon="🎵" app="media_player" target={@target} />
            <.app_icon name="Settings" icon="⚙️" app="settings" target={@target} />
          </div>
        </div>

        <!-- Power Options -->
        <div class="p-3 border-t border-gray-600 bg-gray-800/50 flex justify-between items-center">
          <button 
            phx-click="toggle_start_menu"
            phx-target={@target}
            class="text-gray-400 hover:text-white text-sm px-3 py-1 rounded hover:bg-gray-700"
          >
            Cancel
          </button>
          
          <a 
            href="/users/log_out" 
            method="delete" 
            class="flex items-center space-x-2 px-3 py-1 rounded text-red-400 hover:bg-red-500/10 hover:text-red-300 transition-colors"
          >
            <span>⏻</span>
            <span class="text-sm font-medium">Log Out</span>
          </a>
        </div>
      </div>
    <% end %>
    """
  end

  attr :name, :string, required: true
  attr :icon, :string, required: true
  attr :app, :string, required: true
  attr :target, :any, required: true

  def app_icon(assigns) do
    ~H"""
    <button 
      phx-click="open_app" 
      phx-value-app={@app}
      phx-target={@target}
      class="flex flex-col items-center justify-center p-2 rounded hover:bg-white/10 transition-colors group"
    >
      <div class="text-3xl mb-2 group-hover:scale-110 transition-transform"><%= @icon %></div>
      <div class="text-xs text-gray-300 text-center leading-tight"><%= @name %></div>
    </button>
    """
  end
end
