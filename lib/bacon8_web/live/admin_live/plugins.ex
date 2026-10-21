defmodule Bacon8Web.AdminLive.Plugins do
  @moduledoc """
  /admin/plugins - activate and deactivate installed plugins (BACON8.md §9).

  "Installed" means the folder exists under `plugins/` in this build. Adding or
  removing a plugin is a code change and a deploy; activating one is a click.
  """
  use Bacon8Web, :live_view

  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, Bacon8.Plugins.topic())

    {:ok, socket |> assign(page_title: "Admin - Plugins", busy: nil) |> load()}
  end

  defp load(socket), do: assign(socket, plugins: Bacon8.Plugins.list())

  @impl true
  def handle_event("activate", %{"slug" => slug}, socket), do: toggle(socket, slug, :activate)
  def handle_event("deactivate", %{"slug" => slug}, socket), do: toggle(socket, slug, :deactivate)

  defp toggle(socket, slug, action) do
    actor = socket.assigns.current_user

    result =
      case action do
        :activate -> Bacon8.Plugins.activate(slug, actor)
        :deactivate -> Bacon8.Plugins.deactivate(slug, actor)
      end

    socket =
      case result do
        {:ok, mod} ->
          verb = if action == :activate, do: "activated", else: "deactivated"
          put_flash(socket, :info, "#{mod.name()} #{verb}.")

        {:error, :not_installed} ->
          put_flash(socket, :error, "That plugin is not installed in this build.")

        {:error, {:hook_failed, reason}} ->
          put_flash(socket, :error, "The plugin refused: #{inspect(reason)}")

        {:error, {:requires, missing}} ->
          put_flash(socket, :error, "Activate #{Enum.join(missing, ", ")} first: this plugin requires it.")

        {:error, {:required_by, dependents}} ->
          put_flash(socket, :error, "Deactivate #{Enum.join(dependents, ", ")} first: it requires this plugin.")
      end

    {:noreply, load(socket)}
  end

  # Another admin (or node) changed something: show it.
  @impl true
  def handle_info(:plugins_changed, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/plugins">
      <div class="max-w-6xl mx-auto">
        <div class="dark-glass p-8 rounded-xl">
          <div class="mb-8">
            <h1 class="text-3xl font-bold text-white">Plugins</h1>
            <p class="text-gray-400 mt-1">
              Installed plugins live in <code class="text-gray-300">plugins/</code>. Activating one turns on its
              pages, API, background processes and menu entries. Deactivating hides them again; its data is kept.
            </p>
          </div>

          <%= if @plugins == [] do %>
            <div class="text-center py-12 text-gray-400">
              No plugins are installed in this build. Add a folder under <code>plugins/</code> and redeploy.
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-left text-gray-300">
                <thead class="text-xs uppercase bg-gray-700/50 text-gray-400">
                  <tr>
                    <th class="px-4 py-3">Plugin</th>
                    <th class="px-4 py-3">Version</th>
                    <th class="px-4 py-3">Game</th>
                    <th class="px-4 py-3">Status</th>
                    <th class="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for plugin <- @plugins do %>
                    <tr class="border-b border-gray-700/50">
                      <td class="px-4 py-4">
                        <div class="font-semibold text-white"><%= plugin.name %></div>
                        <div class="text-xs text-gray-500"><%= plugin.slug %></div>
                        <div class="text-sm text-gray-400 mt-1"><%= plugin.description %></div>
                        <div :if={plugin.module.requires() != []} class="text-xs text-gray-500 mt-1">
                          Requires: <%= Enum.join(plugin.module.requires(), ", ") %>
                        </div>
                        <div :if={plugin.module.mount()} class="text-xs text-gray-500 mt-1">
                          Mounted at /<%= plugin.module.mount() %>
                        </div>
                      </td>
                      <td class="px-4 py-4 text-sm"><%= plugin.version %></td>
                      <td class="px-4 py-4 text-sm">
                        <%= if plugin.game do %>
                          <span class="text-gray-300"><%= plugin.game.slug %></span>
                        <% else %>
                          <span class="text-gray-500">&mdash;</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-4">
                        <%= if plugin.active? do %>
                          <span class="px-2 py-1 rounded text-xs bg-green-600/30 text-green-300">Active</span>
                        <% else %>
                          <span class="px-2 py-1 rounded text-xs bg-gray-600/40 text-gray-300">Inactive</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-4 text-right">
                        <%= if plugin.active? do %>
                          <button
                            phx-click="deactivate"
                            phx-value-slug={plugin.slug}
                            data-confirm={"Deactivate #{plugin.name}? Its pages and API will stop responding; its data is kept."}
                            class="px-4 py-2 rounded bg-gray-600 hover:bg-gray-500 text-white text-sm"
                          >
                            Deactivate
                          </button>
                        <% else %>
                          <button
                            phx-click="activate"
                            phx-value-slug={plugin.slug}
                            class="px-4 py-2 rounded bg-blue-600 hover:bg-blue-700 text-white text-sm"
                          >
                            Activate
                          </button>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
