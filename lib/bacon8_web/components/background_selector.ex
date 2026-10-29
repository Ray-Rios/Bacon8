defmodule Bacon8Web.Components.BackgroundSelector do
  use Phoenix.LiveComponent

  # The cosmic backgrounds (Bacon8Web.Components.Cosmos: SVG and CSS, 2026-10-28), then the flat ones.
  @available_backgrounds Bacon8Web.Components.Cosmos.catalogue() ++
                           [
                             %{
                               id: "gradient",
                               name: "Gradient",
                               description: "Smooth color transitions (customizable)",
                               preview_class: "bg-gradient-to-br from-blue-600 to-purple-600"
                             },
                             %{
                               id: "solid",
                               name: "Solid Color",
                               description: "Single color background (customizable)",
                               preview_class: "bg-gray-900"
                             }
                           ]

  @doc "Every background a member can pick (the profile page lists these)."
  def backgrounds, do: @available_backgrounds

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(backgrounds: @available_backgrounds)}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h3 class="text-2xl font-bold text-white mb-2">Background Theme</h3>
        <p class="text-gray-400">Choose how your site looks</p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for bg <- @backgrounds do %>
          <button
            type="button"
            phx-click="select_background"
            phx-value-background={bg.id}
            phx-target={@myself}
            class={[
              "relative overflow-hidden rounded-lg border-2 transition-all duration-300 hover:scale-105",
              if(@selected_background == bg.id,
                do: "border-blue-500 ring-2 ring-blue-500 ring-opacity-50",
                else: "border-gray-700 hover:border-gray-500"
              )
            ]}
          >
            <!-- Preview -->
            <div class={["h-32 relative overflow-hidden group", Map.get(bg, :preview_class)]}>
              <%!-- a cosmos is previewed by the real thing, still until hovered --%>
              <div :if={bg.id in Bacon8Web.Components.Cosmos.kinds()} class="cosmos c-preview" data-cosmos={bg.id} aria-hidden="true">
                <Bacon8Web.Components.Cosmos.layers uid={"cwp-#{bg.id}"} />
              </div>

              <%= if @selected_background == bg.id do %>
                <div class="absolute top-2 right-2 bg-blue-500 text-white px-2 py-1 rounded-full text-xs font-bold">
                  ✓ Active
                </div>
              <% end %>
            </div>

            <!-- Info -->
            <div class="glass-dark p-4 text-left">
              <h4 class="font-bold text-white mb-1"><%= bg.name %></h4>
              <p class="text-sm text-gray-400"><%= bg.description %></p>
            </div>
          </button>
        <% end %>
      </div>

      <!-- Custom Settings (show when gradient or solid is selected) -->
      <%= if @selected_background in ["gradient", "solid"] do %>
        <div class="glass-dark rounded-lg p-6 border border-gray-700">
          <h4 class="text-lg font-bold text-white mb-4">Customize Colors</h4>
          
          <%= if @selected_background == "gradient" do %>
            <div class="space-y-4">
              <div>
                <label class="block text-sm text-gray-400 mb-2">Start Color</label>
                <input
                  type="color"
                  phx-change="update_custom_setting"
                  phx-target={@myself}
                  name="gradient_start"
                  value={get_in(@custom_data, ["gradient_start"]) || "#3B82F6"}
                  class="w-full h-12 rounded cursor-pointer"
                />
              </div>
              <div>
                <label class="block text-sm text-gray-400 mb-2">End Color</label>
                <input
                  type="color"
                  phx-change="update_custom_setting"
                  phx-target={@myself}
                  name="gradient_end"
                  value={get_in(@custom_data, ["gradient_end"]) || "#9333EA"}
                  class="w-full h-12 rounded cursor-pointer"
                />
              </div>
            </div>
          <% else %>
            <div>
              <label class="block text-sm text-gray-400 mb-2">Background Color</label>
              <input
                type="color"
                phx-change="update_custom_setting"
                phx-target={@myself}
                name="solid_color"
                value={get_in(@custom_data, ["solid_color"]) || "#1F2937"}
                class="w-full h-12 rounded cursor-pointer"
              />
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="flex justify-end space-x-4">
        <button
          phx-click="cancel"
          phx-target={@myself}
          class="px-6 py-3 bg-gray-700 hover:bg-gray-600 text-white rounded-lg transition-colors"
        >
          Cancel
        </button>
        <button
          phx-click="save_background"
          phx-target={@myself}
          class="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
        >
          Save Changes
        </button>
      </div>
    </div>
    """
  end

  def handle_event("select_background", %{"background" => bg_id}, socket) do
    {:noreply, assign(socket, selected_background: bg_id)}
  end

  def handle_event("update_custom_setting", %{"_target" => [field]} = params, socket) do
    custom_data = socket.assigns.custom_data || %{}
    updated_data = Map.put(custom_data, field, params[field])
    {:noreply, assign(socket, custom_data: updated_data)}
  end

  def handle_event("save_background", _params, socket) do
    send(self(), {:save_background_preference, socket.assigns.selected_background, socket.assigns.custom_data})
    {:noreply, socket}
  end

  def handle_event("cancel", _params, socket) do
    send(self(), :cancel_background_selection)
    {:noreply, socket}
  end
end
