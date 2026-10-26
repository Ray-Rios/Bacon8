defmodule Bacon8Web.ProfileAvatarsTest do
  # /profile's previous-avatar buttons send an avatar's URL back from the browser.
  #
  # Review of 2026-10-25 (a second reader, BACON8.md section 14): "delete" handed that URL to
  # Uploads.delete_file/1, which deletes anything under uploads/, so any signed-in member could
  # delete other people's files; "select" saved any string as the avatar. Both now take only a
  # file in the user's own avatar folder.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Accounts.User
  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  # a file in `user`'s avatar folder, where an avatar upload leaves it
  defp avatar_file!(user) do
    dir = Uploads.user_dir(user.id, context: "avatar")
    File.mkdir_p!(dir)
    name = Uploads.unique_filename(".png")
    File.write!(Path.join(dir, name), "png bytes")
    on_exit(fn -> File.rm_rf(Uploads.user_dir(user.id)) end)
    {Uploads.url_path(user.id, "avatar", name), Path.join(dir, name)}
  end

  defp avatar_url(user), do: Repo.get!(User, user.id).avatar_url

  setup do
    me = person("member")
    other = person("member")
    {:ok, view, _html} = live(signed_in(me), "/profile")
    %{me: me, other: other, view: view}
  end

  describe "delete_previous_avatar" do
    test "deletes one of my own avatars", %{me: me, view: view} do
      {url, path} = avatar_file!(me)
      render_hook(view, "delete_previous_avatar", %{"url" => url})
      refute File.exists?(path)
    end

    test "leaves another member's avatar alone", %{other: other, view: view} do
      {url, path} = avatar_file!(other)
      render_hook(view, "delete_previous_avatar", %{"url" => url})
      assert File.exists?(path)
    end

    test "leaves every other upload alone, however the URL is spelt", %{me: me, other: other, view: view} do
      {mine, _} = avatar_file!(me)
      {theirs, their_path} = avatar_file!(other)

      File.mkdir_p!(Uploads.public_dir())
      public = Path.join(Uploads.public_dir(), "profile-test-#{System.unique_integer([:positive])}.txt")
      File.write!(public, "site file")
      on_exit(fn -> File.rm(public) end)

      for url <- [
            "/uploads/public/#{Path.basename(public)}",
            Path.dirname(mine) <> "/../../" <> String.replace_prefix(theirs, "/uploads/", ""),
            mine <> "/../../../public/#{Path.basename(public)}",
            String.replace(theirs, "/uploads/", "/uploads/./"),
            String.replace_prefix(theirs, "/uploads/", "")
          ] do
        render_hook(view, "delete_previous_avatar", %{"url" => url})
      end

      render_hook(view, "delete_previous_avatar", %{"url" => 5})

      assert File.exists?(public)
      assert File.exists?(their_path)
    end
  end

  describe "select_previous_avatar" do
    test "takes only one of my own avatars", %{me: me, other: other, view: view} do
      {mine, _} = avatar_file!(me)
      {theirs, _} = avatar_file!(other)
      before = avatar_url(me)

      for url <- [theirs, "https://example.com/tracker.png", "/uploads/public/anything.png"] do
        render_hook(view, "select_previous_avatar", %{"url" => url})
        assert avatar_url(me) == before, url
      end

      render_hook(view, "select_previous_avatar", %{"url" => mine})
      assert avatar_url(me) == mine
    end
  end
end
