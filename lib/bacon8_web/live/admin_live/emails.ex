defmodule Bacon8Web.AdminLive.Emails do
  use Bacon8Web, :live_view
  alias Bacon8.EmailLogging
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Admin - Email Logs",
       emails: EmailLogging.list_email_logs(),
       selected_email: nil
     )}
  end

  def handle_event("view_email", %{"id" => id}, socket) do
    email = EmailLogging.get_email_log!(id)
    {:noreply, assign(socket, selected_email: email)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, selected_email: nil)}
  end

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/emails">
      <div class="max-w-6xl mx-auto">
        <div class="dark-glass p-8 rounded-xl">
          <div class="flex justify-between items-center mb-8">
            <div>
              <h1 class="text-3xl font-bold text-white">Email Logs</h1>
              <p class="text-gray-400 mt-1">View recent system emails</p>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-left text-gray-300">
              <thead class="text-xs uppercase bg-gray-700/50 text-gray-400">
                <tr>
                  <th class="px-6 py-3">Sent At</th>
                  <th class="px-6 py-3">To</th>
                  <th class="px-6 py-3">Subject</th>
                  <th class="px-6 py-3">Status</th>
                  <th class="px-6 py-3">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-700">
                <%= for email <- @emails do %>
                  <tr class="hover:bg-gray-700/30">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= Calendar.strftime(email.sent_at, "%Y-%m-%d %H:%M:%S") %>
                    </td>
                    <td class="px-6 py-4"><%= email.to %></td>
                    <td class="px-6 py-4"><%= email.subject %></td>
                    <td class="px-6 py-4">
                      <span class={"px-2 py-1 rounded-full text-xs " <> if(email.status == "sent", do: "bg-green-900 text-green-200", else: "bg-red-900 text-red-200")}>
                        <%= String.capitalize(email.status) %>
                      </span>
                    </td>
                    <td class="px-6 py-4">
                      <button phx-click="view_email" phx-value-id={email.id} class="text-blue-400 hover:text-blue-300 text-sm">
                        View Content
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <%= if @selected_email do %>
        <div class="fixed inset-0 bg-black/80 flex items-center justify-center z-50" phx-click="close_modal">
          <div class="bg-gray-800 rounded-xl p-6 max-w-4xl w-full mx-4 max-h-[90vh] overflow-y-auto" phx-click-away="close_modal">
            <div class="flex justify-between items-center mb-6 border-b border-gray-700 pb-4">
              <h3 class="text-xl font-bold text-white">Email Details</h3>
              <button phx-click="close_modal" class="text-gray-400 hover:text-white">✕</button>
            </div>
            
            <div class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <p class="text-gray-500 text-sm">From</p>
                  <p class="text-white"><%= @selected_email.from %></p>
                </div>
                <div>
                  <p class="text-gray-500 text-sm">To</p>
                  <p class="text-white"><%= @selected_email.to %></p>
                </div>
                <div class="col-span-2">
                  <p class="text-gray-500 text-sm">Subject</p>
                  <p class="text-white font-medium"><%= @selected_email.subject %></p>
                </div>
              </div>

              <div class="mt-6">
                <div class="flex gap-4 mb-2 border-b border-gray-700">
                  <button class="px-4 py-2 text-blue-400 border-b-2 border-blue-400 font-medium">HTML Content</button>
                </div>
                <div class="bg-white text-black p-4 rounded overflow-auto max-h-96">
                  <iframe srcdoc={@selected_email.html_body} class="w-full h-96 border-0"></iframe>
                </div>
              </div>
              
              <%= if @selected_email.text_body do %>
                <div class="mt-6">
                  <p class="text-gray-500 text-sm mb-2">Text Content</p>
                  <pre class="bg-gray-900 text-gray-300 p-4 rounded overflow-auto max-h-48 whitespace-pre-wrap"><%= @selected_email.text_body %></pre>
                </div>
              <% end %>
              
              <%= if @selected_email.error do %>
                <div class="mt-6 bg-red-900/30 border border-red-800 p-4 rounded">
                  <p class="text-red-400 text-sm font-bold mb-1">Error</p>
                  <p class="text-red-200 text-sm"><%= @selected_email.error %></p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </AdminSidebar.admin_layout>
    """
  end
end
