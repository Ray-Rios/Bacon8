defmodule Bacon8Web.Components.Navigation do
  use Bacon8Web, :html
  import Bacon8Web.AvatarHelpers

  attr :current_user, :any, default: nil
  attr :id_prefix, :string, default: ""
  
  def navbar(assigns) do
    ~H"""
    <!-- Navigation Toggle Button -->
    <button id="nav-toggle" 
            class="fixed top-0 right-0 z-[60] glass-dark hover:bg-gray-700 text-white p-2 pr-2 shadow-lg transition-all duration-300"
            onclick="toggleNavbar()">
      <svg id="nav-toggle-icon" class="w-3 h-3 transition-transform duration-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7"></path>
      </svg>
    </button>

    <nav id="main-navbar" class="auth-glass-panel border-b border-gray-700 fixed top-0 left-0 z-50 w-full h-[30px] transition-transform duration-300 ease-in-out">
      <div class="px-4">
        <div class="flex top-8 justify-between items-center">
          <!-- Left side - Logo and main navigation -->
          <div class="flex items-center space-x-4 flex-1 min-w-0">
            <.link navigate={~p"/games"} class="text-xl font-bold text-white hover:text-blue-400 transition-colors duration-300 flex-shrink-0">
              Bacon<span class="rainbow-text">8</span>
            </.link>
            <div class="hidden lg:flex space-x-4 flex-1 justify-center">
              <%!-- Links from active plugins (BACON8.md §9), e.g. the store --%>
              <.link :for={item <- Bacon8.Plugins.nav_links(@current_user)} navigate={item.path} class="text-white hover:text-blue-400 transition-colors duration-300 text-sm">
                <Bacon8Web.Components.Gem.icon icon={item.icon} size={20} /> <%= item.label %>
                <span :if={Map.get(item, :badge)} class="ml-1 rounded-full bg-red-500 px-1.5 text-[10px] font-bold text-white"><%= item.badge %></span>
              </.link>
              <.link navigate={~p"/games"} class="text-white hover:text-blue-400 transition-colors duration-300 text-sm">
                🎮 Games
              </.link>
              <.link navigate={~p"/blog"} class="text-white hover:text-blue-400 transition-colors duration-300 text-sm">
                🚬 Blog
              </.link>
              <%!-- Admins land on the dashboard; GMs and editors on the part they may open (Bacon8.Permissions) --%>
              <%= if Bacon8.Permissions.staff?(@current_user) do %>
                <.link navigate={Bacon8.Permissions.home_path(@current_user)} class="text-orange-400 hover:text-orange-300 transition-colors duration-300 text-sm font-semibold">
                  ⚙️ Admin
                </.link>
              <% end %>
            </div>
          </div>
          
          <!-- Right side - User menu -->
          <div class="flex items-center space-x-2 flex-shrink-0" style="margin-right: 25px;">
            <%= if @current_user do %>
              <!-- User Avatar and Dropdown -->
              <.live_component 
                module={Bacon8Web.Components.Dropdown}
                id={"#{@id_prefix}user-dropdown"}
                trigger_class="flex items-center space-x-1 text-white hover:text-blue-400 transition-colors duration-300 min-w-0"
                dropdown_class="absolute right-0 mt-2 w-48 glass-menu rounded-md shadow-lg py-1 z-50"
              >
                <:trigger>
                  <%= avatar_tag(@current_user, size_class: "w-6 h-6 text-xs") %>
                  <span class="hidden sm:block text-xs truncate max-w-[80px]"><%= get_user_display_name(@current_user) %></span>
                  <svg class="w-3 h-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                  </svg>
                </:trigger>
                <:content>
                  <.link navigate={~p"/profile"} class="block px-4 py-2 text-sm text-gray-300 hover:bg-white/15 hover:text-white">
                    👤 Profile Settings
                  </.link>
                  <%= if @current_user.is_admin do %>
                    <hr class="border-white/20 my-1">
                    <.link navigate={~p"/admin"} class="block px-4 py-2 text-sm text-orange-300 hover:bg-white/15 hover:text-orange-200">
                      🏠 Admin Dashboard
                    </.link>
                    <.link navigate={~p"/admin/user-management"} class="block px-4 py-2 text-sm text-orange-300 hover:bg-white/15 hover:text-orange-200">
                      👥 User Management
                    </.link>
                    <.link navigate={~p"/admin/blog-management"} class="block px-4 py-2 text-sm text-orange-300 hover:bg-white/15 hover:text-orange-200">
                      📝 Blog Management
                    </.link>

                    <.link navigate={~p"/admin/api-toolbox"} class="block px-4 py-2 text-sm text-orange-300 hover:bg-white/15 hover:text-orange-200">
                      🧰 API Toolbox
                    </.link>
                  <% else %>
                    <%= if Bacon8.Permissions.can?(@current_user, :content) do %>
                      <hr class="border-white/20 my-1">
                      <.link navigate={~p"/admin/pages"} class="block px-4 py-2 text-sm text-orange-300 hover:bg-white/15 hover:text-orange-200">
                        📄 Pages
                      </.link>
                      <.link navigate={~p"/admin/blog-management"} class="block px-4 py-2 text-sm text-orange-300 hover:bg-white/15 hover:text-orange-200">
                        📝 Blog Management
                      </.link>
                    <% end %>
                  <% end %>
                  <hr class="border-white/20 my-1">
                  <.link navigate={~p"/auth/logout"} class="block px-4 py-2 text-sm text-red-300 hover:bg-white/15 hover:text-red-200">
                   🚪 Logout
                  </.link>
                </:content>
              </.live_component>
            <% else %>
              <!-- Login/Register buttons -->
              <.link navigate={~p"/login"} class="text-white hover:text-blue-400 transition-colors duration-300">
                Login
              </.link>
              <.link navigate={~p"/register"} class="bg-blue-600 hover:bg-blue-700 text-white rounded-sm px-2 transition-colors duration-300">
                Register
              </.link>
            <% end %>
          </div>
        </div>
      </div>
    </nav>

    <script>
      // Hide or show the navbar and taskbar. The state is a class on <html> (see app.css,
      // html.chrome-hidden), remembered for the visit: LiveView patches would undo inline
      // styles on the bars.
      function toggleNavbar() {
        const root = document.documentElement;
        const hidden = !root.classList.contains('chrome-hidden');
        root.classList.toggle('chrome-hidden', hidden);
        try { sessionStorage.setItem('bacon8:chrome-hidden', hidden ? '1' : '0'); } catch (e) {}
        // full-window pages (the 3D games) re-measure
        setTimeout(() => window.dispatchEvent(new Event('resize')), 320);
      }
      try {
        if (sessionStorage.getItem('bacon8:chrome-hidden') === '1') document.documentElement.classList.add('chrome-hidden');
      } catch (e) {}

      // Initialize navbar state
      document.addEventListener('DOMContentLoaded', function() {
        // Ensure content has proper spacing for navbar
        const pageContent = document.querySelector('.page-content');
        if (pageContent) pageContent.classList.remove('navbar-hidden');
        
        // Initialize padding/positioning for all responsive containers
        const responsiveContainers = document.querySelectorAll('[data-responsive-content]');
        responsiveContainers.forEach(container => {
          const isFixed = window.getComputedStyle(container).position === 'fixed';
          if (isFixed) {
            container.style.top = '30px';
            container.style.bottom = '35px';
            container.style.paddingTop = '';
            container.style.paddingBottom = '';
          } else {
            container.style.paddingTop = '30px';
            container.style.paddingBottom = '48px';
            container.style.top = '';
            container.style.bottom = '';
          }
        });
      });
    </script>
    """
  end

  defp get_user_display_name(user) do
    cond do
      is_map(user) && Map.has_key?(user, :name) && user.name -> user.name
      is_map(user) && Map.has_key?(user, "name") && user["name"] -> user["name"]
      is_map(user) && Map.has_key?(user, :email) && user.email -> 
        user.email |> String.split("@") |> List.first()
      is_map(user) && Map.has_key?(user, "email") && user["email"] -> 
        user["email"] |> String.split("@") |> List.first()
      true -> "User"
    end
  end
end