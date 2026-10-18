defmodule Bacon8Web.Components.PageContainer do
  @moduledoc """
  Reusable page container component that handles responsive layout
  between navbar and taskbar across all pages.
  """
  use Phoenix.Component

  @doc """
  Main page container that automatically adjusts to navbar/taskbar state.
  
  ## Attributes
  - `class` - Additional CSS classes (default: "")
  - `max_width` - Max width constraint (default: "max-w-[90%]")
  - `glass` - Apply glass theme (default: true)
  - `center` - Center content horizontally (default: true)
  
  ## Slots
  - `inner_block` - Page content
  """
  attr :class, :string, default: ""
  attr :max_width, :string, default: "max-w-[90%]"
  attr :glass, :boolean, default: true
  attr :center, :boolean, default: true
  slot :inner_block, required: true

  def page_container(assigns) do
    ~H"""
    <div 
      data-responsive-content 
      class={[
        "min-h-screen w-full transition-all duration-300",
        @class
      ]} 
      style="padding-top: 30px; padding-bottom: 48px;"
    >
      <div class={[
        "relative z-10",
        if(@center, do: "mx-auto", else: ""),
        if(@max_width != "", do: @max_width, else: ""),
        "px-4 py-8"
      ]}>
        <div :if={@glass} class="auth-glass-panel p-8 rounded-xl">
          <%= render_slot(@inner_block) %>
        </div>
        <div :if={!@glass}>
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Full-screen container for pages like forum that need complete screen coverage.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def fullscreen_container(assigns) do
    ~H"""
    <script>document.documentElement.classList.add('no-scroll');document.body.classList.add('no-scroll');</script>
    <div 
      data-responsive-content 
      phx-hook="FullscreenContainer"
      id="fullscreen-container"
      class={["fixed inset-0 flex flex-col overflow-hidden transition-all duration-300", @class]} 
      style="top: 30px; bottom: 35px;"
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Overlay container for home page and special layouts with absolute positioning.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def overlay_container(assigns) do
    ~H"""
    <div class={["fixed inset-0 z-10 pointer-events-none flex items-center justify-center", @class]}>
      <div class="pointer-events-auto">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end
