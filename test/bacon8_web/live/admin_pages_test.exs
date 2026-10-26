defmodule Bacon8Web.AdminPagesTest do
  # /admin/pages: where pages are made, published and removed.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Content.Page
  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  defp save(view, params, action) do
    render_submit(view, "save", %{"page" => params, "action_type" => action})
  end

  defp title, do: "Admin test page #{System.unique_integer([:positive])}"

  describe "who gets in" do
    test "visitors are sent to log in" do
      assert {:error, {kind, %{to: "/login"}}} = live(build_conn(), "/admin/pages")
      assert kind in [:redirect, :live_redirect]
    end

    # GMs and editors may open the content area of the admin (Bacon8.Permissions), and nothing
    # else in it; test/bacon8_web/live/admin_access_test.exs holds the proof of the "nothing".
    test "members are sent home" do
      assert {:error, {kind, %{to: "/"}}} = live(signed_in(person("member")), "/admin/pages")
      assert kind in [:redirect, :live_redirect]
    end

    test "GMs and editors get in" do
      for role <- ~w(gm editor) do
        assert {:ok, _view, _html} = live(signed_in(person(role)), "/admin/pages")
      end
    end

    test "admins get in" do
      assert {:ok, _view, html} = live(signed_in(person("admin")), "/admin/pages")
      assert html =~ "Pages"
    end
  end

  describe "making a page" do
    setup do
      {:ok, view, _html} = live(signed_in(person("admin")), "/admin/pages")
      render_click(view, "new_page")
      %{view: view}
    end

    test "saving as a draft keeps it unpublished", %{view: view} do
      t = title()
      html = save(view, %{"title" => t, "content" => "<p>words</p>"}, "draft")

      assert html =~ "updated"
      page = Repo.get_by!(Page, title: t)
      refute page.is_published
      assert page.published_at == nil
      assert page.slug == t |> String.downcase() |> String.replace(~r/[^a-z0-9\s]/, "") |> String.replace(~r/\s+/, "-")
    end

    test "publishing sets it live, stamped", %{view: view} do
      t = title()
      save(view, %{"title" => t, "content" => "<p>words</p>"}, "publish")

      page = Repo.get_by!(Page, title: t)
      assert page.is_published
      assert %DateTime{} = page.published_at
    end

    test "a page can't be published without a body", %{view: view} do
      t = title()
      html = save(view, %{"title" => t, "content" => ""}, "publish")

      assert html =~ "Failed to update page"
      assert Repo.get_by(Page, title: t) == nil
    end

    test "two pages can't share an address", %{view: view} do
      slug = "taken-#{System.unique_integer([:positive])}"
      {:ok, _} = Content.create_page(%{title: "First", slug: slug, content: "x"})

      html = save(view, %{"title" => title(), "slug" => slug, "content" => "<p>x</p>"}, "draft")

      assert html =~ "Failed to update page"
      assert Repo.aggregate(from(p in Page, where: p.slug == ^slug), :count) == 1
    end

    test "the page shows up in the list", %{view: view} do
      t = title()
      html = save(view, %{"title" => t, "content" => "<p>x</p>"}, "draft")
      assert html =~ t
    end
  end

  describe "changing a page" do
    setup do
      {:ok, page} = Content.create_page(%{title: title(), slug: "change-#{System.unique_integer([:positive])}", content: "<p>old</p>", is_published: true})
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "pages/#{page.id}")) end)
      %{view: view, page: page}
    end

    test "editing keeps the address when the title changes", %{view: view, page: page} do
      render_click(view, "edit_page", %{"id" => page.id})
      save(view, %{"title" => "Renamed #{page.id}", "content" => "<p>new</p>", "slug" => page.slug}, "publish")

      reloaded = Content.get_page!(page.id)
      assert reloaded.title == "Renamed #{page.id}"
      assert reloaded.content == "<p>new</p>"
      assert reloaded.slug == page.slug
      assert reloaded.is_published
    end

    test "saving a published page as a draft unpublishes it", %{view: view, page: page} do
      render_click(view, "edit_page", %{"id" => page.id})
      save(view, %{"title" => page.title, "content" => page.content, "slug" => page.slug}, "draft")

      reloaded = Content.get_page!(page.id)
      refute reloaded.is_published
      assert reloaded.published_at == nil
    end

    test "the publish switch flips it", %{view: view, page: page} do
      render_click(view, "toggle_publish", %{"id" => page.id})
      refute Content.get_page!(page.id).is_published

      render_click(view, "toggle_publish", %{"id" => page.id})
      assert Content.get_page!(page.id).is_published
      assert %DateTime{} = Content.get_page!(page.id).published_at
    end

    test "deleting removes the page and what was uploaded for it", %{view: view, page: page} do
      folder = Path.join(Uploads.public_dir(), "pages/#{page.id}")
      File.mkdir_p!(folder)
      File.write!(Path.join(folder, "pic.txt"), "x")

      html = render_click(view, "delete_page", %{"id" => page.id})

      assert html =~ "Page deleted"
      assert Repo.get(Page, page.id) == nil
      refute File.exists?(folder)
    end

    test "cancelling closes the form without saving", %{view: view, page: page} do
      render_click(view, "edit_page", %{"id" => page.id})
      render_click(view, "cancel_form")

      refute assigns(view).show_form
      assert Content.get_page!(page.id).title == page.title
    end
  end
end
