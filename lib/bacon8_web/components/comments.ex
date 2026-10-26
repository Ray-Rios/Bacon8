defmodule Bacon8Web.Components.Comments do
  @moduledoc """
  The comments under a blog post: the approved ones, and a form for signed-in members with a
  verified email. A first comment waits for a moderator (`Bacon8.Content.Moderation`), and the
  form says so. Visitors see the comments and a sign-in prompt.
  """
  use Phoenix.Component

  attr :comments, :list, required: true
  attr :current_user, :map, default: nil
  attr :notice, :string, default: nil

  def comments(assigns) do
    ~H"""
    <section id="comments" class="mt-10 pt-6 border-t border-gray-700">
      <h2 class="text-xl font-semibold text-white mb-4">
        Comments <span class="text-gray-400 text-base">(<%= length(@comments) %>)</span>
      </h2>

      <p :if={@comments == []} class="text-gray-400 mb-6">No comments yet.</p>

      <ol class="space-y-4 mb-8">
        <li :for={comment <- @comments} id={"comment-#{comment.id}"} class="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
          <div class="text-sm text-gray-400 mb-1">
            <span class="font-medium text-gray-200"><%= author(comment) %></span>
            · <%= Calendar.strftime(comment.inserted_at, "%B %d, %Y") %>
          </div>
          <%!-- Plain text only: HEEx escapes it, and line breaks are kept by the CSS. --%>
          <p class="text-gray-200 whitespace-pre-line break-words"><%= comment.content %></p>
        </li>
      </ol>

      <p :if={@notice} id="comment-notice" class="mb-4 p-3 rounded bg-cyan-900/40 border border-cyan-500/30 text-cyan-100">
        <%= @notice %>
      </p>

      <%= cond do %>
        <% is_nil(@current_user) -> %>
          <p class="text-gray-400"><.link navigate="/login" class="text-cyan-400 hover:underline">Sign in</.link> to leave a comment.</p>
        <% is_nil(@current_user.email_verified_at) -> %>
          <p class="text-gray-400">Verify your email address to leave a comment.</p>
        <% true -> %>
          <form id="comment-form" phx-submit="post_comment" class="space-y-3">
            <textarea name="comment" rows="4" maxlength="2000" required placeholder="Write a comment..." class="w-full p-3 rounded bg-gray-900 text-white border border-gray-700"></textarea>
            <div class="flex items-center justify-between">
              <span class="text-xs text-gray-500">Plain text. A first comment is checked by a moderator before it appears.</span>
              <button type="submit" class="px-4 py-2 rounded bg-cyan-600 text-white hover:bg-cyan-500">Post comment</button>
            </div>
          </form>
      <% end %>
    </section>
    """
  end

  defp author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp author(%{author_name: name}) when is_binary(name) and name != "", do: name
  defp author(_), do: "A member"
end
