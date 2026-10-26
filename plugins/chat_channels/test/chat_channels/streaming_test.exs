defmodule ChatChannels.StreamingTest do
  # Voice, video and stream channels, and the streaming sessions that go with them.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures

  alias ChatChannels.StreamingSession

  setup do
    settle_on_exit()
    :ok
  end

  describe "channel types" do
    test "text, voice, video and stream are accepted; anything else is not" do
      for type <- ~w(text voice video stream) do
        assert {:ok, %{channel_type: ^type}} = ChatChannels.create_channel(%{name: "#{type}-#{System.unique_integer([:positive])}", channel_type: type})
      end

      assert {:error, cs} = ChatChannels.create_channel(%{name: "bad-#{System.unique_integer([:positive])}", channel_type: "hologram"})
      assert %{channel_type: [_]} = errors_on(cs)
    end

    test "a member creating a voice channel is bound by the same allowance" do
      u = user_with_allowance(1)
      assert {:ok, %{channel_type: "voice"}} = ChatChannels.create_user_channel(u, %{"name" => "v-#{u.id}", "channel_type" => "voice"})
      assert {:error, _} = ChatChannels.create_user_channel(u, %{"name" => "v2-#{u.id}", "channel_type" => "video"})
    end
  end

  describe "streaming sessions" do
    setup do
      streamer = user()
      channel = channel_fixture(%{name: "live-#{System.unique_integer([:positive])}", channel_type: "stream"})
      Phoenix.PubSub.subscribe(Bacon8.PubSub, "channel:#{channel.id}")
      %{streamer: streamer, channel: channel}
    end

    defp attrs(channel, streamer, type \\ "video"),
      do: %{channel_id: channel.id, streamer_id: streamer.id, stream_type: type, title: "Live"}

    test "starting one makes it the channel's active stream and tells the channel", %{channel: channel, streamer: streamer} do
      assert {:ok, %StreamingSession{is_active: true, started_at: %DateTime{}} = session} =
               ChatChannels.start_stream(attrs(channel, streamer))

      assert_receive {:stream_started, %{id: id}}
      assert id == session.id
      assert ChatChannels.get_active_stream(channel.id).id == session.id
      assert ChatChannels.get_active_stream(channel.id).streamer.id == streamer.id
    end

    test "audio, video and screen are the stream types", %{channel: channel, streamer: streamer} do
      for type <- ~w(audio video screen), do: assert({:ok, _} = ChatChannels.start_stream(attrs(channel, streamer, type)))
      assert {:error, cs} = ChatChannels.start_stream(attrs(channel, streamer, "smell"))
      assert %{stream_type: [_]} = errors_on(cs)
    end

    test "a stream needs a channel, a streamer and a title", %{channel: channel, streamer: streamer} do
      assert {:error, cs} = ChatChannels.start_stream(%{stream_type: "video"})
      assert %{channel_id: _, streamer_id: _, title: _} = errors_on(cs)
      assert {:error, _} = ChatChannels.start_stream(%{attrs(channel, streamer) | title: nil})
    end

    test "ending it deactivates it, stamps the end, and tells the channel", %{channel: channel, streamer: streamer} do
      {:ok, session} = ChatChannels.start_stream(attrs(channel, streamer))

      assert {:ok, %{is_active: false, ended_at: %DateTime{}}} = ChatChannels.end_stream(session.id)
      assert_receive :stream_ended
      assert ChatChannels.get_active_stream(channel.id) == nil
    end

    test "ending one that doesn't exist is an error, not a crash" do
      assert {:error, :not_found} = ChatChannels.end_stream(Ecto.UUID.generate())
    end

    test "the viewer count can be updated", %{channel: channel, streamer: streamer} do
      {:ok, session} = ChatChannels.start_stream(attrs(channel, streamer))
      assert {:ok, %{viewer_count: 12}} = ChatChannels.update_stream_viewer_count(session.id, 12)
      assert {:error, :not_found} = ChatChannels.update_stream_viewer_count(Ecto.UUID.generate(), 1)
    end

    test "deleting the channel removes its sessions", %{channel: channel, streamer: streamer} do
      {:ok, session} = ChatChannels.start_stream(attrs(channel, streamer))
      {:ok, _} = ChatChannels.delete_channel(channel)
      refute Repo.get(StreamingSession, session.id)
    end
  end
end
