defmodule Bacon8Web.AvatarLive do
  use Bacon8Web, :live_view
  alias Bacon8.Accounts

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    
    if current_user do
      shapes = generate_avatar_shapes()
      colors = generate_avatar_colors()
      
      {:ok, assign(socket, 
        shapes: shapes, 
        colors: colors, 
        selected_shape: nil, 
        selected_color: nil,
        page_title: "Choose Your Avatar"
      )}
    else
      {:ok, 
       socket
       |> put_flash(:error, "Please log in to access this page")
       |> push_navigate(to: ~p"/login")}
    end
  end

  def handle_event("select_shape", %{"shape" => shape}, socket) do
    {:noreply, assign(socket, selected_shape: shape)}
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, selected_color: color)}
  end

  def handle_event("save_avatar", _params, socket) do
    %{selected_shape: shape, selected_color: color, current_user: user} = socket.assigns
    
    if shape && color do
      case Accounts.update_user(user, %{avatar_shape: shape, avatar_color: color}) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Avatar saved successfully!")
           |> redirect(to: ~p"/games")}
        
        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save avatar")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select both a shape and color")}
    end
  end

  defp generate_avatar_shapes do
    [
      "circle", "square", "rounded"
    ]
  end

  defp generate_avatar_colors do
    [
      "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
      "#BB8FCE", "#85C1E9", "#F8C471", "#82E0AA", "#F1948A", "#85929E", "#D7BDE2", "#A9DFBF",
      "#F9E79F", "#AED6F1", "#F5B7B1", "#D5A6BD", "#A3E4D7", "#F4D03F", "#D2B4DE", "#A9CCE3",
      "#FADBD8", "#D6EAF8", "#EBDEF0", "#D1F2EB", "#FCF3CF", "#EAEDED", "#FDEBD0", "#E8DAEF",
      "#D4EDDA", "#FFF3CD", "#F8D7DA", "#D1ECF1", "#E2E3E5", "#F5C6CB", "#C3E6CB", "#BEE5EB",
      "#FEFEFE", "#212529", "#6C757D", "#495057", "#343A40", "#007BFF", "#6610F2", "#6F42C1",
      "#E83E8C", "#DC3545", "#FD7E14", "#FFC107", "#28A745", "#20C997", "#17A2B8", "#6C757D"
    ]
  end

  def render(assigns) do
    ~H"""
    <div data-responsive-content class="min-h-screen" style="padding-top: 30px; padding-bottom: 48px;">
      <div class="container mx-auto px-4 py-8 relative z-10">
        <div class="text-center mb-8">
          <h1 class="text-4xl font-bold text-white mb-4">Choose Your Avatar</h1>
          <p class="text-gray-300">Select a shape and color to represent you in the app</p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 max-w-6xl mx-auto">
          <!-- Shape Selection -->
          <div class="bg-white bg-opacity-10 backdrop-blur-sm rounded-xl p-6">
            <h2 class="text-2xl font-bold text-white mb-4">Choose Shape</h2>
            <div class="grid grid-cols-5 gap-3 max-h-96 overflow-y-auto">
              <%= for shape <- @shapes do %>
                <button
                  phx-click="select_shape"
                  phx-value-shape={shape}
                  class={[
                    "w-16 h-16 rounded-lg border-2 transition-all duration-300 flex items-center justify-center",
                    if(@selected_shape == shape, do: "border-yellow-400 bg-yellow-400 bg-opacity-20", else: "border-gray-400 hover:border-white")
                  ]}
                >
                  <div class={[
                    "w-8 h-8 transition-all duration-300",
                    get_shape_class(shape),
                    if(@selected_color, do: "bg-[#{@selected_color}]", else: "bg-white")
                  ]}>
                  </div>
                </button>
              <% end %>
            </div>
          </div>

          <!-- Color Selection -->
          <div class="bg-white bg-opacity-10 backdrop-blur-sm rounded-xl p-6">
            <h2 class="text-2xl font-bold text-white mb-4">Choose Color</h2>
            <div class="grid grid-cols-8 gap-3 max-h-96 overflow-y-auto">
              <%= for color <- @colors do %>
                <button
                  phx-click="select_color"
                  phx-value-color={color}
                  class={[
                    "w-12 h-12 rounded-lg border-2 transition-all duration-300",
                    if(@selected_color == color, do: "border-yellow-400 scale-110", else: "border-gray-400 hover:border-white hover:scale-105")
                  ]}
                  style={"background-color: #{color}"}
                >
                </button>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Preview and Save -->
        <div class="text-center mt-8">
          <%= if @selected_shape && @selected_color do %>
            <div class="mb-6">
              <h3 class="text-xl text-white mb-4">Preview</h3>
              <div class="inline-block p-4 bg-white bg-opacity-10 rounded-xl">
                <div class={[
                  "w-20 h-20 mx-auto transition-all duration-300",
                  get_shape_class(@selected_shape)
                ]} style={"background-color: #{@selected_color}"}>
                </div>
              </div>
            </div>
            
            <button
              phx-click="save_avatar"
              class="bg-gradient-to-r from-green-500 to-blue-500 hover:from-green-600 hover:to-blue-600 text-white font-bold py-3 px-8 rounded-lg transition-all duration-300 transform hover:scale-105"
            >
              Save Avatar
            </button>
          <% else %>
            <p class="text-gray-300">Select a shape and color to see preview</p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp get_shape_class("circle"), do: "rounded-full"
  defp get_shape_class("square"), do: "rounded-none"
  defp get_shape_class("rounded"), do: "rounded-lg"
  defp get_shape_class(_), do: "rounded-lg"
end