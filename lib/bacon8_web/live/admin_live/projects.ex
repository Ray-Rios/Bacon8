defmodule Bacon8Web.AdminLive.Projects do
  @moduledoc """
  Admin Projects LiveView - Full project management with tasks, events, and calendar integration.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Scheduler
  alias Bacon8.Scheduler.Task
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "scheduler:projects")
    end

    projects = Scheduler.list_projects()
    users = Bacon8.Accounts.list_users()

    {:ok, assign(socket,
      projects: projects,
      selected_project: nil,
      users: users,
      page_title: "Projects",
      show_task_form: false,
      task_changeset: Task.changeset(%Task{}, %{}),
      project_events: [],
      view_mode: "details",  # details, tasks, timeline, events
      scheduled_events: []
    )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = case params do
      %{"id" => id} ->
        project = Scheduler.get_project!(id)
        tasks = Scheduler.list_tasks_for_project(id)
        events = Scheduler.list_project_events(id)
        scheduled = list_scheduled_events_for_project(id)
        assign(socket, 
          selected_project: project, 
          project_tasks: tasks,
          project_events: events,
          scheduled_events: scheduled
        )
      _ ->
        assign(socket, selected_project: nil, project_tasks: [], project_events: [], scheduled_events: [])
    end
    {:noreply, socket}
  end

  defp list_scheduled_events_for_project(project_id) do
    Scheduler.list_scheduled_events()
    |> Enum.filter(fn e -> 
      e.trigger_project_id == project_id || e.target_project_id == project_id
    end)
  end

  @impl true
  def handle_event("select_project", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/admin/projects?id=#{id}")}
  end

  @impl true
  def handle_event("create_project", %{"name" => name}, socket) do
    case Scheduler.create_project(%{name: name}, socket.assigns.current_user.id) do
      {:ok, project} ->
        {:noreply, 
         socket
         |> assign(projects: Scheduler.list_projects())
         |> push_patch(to: "/admin/projects?id=#{project.id}")
         |> put_flash(:info, "Project created")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create project")}
    end
  end

  @impl true
  def handle_event("update_project", %{"project" => params}, socket) do
    project = socket.assigns.selected_project

    case Scheduler.update_project(project, params, socket.assigns.current_user.id) do
      {:ok, updated} ->
        projects = Scheduler.list_projects()
        events = Scheduler.list_project_events(updated.id)
        {:noreply, 
         socket
         |> assign(
           selected_project: Scheduler.get_project!(updated.id), 
           projects: projects,
           project_events: events
         )
         |> put_flash(:info, "Project updated")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update project")}
    end
  end

  @impl true
  def handle_event("delete_project", %{"id" => id}, socket) do
    project = Scheduler.get_project!(id)

    case Scheduler.delete_project(project) do
      {:ok, _} ->
        {:noreply, 
         socket
         |> assign(projects: Scheduler.list_projects(), selected_project: nil)
         |> push_patch(to: "/admin/projects")
         |> put_flash(:info, "Project deleted")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete project")}
    end
  end

  @impl true
  def handle_event("set_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, view_mode: view)}
  end

  # Task Management
  @impl true
  def handle_event("show_task_form", _params, socket) do
    changeset = Task.changeset(%Task{project_id: socket.assigns.selected_project.id}, %{})
    {:noreply, assign(socket, show_task_form: true, task_changeset: changeset, editing_task: nil)}
  end

  @impl true
  def handle_event("edit_task", %{"id" => id}, socket) do
    task = Scheduler.get_task!(id)
    changeset = Task.changeset(task, %{})
    {:noreply, assign(socket, show_task_form: true, task_changeset: changeset, editing_task: task)}
  end

  @impl true
  def handle_event("close_task_form", _params, socket) do
    {:noreply, assign(socket, show_task_form: false, editing_task: nil)}
  end

  @impl true
  def handle_event("validate_task", %{"task" => params}, socket) do
    task = socket.assigns[:editing_task] || %Task{}
    changeset = Task.changeset(task, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, task_changeset: changeset)}
  end

  @impl true
  def handle_event("save_task", %{"task" => params}, socket) do
    params = Map.put(params, "project_id", socket.assigns.selected_project.id)
    
    result = if socket.assigns[:editing_task] do
      Scheduler.update_task(socket.assigns.editing_task, params, socket.assigns.current_user.id)
    else
      Scheduler.create_task(params, socket.assigns.current_user.id)
    end

    case result do
      {:ok, _task} ->
        tasks = Scheduler.list_tasks_for_project(socket.assigns.selected_project.id)
        events = Scheduler.list_project_events(socket.assigns.selected_project.id)
        {:noreply, 
         socket
         |> assign(project_tasks: tasks, project_events: events, show_task_form: false, editing_task: nil)
         |> put_flash(:info, "Task saved")}
      {:error, changeset} ->
        {:noreply, assign(socket, task_changeset: changeset)}
    end
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Scheduler.get_task!(id)
    case Scheduler.delete_task(task) do
      {:ok, _} ->
        tasks = Scheduler.list_tasks_for_project(socket.assigns.selected_project.id)
        {:noreply, 
         socket
         |> assign(project_tasks: tasks)
         |> put_flash(:info, "Task deleted")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  @impl true
  def handle_event("update_task_status", %{"id" => id, "status" => status}, socket) do
    task = Scheduler.get_task!(id)
    case Scheduler.update_task(task, %{status: status}, socket.assigns.current_user.id) do
      {:ok, _} ->
        tasks = Scheduler.list_tasks_for_project(socket.assigns.selected_project.id)
        events = Scheduler.list_project_events(socket.assigns.selected_project.id)
        {:noreply, assign(socket, project_tasks: tasks, project_events: events)}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  @impl true
  def handle_info({:project_change, _project, _action}, socket) do
    projects = Scheduler.list_projects()
    {:noreply, assign(socket, projects: projects)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/projects">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-white">Projects</h1>
        <p class="mt-2 text-sm text-gray-400">Project management, tasks, and calendar integration</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
        <!-- Left Panel: Project List -->
        <div class="lg:col-span-1">
          <div class="dark-glass rounded-lg p-4 mb-4">
            <h3 class="text-lg text-white mb-3 flex items-center gap-2">
              <span>➕</span> Create Project
            </h3>
            <form phx-submit="create_project" class="space-y-2">
              <input 
                name="name" 
                placeholder="Project name" 
                class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700 focus:border-blue-500 focus:outline-none" 
              />
              <button type="submit" class="w-full bg-blue-600 hover:bg-blue-700 text-white px-3 py-2 rounded font-medium transition-colors">
                Create Project
              </button>
            </form>
          </div>

          <div class="dark-glass rounded-lg p-4">
            <h3 class="text-lg text-white mb-3 flex items-center gap-2">
              <span>📁</span> Projects
            </h3>
            <div class="space-y-2 max-h-[500px] overflow-y-auto">
              <%= for project <- @projects do %>
                <button 
                  phx-click="select_project" 
                  phx-value-id={project.id} 
                  class={"w-full text-left p-3 rounded-lg transition-colors " <> if(@selected_project && @selected_project.id == project.id, do: "bg-blue-600/30 border border-blue-500", else: "bg-gray-800/50 hover:bg-gray-700/50 border border-transparent")}
                >
                  <div class="font-medium text-white"><%= project.name %></div>
                  <div class="text-xs text-gray-400 flex items-center gap-2 mt-1">
                    <span class={"w-2 h-2 rounded-full " <> status_dot(project.status)}></span>
                    <span><%= project.status %></span>
                    <%= if project.owner do %>
                      <span>•</span>
                      <span><%= project.owner.email |> String.split("@") |> hd() %></span>
                    <% end %>
                  </div>
                </button>
              <% end %>
              
              <%= if Enum.empty?(@projects) do %>
                <div class="text-gray-400 text-center py-6">No projects yet</div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Right Panel: Project Details -->
        <div class="lg:col-span-3">
          <%= if @selected_project do %>
            <div class="dark-glass rounded-lg p-6">
              <!-- Project Header -->
              <div class="flex justify-between items-start mb-6">
                <div>
                  <h2 class="text-2xl font-semibold text-white"><%= @selected_project.name %></h2>
                  <p class="text-gray-400 mt-1"><%= @selected_project.description || "No description" %></p>
                </div>
                <div class="flex items-center gap-2">
                  <span class={"px-3 py-1 rounded-full text-sm font-medium " <> status_badge(@selected_project.status)}>
                    <%= @selected_project.status %>
                  </span>
                </div>
              </div>

              <!-- View Tabs -->
              <div class="flex gap-2 mb-6 border-b border-gray-700 pb-2">
                <button 
                  phx-click="set_view" phx-value-view="details"
                  class={"px-4 py-2 rounded-t font-medium transition-colors " <> if(@view_mode == "details", do: "bg-blue-600 text-white", else: "text-gray-400 hover:text-white")}
                >
                  Details
                </button>
                <button 
                  phx-click="set_view" phx-value-view="tasks"
                  class={"px-4 py-2 rounded-t font-medium transition-colors " <> if(@view_mode == "tasks", do: "bg-blue-600 text-white", else: "text-gray-400 hover:text-white")}
                >
                  Tasks (<%= length(@project_tasks || []) %>)
                </button>
                <button 
                  phx-click="set_view" phx-value-view="events"
                  class={"px-4 py-2 rounded-t font-medium transition-colors " <> if(@view_mode == "events", do: "bg-blue-600 text-white", else: "text-gray-400 hover:text-white")}
                >
                  Events (<%= length(@scheduled_events || []) %>)
                </button>
                <button 
                  phx-click="set_view" phx-value-view="automation"
                  class={"px-4 py-2 rounded-t font-medium transition-colors " <> if(@view_mode == "automation", do: "bg-blue-600 text-white", else: "text-gray-400 hover:text-white")}
                >
                  Automation
                </button>
              </div>

              <!-- Details View -->
              <%= if @view_mode == "details" do %>
                <form phx-submit="update_project" class="space-y-4">
                  <div>
                    <label class="block text-gray-300 text-sm mb-1">Description</label>
                    <textarea 
                      name="project[description]" 
                      placeholder="Project description" 
                      class="w-full bg-gray-800 text-gray-200 p-3 rounded border border-gray-700 focus:border-blue-500 focus:outline-none h-24"
                    ><%= @selected_project.description %></textarea>
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div>
                      <label class="block text-gray-300 text-sm mb-1">Owner</label>
                      <select name="project[owner_id]" class="w-full bg-gray-800 text-gray-200 rounded px-3 py-2 border border-gray-700">
                        <option value="">No owner</option>
                        <%= for user <- @users do %>
                          <option value={user.id} selected={@selected_project.owner_id == user.id}><%= user.email %></option>
                        <% end %>
                      </select>
                    </div>

                    <div>
                      <label class="block text-gray-300 text-sm mb-1">Status</label>
                      <select name="project[status]" class="w-full bg-gray-800 text-gray-200 rounded px-3 py-2 border border-gray-700">
                        <option value="active" selected={@selected_project.status == "active"}>Active</option>
                        <option value="pending" selected={@selected_project.status == "pending"}>Pending</option>
                        <option value="completed" selected={@selected_project.status == "completed"}>Completed</option>
                        <option value="archived" selected={@selected_project.status == "archived"}>Archived</option>
                      </select>
                    </div>

                    <div>
                      <label class="block text-gray-300 text-sm mb-1">Start Date</label>
                      <input 
                        type="datetime-local" 
                        name="project[start_date]"
                        value={format_datetime(@selected_project.start_date)}
                        class="w-full bg-gray-800 text-gray-200 rounded px-3 py-2 border border-gray-700"
                      />
                    </div>
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label class="block text-gray-300 text-sm mb-1">End Date</label>
                      <input 
                        type="datetime-local" 
                        name="project[end_date]"
                        value={format_datetime(@selected_project.end_date)}
                        class="w-full bg-gray-800 text-gray-200 rounded px-3 py-2 border border-gray-700"
                      />
                    </div>
                  </div>

                  <div class="flex gap-3 pt-4">
                    <button type="submit" class="bg-green-600 hover:bg-green-700 text-white px-6 py-2 rounded font-medium transition-colors">
                      Save Changes
                    </button>
                    <button 
                      type="button"
                      phx-click="delete_project" 
                      phx-value-id={@selected_project.id}
                      data-confirm="Delete this project? This cannot be undone."
                      class="bg-red-600 hover:bg-red-700 text-white px-6 py-2 rounded font-medium transition-colors"
                    >
                      Delete Project
                    </button>
                  </div>
                </form>
              <% end %>

              <!-- Tasks View -->
              <%= if @view_mode == "tasks" do %>
                <div class="mb-4">
                  <button phx-click="show_task_form" class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded flex items-center gap-2">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
                    </svg>
                    Add Task
                  </button>
                </div>

                <div class="space-y-3">
                  <%= for task <- @project_tasks || [] do %>
                    <div class="bg-gray-800/50 rounded-lg p-4 flex items-center justify-between">
                      <div class="flex items-center gap-4">
                        <select 
                          phx-change="update_task_status" 
                          phx-value-id={task.id}
                          name="status"
                          class={"w-8 h-8 rounded cursor-pointer " <> task_status_bg(task.status)}
                        >
                          <option value="todo" selected={task.status == "todo"}>⬜</option>
                          <option value="in_progress" selected={task.status == "in_progress"}>🔄</option>
                          <option value="completed" selected={task.status == "completed"}>✅</option>
                        </select>
                        <div>
                          <div class={"font-medium " <> if(task.status == "completed", do: "text-gray-500 line-through", else: "text-white")}>
                            <%= task.title %>
                          </div>
                          <%= if task.description do %>
                            <div class="text-sm text-gray-400"><%= String.slice(task.description, 0, 60) %></div>
                          <% end %>
                        </div>
                      </div>
                      <div class="flex items-center gap-2">
                        <%= if task.start_at do %>
                          <span class="text-xs text-gray-400"><%= Calendar.strftime(task.start_at, "%b %d") %></span>
                        <% end %>
                        <button phx-click="edit_task" phx-value-id={task.id} class="p-2 hover:bg-gray-700 rounded text-gray-400 hover:text-white">
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
                          </svg>
                        </button>
                        <button phx-click="delete_task" phx-value-id={task.id} data-confirm="Delete this task?" class="p-2 hover:bg-red-900/50 rounded text-gray-400 hover:text-red-400">
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                          </svg>
                        </button>
                      </div>
                    </div>
                  <% end %>
                  
                  <%= if Enum.empty?(@project_tasks || []) do %>
                    <div class="text-gray-400 text-center py-8">
                      No tasks yet. Click "Add Task" to create one.
                    </div>
                  <% end %>
                </div>
              <% end %>

              <!-- Events View -->
              <%= if @view_mode == "events" do %>
                <div class="space-y-4">
                  <div class="flex justify-between items-center mb-4">
                    <h4 class="text-white font-medium">Scheduled Events</h4>
                    <a href="/admin/scheduler" class="text-blue-400 hover:text-blue-300 text-sm">
                      Manage in Scheduler →
                    </a>
                  </div>
                  
                  <div class="space-y-3 max-h-96 overflow-y-auto">
                    <%= for event <- @scheduled_events || [] do %>
                      <div class="bg-gray-800/50 rounded-lg p-4">
                        <div class="flex items-center justify-between mb-2">
                          <div class="flex items-center gap-3">
                            <span class={"w-2 h-2 rounded-full " <> sched_status_color(event.status)}></span>
                            <span class="text-white font-medium"><%= event.title %></span>
                            <span class="text-xs px-2 py-0.5 rounded bg-gray-700 text-gray-300">
                              <%= event.event_type %>
                            </span>
                          </div>
                          <span class="text-xs text-gray-400">
                            <%= if event.trigger_project_id == @selected_project.id, do: "Triggered by", else: "Targets" %> this project
                          </span>
                        </div>
                        <%= if event.description do %>
                          <div class="text-sm text-gray-400 mt-2"><%= event.description %></div>
                        <% end %>
                        <%= if event.action_type do %>
                          <div class="text-sm text-gray-500 mt-2">
                            Action: <%= event.action_type %>
                          </div>
                        <% end %>
                        <%= if event.next_run_at do %>
                          <div class="text-xs text-blue-400 mt-2">
                            Next run: <%= Calendar.strftime(event.next_run_at, "%Y-%m-%d %H:%M") %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                    
                    <%= if Enum.empty?(@scheduled_events || []) do %>
                      <div class="text-gray-400 text-center py-8">
                        No scheduled events linked to this project.
                      </div>
                    <% end %>
                  </div>

                  <!-- Event History -->
                  <div class="mt-8">
                    <h4 class="text-white font-medium mb-3">Event History</h4>
                    <div class="space-y-2 max-h-64 overflow-y-auto">
                      <%= for event <- @project_events || [] do %>
                        <div class="bg-gray-900/50 rounded-lg p-3 flex items-start gap-3">
                          <div class={"w-2 h-2 rounded-full mt-1.5 " <> event_type_color(event.event_type)}></div>
                          <div class="flex-1">
                            <div class="text-sm text-white"><%= event.title %></div>
                            <div class="text-xs text-gray-400 mt-1">
                              <%= Calendar.strftime(event.occurred_at, "%Y-%m-%d %H:%M:%S") %>
                            </div>
                            <%= if event.description do %>
                              <div class="text-xs text-gray-500 mt-1"><%= event.description %></div>
                            <% end %>
                          </div>
                        </div>
                      <% end %>
                      
                      <%= if Enum.empty?(@project_events || []) do %>
                        <div class="text-gray-400 text-center py-4 text-sm">
                          No history events yet.
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>

              <!-- Automation View -->
              <%= if @view_mode == "automation" do %>
                <div class="space-y-4">
                  <div class="flex justify-between items-center">
                    <h4 class="text-white font-medium">Scheduled Events for this Project</h4>
                    <a href={"/admin/scheduler"} class="text-blue-400 hover:text-blue-300 text-sm">
                      Manage in Scheduler →
                    </a>
                  </div>
                  
                  <div class="space-y-3">
                    <%= for event <- @scheduled_events || [] do %>
                      <div class="bg-gray-800/50 rounded-lg p-4">
                        <div class="flex items-center justify-between">
                          <div class="flex items-center gap-3">
                            <span class={"w-2 h-2 rounded-full " <> sched_status_color(event.status)}></span>
                            <span class="text-white font-medium"><%= event.title %></span>
                            <span class="text-xs px-2 py-0.5 rounded bg-gray-700 text-gray-300">
                              <%= event.event_type %>
                            </span>
                          </div>
                          <span class="text-xs text-gray-400">
                            <%= if event.trigger_project_id == @selected_project.id, do: "Triggered by", else: "Targets" %> this project
                          </span>
                        </div>
                        <%= if event.action_type do %>
                          <div class="text-sm text-gray-400 mt-2 pl-5">
                            Action: <%= event.action_type %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                    
                    <%= if Enum.empty?(@scheduled_events || []) do %>
                      <div class="text-gray-400 text-center py-8">
                        <p>No automation events linked to this project.</p>
                        <a href="/admin/scheduler" class="text-blue-400 hover:text-blue-300 text-sm mt-2 inline-block">
                          Create one in Scheduler →
                        </a>
                      </div>
                    <% end %>
                  </div>

                  <div class="border-t border-gray-700 pt-4 mt-6">
                    <h5 class="text-white font-medium mb-3">Quick Actions</h5>
                    <div class="grid grid-cols-2 gap-3">
                      <a 
                        href={"/admin/scheduler?trigger_project=#{@selected_project.id}"}
                        class="p-3 bg-gray-800/50 rounded-lg hover:bg-gray-700/50 text-center"
                      >
                        <div class="text-2xl mb-1">⚡</div>
                        <div class="text-sm text-gray-300">Create Trigger Event</div>
                      </a>
                      <a 
                        href={"/admin/scheduler?target_project=#{@selected_project.id}"}
                        class="p-3 bg-gray-800/50 rounded-lg hover:bg-gray-700/50 text-center"
                      >
                        <div class="text-2xl mb-1">🎯</div>
                        <div class="text-sm text-gray-300">Create Target Event</div>
                      </a>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="dark-glass rounded-lg p-6 flex items-center justify-center h-96">
              <div class="text-center text-gray-400">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"></path>
                </svg>
                <p>Select a project to view details</p>
                <p class="text-sm mt-2">or create a new project</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Task Form Modal -->
      <%= if @show_task_form do %>
        <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div class="bg-gray-900 rounded-lg p-6 w-full max-w-lg border border-gray-700" phx-click-away="close_task_form">
            <div class="flex justify-between items-center mb-4">
              <h3 class="text-xl font-semibold text-white">
                <%= if @editing_task, do: "Edit Task", else: "New Task" %>
              </h3>
              <button phx-click="close_task_form" class="text-gray-400 hover:text-white">✕</button>
            </div>

            <.form for={@task_changeset} phx-change="validate_task" phx-submit="save_task" class="space-y-4">
              <div>
                <label class="block text-gray-300 text-sm mb-1">Title *</label>
                <input 
                  type="text"
                  name="task[title]"
                  value={Ecto.Changeset.get_field(@task_changeset, :title)}
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700 focus:border-blue-500 focus:outline-none"
                  placeholder="Task title"
                />
              </div>

              <div>
                <label class="block text-gray-300 text-sm mb-1">Description</label>
                <textarea 
                  name="task[description]"
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700 focus:border-blue-500 focus:outline-none h-20"
                  placeholder="Task description"
                ><%= Ecto.Changeset.get_field(@task_changeset, :description) %></textarea>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-gray-300 text-sm mb-1">Status</label>
                  <select name="task[status]" class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700">
                    <option value="todo" selected={Ecto.Changeset.get_field(@task_changeset, :status) == "todo"}>To Do</option>
                    <option value="in_progress" selected={Ecto.Changeset.get_field(@task_changeset, :status) == "in_progress"}>In Progress</option>
                    <option value="completed" selected={Ecto.Changeset.get_field(@task_changeset, :status) == "completed"}>Completed</option>
                  </select>
                </div>

                <div>
                  <label class="block text-gray-300 text-sm mb-1">Assignee</label>
                  <select name="task[assignee_id]" class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700">
                    <option value="">Unassigned</option>
                    <%= for user <- @users do %>
                      <option value={user.id} selected={Ecto.Changeset.get_field(@task_changeset, :assignee_id) == user.id}>
                        <%= user.email %>
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-gray-300 text-sm mb-1">Start Date</label>
                  <input 
                    type="datetime-local"
                    name="task[start_at]"
                    value={format_datetime(Ecto.Changeset.get_field(@task_changeset, :start_at))}
                    class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                  />
                </div>

                <div>
                  <label class="block text-gray-300 text-sm mb-1">End Date</label>
                  <input 
                    type="datetime-local"
                    name="task[end_at]"
                    value={format_datetime(Ecto.Changeset.get_field(@task_changeset, :end_at))}
                    class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                  />
                </div>
              </div>

              <div class="flex justify-end gap-3 pt-4">
                <button type="button" phx-click="close_task_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded">
                  Cancel
                </button>
                <button type="submit" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded">
                  <%= if @editing_task, do: "Save Task", else: "Create Task" %>
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </AdminSidebar.admin_layout>
    """
  end

  # Helper functions
  defp status_dot(status) do
    case status do
      "active" -> "bg-green-500"
      "pending" -> "bg-yellow-500"
      "completed" -> "bg-blue-500"
      "archived" -> "bg-gray-500"
      _ -> "bg-gray-500"
    end
  end

  defp status_badge(status) do
    case status do
      "active" -> "bg-green-600/30 text-green-400"
      "pending" -> "bg-yellow-600/30 text-yellow-400"
      "completed" -> "bg-blue-600/30 text-blue-400"
      "archived" -> "bg-gray-600/30 text-gray-400"
      _ -> "bg-gray-600/30 text-gray-400"
    end
  end

  defp task_status_bg(status) do
    case status do
      "todo" -> "bg-gray-600"
      "in_progress" -> "bg-blue-600"
      "completed" -> "bg-green-600"
      _ -> "bg-gray-600"
    end
  end

  defp event_type_color(type) do
    case type do
      "project_created" -> "bg-green-500"
      "project_started" -> "bg-blue-500"
      "project_completed" -> "bg-purple-500"
      "project_archived" -> "bg-gray-500"
      "task_created" -> "bg-cyan-500"
      "task_completed" -> "bg-green-400"
      _ -> "bg-gray-500"
    end
  end

  defp sched_status_color(status) do
    case status do
      "active" -> "bg-green-500"
      "paused" -> "bg-yellow-500"
      "completed" -> "bg-blue-500"
      "failed" -> "bg-red-500"
      _ -> "bg-gray-500"
    end
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end
  defp format_datetime(_), do: ""
end
