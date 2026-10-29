defmodule Bacon8Web.Components.AdminSidebar do
  @moduledoc """
  Shared admin sidebar component with drag-resize functionality.
  Used across all /admin pages.
  """
  use Phoenix.Component
  use Bacon8Web, :verified_routes

  @doc """
  Renders the admin sidebar with navigation links.
  
  ## Attributes
  
    * `:current_path` - The current URL path to highlight active nav item
  """
  attr :current_path, :string, default: "/admin"
  attr :current_user, :map, default: nil, doc: "who is looking; nil is taken as an admin (those pages are admin-only anyway)"

  def admin_sidebar(assigns) do
    # Staff roles (Bacon8.Permissions) see only the links to the areas they may open.
    assigns = assign(assigns, :full, is_nil(assigns.current_user) or Bacon8.Permissions.admin?(assigns.current_user))

    ~H"""
    <div
      id="admin-sidebar"
      phx-hook="AdminSidebarResizer"
      phx-update="ignore"
      class="dark-glass border-r border-cyan-500/30 flex flex-col flex-none overflow-hidden z-40 relative h-full"
    >
      <div class="flex-1 overflow-y-auto p-4 overflow-x-hidden sidebar-content">
        <!-- Dashboard Section -->
        <div :if={@full} class="mb-6">
          <.sidebar_link
            href="/admin"
            icon="📊"
            label="Dashboard"
            active={@current_path == "/admin"}
          />
        </div>
        
        <!-- Users Section -->
        <div :if={@full} class="mb-6">
          <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 sidebar-section-header">
            Users
          </h2>
          <.sidebar_link
            href="/admin/user-management"
            icon="👥"
            label="User Management"
            active={String.starts_with?(@current_path, "/admin/user-management")}
          />
        </div>
        
        <!-- Content Section -->
        <div class="mb-6">
          <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 sidebar-section-header">
            Content
          </h2>
          <.sidebar_link
            href="/admin/blog-management"
            icon="📝"
            label="Blog Posts"
            active={String.starts_with?(@current_path, "/admin/blog-management")}
          />
          <.sidebar_link
            href="/admin/pages"
            icon="📄"
            label="Pages"
            active={String.starts_with?(@current_path, "/admin/pages")}
          />
          <.sidebar_link
            href="/admin/comments"
            icon="💬"
            label="Comments"
            active={String.starts_with?(@current_path, "/admin/comments")}
          />
          <.sidebar_link
            :if={@full}
            href="/admin/uploads"
            icon="📤"
            label="Uploads"
            active={String.starts_with?(@current_path, "/admin/uploads")}
          />
        </div>
        
        <!-- Tools Section -->
        <div :if={@full} class="mb-6">
          <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 sidebar-section-header">
            Tools
          </h2>
          <.sidebar_link
            href="/admin/projects"
            icon="🗂️"
            label="Projects"
            active={String.starts_with?(@current_path, "/admin/projects")}
          />
          <.sidebar_link
            href="/admin/scheduler"
            icon="⏰"
            label="Scheduler"
            active={String.starts_with?(@current_path, "/admin/scheduler")}
          />
        </div>
        
        <!-- Games Section -->
        <div :if={@full} class="mb-6">
          <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 sidebar-section-header">
            Games
          </h2>
          <%!-- Admin pages contributed by active plugins (BACON8.md §9) --%>
          <%= for item <- Bacon8.Plugins.admin_nav() do %>
            <.sidebar_link
              href={item.path}
              icon={item.icon}
              label={item.label}
              active={String.starts_with?(@current_path, item.path)}
            />
          <% end %>
        </div>

        <!-- Tools Section -->
        <div :if={@full} class="mb-6">
          <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 sidebar-section-header">
            Tools
          </h2>
          <.sidebar_link
            href="/admin/plugins"
            icon="🧩"
            label="Plugins"
            active={String.starts_with?(@current_path, "/admin/plugins")}
          />
          <.sidebar_link
            href="/admin/security"
            icon="🛡️"
            label="Security"
            active={String.starts_with?(@current_path, "/admin/security")}
          />
          <.sidebar_link
            href="/admin/audit"
            icon="📜"
            label="Audit log"
            active={String.starts_with?(@current_path, "/admin/audit")}
          />
          <.sidebar_link
            href="/admin/emails"
            icon="📧"
            label="Email Logs"
            active={String.starts_with?(@current_path, "/admin/emails")}
          />
          <.sidebar_link
            href="/admin/sql"
            icon="🗄️"
            label="SQL Console"
            active={String.starts_with?(@current_path, "/admin/sql")}
          />
          <.sidebar_link
            href="/admin/api-toolbox"
            icon="🔧"
            label="API Toolbox"
            active={String.starts_with?(@current_path, "/admin/api-toolbox")}
          />
        </div>
      </div>
      
      <!-- Resize Handle -->
      <div class="resize-handle absolute top-0 right-0 w-2 h-full cursor-col-resize hover:bg-blue-500/50 transition-colors z-20 flex items-center justify-center">
        <div class="w-1 h-8 bg-gray-400/50 rounded-full"></div>
      </div>
    </div>
    
    <!-- Collapsed sidebar indicator/handle -->
    <div 
      id="admin-sidebar-collapsed-handle"
      phx-update="ignore"
      class="hidden w-1 h-full bg-gray-600/30 hover:bg-blue-500/50 cursor-pointer flex-shrink-0 transition-colors"
      title="Click to expand sidebar"
    ></div>
    """
  end

  @doc """
  Renders a sidebar navigation link.
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def sidebar_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center px-3 py-2 rounded-lg text-sm transition-colors mb-1 sidebar-link",
        if(@active,
          do: "bg-blue-600/30 text-blue-300 border border-blue-500/30",
          else: "text-gray-300 hover:bg-gray-700/50 hover:text-white"
        )
      ]}
    >
      <span class="text-lg mr-3 sidebar-icon flex-shrink-0"><Bacon8Web.Components.Gem.icon icon={@icon} size={20} /></span>
      <span class="sidebar-label truncate"><%= @label %></span>
    </.link>
    """
  end

  @doc """
  Wraps admin page content with the sidebar layout.
  Provides consistent layout across all admin pages.
  """
  attr :current_path, :string, default: "/admin"
  attr :current_user, :map, default: nil
  slot :inner_block, required: true

  def admin_layout(assigns) do
    ~H"""
    <Bacon8Web.Components.PageContainer.fullscreen_container>
      <div class="flex h-full relative z-10">
        <.admin_sidebar current_path={@current_path} current_user={@current_user} />
        
        <!-- Main Content. min-w-0 lets it shrink to the screen; anything wider (a table)
             scrolls inside it (phones, 2026-10-29). -->
        <main id="admin-main-content" class="flex-1 min-w-0 overflow-y-auto overflow-x-auto p-3 sm:p-6">
          <%!-- On a phone the sidebar is a drawer: this opens it (AdminSidebarResizer, mobile.css) --%>
          <button type="button" id="admin-menu-toggle" class="admin-menu-toggle" aria-controls="admin-sidebar" aria-expanded="false">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" /></svg>
            Admin menu
          </button>
          <%= render_slot(@inner_block) %>
        </main>
      </div>
    </Bacon8Web.Components.PageContainer.fullscreen_container>
    """
  end
end
