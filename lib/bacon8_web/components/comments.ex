defmodule Bacon8Web.Components.Comments do
  @moduledoc """
  The comments under a blog post: the approved ones with their replies (one level deep), and a
  form for signed-in members with a verified email. A first comment waits for a moderator
  (`Bacon8.Content.Moderation`), and the form says so. A member can reply to a comment and edit
  or delete their own. Visitors see the comments and a sign-in prompt.
  """
  use Phoenix.Component

  attr :comments, :list, required: true
  attr :current_user, :map, default: nil
  attr :notice, :string, default: nil
  attr :reply, :string, default: nil, doc: "the id of the comment a reply form is open under"
  attr :edit, :string, default: nil, doc: "the id of the comment being edited"

  def comments(assigns) do
    top = Enum.filter(assigns.comments, &is_nil(&1.parent_id))
    visible = MapSet.new(top, & &1.id)

    replies =
      assigns.comments
      |> Enum.filter(&(&1.parent_id in visible))
      |> Enum.group_by(& &1.parent_id)

    assigns =
      assign(assigns,
        top: top,
        replies: replies,
        shown: length(top) + Enum.sum(Enum.map(replies, fn {_, list} -> length(list) end)),
        can_comment?: not is_nil(assigns.current_user) and not is_nil(assigns.current_user.email_verified_at)
      )

    ~H"""
    <section id="comments" class="mt-10 pt-6 border-t border-gray-700">
      <h2 class="text-xl font-semibold text-white mb-4">
        Comments <span class="text-gray-400 text-base">(<%= @shown %>)</span>
      </h2>

      <p :if={@top == []} class="text-gray-400 mb-6">No comments yet.</p>

      <ol class="space-y-4 mb-8">
        <li :for={comment <- @top} id={"comment-#{comment.id}"}>
          <.entry comment={comment} current_user={@current_user} can_comment?={@can_comment?} edit={@edit} />

          <ol :if={@replies[comment.id]} class="mt-3 ml-6 space-y-3 border-l border-gray-700 pl-4">
            <li :for={child <- @replies[comment.id]} id={"comment-#{child.id}"}>
              <.entry comment={child} current_user={@current_user} can_comment?={@can_comment?} edit={@edit} reply_target={comment.id} />
            </li>
          </ol>

          <form :if={@reply == comment.id and @can_comment?} id="reply-form" phx-submit="post_comment" class="mt-3 ml-6 space-y-2">
            <input type="hidden" name="parent_id" value={comment.id} />
            <textarea name="comment" rows="3" maxlength="2000" required placeholder="Write a reply..." class="w-full p-3 rounded bg-gray-900 text-white border border-gray-700"></textarea>
            <div class="flex gap-2">
              <button type="submit" class="px-3 py-1 rounded bg-cyan-600 text-white hover:bg-cyan-500 text-sm">Reply</button>
              <button type="button" phx-click="cancel_reply" class="px-3 py-1 rounded bg-gray-700 text-gray-200 hover:bg-gray-600 text-sm">Cancel</button>
            </div>
          </form>
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

  attr :comment, :map, required: true
  attr :current_user, :map, default: nil
  attr :can_comment?, :boolean, default: false
  attr :edit, :string, default: nil
  attr :reply_target, :string, default: nil, doc: "for a reply: the comment a reply to it goes under"

  defp entry(assigns) do
    assigns = assign(assigns, own?: assigns.current_user != nil and assigns.comment.user_id == assigns.current_user.id)

    ~H"""
    <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
      <div class="text-sm text-gray-400 mb-1">
        <span class="font-medium text-gray-200"><%= author(@comment) %></span>
        · <%= Calendar.strftime(@comment.inserted_at, "%B %d, %Y") %>
        <span :if={@comment.edited_at} class="text-gray-500">(edited)</span>
        <span :if={!@comment.is_approved} class="ml-1 px-2 py-0.5 rounded-full bg-amber-700/60 text-amber-100 text-xs">Waiting for a moderator. Only you can see it.</span>
      </div>

      <form :if={@edit == @comment.id and @own?} id={"edit-form-#{@comment.id}"} phx-submit="save_comment" class="space-y-2">
        <input type="hidden" name="comment_id" value={@comment.id} />
        <textarea name="comment" rows="3" maxlength="2000" required class="w-full p-3 rounded bg-gray-900 text-white border border-gray-700"><%= @comment.content %></textarea>
        <div class="flex gap-2">
          <button type="submit" class="px-3 py-1 rounded bg-cyan-600 text-white hover:bg-cyan-500 text-sm">Save</button>
          <button type="button" phx-click="cancel_comment_edit" class="px-3 py-1 rounded bg-gray-700 text-gray-200 hover:bg-gray-600 text-sm">Cancel</button>
        </div>
      </form>

      <%!-- Plain text only: HEEx escapes it, and line breaks are kept by the CSS. --%>
      <p :if={not (@edit == @comment.id and @own?)} class="text-gray-200 whitespace-pre-line break-words"><%= @comment.content %></p>

      <div :if={@edit != @comment.id} class="mt-2 flex gap-3 text-xs">
        <button :if={@can_comment? and is_nil(@reply_target)} type="button" phx-click="reply_to" phx-value-id={@comment.id} class="text-cyan-400 hover:underline">Reply</button>
        <button :if={@can_comment? and @reply_target} type="button" phx-click="reply_to" phx-value-id={@reply_target} class="text-cyan-400 hover:underline">Reply</button>
        <button :if={@own?} type="button" phx-click="edit_comment" phx-value-id={@comment.id} class="text-gray-400 hover:underline">Edit</button>
        <button :if={@own?} type="button" phx-click="delete_comment" phx-value-id={@comment.id} data-confirm="Delete this comment?" class="text-red-400 hover:underline">Delete</button>
      </div>
    </div>
    """
  end

  defp author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp author(%{author_name: name}) when is_binary(name) and name != "", do: name
  defp author(_), do: "A member"
end
