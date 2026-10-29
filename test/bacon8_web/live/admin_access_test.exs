defmodule Bacon8Web.AdminAccessTest do
  # GMs and editors may open the content part of /admin (pages and blog) and nothing else.
  # This is the check that a new area never opens a door by accident: every other admin page,
  # core or plugin, must still turn a GM or an editor away, and the menus must show them only
  # what they can open.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  @endpoint Bacon8Web.Endpoint

  @content_routes ["/admin/pages", "/admin/blog-management", "/admin/comments"]

  # Every other admin page: core, then the plugins' (activated below).
  @admin_only_routes [
    "/admin",
    "/admin/projects",
    "/admin/scheduler",
    "/admin/uploads",
    "/admin/user-management",
    "/admin/sql",
    "/admin/security",
    "/admin/emails",
    "/admin/api-toolbox",
    "/admin/plugins",
    "/admin/audit",
    "/admin/bacon_store/products",
    "/admin/bacon_store/orders",
    "/admin/bacon_world",
    "/admin/bacon_world/skills",
    "/admin/chat_channels/custom-emojis"
  ]

  setup do
    for slug <- ~w(bacon_world bacon_store chat_channels), do: {:ok, _} = Bacon8.Plugins.activate(slug)
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  # a page that turned the visitor away (a redirect, or a 404 for a plugin page)
  defp turned_away?(conn, path) do
    case live(conn, path) do
      {:error, {kind, _}} when kind in [:redirect, :live_redirect] -> true
      {:ok, _view, _html} -> false
      other -> flunk("unexpected result for #{path}: #{inspect(other)}")
    end
  rescue
    # a controller-style 404 raised through the test connection
    _ -> true
  end

  describe "the content pages" do
    test "are open to admins, GMs and editors" do
      for role <- staff_roles(), path <- @content_routes do
        assert {:ok, _view, _html} = live(signed_in(person(role)), path), "#{role} was turned away from #{path}"
      end
    end

    test "are not open to members or visitors" do
      for path <- @content_routes do
        assert turned_away?(signed_in(person("member")), path), "a member got into #{path}"
        assert turned_away?(build_conn(), path), "a visitor got into #{path}"
      end
    end

    test "are not open to a banned or suspended staff member" do
      for role <- ~w(gm editor) do
        banned = person(role)
        {:ok, banned} = banned |> Ecto.Changeset.change(status: "suspended") |> Repo.update()

        for path <- @content_routes, do: assert(turned_away?(signed_in(banned), path), "a suspended #{role} got into #{path}")
      end
    end
  end

  describe "everything else in the admin" do
    test "turns GMs, editors and members away" do
      for role <- ~w(gm editor member), path <- @admin_only_routes do
        assert turned_away?(signed_in(person(role)), path), "a #{role} got into #{path}"
      end
    end

    # (This also proves every path in the list exists: a typo would otherwise look like
    # "turned away" in the test above.)
    test "still opens, every one of them, for an admin" do
      for path <- @admin_only_routes do
        assert {:ok, _view, _html} = live(signed_in(person("admin")), path), "an admin was turned away from #{path}"
      end
    end
  end

  describe "what staff see" do
    test "the sidebar of a content page shows the content links and no others" do
      for role <- ~w(gm editor) do
        {:ok, _view, html} = live(signed_in(person(role)), "/admin/pages")

        assert html =~ ~s(href="/admin/pages")
        assert html =~ ~s(href="/admin/blog-management")

        for hidden <- ~w(/admin/user-management /admin/sql /admin/security /admin/emails /admin/plugins /admin/api-toolbox /admin/uploads /admin/scheduler /admin/projects /admin/bacon_store /admin/chat_channels) do
          refute html =~ ~s(href="#{hidden}), "#{role} was shown a link to #{hidden}"
        end

        # the Dashboard link is the admin's (href="/admin" exactly)
        refute html =~ ~s(href="/admin")
      end
    end

    test "an admin's sidebar shows everything" do
      {:ok, _view, html} = live(signed_in(person("admin")), "/admin/pages")

      for shown <- ~w(/admin/user-management /admin/sql /admin/security /admin/plugins /admin/pages /admin/blog-management /admin/uploads) do
        assert html =~ ~s(href="#{shown}"), "no link to #{shown}"
      end

      assert html =~ ~s(href="/admin")
    end

    test "the navbar sends an editor to the pages, and lists only their two links" do
      {:ok, _view, html} = live(signed_in(person("editor")), "/blog")

      assert html =~ ~s(href="/admin/pages")
      assert html =~ ~s(href="/admin/blog-management")
      refute html =~ ~s(href="/admin/user-management")
      refute html =~ ~s(href="/admin/api-toolbox")
      refute html =~ ~s(href="/admin")
    end

    test "the navbar sends an admin to the dashboard with the full menu" do
      {:ok, _view, html} = live(signed_in(person("admin")), "/blog")

      assert html =~ ~s(href="/admin")
      assert html =~ ~s(href="/admin/user-management")
      assert html =~ ~s(href="/admin/api-toolbox")
    end

    test "members and visitors see no admin links at all" do
      for conn <- [signed_in(person("member")), build_conn()] do
        {:ok, _view, html} = live(conn, "/blog")
        refute html =~ ~s(href="/admin"), "an admin link showed"
        refute html =~ ~s(href="/admin/pages")
      end
    end
  end
end
