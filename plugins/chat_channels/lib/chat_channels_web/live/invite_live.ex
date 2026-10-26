defmodule ChatChannelsWeb.InviteLive do
  @moduledoc """
  The page an invite link opens (`/chat/invite/:code`, the address `ChatChannels.get_invite_link/1`
  hands out). It shows which channel the code is for and joins only when the person presses the
  button: opening a link (or a link preview fetching it) never changes anything.
  """
  use Bacon8Web, :live_view

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    user = socket.assigns[:current_user]
    invite = ChatChannels.get_invite_by_code(code)

    {:ok, assign(socket, page_title: "Chat invitation", code: code, invite: usable(invite, user), user: user, problem: nil)}
  end

  # Only an invite that could be used shows its channel; anything else looks the same as a wrong code.
  defp usable(nil, _user), do: nil

  defp usable(invite, user) do
    cond do
      invite.is_revoked == true or invite.revoked_at != nil -> nil
      not ChatChannels.ChannelInvite.is_valid?(invite) -> nil
      invite.invitee_id && (is_nil(user) or invite.invitee_id != user.id) -> nil
      true -> invite
    end
  end

  @impl true
  def handle_event("join", _params, %{assigns: %{user: nil}} = socket), do: {:noreply, socket}

  def handle_event("join", _params, socket) do
    %{code: code, user: user, invite: invite} = socket.assigns

    case ChatChannels.use_channel_invite(code, user.id) do
      {:ok, _member} ->
        {:noreply, socket |> put_flash(:info, "You joined #{invite.channel.name}") |> push_navigate(to: "/chat/#{invite.channel_id}")}

      {:error, :already_member} ->
        {:noreply, push_navigate(socket, to: "/chat/#{invite.channel_id}")}

      {:error, _} ->
        {:noreply, assign(socket, invite: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center p-6">
      <div id="invite-card" class="dark-glass border border-cyan-500/30 rounded-xl p-8 max-w-md w-full text-center">
        <%= cond do %>
          <% is_nil(@invite) -> %>
            <h1 class="text-xl font-semibold text-white mb-2">This invitation can't be used</h1>
            <p class="text-gray-400 mb-6">The link may have expired, been used up, or been withdrawn.</p>
            <.link navigate="/chat" class="text-cyan-400 hover:underline">Go to Chat</.link>
          <% is_nil(@user) -> %>
            <h1 class="text-xl font-semibold text-white mb-2">You're invited to <%= @invite.channel.name %></h1>
            <p class="text-gray-400 mb-6">Sign in to accept the invitation.</p>
            <.link navigate="/login" class="text-cyan-400 hover:underline">Sign in</.link>
          <% true -> %>
            <h1 class="text-xl font-semibold text-white mb-2">Join <%= @invite.channel.name %>?</h1>
            <p :if={@invite.channel.description} class="text-gray-400 mb-6"><%= @invite.channel.description %></p>
            <div class="flex gap-3 justify-center mt-6">
              <button id="join-invite" phx-click="join" class="px-4 py-2 rounded bg-cyan-600 text-white hover:bg-cyan-500">Join</button>
              <.link navigate="/chat" class="px-4 py-2 rounded bg-gray-700 text-gray-200 hover:bg-gray-600">Not now</.link>
            </div>
        <% end %>
      </div>
    </div>
    """
  end
end
