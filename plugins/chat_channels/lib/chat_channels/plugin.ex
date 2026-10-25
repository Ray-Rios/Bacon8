defmodule ChatChannels.Plugin do
  @moduledoc """
  Chat Channels: text, voice, video and stream channels, messages, replies,
  reactions, pins, invites, custom emojis and per-channel membership. It was the
  hub's forum until 2026-10-25 (docs/chat-channels-plugin.md).

  It is a *site* plugin: it mounts at `/chat`, and the hub reaches it only through
  plugin hooks. Games that build things per channel (RaysSpaceSim's Holo-sims)
  declare `requires/0 = ["chat_channels"]`, so the hub refuses to switch chat off
  under them. Bacon Store treats it as optional.

  The tables keep their names (`chat_channels`, `chat_messages`, `channel_members`,
  ...) and are still created by the core baseline migration; moving that DDL here is
  the plan's last phase.
  """
  use Bacon8.Plugin,
    slug: "chat_channels",
    name: "Chat Channels",
    version: "1.0.0",
    description: "Channels, messages, reactions, invites and custom emojis."

  import Ecto.Query, only: [from: 2]

  alias Bacon8.Repo
  alias ChatChannels.{Message, Reaction}

  @impl true
  def mount, do: "chat"

  @impl true
  def routes, do: ChatChannelsWeb.Routes

  # The nav link is the one place the pending-invite count shows (the notification
  # panel no longer lists invites); `badge` is omitted when there is nothing pending.
  @impl true
  def nav_links(nil), do: [%{label: "Chat", path: "/chat", icon: "💬"}]

  def nav_links(%{id: user_id}) do
    item = %{label: "Chat", path: "/chat", icon: "💬"}

    case ChatChannels.count_pending_invites(user_id) do
      n when is_integer(n) and n > 0 -> [Map.put(item, :badge, n)]
      _ -> [item]
    end
  end

  @impl true
  def admin_nav, do: [%{label: "Custom emojis", path: "/admin/chat_channels/custom-emojis", icon: "😀"}]

  # A user was banned or deleted: what they wrote goes with them. Called by the hub
  # inside the account's transaction, so a failure rolls the whole removal back.
  @impl true
  def hub_event({:user_content_removed, user_id}) do
    Repo.delete_all(from(r in Reaction, where: r.user_id == ^user_id))
    Repo.delete_all(from(m in Message, where: m.user_id == ^user_id))
    :ok
  end

  def hub_event(_event), do: :ok
end
