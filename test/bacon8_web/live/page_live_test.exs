defmodule Bacon8Web.PageLiveTest do
  # /pages/:slug: who may see a page, and what staff (admins, GMs and editors, the owner's rule
  # of 2026-10-25) can do to it in place. Members and visitors can do nothing to it.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content
  alias Bacon8.Uploads

  @endpoint Bacon8Web.Endpoint

  defp page!(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    {:ok, page} =
      Content.create_page(
        Map.merge(%{title: "Page #{n}", slug: "page-#{n}", content: "<p>Body words #{n}</p>", is_published: true}, Map.new(attrs))
      )

    on_exit(fn -> File.rm_rf(Path.join(Uploads.public_dir(), "pages/#{page.id}")) end)
    page
  end

  # a mount or a handle_params that sends the visitor elsewhere
  defp redirected_to!(result, path) do
    assert {:error, {kind, %{to: ^path}}} = result
    assert kind in [:redirect, :live_redirect]
  end

  describe "who sees a page" do
    test "anyone sees a published page, with its words" do
      page = page!()
      {:ok, _view, html} = live(build_conn(), "/pages/#{page.slug}")

      assert html =~ page.title
      assert html =~ "Body words"
    end

    test "a draft is hidden from visitors and members: they are sent home" do
      page = page!(%{is_published: false})

      redirected_to!(live(build_conn(), "/pages/#{page.slug}"), "/")
      redirected_to!(live(signed_in(person("member")), "/pages/#{page.slug}"), "/")
    end

    test "a draft is open to staff, the roles that may edit it" do
      page = page!(%{is_published: false})

      for role <- staff_roles() do
        assert {:ok, _view, html} = live(signed_in(person(role)), "/pages/#{page.slug}")
        assert html =~ page.title, "#{role} could not open the draft"
      end
    end

    test "a page that doesn't exist sends the visitor home" do
      redirected_to!(live(build_conn(), "/pages/no-such-page"), "/")
    end
  end

  describe "the edit button" do
    test "is for staff" do
      page = page!()

      for role <- staff_roles() do
        {:ok, _view, html} = live(signed_in(person(role)), "/pages/#{page.slug}")
        assert html =~ "Edit Page", "no button for #{role}"
      end
    end

    test "is not for members or visitors" do
      page = page!()

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, _view, html} = live(conn, "/pages/#{page.slug}")
        refute html =~ "Edit Page"
      end
    end
  end

  describe "editing in place" do
    test "staff switch editing on and off" do
      page = page!()

      for role <- staff_roles() do
        {:ok, view, _} = live(signed_in(person(role)), "/pages/#{page.slug}")
        refute assigns(view).editing

        render_click(view, "toggle_edit")
        assert assigns(view).editing, "#{role} could not start editing"

        render_click(view, "toggle_edit")
        refute assigns(view).editing
      end
    end

    test "a member or visitor who tries is told no, and the page isn't editing" do
      page = page!()

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, view, _} = live(conn, "/pages/#{page.slug}")
        html = render_click(view, "toggle_edit")

        assert html =~ "permission"
        refute assigns(view).editing
      end
    end

    test "renaming a page keeps its address (the old links keep working)" do
      page = page!(%{slug: "stays-put-#{System.unique_integer([:positive])}"})
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}")

      render_click(view, "update_title", %{"value" => "A Brand New Name"})

      reloaded = Content.get_page!(page.id)
      assert reloaded.title == "A Brand New Name"
      assert reloaded.slug == page.slug
      assert {:ok, _view, html} = live(build_conn(), "/pages/#{page.slug}")
      assert html =~ "A Brand New Name"
    end

    test "a member's or visitor's title edit changes nothing" do
      page = page!()

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, view, _} = live(conn, "/pages/#{page.slug}")
        render_click(view, "update_title", %{"value" => "Hijacked"})
        assert Content.get_page!(page.id).title == page.title
      end
    end

    test "autosave stores the content, but only while editing" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}")

      render_click(view, "editor-autosave", %{"content" => "<p>Too early</p>"})
      assert Content.get_page!(page.id).content == page.content

      render_click(view, "toggle_edit")
      render_click(view, "editor-autosave", %{"content" => "<p>Saved while editing</p>"})

      assert Content.get_page!(page.id).content == "<p>Saved while editing</p>"
      assert_push_event(view, "content-saved", %{})
      assert assigns(view).last_saved
    end

    test "a member's autosave changes nothing, even if they got editing switched on somehow" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("member")), "/pages/#{page.slug}")

      render_click(view, "editor-autosave", %{"content" => "<p>Defaced</p>"})
      assert Content.get_page!(page.id).content == page.content
    end

    test "save & exit leaves editing, and cancel leaves it too" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("gm")), "/pages/#{page.slug}")

      render_click(view, "toggle_edit")
      assert render_click(view, "save_content") =~ "saved"
      refute assigns(view).editing

      render_click(view, "toggle_edit")
      assert render_click(view, "cancel_edit") =~ "discarded"
      refute assigns(view).editing
    end

    test "saving without editing does nothing" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}")

      render_click(view, "save_content")
      refute assigns(view).editing
    end
  end

  describe "media dropped into the editor" do
    defp drop(view, name, extra \\ %{}) do
      render_click(
        view,
        "block-media-upload",
        Map.merge(%{"blockId" => "b1", "mediaType" => "file", "data" => Base.encode64("hi there"), "filename" => name, "mimeType" => "text/plain"}, extra)
      )
    end

    test "goes in the page's own folder, and the editor is told where" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}")

      drop(view, "notes.txt")

      assert_push_event(view, "block-media-uploaded", %{blockId: "b1", url: url, filename: "notes.txt", mediaType: "file"})
      assert String.starts_with?(url, "/uploads/public/pages/#{page.id}/")
      assert File.read!(Uploads.url_to_path(url)) == "hi there"
    end

    test "a file name that climbs out is cut down and stays in the folder" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("admin")), "/pages/#{page.slug}")

      drop(view, "../../../../tmp/evil.txt")

      assert_push_event(view, "block-media-uploaded", %{url: url, filename: "evil.txt"})
      assert String.starts_with?(url, "/uploads/public/pages/#{page.id}/")
      refute File.exists?("/tmp/evil.txt")
    end

    test "a broken upload is reported to the editor, and the page carries on" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}")

      drop(view, "a.txt", %{"data" => "%%not base64%%"})
      assert_push_event(view, "block-media-error", %{blockId: "b1", error: "Invalid file data"})

      drop(view, "..")
      assert_push_event(view, "block-media-error", %{blockId: "b1", error: "Invalid file name"})

      # an event with no data at all is ignored rather than crashing the page
      render_click(view, "block-media-upload", %{"blockId" => "b1", "mediaType" => "file"})
      assert Process.alive?(view.pid)
    end

    test "members and visitors can't upload" do
      page = page!()

      for conn <- [build_conn(), signed_in(person("member"))] do
        {:ok, view, _} = live(conn, "/pages/#{page.slug}")
        drop(view, "sneaky.txt")
        refute File.exists?(Path.join(Uploads.public_dir(), "pages/#{page.id}")), "an upload got through"
      end
    end

    test "removing deletes the page's own file, and nothing outside it" do
      page = page!()
      {:ok, view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}")
      drop(view, "mine.txt")
      assert_push_event(view, "block-media-uploaded", %{url: url})
      mine = Uploads.url_to_path(url)

      File.mkdir_p!(Uploads.base_dir())
      canary = Path.join(Uploads.base_dir(), "canary-#{System.unique_integer([:positive])}.txt")
      File.write!(canary, "keep")
      on_exit(fn -> File.rm(canary) end)

      render_click(view, "block-media-remove", %{"blockId" => "b1", "url" => "/uploads/public/../#{Path.basename(canary)}"})
      render_click(view, "block-media-remove", %{"blockId" => "b1", "url" => "/uploads/public/pages/#{page.id}/../../../#{Path.basename(canary)}"})
      assert File.exists?(canary)
      assert File.exists?(mine)

      render_click(view, "block-media-remove", %{"blockId" => "b1", "url" => url})
      refute File.exists?(mine)
    end

    test "a member's removal does nothing" do
      page = page!()
      {:ok, editor_view, _} = live(signed_in(person("editor")), "/pages/#{page.slug}")
      drop(editor_view, "mine.txt")
      assert_push_event(editor_view, "block-media-uploaded", %{url: url})

      {:ok, view, _} = live(signed_in(person("member")), "/pages/#{page.slug}")
      render_click(view, "block-media-remove", %{"blockId" => "b1", "url" => url})
      assert File.exists?(Uploads.url_to_path(url))
    end
  end
end
