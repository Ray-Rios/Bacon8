defmodule ChatChannels.Notices do
  @moduledoc """
  What chat tells the hub's notification system: someone was @mentioned, someone was
  invited. The hub knows nothing about channels: a notification carries a `path` in
  its metadata (where clicking it goes), a `source_kind`/`source_id` (what it came
  from) and the name to show, and the hub's panel renders those.

  Until 2026-10-25 this lived in the core and never worked: it read `actor.username`,
  a field users don't have, inside a fire-and-forget task, so every @mention crashed
  quietly in the log.
  """
  alias Bacon8.{Accounts, Notifications}

  @source_kind "chat_channel"

  @doc "The `source_kind` chat's notifications carry."
  def source_kind, do: @source_kind

  @doc """
  Usernames mentioned in a message (`@name`, letters, digits, `_` and `-`), once each. An `@`
  inside a word is not a mention: `bob@example.com` mentions nobody.
  """
  def extract_mentions(content) when is_binary(content) do
    ~r/(?<![A-Za-z0-9_.+-])@([a-zA-Z0-9_-]+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  def extract_mentions(_), do: []

  @doc """
  Notifies every user @mentioned in the message (never the author). Returns the
  notifications created. Mentions of names nobody has are ignored.
  """
  def mentions(%{content: content} = message, actor) do
    case extract_mentions(content) do
      [] ->
        {:ok, []}

      names ->
        channel = ChatChannels.get_channel(message.channel_id)

        notifications =
          for user <- Accounts.get_users_by_usernames(names),
              user.id != actor.id,
              {:ok, n} <- [mention(user, message, actor, channel)],
              do: n

        {:ok, notifications}
    end
  end

  defp mention(user, message, actor, channel) do
    name = channel && channel.name

    Notifications.create_notification(%{
      type: "mention",
      title: "#{display_name(actor)} mentioned you",
      content: truncate(message.content, 100),
      user_id: user.id,
      actor_id: actor.id,
      resource_type: "message",
      resource_id: message.id,
      source_kind: @source_kind,
      source_id: message.channel_id,
      metadata: %{
        source_name: name,
        path: "/chat/#{message.channel_id}",
        message_preview: truncate(message.content, 200)
      }
    })
  end

  @doc "Notifies the person a personal invite names. `invite` needs `:channel` and `:inviter` loaded."
  def invite(%{invitee_id: nil}), do: {:ok, nil}

  def invite(invite) do
    channel = invite.channel
    inviter = invite.inviter

    Notifications.create_notification(%{
      type: "invite",
      title: "#{display_name(inviter)} invited you to ##{channel.name}",
      content: truncate(channel.description, 100),
      user_id: invite.invitee_id,
      actor_id: invite.inviter_id,
      resource_type: "channel_invite",
      resource_id: invite.id,
      source_kind: @source_kind,
      source_id: channel.id,
      metadata: %{source_name: channel.name, path: "/chat"}
    })
  end

  defp display_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{email: email}) when is_binary(email), do: email
  defp display_name(_), do: "Someone"

  defp truncate(nil, _), do: ""
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."
end
