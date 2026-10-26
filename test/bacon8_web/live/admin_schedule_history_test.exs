defmodule Bacon8Web.AdminScheduleHistoryTest do
  # The schedule box and the list of earlier versions in the two admin editors.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Content.Revisions

  @endpoint Bacon8Web.Endpoint

  describe "pages" do
    setup do
      {:ok, page} = Content.create_page(%{title: "History page", slug: "history-page", content: "<p>one</p>"})
      {:ok, edited} = Content.update_page(page, %{content: "<p>two</p>"})
      {:ok, view, _} = live(signed_in(person("editor")), "/admin/pages")
      %{page: edited, view: view}
    end

    test "saving a draft with a time schedules it, and the list says so", %{page: page, view: view} do
      render_click(view, "edit_page", %{"id" => page.id})

      html =
        render_submit(view, "save", %{
          "page" => %{"title" => "History page", "content" => "<p>two</p>", "scheduled_at" => "2031-10-27T09:30"},
          "action_type" => "draft"
        })

      assert html =~ "Goes live"
      assert Content.get_page!(page.id).scheduled_at == ~U[2031-10-27 09:30:00Z]
      refute Content.get_page!(page.id).is_published
    end

    test "publishing now clears the time", %{page: page, view: view} do
      {:ok, _} = Content.update_page(page, %{scheduled_at: ~U[2031-10-27 09:30:00Z]})
      render_click(view, "edit_page", %{"id" => page.id})

      render_submit(view, "save", %{"page" => %{"title" => "History page", "content" => "<p>two</p>"}, "action_type" => "publish"})

      published = Content.get_page!(page.id)
      assert published.is_published
      assert is_nil(published.scheduled_at)
    end

    test "the editor lists earlier versions and restores one", %{page: page, view: view} do
      html = render_click(view, "edit_page", %{"id" => page.id})
      assert html =~ "Earlier versions"

      [rev] = Revisions.list(:page, page.id)
      html = view |> element("#revision-#{rev.id} button") |> render_click()

      assert html =~ "Earlier version restored"
      assert Content.get_page!(page.id).content == "<p>one</p>"
    end

    test "a saved draft can be previewed by staff, and not by the public", %{page: page, view: view} do
      html = render_click(view, "edit_page", %{"id" => page.id})
      assert html =~ ~s(id="preview-link")
      assert html =~ "/pages/history-page"

      {:ok, _view, shown} = live(signed_in(person("editor")), "/pages/history-page")
      assert shown =~ "two"
      assert {:error, _} = live(build_conn(), "/pages/history-page")
    end

    test "a version that isn't this page's is refused", %{page: page, view: view} do
      render_click(view, "edit_page", %{"id" => page.id})
      html = render_hook(view, "restore_revision", %{"id" => Ecto.UUID.generate()})

      assert html =~ "no longer there"
      assert Content.get_page!(page.id).content == "<p>two</p>"
    end
  end

  describe "posts" do
    setup do
      {:ok, post} = Content.create_post(person("admin"), %{title: "History post", content: "<p>one</p>"})
      {:ok, edited} = Content.update_post(post, %{content: "<p>two</p>"})
      {:ok, view, _} = live(signed_in(person("gm")), "/admin/blog-management")
      %{post: edited, view: view}
    end

    test "a draft with a time shows when it goes live", %{post: post, view: view} do
      render_click(view, "edit_post", %{"id" => post.id})

      html =
        render_submit(view, "save", %{
          "post" => %{"title" => "History post", "content" => "<p>two</p>", "scheduled_at" => "2031-10-27T09:30"},
          "action_type" => "draft"
        })

      assert html =~ "Goes live"
      assert Content.get_post!(post.id).scheduled_at == ~U[2031-10-27 09:30:00Z]
    end

    test "restores an earlier version", %{post: post, view: view} do
      html = render_click(view, "edit_post", %{"id" => post.id})
      assert html =~ "Earlier versions"

      [rev] = Revisions.list(:post, post.id)
      html = view |> element("#revision-#{rev.id} button") |> render_click()

      assert html =~ "Earlier version restored"
      assert Content.get_post!(post.id).content == "<p>one</p>"
    end
  end
end
