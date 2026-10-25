defmodule Bacon8Web.AdminBlogManagementTest do
  # /admin/blog-management: where posts are written, published and removed.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Content.Post
  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  defp save(view, params, action) do
    render_submit(view, "save", %{"post" => params, "action_type" => action})
  end

  defp title, do: "Admin test post #{System.unique_integer([:positive])}"

  describe "who gets in" do
    test "visitors are sent to log in" do
      assert {:error, {kind, %{to: "/login"}}} = live(build_conn(), "/admin/blog-management")
      assert kind in [:redirect, :live_redirect]
    end

    # As for pages: GMs and editors write in place on the public blog; this page is for admins.
    test "members, GMs and editors are sent home" do
      for role <- ~w(member gm editor) do
        assert {:error, {kind, %{to: "/"}}} = live(signed_in(person(role)), "/admin/blog-management")
        assert kind in [:redirect, :live_redirect]
      end
    end

    test "admins get in" do
      assert {:ok, _view, _html} = live(signed_in(person("admin")), "/admin/blog-management")
    end
  end

  describe "writing a post" do
    setup do
      admin = person("admin")
      {:ok, view, _} = live(signed_in(admin), "/admin/blog-management")
      render_click(view, "new_post")
      %{view: view, admin: admin}
    end

    test "a draft belongs to its author and stays unpublished", %{view: view, admin: admin} do
      t = title()
      html = save(view, %{"title" => t, "content" => "<p>words</p>"}, "draft")

      assert html =~ "Draft saved"
      post = Repo.get_by!(Post, title: t) |> Repo.preload(:user)
      assert post.user.id == admin.id
      refute post.is_published
      assert post.published_at == nil
    end

    test "publishing needs a title and a body, and says so", %{view: view} do
      html = save(view, %{"title" => "", "content" => "<p>words</p>"}, "publish")
      assert html =~ "Cannot publish: Post must have a title and content"

      html = save(view, %{"title" => title(), "content" => "  "}, "publish")
      assert html =~ "Cannot publish: Post must have a title and content"

      assert Repo.aggregate(Post, :count) == 0
    end

    test "publishing stamps it", %{view: view} do
      t = title()
      html = save(view, %{"title" => t, "content" => "<p>words</p>"}, "publish")

      assert html =~ "published successfully"
      post = Repo.get_by!(Post, title: t)
      assert post.is_published
      assert %DateTime{} = post.published_at
    end

    test "tags typed as a comma list become a list", %{view: view} do
      t = title()
      save(view, %{"title" => t, "content" => "<p>x</p>", "tags" => " elixir, , phoenix ,news "}, "draft")

      assert Repo.get_by!(Post, title: t).tags == ["elixir", "phoenix", "news"]
    end

    test "a draft with no body saves (it can be finished later)", %{view: view} do
      t = title()
      save(view, %{"title" => t, "content" => ""}, "draft")

      assert %Post{content: ""} = Repo.get_by!(Post, title: t)
    end

    test "autosave makes one draft, then keeps updating that one", %{view: view} do
      t = title()
      render_hook(view, "autosave_draft", %{"post" => %{"title" => t, "content" => "<p>one</p>"}})
      render_hook(view, "autosave_draft", %{"post" => %{"title" => t, "content" => "<p>two</p>"}})

      assert [post] = Repo.all(from p in Post, where: p.title == ^t)
      assert post.content == "<p>two</p>"
      refute post.is_published
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

    test "editing keeps the address when the title changes", %{view: view, post: post} do
      render_click(view, "edit_post", %{"id" => post.id})
      save(view, %{"title" => "Renamed #{post.id}", "content" => "<p>new</p>", "slug" => post.slug}, "publish")

      reloaded = Content.get_post!(post.id)
      assert reloaded.title == "Renamed #{post.id}"
      assert reloaded.slug == post.slug
      assert reloaded.is_published
    end

    test "saving a published post as a draft takes it off the blog", %{view: view, post: post} do
      render_click(view, "edit_post", %{"id" => post.id})
      save(view, %{"title" => post.title, "content" => post.content, "slug" => post.slug}, "draft")

      refute Content.get_post!(post.id).is_published
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

    test "events the page doesn't know are ignored", %{view: view} do
      render_hook(view, "update_window_position", %{"x" => 1})
      assert Process.alive?(view.pid)
    end
  end
end
