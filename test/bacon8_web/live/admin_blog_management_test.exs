defmodule Bacon8Web.AdminBlogManagementTest do
  # /admin/blog-management: where posts are written, published and removed.
  use Bacon8.DataCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Content.Post
  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  defp title, do: "Admin test post #{System.unique_integer([:positive])}"

  describe "who gets in" do
    test "visitors are sent to log in" do
      assert {:error, {kind, %{to: "/login"}}} = live(build_conn(), "/admin/blog-management")
      assert kind in [:redirect, :live_redirect]
    end

    # GMs and editors may open the content area of the admin (Bacon8.Permissions), and nothing
    # else in it; test/bacon8_web/live/admin_access_test.exs holds the proof of the "nothing".
    test "members are sent home" do
      assert {:error, {kind, %{to: "/"}}} = live(signed_in(person("member")), "/admin/blog-management")
      assert kind in [:redirect, :live_redirect]
    end

    test "GMs and editors get in" do
      for role <- ~w(gm editor) do
        assert {:ok, _view, _html} = live(signed_in(person(role)), "/admin/blog-management")
      end
    end

    test "admins get in" do
      assert {:ok, _view, _html} = live(signed_in(person("admin")), "/admin/blog-management")
    end
  end

  describe "starting a post" do
    test "New post makes an untitled draft by the admin and opens it on the post itself" do
      admin = person("admin")
      {:ok, view, _html} = live(signed_in(admin), "/admin/blog-management")

      assert {:error, {:live_redirect, %{to: to}}} = render_click(view, "new_post")

      [post] = Repo.all(from p in Post, where: p.title == "Untitled", preload: :user)
      refute post.is_published
      assert post.user.id == admin.id
      assert to == "/blog/#{post.slug}?edit=1"
    end

    test "the post shows up in the list, with a link to edit it where it lives" do
      t = title()
      {:ok, post} = Content.create_post(person("admin"), %{title: t, content: "<p>x</p>"})
      {:ok, _view, html} = live(signed_in(person("gm")), "/admin/blog-management")

      assert html =~ t
      assert html =~ ~s(href="/blog/#{post.slug}?edit=1")
      refute html =~ ~s(id="blog-post-form")
    end
  end

  describe "changing a post" do
    setup do
      admin = person("admin")
      {:ok, post} = Content.create_post(admin, %{title: title(), slug: "change-#{System.unique_integer([:positive])}", content: "<p>old</p>", is_published: true})
      {:ok, view, _} = live(signed_in(admin), "/admin/blog-management")
      on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "blog/#{post.id}")) end)
      %{view: view, post: post}
    end

    test "the publish switch flips it", %{view: view, post: post} do
      assert render_click(view, "toggle_publish", %{"id" => post.id}) =~ "unpublished"
      refute Content.get_post!(post.id).is_published

      assert render_click(view, "toggle_publish", %{"id" => post.id}) =~ "published successfully"
      assert Content.get_post!(post.id).is_published
    end

    test "a post without a body can't be switched on", %{view: view, post: post} do
      {:ok, bare} = Content.update_post(post, %{is_published: false, content: ""})

      html = render_click(view, "toggle_publish", %{"id" => bare.id})

      assert html =~ "Cannot publish: Post must have a title and content"
      refute Content.get_post!(post.id).is_published
    end

    test "deleting removes the post and what was uploaded for it", %{view: view, post: post} do
      folder = Path.join(Uploads.public_dir(), "blog/#{post.id}")
      File.mkdir_p!(folder)
      File.write!(Path.join(folder, "pic.txt"), "x")

      html = render_click(view, "delete_post", %{"id" => post.id})

      assert html =~ "Post deleted successfully"
      assert Repo.get(Post, post.id) == nil
      refute File.exists?(folder)
    end

    test "a draft can be given a time to go live", %{view: view, post: post} do
      {:ok, draft} = Content.update_post(post, %{is_published: false})

      html = render_submit(view, "set_schedule", %{"record_id" => draft.id, "scheduled_at" => "2031-10-27T09:30"})

      assert html =~ "Goes live"
      assert Content.get_post!(post.id).scheduled_at == ~U[2031-10-27 09:30:00Z]
      assert render_submit(view, "set_schedule", %{"record_id" => draft.id, "scheduled_at" => "2001-01-01T00:00"}) =~ "has passed"
    end

    test "an id that isn't a post is answered, not a crash", %{view: view} do
      render_click(view, "delete_post", %{"id" => "nonsense"})
      render_click(view, "toggle_publish", %{"id" => Ecto.UUID.generate()})
      assert Process.alive?(view.pid)
    end

    test "events the page doesn't know are ignored", %{view: view} do
      render_hook(view, "update_window_position", %{"x" => 1})
      assert Process.alive?(view.pid)
    end
  end
end
