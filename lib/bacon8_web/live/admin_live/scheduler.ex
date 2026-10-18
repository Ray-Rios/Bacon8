defmodule Bacon8Web.AdminLive.Scheduler do
  @moduledoc """
  Admin Scheduler LiveView - Manage scheduled events, cron jobs, webhooks, and automations.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Scheduler
  alias Bacon8.Scheduler.ScheduledEvent
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "scheduler:events")
    end

    events = Scheduler.list_scheduled_events()
    projects = Scheduler.list_projects()

    {:ok, assign(socket,
      events: events,
      projects: projects,
      selected_event: nil,
      event_runs: [],
      show_form: false,
      form_mode: :create,
      changeset: ScheduledEvent.changeset(%ScheduledEvent{}, %{}),
      filter_status: "all",
      filter_type: "all",
      page_title: "Scheduler"
    )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Only update event-related assigns, preserve form state
    socket = case params do
      %{"id" => id} ->
        event = Scheduler.get_scheduled_event!(id)
        runs = Scheduler.list_event_runs(id)
        assign(socket, selected_event: event, event_runs: runs)
      _ ->
        # Don't reset selected_event if we already have one and no id param
        # This preserves the state when showing forms
        if Map.has_key?(socket.assigns, :selected_event) do
          socket
        else
          assign(socket, selected_event: nil, event_runs: [])
        end
    end
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_event", _params, socket) do
    changeset = ScheduledEvent.changeset(%ScheduledEvent{}, %{})
    {:noreply, assign(socket, show_form: true, form_mode: :create, changeset: changeset)}
  end

  @impl true
  def handle_event("edit_event", %{"id" => id}, socket) do
    event = Scheduler.get_scheduled_event!(id)
    changeset = ScheduledEvent.changeset(event, %{})
    {:noreply, assign(socket, show_form: true, form_mode: :edit, changeset: changeset, selected_event: event)}
  end

  @impl true
  def handle_event("close_form", _params, socket) do
    {:noreply, assign(socket, show_form: false)}
  end

  @impl true
  def handle_event("validate", %{"scheduled_event" => params}, socket) do
    event = if socket.assigns.form_mode == :edit, do: socket.assigns.selected_event, else: %ScheduledEvent{}
    changeset = ScheduledEvent.changeset(event, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("save", %{"scheduled_event" => params}, socket) do
    params = Map.put(params, "created_by_id", socket.assigns.current_user.id)
    
    result = case socket.assigns.form_mode do
      :create -> Scheduler.create_scheduled_event(params)
      :edit -> Scheduler.update_scheduled_event(socket.assigns.selected_event, params)
    end

    case result do
      {:ok, event} ->
        events = Scheduler.list_scheduled_events()
        {:noreply, 
         socket
         |> assign(events: events, show_form: false, selected_event: event)
         |> put_flash(:info, "Event #{if socket.assigns.form_mode == :create, do: "created", else: "updated"} successfully")}
      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("delete_event", %{"id" => id}, socket) do
    event = Scheduler.get_scheduled_event!(id)
    case Scheduler.delete_scheduled_event(event) do
      {:ok, _} ->
        events = Scheduler.list_scheduled_events()
        {:noreply, 
         socket
         |> assign(events: events, selected_event: nil)
         |> put_flash(:info, "Event deleted")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete event")}
    end
  end

  @impl true
  def handle_event("pause_event", %{"id" => id}, socket) do
    event = Scheduler.get_scheduled_event!(id)
    case Scheduler.pause_scheduled_event(event) do
      {:ok, updated} ->
        events = Scheduler.list_scheduled_events()
        {:noreply, assign(socket, events: events, selected_event: updated)}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to pause event")}
    end
  end

  @impl true
  def handle_event("resume_event", %{"id" => id}, socket) do
    event = Scheduler.get_scheduled_event!(id)
    case Scheduler.resume_scheduled_event(event) do
      {:ok, updated} ->
        events = Scheduler.list_scheduled_events()
        {:noreply, assign(socket, events: events, selected_event: updated)}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resume event")}
    end
  end

  @impl true
  def handle_event("run_now", %{"id" => id}, socket) do
    event = Scheduler.get_scheduled_event!(id)
    case Scheduler.execute_scheduled_event(event) do
      {:ok, result} ->
        runs = Scheduler.list_event_runs(id)
        {:noreply, 
         socket
         |> assign(event_runs: runs)
         |> put_flash(:info, "Event executed successfully: #{inspect(result)}")}
      {:error, error} ->
        runs = Scheduler.list_event_runs(id)
        {:noreply, 
         socket
         |> assign(event_runs: runs)
         |> put_flash(:error, "Event execution failed: #{error}")}
    end
  end

  @impl true
  def handle_event("select_event", %{"id" => id}, socket) do
    event = Scheduler.get_scheduled_event!(id)
    runs = Scheduler.list_event_runs(id)
    {:noreply, assign(socket, selected_event: event, event_runs: runs)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    status = Map.get(params, "status", socket.assigns.filter_status)
    type = Map.get(params, "type", socket.assigns.filter_type)
    {:noreply, assign(socket, filter_status: status, filter_type: type)}
  end

  defp filtered_events(events, status, type) do
    events
    |> Enum.filter(fn e -> status == "all" || e.status == status end)
    |> Enum.filter(fn e -> type == "all" || e.event_type == type end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/scheduler">
      <div class="mb-8 flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold text-white">Scheduler</h1>
          <p class="mt-2 text-sm text-gray-400">Manage scheduled events, cron jobs, and automations</p>
        </div>
        <button type="button" phx-click="new_event" class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg flex items-center gap-2">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
          </svg>
          New Event
        </button>
      </div>

      <!-- Filters -->
      <div class="mb-6 flex gap-4">
        <select phx-change="filter" name="status" class="bg-gray-800 text-gray-200 rounded px-3 py-2 border border-gray-700">
          <option value="all" selected={@filter_status == "all"}>All Status</option>
          <option value="active" selected={@filter_status == "active"}>Active</option>
          <option value="paused" selected={@filter_status == "paused"}>Paused</option>
          <option value="completed" selected={@filter_status == "completed"}>Completed</option>
          <option value="failed" selected={@filter_status == "failed"}>Failed</option>
        </select>
        <select phx-change="filter" name="type" class="bg-gray-800 text-gray-200 rounded px-3 py-2 border border-gray-700">
          <option value="all" selected={@filter_type == "all"}>All Types</option>
          <option value="one_time" selected={@filter_type == "one_time"}>One-time</option>
          <option value="recurring" selected={@filter_type == "recurring"}>Recurring</option>
          <option value="webhook" selected={@filter_type == "webhook"}>Webhook</option>
          <option value="project_trigger" selected={@filter_type == "project_trigger"}>Project Trigger</option>
        </select>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Events List -->
        <div class="lg:col-span-1">
          <div class="dark-glass rounded-lg p-4">
            <h3 class="text-lg text-white mb-4 flex items-center gap-2">
              <span>📅</span> Scheduled Events
            </h3>
            
            <div class="space-y-2 max-h-[600px] overflow-y-auto">
              <%= for event <- filtered_events(@events, @filter_status, @filter_type) do %>
                <button 
                  phx-click="select_event" 
                  phx-value-id={event.id} 
                  class={"w-full text-left p-3 rounded-lg transition-colors " <> if(@selected_event && @selected_event.id == event.id, do: "bg-blue-600/30 border border-blue-500", else: "bg-gray-800/50 hover:bg-gray-700/50 border border-transparent")}
                >
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <span class={"w-2 h-2 rounded-full " <> status_color(event.status)}></span>
                      <span class="text-white font-medium truncate"><%= event.title %></span>
                    </div>
                    <span class={"text-xs px-2 py-0.5 rounded " <> type_badge(event.event_type)}>
                      <%= event.event_type %>
                    </span>
                  </div>
                  <div class="text-xs text-gray-400 mt-1 pl-4">
                    <%= if event.next_run_at do %>
                      Next: <%= Calendar.strftime(event.next_run_at, "%b %d, %H:%M") %>
                    <% else %>
                      <%= if event.event_type == "webhook", do: "Webhook triggered", else: "Not scheduled" %>
                    <% end %>
                  </div>
                </button>
              <% end %>
              
              <%= if Enum.empty?(filtered_events(@events, @filter_status, @filter_type)) do %>
                <div class="text-gray-400 text-center py-8">
                  No scheduled events found
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Event Details -->
        <div class="lg:col-span-2">
          <%= if @selected_event do %>
            <div class="dark-glass rounded-lg p-6">
              <div class="flex justify-between items-start mb-6">
                <div>
                  <h2 class="text-2xl font-semibold text-white"><%= @selected_event.title %></h2>
                  <p class="text-gray-400 mt-1"><%= @selected_event.description || "No description" %></p>
                </div>
                <div class="flex gap-2">
                  <button phx-click="edit_event" phx-value-id={@selected_event.id} class="p-2 bg-gray-700 hover:bg-gray-600 rounded text-gray-300">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
                    </svg>
                  </button>
                  <%= if @selected_event.status == "active" do %>
                    <button phx-click="pause_event" phx-value-id={@selected_event.id} class="p-2 bg-yellow-600 hover:bg-yellow-700 rounded text-white" title="Pause">
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                      </svg>
                    </button>
                  <% else %>
                    <button phx-click="resume_event" phx-value-id={@selected_event.id} class="p-2 bg-green-600 hover:bg-green-700 rounded text-white" title="Resume">
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"></path>
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                      </svg>
                    </button>
                  <% end %>
                  <button phx-click="run_now" phx-value-id={@selected_event.id} class="p-2 bg-blue-600 hover:bg-blue-700 rounded text-white" title="Run Now">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
                    </svg>
                  </button>
                  <button phx-click="delete_event" phx-value-id={@selected_event.id} data-confirm="Delete this event?" class="p-2 bg-red-600 hover:bg-red-700 rounded text-white">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                    </svg>
                  </button>
                </div>
              </div>

              <!-- Event Info Grid -->
              <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <div class="bg-gray-800/50 rounded-lg p-3">
                  <div class="text-xs text-gray-400">Status</div>
                  <div class={"text-lg font-medium " <> status_text_color(@selected_event.status)}><%= @selected_event.status %></div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3">
                  <div class="text-xs text-gray-400">Type</div>
                  <div class="text-lg font-medium text-white"><%= @selected_event.event_type %></div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3">
                  <div class="text-xs text-gray-400">Run Count</div>
                  <div class="text-lg font-medium text-white"><%= @selected_event.run_count %><%= if @selected_event.max_runs, do: " / #{@selected_event.max_runs}" %></div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3">
                  <div class="text-xs text-gray-400">Action</div>
                  <div class="text-lg font-medium text-white"><%= @selected_event.action_type || "—" %></div>
                </div>
              </div>

              <!-- Scheduling Info -->
              <div class="bg-gray-800/30 rounded-lg p-4 mb-6">
                <h4 class="text-white font-medium mb-3">Scheduling</h4>
                <div class="grid grid-cols-2 gap-4 text-sm">
                  <%= if @selected_event.scheduled_at do %>
                    <div>
                      <span class="text-gray-400">Scheduled At:</span>
                      <span class="text-white ml-2"><%= Calendar.strftime(@selected_event.scheduled_at, "%Y-%m-%d %H:%M:%S UTC") %></span>
                    </div>
                  <% end %>
                  <%= if @selected_event.cron_expression do %>
                    <div>
                      <span class="text-gray-400">Cron:</span>
                      <code class="text-green-400 ml-2 bg-gray-900 px-2 py-0.5 rounded"><%= @selected_event.cron_expression %></code>
                    </div>
                  <% end %>
                  <%= if @selected_event.next_run_at do %>
                    <div>
                      <span class="text-gray-400">Next Run:</span>
                      <span class="text-white ml-2"><%= Calendar.strftime(@selected_event.next_run_at, "%Y-%m-%d %H:%M:%S UTC") %></span>
                    </div>
                  <% end %>
                  <%= if @selected_event.last_run_at do %>
                    <div>
                      <span class="text-gray-400">Last Run:</span>
                      <span class="text-white ml-2"><%= Calendar.strftime(@selected_event.last_run_at, "%Y-%m-%d %H:%M:%S UTC") %></span>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Webhook Info -->
              <%= if @selected_event.event_type == "webhook" && @selected_event.webhook_secret do %>
                <div class="bg-gray-800/30 rounded-lg p-4 mb-6">
                  <h4 class="text-white font-medium mb-3">Webhook</h4>
                  <div class="text-sm">
                    <div class="text-gray-400 mb-1">Trigger URL:</div>
                    <code class="text-blue-400 bg-gray-900 px-3 py-2 rounded block break-all">
                      POST /api/webhooks/scheduler/<%= @selected_event.webhook_secret %>
                    </code>
                  </div>
                </div>
              <% end %>

              <!-- Action Config -->
              <%= if @selected_event.action_config && map_size(@selected_event.action_config) > 0 do %>
                <div class="bg-gray-800/30 rounded-lg p-4 mb-6">
                  <h4 class="text-white font-medium mb-3">Action Configuration</h4>
                  <pre class="text-sm text-gray-300 bg-gray-900 rounded p-3 overflow-x-auto"><%= Jason.encode!(@selected_event.action_config, pretty: true) %></pre>
                </div>
              <% end %>

              <!-- Execution History -->
              <div class="bg-gray-800/30 rounded-lg p-4">
                <h4 class="text-white font-medium mb-3">Execution History</h4>
                <div class="space-y-2 max-h-64 overflow-y-auto">
                  <%= for run <- @event_runs || [] do %>
                    <div class={"flex items-center justify-between p-2 rounded " <> run_bg(run.status)}>
                      <div class="flex items-center gap-3">
                        <span class={"w-2 h-2 rounded-full " <> run_status_color(run.status)}></span>
                        <span class="text-gray-300 text-sm"><%= Calendar.strftime(run.started_at, "%Y-%m-%d %H:%M:%S") %></span>
                      </div>
                      <div class="flex items-center gap-4">
                        <%= if run.duration_ms do %>
                          <span class="text-gray-400 text-xs"><%= run.duration_ms %>ms</span>
                        <% end %>
                        <span class={"text-xs px-2 py-0.5 rounded " <> run_status_badge(run.status)}><%= run.status %></span>
                      </div>
                    </div>
                  <% end %>
                  <%= if Enum.empty?(@event_runs || []) do %>
                    <div class="text-gray-400 text-center py-4">No execution history</div>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <div class="dark-glass rounded-lg p-6 flex items-center justify-center h-96">
              <div class="text-center text-gray-400">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p>Select an event to view details</p>
                <p class="text-sm mt-2">or create a new scheduled event</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Create/Edit Form Modal -->
      <%= if @show_form do %>
        <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div class="bg-gray-900 rounded-lg p-6 w-full max-w-2xl max-h-[90vh] overflow-y-auto border border-gray-700" phx-click-away="close_form" phx-window-keydown="close_form" phx-key="Escape">
            <div class="flex justify-between items-center mb-6">
              <h3 class="text-xl font-semibold text-white">
                <%= if @form_mode == :create, do: "Create Scheduled Event", else: "Edit Event" %>
              </h3>
              <button phx-click="close_form" class="text-gray-400 hover:text-white">
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>

            <.form for={@changeset} phx-change="validate" phx-submit="save" class="space-y-4">
              <div>
                <label class="block text-gray-300 text-sm mb-1">Title *</label>
                <input 
                  type="text" 
                  name="scheduled_event[title]" 
                  value={Ecto.Changeset.get_field(@changeset, :title)}
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700 focus:border-blue-500 focus:outline-none"
                  placeholder="Event title"
                />
              </div>

              <div>
                <label class="block text-gray-300 text-sm mb-1">Description</label>
                <textarea 
                  name="scheduled_event[description]"
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700 focus:border-blue-500 focus:outline-none h-20"
                  placeholder="Event description"
                ><%= Ecto.Changeset.get_field(@changeset, :description) %></textarea>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-gray-300 text-sm mb-1">Event Type *</label>
                  <select 
                    name="scheduled_event[event_type]"
                    class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                  >
                    <%= for type <- ScheduledEvent.event_types() do %>
                      <option value={type} selected={Ecto.Changeset.get_field(@changeset, :event_type) == type}>
                        <%= type |> String.replace("_", " ") |> String.capitalize() %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-gray-300 text-sm mb-1">Action Type</label>
                  <select 
                    name="scheduled_event[action_type]"
                    class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                  >
                    <option value="">None</option>
                    <%= for action <- ScheduledEvent.action_types() do %>
                      <option value={action} selected={Ecto.Changeset.get_field(@changeset, :action_type) == action}>
                        <%= action |> String.replace("_", " ") |> String.capitalize() %>
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>

              <!-- One-time scheduling -->
              <div id="one-time-fields">
                <label class="block text-gray-300 text-sm mb-1">Scheduled At (for one-time events)</label>
                <input 
                  type="datetime-local" 
                  name="scheduled_event[scheduled_at]"
                  value={format_datetime(Ecto.Changeset.get_field(@changeset, :scheduled_at))}
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                />
              </div>

              <!-- Recurring scheduling -->
              <div id="recurring-fields">
                <label class="block text-gray-300 text-sm mb-1">Cron Expression (for recurring events)</label>
                <input 
                  type="text" 
                  name="scheduled_event[cron_expression]"
                  value={Ecto.Changeset.get_field(@changeset, :cron_expression)}
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700 font-mono"
                  placeholder="0 9 * * 1 (9am every Monday)"
                />
                <p class="text-xs text-gray-500 mt-1">Format: minute hour day month weekday</p>
              </div>

              <!-- Project Trigger -->
              <div id="trigger-fields" class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-gray-300 text-sm mb-1">Trigger Project</label>
                  <select 
                    name="scheduled_event[trigger_project_id]"
                    class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                  >
                    <option value="">Select project...</option>
                    <%= for project <- @projects do %>
                      <option value={project.id} selected={Ecto.Changeset.get_field(@changeset, :trigger_project_id) == project.id}>
                        <%= project.name %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-gray-300 text-sm mb-1">Trigger On</label>
                  <select 
                    name="scheduled_event[trigger_on]"
                    class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                  >
                    <option value="">Select trigger...</option>
                    <option value="project_start" selected={Ecto.Changeset.get_field(@changeset, :trigger_on) == "project_start"}>Project Start</option>
                    <option value="project_complete" selected={Ecto.Changeset.get_field(@changeset, :trigger_on) == "project_complete"}>Project Complete</option>
                    <option value="task_complete" selected={Ecto.Changeset.get_field(@changeset, :trigger_on) == "task_complete"}>Task Complete</option>
                  </select>
                </div>
              </div>

              <!-- Target Project -->
              <div>
                <label class="block text-gray-300 text-sm mb-1">Target Project (for create/complete actions)</label>
                <select 
                  name="scheduled_event[target_project_id]"
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700"
                >
                  <option value="">Select project...</option>
                  <%= for project <- @projects do %>
                    <option value={project.id} selected={Ecto.Changeset.get_field(@changeset, :target_project_id) == project.id}>
                      <%= project.name %>
                    </option>
                  <% end %>
                </select>
              </div>

              <!-- Action Config (JSON) -->
              <div>
                <label class="block text-gray-300 text-sm mb-1">Action Configuration (JSON)</label>
                <textarea 
                  name="scheduled_event[action_config_json]"
                  class="w-full bg-gray-800 text-white px-3 py-2 rounded border border-gray-700 font-mono h-24"
                  placeholder='{"url": "https://api.example.com/webhook", "method": "POST"}'
                ><%= Jason.encode!(Ecto.Changeset.get_field(@changeset, :action_config) || %{}) %></textarea>
              </div>

              <div class="flex justify-end gap-3 pt-4 border-t border-gray-700">
                <button type="button" phx-click="close_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded">
                  Cancel
                </button>
                <button type="submit" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded">
                  <%= if @form_mode == :create, do: "Create Event", else: "Save Changes" %>
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
  defp status_color(status) do
    case status do
      "active" -> "bg-green-500"
      "paused" -> "bg-yellow-500"
      "completed" -> "bg-blue-500"
      "failed" -> "bg-red-500"
      _ -> "bg-gray-500"
    end
  end

  defp status_text_color(status) do
    case status do
      "active" -> "text-green-400"
      "paused" -> "text-yellow-400"
      "completed" -> "text-blue-400"
      "failed" -> "text-red-400"
      _ -> "text-gray-400"
    end
  end

  defp type_badge(type) do
    case type do
      "one_time" -> "bg-blue-600/30 text-blue-400"
      "recurring" -> "bg-purple-600/30 text-purple-400"
      "webhook" -> "bg-orange-600/30 text-orange-400"
      "project_trigger" -> "bg-green-600/30 text-green-400"
      _ -> "bg-gray-600/30 text-gray-400"
    end
  end

  defp run_bg(status) do
    case status do
      "success" -> "bg-green-900/20"
      "failed" -> "bg-red-900/20"
      _ -> "bg-gray-800/50"
    end
  end

  defp run_status_color(status) do
    case status do
      "success" -> "bg-green-500"
      "failed" -> "bg-red-500"
      "running" -> "bg-blue-500 animate-pulse"
      _ -> "bg-gray-500"
    end
  end

  defp run_status_badge(status) do
    case status do
      "success" -> "bg-green-600/30 text-green-400"
      "failed" -> "bg-red-600/30 text-red-400"
      "running" -> "bg-blue-600/30 text-blue-400"
      _ -> "bg-gray-600/30 text-gray-400"
    end
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end
  defp format_datetime(_), do: ""
end
