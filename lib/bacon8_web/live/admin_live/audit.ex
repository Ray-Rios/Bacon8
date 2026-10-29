defmodule Bacon8Web.AdminLive.Audit do
  @moduledoc """
  /admin/audit - the audit log (2026-10-29): who changed what, newest first. `Bacon8.Audit.log/5`
  writes it; today that is role changes, plugins switched on and off, pages and posts published,
  unpublished and deleted, identifiers blocked and unblocked, store deliveries retried, channels
  created and deleted, and the feedback queue's agent settings. Admins only. Filter by action
  ("user.", "plugin", "post.deleted"...).
  """
  use Bacon8Web, :live_view

  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @page 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Admin - Audit log", query: "") |> load()}
  end

  defp load(socket) do
    rows = Bacon8.Audit.list(query: socket.assigns.query, limit: @page)
    assign(socket, rows: rows, more: length(rows) == @page)
  end

  @impl true
  def handle_event("filter", %{"query" => query}, socket), do: {:noreply, socket |> assign(query: String.trim(query)) |> load()}

  def handle_event("more", _params, %{assigns: %{rows: rows}} = socket) when rows != [] do
    last = List.last(rows).entry.inserted_at
    more = Bacon8.Audit.list(query: socket.assigns.query, limit: @page, before: last)
    {:noreply, assign(socket, rows: rows ++ more, more: length(more) == @page)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp who(%{actor: %{name: name, email: email}}), do: name || email
  defp who(%{entry: %{actor_id: nil}}), do: "system"
  defp who(_), do: "a deleted user"

  defp details(%{} = meta) when map_size(meta) > 0,
    do: meta |> Enum.map(fn {k, v} -> "#{k}: #{if is_binary(v), do: v, else: inspect(v)}" end) |> Enum.join(" · ")

  defp details(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/audit">
      <div class="max-w-6xl mx-auto">
        <div class="dark-glass p-4 sm:p-8 rounded-xl">
          <div class="flex flex-wrap justify-between items-end gap-4 mb-6">
            <div>
              <h1 class="text-3xl font-bold text-white">Audit log</h1>
              <p class="text-gray-400 mt-1">Who changed what, newest first.</p>
            </div>
            <form phx-change="filter" phx-submit="filter" class="w-full sm:w-72">
              <input
                type="search"
                name="query"
                value={@query}
                placeholder="Filter by action: user., plugin, post"
                phx-debounce="300"
                class="w-full bg-gray-800 border border-gray-600 text-white rounded-lg px-3 py-2 text-sm"
              />
            </form>
          </div>

          <ul id="audit-list" class="divide-y divide-gray-800 rounded-lg border border-gray-800">
            <li :for={row <- @rows} class="flex flex-wrap items-baseline gap-x-4 gap-y-1 px-4 py-3 text-sm">
              <span class="w-40 flex-none whitespace-nowrap text-gray-500">{Calendar.strftime(row.entry.inserted_at, "%Y-%m-%d %H:%M")} UTC</span>
              <code class="flex-none rounded bg-gray-800 px-2 py-0.5 text-xs text-cyan-300">{row.entry.action}</code>
              <span class="text-gray-200">{who(row)}</span>
              <span :if={row.entry.target_type} class="text-gray-500">→ {row.entry.target_type}{if row.entry.target_id, do: " " <> String.slice(row.entry.target_id, 0, 8)}</span>
              <span class="basis-full text-xs text-gray-400 break-words sm:basis-auto">{details(row.entry.metadata)}</span>
            </li>
          </ul>
          <p :if={@rows == []} class="px-4 py-8 text-center text-gray-500">Nothing recorded yet.</p>
          <button :if={@more} type="button" phx-click="more" class="mt-4 px-4 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-white text-sm">Older</button>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
