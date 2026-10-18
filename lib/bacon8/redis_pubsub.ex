defmodule Bacon8.RedisPubSub do
  @moduledoc "Small bridge to publish/subscribe messages via Redis PubSub when ENABLE_REDIS is enabled.
  This module encodes Erlang terms to base64 when publishing, and decodes them when receiving.
  It forwards Redis messages into the local Phoenix.PubSub so LiveViews across pods receive them.
  "
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    if Application.get_env(:bacon8, :enable_redis, false) do
      subscribe_patterns()
      {:ok, %{}}
    else
      {:ok, %{}}
    end
  end

  def publish(topic, term) do
    if Application.get_env(:bacon8, :enable_redis, false) do
      payload = Base.encode64(:erlang.term_to_binary(term))
      case Redix.command(:redix, ["PUBLISH", topic, payload]) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Redis publish failed: #{inspect(reason)}"); {:error, reason}
      end
    else
      :disabled
    end
  end

  defp subscribe_patterns do
    patterns = ["channel:*", "presence:channel:*", "chat:channels"]
    Enum.each(patterns, fn pat ->
      {:ok, _ref} = Redix.PubSub.psubscribe(:redix_pubsub, pat, self())
    end)
  end

  def handle_info({:redix_pubsub, _pubsub, :psubscribe, %{pattern: pat}}, state) do
    Logger.info("Subscribed to Redis pattern: #{pat}")
    {:noreply, state}
  end

  def handle_info({:redix_pubsub, _pubsub, :pmessage, %{pattern: _pat, channel: chan, payload: payload}}, state) do
    # Decode and forward to Phoenix.PubSub
    try do
      term = :erlang.binary_to_term(Base.decode64!(payload))
      Phoenix.PubSub.broadcast(Bacon8.PubSub, chan, term)
    rescue
      e -> Logger.warning("Failed to decode Redis payload for #{chan}: #{inspect(e)}")
    end
    {:noreply, state}
  end

  def handle_info(other, state) do
    Logger.debug("Redis pubsub event: #{inspect(other)}")
    {:noreply, state}
  end
end
