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

  describe "starting a page" do
    test "New page makes an untitled draft and opens it on the page itself" do
      {:ok, view, _html} = live(signed_in(person("admin")), "/admin/pages")

      assert {:error, {:live_redirect, %{to: to}}} = render_click(view, "new_page")

      [page] = Repo.all(from p in Page, where: p.title == "Untitled")
      refute page.is_published
      assert to == "/pages/#{page.slug}?edit=1"
    end

    test "the page shows up in the list, with a link to edit it where it lives" do
      t = title()
      {:ok, page} = Content.create_page(%{title: t, slug: "listed-#{System.unique_integer([:positive])}", content: "<p>x</p>"})
      {:ok, _view, html} = live(signed_in(person("editor")), "/admin/pages")

      assert html =~ t
      assert html =~ ~s(href="/pages/#{page.slug}?edit=1")
      # (there is no editing form here any more)
      refute html =~ ~s(id="page-form")
    end
  end

  describe "changing a page" do
    setup do
      {:ok, page} = Content.create_page(%{title: title(), slug: "change-#{System.unique_integer([:positive])}", content: "<p>old</p>", is_published: true})
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/pages")
      on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "pages/#{page.id}")) end)
      %{view: view, page: page}
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

    test "a page without a body can't be switched on", %{view: view, page: page} do
      {:ok, bare} = Content.update_page(page, %{is_published: false, content: ""})
      html = render_click(view, "toggle_publish", %{"id" => bare.id})

      assert html =~ "Failed to update publish status"
      refute Content.get_page!(page.id).is_published
    end

    test "a draft can be given a time to go live, and the list says so", %{view: view, page: page} do
      {:ok, draft} = Content.update_page(page, %{is_published: false})

      html = render_submit(view, "set_schedule", %{"record_id" => draft.id, "scheduled_at" => "2031-10-27T09:30"})

      assert html =~ "Goes live"
      assert Content.get_page!(page.id).scheduled_at == ~U[2031-10-27 09:30:00Z]

      render_submit(view, "set_schedule", %{"record_id" => draft.id, "scheduled_at" => ""})
      assert Content.get_page!(page.id).scheduled_at == nil
    end

    test "a time that has passed, a garbage time and a published page are refused", %{view: view, page: page} do
      {:ok, draft} = Content.update_page(page, %{is_published: false})

      assert render_submit(view, "set_schedule", %{"record_id" => draft.id, "scheduled_at" => "2001-01-01T00:00"}) =~ "has passed"
      assert render_submit(view, "set_schedule", %{"record_id" => draft.id, "scheduled_at" => "banana"}) =~ "isn't a time"
      assert Content.get_page!(page.id).scheduled_at == nil

      {:ok, live_page} = Content.update_page(draft, %{is_published: true})
      assert render_submit(view, "set_schedule", %{"record_id" => live_page.id, "scheduled_at" => "2031-10-27T09:30"}) =~ "published already"
    end

    test "an id that isn't a page is answered, not a crash", %{view: view} do
      render_click(view, "delete_page", %{"id" => "nonsense"})
      render_click(view, "toggle_publish", %{"id" => Ecto.UUID.generate()})
      render_submit(view, "set_schedule", %{"record_id" => "nonsense", "scheduled_at" => ""})
      assert Process.alive?(view.pid)
    end
  end
end
