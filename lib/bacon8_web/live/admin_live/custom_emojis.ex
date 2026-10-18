defmodule Bacon8Web.AdminLive.CustomEmojis do
  @moduledoc """
  Admin interface for managing custom emojis.
  Only Admin, GM, and Editor roles can access this page.
  """
  use Bacon8Web, :live_view
  alias Bacon8.Forum
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    # on_mount already verified admin access
    # Additional check for emoji management permissions
    user = socket.assigns.current_user
    
    if Forum.can_manage_emojis?(user) do
      custom_emojis = Forum.list_custom_emojis()
      
      {:ok, assign(socket,
        custom_emojis: custom_emojis,
        show_add_modal: false,
        show_delete_modal: false,
        editing_emoji: nil,
        delete_emoji: nil,
        form: to_form(%{"shortcode" => "", "emoji" => "", "image_url" => "", "category" => "Custom"}),
        page_title: "Custom Emojis"
      )}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  @impl true
  def handle_event("show_add_modal", _params, socket) do
    {:noreply, assign(socket,
      show_add_modal: true,
      editing_emoji: nil,
      form: to_form(%{"shortcode" => "", "emoji" => "", "image_url" => "", "category" => "Custom"})
    )}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: false, show_delete_modal: false, editing_emoji: nil, delete_emoji: nil)}
  end

  @impl true
  def handle_event("edit_emoji", %{"id" => id}, socket) do
    emoji = Forum.get_custom_emoji!(id)
    form_data = %{
      "shortcode" => emoji.shortcode,
      "emoji" => emoji.emoji || "",
      "image_url" => emoji.image_url || "",
      "category" => emoji.category || "Custom"
    }
    {:noreply, assign(socket, show_add_modal: true, editing_emoji: emoji, form: to_form(form_data))}
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    emoji = Forum.get_custom_emoji!(id)
    {:noreply, assign(socket, show_delete_modal: true, delete_emoji: emoji)}
  end

  @impl true
  def handle_event("delete_emoji", _params, socket) do
    user = socket.assigns.current_user
    case Forum.delete_custom_emoji(user, socket.assigns.delete_emoji) do
      {:ok, _} ->
        {:noreply, 
         socket
         |> assign(custom_emojis: Forum.list_custom_emojis(), show_delete_modal: false, delete_emoji: nil)
         |> put_flash(:info, "Custom emoji deleted successfully")}
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete emojis")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete emoji")}
    end
  end

  @impl true
  def handle_event("validate", %{"shortcode" => _, "emoji" => _, "image_url" => _, "category" => _} = params, socket) do
    {:noreply, assign(socket, form: to_form(params))}
  end

  @impl true
  def handle_event("save_emoji", params, socket) do
    user = socket.assigns.current_user
    
    attrs = %{
      shortcode: String.trim(params["shortcode"] || ""),
      emoji: String.trim(params["emoji"] || ""),
      image_url: String.trim(params["image_url"] || ""),
      category: String.trim(params["category"] || "Custom")
    }
    
    # Ensure at least one of emoji or image_url is provided
    if attrs.emoji == "" && attrs.image_url == "" do
      {:noreply, put_flash(socket, :error, "Please provide either an emoji character or an image URL")}
    else
      result = if socket.assigns.editing_emoji do
        Forum.update_custom_emoji(user, socket.assigns.editing_emoji, attrs)
      else
        Forum.create_custom_emoji(user, attrs)
      end
      
      case result do
        {:ok, _emoji} ->
          action = if socket.assigns.editing_emoji, do: "updated", else: "created"
          {:noreply, 
           socket
           |> assign(custom_emojis: Forum.list_custom_emojis(), show_add_modal: false, editing_emoji: nil)
           |> put_flash(:info, "Custom emoji #{action} successfully")}
        {:error, changeset} ->
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          error_msg = errors |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end) |> Enum.join("; ")
          {:noreply, put_flash(socket, :error, "Error: #{error_msg}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/custom-emojis">
      <div class="flex-1">
        <div class="max-w-6xl mx-auto">
          <div class="flex justify-between items-center mb-8">
            <h1 class="text-3xl font-bold text-white">Custom Emojis</h1>
            <button 
              phx-click="show_add_modal"
              class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg flex items-center gap-2"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
              </svg>
              Add Custom Emoji
            </button>
          </div>

          <p class="text-gray-600 dark:text-gray-400 mb-6">
            Add custom emojis that can be used in forum messages and reactions. 
            You can add either unicode emoji aliases (shortcuts) or upload custom image emojis.
          </p>

          <%!-- Emoji List --%>
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow overflow-hidden">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <thead class="bg-gray-50 dark:bg-gray-700">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Preview
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Shortcode
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Category
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Type
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                <%= if Enum.empty?(@custom_emojis) do %>
                  <tr>
                    <td colspan="5" class="px-6 py-12 text-center text-gray-500 dark:text-gray-400">
                      <div class="flex flex-col items-center">
                        <svg class="w-12 h-12 mb-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                        <p class="text-lg font-medium">No custom emojis yet</p>
                        <p class="text-sm">Click "Add Custom Emoji" to create your first one!</p>
                      </div>
                    </td>
                  </tr>
                <% else %>
                  <%= for emoji <- @custom_emojis do %>
                    <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= if emoji.image_url do %>
                          <img src={emoji.image_url} class="w-8 h-8 object-contain" alt={emoji.shortcode} />
                        <% else %>
                          <span class="text-2xl"><%= emoji.emoji %></span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <code class="text-sm bg-gray-100 dark:bg-gray-600 px-2 py-1 rounded">
                          :<%= emoji.shortcode %>:
                        </code>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-gray-700 dark:text-gray-300">
                        <%= emoji.category %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= if emoji.image_url do %>
                          <span class="px-2 py-1 text-xs font-medium rounded bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200">
                            Image
                          </span>
                        <% else %>
                          <span class="px-2 py-1 text-xs font-medium rounded bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                            Unicode
                          </span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm">
                        <button 
                          phx-click="edit_emoji" 
                          phx-value-id={emoji.id}
                          class="text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 mr-3"
                        >
                          Edit
                        </button>
                        <button 
                          phx-click="confirm_delete" 
                          phx-value-id={emoji.id}
                          class="text-red-600 hover:text-red-800 dark:text-red-400 dark:hover:text-red-300"
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>

    <%!-- Add/Edit Modal --%>
    <%= if @show_add_modal do %>
      <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" phx-click="close_modal">
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-md w-full mx-4" phx-click-away="close_modal">
          <div class="p-6" onclick="event.stopPropagation()">
            <h2 class="text-xl font-bold mb-4 text-gray-800 dark:text-gray-100">
              <%= if @editing_emoji, do: "Edit Custom Emoji", else: "Add Custom Emoji" %>
            </h2>
            
            <form phx-submit="save_emoji" phx-change="validate" class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Shortcode <span class="text-red-500">*</span>
                </label>
                <div class="flex items-center">
                  <span class="text-gray-500 dark:text-gray-400 mr-1">:</span>
                  <input 
                    type="text" 
                    name="shortcode"
                    value={@form[:shortcode].value}
                    placeholder="my_emoji"
                    class="flex-1 border border-gray-300 dark:border-gray-600 rounded px-3 py-2 dark:bg-gray-700 dark:text-white"
                    required
                  />
                  <span class="text-gray-500 dark:text-gray-400 ml-1">:</span>
                </div>
                <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  Users will type :shortcode: to insert this emoji
                </p>
              </div>
              
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Emoji Character
                </label>
                <input 
                  type="text" 
                  name="emoji"
                  value={@form[:emoji].value}
                  placeholder="😀"
                  class="w-full border border-gray-300 dark:border-gray-600 rounded px-3 py-2 dark:bg-gray-700 dark:text-white"
                />
                <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  Unicode emoji character (for aliases)
                </p>
              </div>
              
              <div class="relative">
                <div class="absolute inset-0 flex items-center">
                  <div class="w-full border-t border-gray-300 dark:border-gray-600"></div>
                </div>
                <div class="relative flex justify-center text-sm">
                  <span class="px-2 bg-white dark:bg-gray-800 text-gray-500">OR</span>
                </div>
              </div>
              
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Image URL
                </label>
                <input 
                  type="url" 
                  name="image_url"
                  value={@form[:image_url].value}
                  placeholder="https://example.com/emoji.png"
                  class="w-full border border-gray-300 dark:border-gray-600 rounded px-3 py-2 dark:bg-gray-700 dark:text-white"
                />
                <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  URL to a custom emoji image (PNG, GIF, etc.)
                </p>
              </div>
              
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Category
                </label>
                <select 
                  name="category"
                  class="w-full border border-gray-300 dark:border-gray-600 rounded px-3 py-2 dark:bg-gray-700 dark:text-white"
                >
                  <option value="Custom" selected={@form[:category].value == "Custom"}>Custom</option>
                  <option value="Reactions" selected={@form[:category].value == "Reactions"}>Reactions</option>
                  <option value="Memes" selected={@form[:category].value == "Memes"}>Memes</option>
                  <option value="Emotes" selected={@form[:category].value == "Emotes"}>Emotes</option>
                  <option value="Brand" selected={@form[:category].value == "Brand"}>Brand</option>
                </select>
              </div>
              
              <div class="flex justify-end gap-3 pt-4">
                <button 
                  type="button"
                  phx-click="close_modal"
                  class="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"
                >
                  Cancel
                </button>
                <button 
                  type="submit"
                  class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded"
                >
                  <%= if @editing_emoji, do: "Update", else: "Create" %>
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>

    <%!-- Delete Confirmation Modal --%>
    <%= if @show_delete_modal && @delete_emoji do %>
      <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-sm w-full mx-4 p-6">
          <h2 class="text-xl font-bold mb-4 text-gray-800 dark:text-gray-100">Delete Emoji?</h2>
          <p class="text-gray-600 dark:text-gray-400 mb-4">
            Are you sure you want to delete <code class="bg-gray-100 dark:bg-gray-700 px-1 rounded">:<%= @delete_emoji.shortcode %>:</code>?
            This action cannot be undone.
          </p>
          <div class="flex justify-end gap-3">
            <button 
              phx-click="close_modal"
              class="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"
            >
              Cancel
            </button>
            <button 
              phx-click="delete_emoji"
              class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    <% end %>
    </AdminSidebar.admin_layout>
    """
  end
end
