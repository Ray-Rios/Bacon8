defmodule Bacon8Web.Components.AudioPanel do
  use Bacon8Web, :html

  attr :show, :boolean, default: false
  attr :current_user, :map, required: true
  attr :target, :any, default: nil

  def audio_panel(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        class="fixed bottom-14 right-20 w-80 glass-dark rounded-lg shadow-2xl border border-gray-600 overflow-hidden z-50 animate-slide-up"
      >
        <div class="p-4 border-b border-gray-600 flex items-center justify-between">
          <h3 class="text-white font-semibold">Audio Settings</h3>
          <button
            phx-click="toggle_audio_panel"
            phx-target={@target}
            class="text-gray-400 hover:text-white transition-colors"
          >
            ✕
          </button>
        </div>

        <div class="p-6 space-y-6">
          <!-- Master Volume -->
          <div class="space-y-2">
            <div class="flex justify-between text-sm text-gray-300">
              <span>Master Volume</span>
              <span><%= round((@current_user.master_volume || 0.5) * 100) %>%</span>
            </div>
            <input 
              type="range" 
              min="0" 
              max="100" 
              value={round((@current_user.master_volume || 0.5) * 100)}
              phx-change="update_volume"
              phx-target={@target}
              name="volume"
              class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-blue-500"
            />
          </div>

          <!-- Notification Sounds -->
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-300">Notification Sounds</span>
            <button 
              phx-click="toggle_notification_sound"
              phx-target={@target}
              class={"w-12 h-6 rounded-full transition-colors relative " <> if(@current_user.notification_sound_enabled, do: "bg-blue-600", else: "bg-gray-600")}
            >
              <div class={"absolute top-1 w-4 h-4 bg-white rounded-full transition-all " <> if(@current_user.notification_sound_enabled, do: "left-7", else: "left-1")}></div>
            </button>
          </div>

          <!-- Test Sound -->
          <button 
            phx-click="test_sound"
            phx-target={@target}
            class="w-full py-2 bg-gray-700 hover:bg-gray-600 text-white rounded transition-colors text-sm"
          >
            🔊 Test Sound
          </button>
        </div>
      </div>
    <% end %>
    """
  end
end
