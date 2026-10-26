defmodule ChatChannels.ChannelIconsTest do
  # A channel's icon is a path under uploads/ that the plugin deletes: the old file when the icon
  # changes, and the icon's whole folder when the channel goes.
  #
  # Review of 2026-10-25 (a second reader, BACON8.md section 14): the icon was cast from the
  # create form, so a member creating a channel could name any file under uploads/, and deleting
  # that channel removed the named file's folder. Now the server alone sets an icon, it must sit
  # in the channel's own icon folder, and it is checked again before anything is deleted (rows
  # saved before the check may hold anything).
  #
  # Not async: the forum fires audit tasks that need the shared sandbox connection.
  use Bacon8.DataCase, async: false

  import ChatChannels.Fixtures

  alias Bacon8.Uploads
  alias ChatChannels.Channel

  setup do
    settle_on_exit()
    n = System.unique_integer([:positive])

    # stands for everyone else's uploads: nothing below may touch it
    victim_dir = Path.join(Uploads.public_dir(), "icons-test-victim-#{n}")
    File.mkdir_p!(victim_dir)
    victim = Path.join(victim_dir, "keep.txt")
    File.write!(victim, "keep me")
    on_exit(fn -> File.rm_rf(victim_dir) end)

    %{victim: victim, victim_url: "/uploads/public/icons-test-victim-#{n}/keep.txt"}
  end

  defp name, do: "icons-#{System.unique_integer([:positive])}"

  # an icon file where the channel icon upload puts one
  defp icon_file!(uploader, channel) do
    context = "channel_icons/#{channel.id}"
    dir = Uploads.user_dir(uploader.id, context: context)
    File.mkdir_p!(dir)
    file = Uploads.unique_filename(".png")
    File.write!(Path.join(dir, file), "png")
    on_exit(fn -> File.rm_rf(Uploads.user_dir(uploader.id)) end)
    {Uploads.url_path(uploader.id, context, file), Path.join(dir, file)}
  end

  # what a row saved before the check existed may hold
  defp force_icon!(channel, path) do
    {1, _} = Repo.update_all(from(c in Channel, where: c.id == ^channel.id), set: [icon_path: path])
    Repo.get!(Channel, channel.id)
  end

  # deleting a channel cleans its files up in a task
  defp wait_for_cleanup, do: Process.sleep(300)

  describe "setting an icon" do
    test "a member can't name one when creating a channel", %{victim_url: url} do
      assert {:ok, channel} = ChatChannels.create_user_channel(user(), %{"name" => name(), "icon_path" => url})
      assert channel.icon_path == nil
    end

    test "nor can staff, through the admin form", %{victim_url: url} do
      assert {:ok, channel} = ChatChannels.create_channel(%{"name" => name(), "icon_path" => url})
      assert channel.icon_path == nil
    end

    test "a path outside the channel's own icon folder is refused", %{victim_url: url} do
      owner = user()
      channel = channel_fixture(owner_id: owner.id)
      {other_channels_icon, _} = icon_file!(owner, channel_fixture())

      for path <- [
            url,
            other_channels_icon,
            "/uploads/_drive/channel_icons/#{channel.id}/x",
            "/uploads/#{owner.id}/channel_icons/#{channel.id}/../../../public/x.png",
            "/uploads/#{owner.id}/channel_icons/#{channel.id}/a/b.png",
            "/uploads/../channel_icons/#{channel.id}/x.png",
            "https://example.com/i.png",
            ""
          ] do
        assert {:error, cs} = ChatChannels.update_channel(channel, %{icon_path: path}), path
        assert %{icon_path: [_]} = errors_on(cs)
      end
    end

    test "the channel's own uploaded icon is accepted, and so is none" do
      owner = user()
      channel = channel_fixture(owner_id: owner.id)
      {icon, _} = icon_file!(owner, channel)

      assert {:ok, %{icon_path: ^icon} = channel} = ChatChannels.update_channel(channel, %{icon_path: icon})
      assert {:ok, %{icon_path: nil}} = ChatChannels.update_channel(channel, %{"icon_path" => nil})
    end

    test "other edits leave the icon as it is" do
      owner = user()
      channel = channel_fixture(owner_id: owner.id)
      {icon, path} = icon_file!(owner, channel)
      {:ok, channel} = ChatChannels.update_channel(channel, %{icon_path: icon})

      assert {:ok, %{icon_path: ^icon}} = ChatChannels.update_channel(channel, %{name: name()})
      assert File.exists?(path)
    end
  end

  describe "removing an icon" do
    test "a new icon deletes the old one, when the old one is the channel's own" do
      owner = user()
      channel = channel_fixture(owner_id: owner.id)
      {old, old_path} = icon_file!(owner, channel)
      {new, new_path} = icon_file!(owner, channel)

      {:ok, channel} = ChatChannels.update_channel(channel, %{icon_path: old})
      {:ok, _} = ChatChannels.update_channel(channel, %{icon_path: new})

      refute File.exists?(old_path)
      assert File.exists?(new_path)
    end

    test "a stored icon that points elsewhere is not deleted when the icon changes", %{victim: victim, victim_url: url} do
      channel = channel_fixture() |> force_icon!(url)

      assert {:ok, %{icon_path: nil}} = ChatChannels.update_channel(channel, %{icon_path: nil})
      assert File.exists?(victim)
    end

    test "deleting a channel removes its own icon folder" do
      owner = user()
      channel = channel_fixture(owner_id: owner.id)
      {icon, path} = icon_file!(owner, channel)
      {:ok, channel} = ChatChannels.update_channel(channel, %{icon_path: icon})

      assert {:ok, _} = ChatChannels.delete_channel(channel)
      wait_for_cleanup()
      refute File.exists?(Path.dirname(path))
    end

    test "deleting a channel whose stored icon points elsewhere leaves that folder alone", %{victim: victim, victim_url: url} do
      folder = Path.basename(Path.dirname(url))

      # Every path here points into the test's own folder (or nowhere), so a regression deletes
      # only test files; never add one whose folder is uploads/ itself.
      for path <- [url, "/uploads/public/#{folder}/missing.png", "/uploads/public/x/../#{folder}/keep.txt", "/uploads/../../etc/x"] do
        channel = channel_fixture() |> force_icon!(path)

        assert {:ok, _} = ChatChannels.delete_channel(channel)
        wait_for_cleanup()
        assert File.exists?(victim), path
      end
    end
  end

  describe "Channel.icon_path?/2" do
    test "is true only for a single file in this channel's icon folder" do
      channel = %Channel{id: Ecto.UUID.generate()}
      uploader = Ecto.UUID.generate()
      own = "/uploads/#{uploader}/channel_icons/#{channel.id}/0a1b.png"

      assert Channel.icon_path?(channel, own)

      for path <- [
            nil,
            "",
            "/uploads/#{uploader}/channel_icons/#{Ecto.UUID.generate()}/0a1b.png",
            "/uploads/../channel_icons/#{channel.id}/0a1b.png",
            "/uploads/_drive/channel_icons/#{channel.id}/0a1b.png",
            "/uploads/#{uploader}/channel_icons/#{channel.id}/..",
            "/uploads/#{uploader}/channel_icons/#{channel.id}/",
            "/uploads/#{uploader}/channel_icons/#{channel.id}/a b.png",
            own <> "/x"
          ] do
        refute Channel.icon_path?(channel, path), inspect(path)
      end

      refute Channel.icon_path?(%Channel{id: nil}, own)
    end
  end
end
