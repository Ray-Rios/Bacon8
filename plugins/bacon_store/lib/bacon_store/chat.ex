defmodule BaconStore.Chat do
  @moduledoc """
  The store's view of Chat Channels, which is optional: a site can sell downloads and
  Gems without chat, and delete `plugins/chat_channels` without breaking this plugin's
  build. Channel passes and channel slots (product kinds that need chat) use these
  functions instead of calling `ChatChannels` directly.

  Chat is looked up when called, so there is no compile-time dependency. It counts as
  available when it is *installed*, active or not: a purchase made while an admin has
  chat switched off still has to leave the membership right (BACON8.md §9: a plugin's
  data stays consistent either way).
  """
  import Ecto.Query, only: [from: 2]

  alias Bacon8.Repo

  @chat Module.concat([ChatChannels])

  @doc "True when the chat_channels plugin is installed."
  def available?, do: Code.ensure_loaded?(@chat)

  @doc "Adds `n` (negative to take away) to a user's channel allowance; nothing happens without chat."
  def add_channel_allowance(user_id, n), do: call(:add_channel_allowance, [user_id, n], {:ok, nil})

  @doc "A user's membership row in a channel, or nil."
  def get_member(channel_id, user_id), do: call(:get_channel_member, [channel_id, user_id], nil)

  @doc "True when the user is a member of the channel."
  def member?(channel_id, user_id), do: call(:is_channel_member?, [channel_id, user_id], false)

  @doc "Adds a member (`%{channel_id, user_id, role}`)."
  def add_member(attrs), do: call(:create_channel_member, [attrs], {:error, :chat_unavailable})

  @doc "Removes a member (also tells running games, as chat does for a kick)."
  def remove_member(channel_id, user_id), do: call(:remove_channel_member, [channel_id, user_id], {:error, :chat_unavailable})

  @doc "Private channels, the ones an access pass can sell: `[%{id, name}]`. Empty without chat."
  def private_channels do
    if available?() do
      Repo.all(
        from c in "chat_channels",
          where: c.is_private == true,
          order_by: [asc: c.name],
          select: %{id: type(c.id, Ecto.UUID), name: c.name}
      )
    else
      []
    end
  end

  @doc "A channel's name, or nil."
  def channel_name(id) do
    with true <- available?(),
         {:ok, uuid} <- Ecto.UUID.cast(id) do
      Repo.one(from c in "chat_channels", where: c.id == type(^uuid, Ecto.UUID), select: c.name)
    else
      _ -> nil
    end
  end

  defp call(fun, args, default) do
    if available?(), do: apply(@chat, fun, args), else: default
  end
end
