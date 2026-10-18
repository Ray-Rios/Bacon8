defmodule Bacon8Web.Components.Dropdown do
  @moduledoc """
  Reusable dropdown component for Phoenix LiveView.
  Can be used for navigation, chat channels, user settings, character management, etc.
  """
  
  use Phoenix.Component
  use Bacon8Web, :live_component
  
  @doc """
  Generic dropdown component with customizable trigger and content.
  
  ## Examples
  
      # User navigation dropdown
      <.live_component 
        module={Bacon8Web.Components.Dropdown}
        id="user-dropdown"
        trigger_class="flex items-center space-x-2 cursor-pointer"
        dropdown_class="absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg"
        position="bottom-right"
      >
        <:trigger>
          <img src={@current_user.avatar} class="w-8 h-8 rounded-full">
          <span>{@current_user.name}</span>
        </:trigger>
        <:content>
          <a href="/profile" class="block px-4 py-2 hover:bg-gray-100">Profile</a>
          <a href="/settings" class="block px-4 py-2 hover:bg-gray-100">Settings</a>
          <button phx-click="logout" class="block w-full text-left px-4 py-2 hover:bg-gray-100">Logout</button>
        </:content>
      </.live_component>
      
      # Chat channel selector
      <.live_component 
        module={Bacon8Web.Components.Dropdown}
        id="chat-channels"
        trigger_class="flex items-center space-x-1 px-3 py-2 bg-blue-600 text-white rounded"
        dropdown_class="absolute left-0 mt-2 w-64 bg-white rounded-md shadow-lg max-h-64 overflow-y-auto"
        position="bottom-left"
      >
        <:trigger>
          <span>General</span>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
          </svg>
        </:trigger>
        <:content>
          <button 
            phx-click="switch-channel" 
            phx-value-channel-id="1"
            class="block w-full text-left px-4 py-2 hover:bg-gray-100"
          >
            General (0)
          </button>
        </:content>
      </.live_component>
  """
  
  @impl true
  def mount(socket) do
    {:ok, assign(socket, :open, false)}
  end
  
  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative" id={"dropdown-#{@id}"}>
      <!-- Trigger Element -->
      <div 
        class={@trigger_class || "cursor-pointer"}
        phx-click="toggle-dropdown"
        phx-target={@myself}
      >
        <%= render_slot(@trigger) %>
      </div>
      
      <!-- Dropdown Content -->
      <div 
        class={[
          @dropdown_class || "absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg border border-gray-200 z-50",
          if(@open, do: "block", else: "hidden")
        ]}
        phx-click-away="close-dropdown"
        phx-target={@myself}
      >
        <%= render_slot(@content) %>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_event("toggle-dropdown", _params, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end
  
  @impl true
  def handle_event("close-dropdown", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end
  
  # Optional: Handle external events to close dropdown
  @impl true
  def handle_event("force-close", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end
end