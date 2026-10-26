defmodule Bacon8Web.AdminLive.Comments do
  @moduledoc """
  Comment moderation: the comments waiting for approval, the approved ones, and the ones marked
  spam. Admins, GMs and editors may use it (the :content area, `Bacon8.Permissions`).
  """
  use Bacon8Web, :live_view

  alias Bacon8.Content
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, {:require_area, :content}}

  @tabs [pending: "Waiting", approved: "Approved", spam: "Spam"]

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Comments", tabs: @tabs) |> load(:pending)}
  end

  def handle_event("show", %{"tab" => tab}, socket) do
    {:noreply, load(socket, tab_atom(tab))}
  end

  def handle_event("approve", %{"id" => id}, socket), do: change(socket, id, &Content.approve_comment/1)
  def handle_event("spam", %{"id" => id}, socket), do: change(socket, id, &Content.mark_spam/1)
  def handle_event("delete", %{"id" => id}, socket), do: change(socket, id, &Content.delete_comment/1)

  # Approve every comment waiting (after reading them)
  def handle_event("approve_all", _params, socket) do
    for comment <- Content.list_comments_by_status(:pending), do: Content.approve_comment(comment)
    {:noreply, load(socket, :pending)}
  end

  # Delete every comment marked spam
  def handle_event("empty_spam", _params, socket) do
    for comment <- Content.list_comments_by_status(:spam), do: Content.delete_comment(comment)
    {:noreply, load(socket, :spam)}
  end

  defp change(socket, id, fun) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        # (an id that doesn't exist any more - someone else moderated it first - is just a refresh)
        case Bacon8.Repo.get(Bacon8.Content.Comment, uuid) do
          nil -> :ok
          comment -> fun.(comment)
        end

      :error ->
        :ok
    end

    {:noreply, load(socket, socket.assigns.tab)}
  end

  defp load(socket, tab) do
    assign(socket,
      tab: tab,
      comments: Content.list_comments_by_status(tab),
      counts: %{
        pending: Content.count_comments_by_status(:pending),
        approved: Content.count_comments_by_status(:approved),
        spam: Content.count_comments_by_status(:spam)
      }
    )
  end

  defp tab_atom("approved"), do: :approved
  defp tab_atom("spam"), do: :spam
  defp tab_atom(_), do: :pending

  defp author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp author(_), do: "(deleted account)"

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/comments" current_user={@current_user}>
      <div class="max-w-6xl mx-auto">
        <div class="auth-glass-panel p-8 rounded-xl">
          <div class="flex justify-between items-center mb-6">
            <h1 class="text-3xl font-bold text-white">Comments</h1>
            <div class="flex gap-2">
              <button :if={@tab == :pending and @comments != []} id="approve-all" phx-click="approve_all" data-confirm="Approve every comment waiting?" class="px-4 py-2 rounded bg-green-600 hover:bg-green-700 text-white text-sm">Approve all</button>
              <button :if={@tab == :spam and @comments != []} id="empty-spam" phx-click="empty_spam" data-confirm="Delete every comment marked spam?" class="px-4 py-2 rounded bg-red-600 hover:bg-red-700 text-white text-sm">Delete all spam</button>
            </div>
          </div>

          <div class="flex gap-2 mb-6">
            <button :for={{key, label} <- @tabs} id={"tab-#{key}"} phx-click="show" phx-value-tab={key}
              class={["px-4 py-2 rounded-lg text-sm", if(@tab == key, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}>
              <%= label %> (<%= @counts[key] %>)
            </button>
          </div>

          <p :if={@comments == []} class="text-gray-400 py-8 text-center">Nothing here.</p>

          <ul class="space-y-3">
            <li :for={comment <- @comments} id={"comment-#{comment.id}"} class="p-4 rounded-lg bg-gray-800/60 border border-gray-700">
              <div class="flex justify-between items-start gap-4">
                <div class="min-w-0 flex-1">
                  <div class="text-sm text-gray-400 mb-1">
                    <span class="text-gray-200 font-medium"><%= author(comment) %></span>
                    on <span class="text-cyan-400"><%= comment.post && comment.post.title %></span>
                    · <%= Calendar.strftime(comment.inserted_at, "%b %d, %Y %H:%M") %>
                  </div>
                  <p class="text-gray-100 whitespace-pre-line break-words"><%= comment.content %></p>
                </div>
                <div class="flex gap-2 shrink-0">
                  <button :if={@tab != :approved} phx-click="approve" phx-value-id={comment.id} class="px-3 py-1 rounded bg-green-600 hover:bg-green-700 text-white text-sm">Approve</button>
                  <button :if={@tab != :spam} phx-click="spam" phx-value-id={comment.id} class="px-3 py-1 rounded bg-amber-600 hover:bg-amber-700 text-white text-sm">Spam</button>
                  <button phx-click="delete" phx-value-id={comment.id} data-confirm="Delete this comment?" class="px-3 py-1 rounded bg-red-600 hover:bg-red-700 text-white text-sm">Delete</button>
                </div>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end
