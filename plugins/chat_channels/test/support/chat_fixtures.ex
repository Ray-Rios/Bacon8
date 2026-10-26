defmodule ChatChannels.Fixtures do
  @moduledoc """
  Rows for the forum tests (`test/bacon8/forum/*`).

  Messages are inserted directly with an explicit `inserted_at`: the column is
  whole seconds, so messages created in one test run would otherwise tie and
  come back in no particular order.
  """

  alias Bacon8.Repo
  alias ChatChannels.Message

  def user(attrs \\ %{}), do: Bacon8.DataCase.user_fixture(attrs)

  @doc "A user whose channel allowance is `n`."
  def user_with_allowance(n, attrs \\ %{}) do
    user = user(attrs)
    {:ok, _} = ChatChannels.set_channel_allowance(user.id, n)
    user
  end

  def admin(attrs \\ %{}), do: user(Map.merge(%{role: "admin"}, Map.new(attrs)))

  def channel_fixture(attrs \\ %{}) do
    attrs = Map.merge(%{name: "chan-#{System.unique_integer([:positive])}"}, Map.new(attrs))
    {:ok, channel} = ChatChannels.create_channel(attrs)
    channel
  end

  def member_fixture(channel, user, role \\ "member", extra \\ %{}) do
    {:ok, member} =
      ChatChannels.create_channel_member(
        Map.merge(%{channel_id: channel.id, user_id: user.id, role: role}, Map.new(extra))
      )

    member
  end

  @doc "Inserts a message `seconds_ago` seconds in the past (no rate limit, no side effects)."
  def message_fixture(channel, user, content \\ "hello", seconds_ago \\ 0, extra \\ %{}) do
    at = DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)

    %Message{channel_id: channel.id, user_id: user.id, content: content, inserted_at: at, updated_at: at}
    |> Map.merge(Map.new(extra))
    |> Repo.insert!()
  end

  @doc """
  Gives the forum's fire-and-forget tasks (audit log, mention notifications) a moment to finish
  before the test's database connection is closed under them. Call it from `setup`.
  """
  def settle_on_exit, do: ExUnit.Callbacks.on_exit(fn -> Process.sleep(40) end)

  def past(seconds), do: DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)
  def future(seconds), do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)
end
