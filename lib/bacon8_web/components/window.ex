defmodule Bacon8Web.Components.Window do
  @moduledoc """
  Window component for the desktop environment
  """
  use Phoenix.Component
  use Gettext, backend: Bacon8Web.Gettext

  @doc """
  Renders a desktop window with resize, move, minimize, maximize capabilities
  """
  attr :window, :map, required: true
  attr :current_user, :map, default: nil
  attr :target, :any, default: nil
  slot :inner_block, required: true

  def desktop_window(assigns) do
    ~H"""
    <div :if={!@window.minimized} 
         class={["desktop-window", if(@window.maximized, do: "!w-full !h-full !top-0 !left-0")]}
         style={"left: #{@window.x}px; top: #{@window.y}px; width: #{@window.width}px; height: #{@window.height}px; z-index: #{@window.z_index}"}
         id={"window-#{@window.id}"}
         phx-hook="DesktopWindow"
         phx-click="focus_window" 
         phx-target={@target}
         phx-value-window_id={@window.id}
         data-desktop-target="#bacon8-desktop">
      
      <!-- Window Header -->
      <div class="window-header auth-glass-panel border-b border-gray-600 px-4 py-2 flex justify-between items-center cursor-move">
        <div class="flex items-center space-x-3">
          <span class="text-lg"><%= get_app_icon(@window.app) %></span>
          <span class="text-white font-medium"><%= @window.title %></span>
        </div>
        
        <div class="flex items-center space-x-1">
          <button 
            type="button"
            phx-click="minimize_window" 
            phx-value-window_id={@window.id}
            phx-target={@target}
            class="w-6 h-6 bg-yellow-500 hover:bg-yellow-600 rounded-full flex items-center justify-center transition-colors"
            title="Minimize"
          >
            <span class="text-xs text-black">−</span>
          </button>
          
          <button 
            type="button"
            phx-click="toggle_maximize"
            phx-value-window_id={@window.id}
            phx-target={@target}
            class="w-6 h-6 bg-green-500 hover:bg-green-600 rounded-full flex items-center justify-center transition-colors"
            title={if @window.maximized, do: "Restore", else: "Maximize"}
          >
            <span class="text-xs text-black">□</span>
          </button>
          
          <button 
            type="button"
            phx-click="close_window" 
            phx-value-window_id={@window.id}
            phx-target={@target}
            class="w-6 h-6 bg-red-500 hover:bg-red-600 rounded-full flex items-center justify-center transition-colors"
            title="Close"
          >
            <span class="text-xs text-white">×</span>
          </button>
        </div>
      </div>
      
      <!-- Window Content -->
      <div class="window-content auth-glass-panel text-white flex-1 overflow-hidden">
        <%= render_slot(@inner_block) %>
      </div>
      
      <!-- Resize Handles -->
      <div id={"#{@window.id}-resize-n"} class="resize-handle resize-n" phx-hook="ResizeHandle" data-direction="n"></div>
      <div id={"#{@window.id}-resize-s"} class="resize-handle resize-s" phx-hook="ResizeHandle" data-direction="s"></div>
      <div id={"#{@window.id}-resize-e"} class="resize-handle resize-e" phx-hook="ResizeHandle" data-direction="e"></div>
      <div id={"#{@window.id}-resize-w"} class="resize-handle resize-w" phx-hook="ResizeHandle" data-direction="w"></div>
      <div id={"#{@window.id}-resize-ne"} class="resize-handle resize-ne" phx-hook="ResizeHandle" data-direction="ne"></div>
      <div id={"#{@window.id}-resize-nw"} class="resize-handle resize-nw" phx-hook="ResizeHandle" data-direction="nw"></div>
      <div id={"#{@window.id}-resize-se"} class="resize-handle resize-se" phx-hook="ResizeHandle" data-direction="se"></div>
      <div id={"#{@window.id}-resize-sw"} class="resize-handle resize-sw" phx-hook="ResizeHandle" data-direction="sw"></div>
    </div>
    """
  end

  # Helper functions
  defp get_app_icon(app) do
    case app do
      "file_manager" -> "📁"
      "terminal" -> "💻"
      "calculator" -> "🧮"
      "notepad" -> "📝"
      "media_player" -> "🎵"
      "media_preview" -> "🎬"
      "settings" -> "⚙️"
      "welcome" -> "👋"
      "text_editor" -> "📝"
      "browser" -> "🌐"
      _ -> "💻"
    end
  end
end