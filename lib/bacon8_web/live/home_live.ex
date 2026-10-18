defmodule Bacon8Web.HomeLive do
  use Bacon8Web, :live_view

  # Note: on_mount :default is handled by router's live_session

  def mount(_params, _session, socket) do
    # If user is logged in and has a cached location, redirect there
    # Otherwise redirect to desktop
    if socket.assigns.current_user do
      # Check if user has a cached location (future feature)
      # For now, always redirect to desktop
      {:ok, push_navigate(socket, to: ~p"/games")}
    else
      # Ensure we explicitly set that user is not authenticated
      # This helps prevent race conditions with hook elements
      {:ok, assign(socket, page_title: "Welcome", user_authenticated: false, will_redirect: false)}
    end
  end

  def render(assigns) do
    ~H"""
    <!-- Content Overlay - Galaxy background now handled by main layout -->
    <div class="fixed inset-0 z-10 pointer-events-none flex items-center justify-center">
        <div class="pointer-events-auto text-center text-white px-4">
            <!-- Welcome Section with Terminal Typewriter Effect -->
              <div class="relative z-20">
                <!-- Terminal-style Welcome Text -->
                <%= if is_nil(@current_user) do %>
                  <!-- Terminal Typewriter Effect -->
                  <div id="terminal-typewriter" 
                    phx-hook="TerminalTypewriter"
                    phx-update="ignore"
                    class="mb-8">
                    <div class="text-green-400">
                      <span class="typewriter-text font-sad-machine" data-text="IT'S A SECRET TO EVERYBODY."></span>
                      <span class="typewriter-cursor">_</span>
                    </div>
                  </div>
                <% end %>
                
                <!-- Main Welcome Content (only show for non-authenticated users) -->
                <%= if is_nil(@current_user) do %>
                <h1 class="text-4xl md:text-5xl font-bold mb-6 animate-pulse">
                  Welcome to Bacon8.net
                </h1>
                <p class="text-xl mb-8 opacity-80">
                  Fork our projekt -> 
                  <a href="https://github.com/Ray-Rios/Bacon8" target="_blank" rel="noopener noreferrer" class="inline-block ml-2 hover:scale-115 transition-transform duration-200">
                    <svg class="w-6 h-6 fill-current opacity-80 hover:opacity-100" viewBox="0 0 24 24">
                      <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                    </svg>
                  </a>
                </p>
                
                <!-- Action Buttons -->
                <div class="flex flex-wrap gap-4 justify-center">
                  <.link navigate={~p"/register"} class="bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 text-white px-8 py-3 rounded-lg text-lg transition-all duration-300 ease-in-out transform hover:scale-105 whitespace-nowrap">
                    Create Account
                  </.link>
                  <.link navigate={~p"/login"} class="border-2 border-white text-white hover:bg-white hover:text-black px-8 py-3 rounded-lg text-lg transition-all duration-300 ease-in-out whitespace-nowrap">
                    Sign In
                  </.link>
                </div>
                <% end %>
              </div>
        </div>
      </div>
    """
  end
end