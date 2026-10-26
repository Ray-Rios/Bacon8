defmodule Bacon8Web.CommentsTest do
  # Comments on a post, and the moderation screen.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Content

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, post} = Content.create_post(person("admin"), %{title: "Talk about it", content: "<p>x</p>", is_published: true, published_at: ~U[2026-03-01 10:00:00Z]})
    %{post: post}
  end

  describe "under a post" do
    test "a visitor sees the comments and a sign-in prompt, no form", %{post: post} do
      {:ok, c} = Content.submit_comment(person("gm"), post, "Official word")
      {:ok, _view, html} = live(build_conn(), "/blog/#{post.slug}")

      assert html =~ "Official word"
      assert html =~ c.content
      assert html =~ "to leave a comment"
      refute html =~ ~s(id="comment-form")
    end

    test "a member's first comment is held, with a message, and not shown", %{post: post} do
      {:ok, view, html} = live(signed_in(person("member")), "/blog/#{post.slug}")
      assert html =~ ~s(id="comment-form")

      html = view |> form("#comment-form", %{"comment" => "My first thoughts"}) |> render_submit()

      assert html =~ "once a moderator has checked it"
      refute html =~ "My first thoughts"
      assert Content.count_comments_by_status(:pending) == 1
    end

    test "a staff member's comment appears at once", %{post: post} do
      {:ok, view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")

      html = view |> form("#comment-form", %{"comment" => "hello everyone"}) |> render_submit()

      assert html =~ "hello everyone"
      assert Content.count_comments_by_status(:approved) == 1
    end

    # (checked on the real HTML a browser receives: LiveViewTest's re-serialised HTML doesn't show escaping)
    test "comment text is escaped, never markup", %{post: post} do
      {:ok, _} = Content.create_comment(%{content: "<script>alert(1)</script> hello", post_id: post.id, is_approved: true})

      html = build_conn() |> get("/blog/#{post.slug}") |> html_response(200)

      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt; hello"
      refute html =~ "<script>alert(1)"
    end

    test "spam and pending comments don't show to others", %{post: post} do
      member = person("member")
      {:ok, held} = Content.submit_comment(member, post, "held back")
      {:ok, _} = Content.mark_spam(held)

      {:ok, _view, html} = live(build_conn(), "/blog/#{post.slug}")
      refute html =~ "held back"
    end

    test "a member who is over the hourly limit is told so", %{post: post} do
      {:ok, view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")

      for n <- 1..Bacon8.Content.Moderation.rate_limit() do
        view |> form("#comment-form", %{"comment" => "c#{n}"}) |> render_submit()
      end

      html = view |> form("#comment-form", %{"comment" => "one more"}) |> render_submit()
      assert html =~ "commenting too fast"
    end
  end

  describe "the moderation screen" do
    setup %{post: post} do
      member = person("member")
      {:ok, held} = Content.submit_comment(member, post, "waiting for you")
      %{held: held, member: member}
    end

    test "staff see what is waiting and can approve it", %{post: post, held: held} do
      {:ok, view, html} = live(signed_in(person("gm")), "/admin/comments")
      assert html =~ "waiting for you"
      assert html =~ "Waiting (1)"

      view |> element(~s(#comment-#{held.id} button[phx-click=approve])) |> render_click()

      assert Content.get_comment!(held.id).is_approved
      assert Content.list_approved_comments(post.id) |> length() == 1
      refute render(view) =~ ~s(id="comment-#{held.id}")
    end

    test "spam moves to the spam tab, and can be deleted for good", %{held: held} do
      {:ok, view, _} = live(signed_in(person("editor")), "/admin/comments")

      view |> element(~s(#comment-#{held.id} button[phx-click=spam])) |> render_click()
      assert Content.get_comment!(held.id).is_spam

      html = view |> element("#tab-spam") |> render_click()
      assert html =~ "waiting for you"

      view |> element("#empty-spam") |> render_click()
      assert_raise Ecto.NoResultsError, fn -> Content.get_comment!(held.id) end
    end

    test "approve all clears the queue", %{post: post, member: member} do
      {:ok, _} = Content.submit_comment(member, post, "another waiting one")
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/comments")

      view |> element("#approve-all") |> render_click()
      assert Content.count_comments_by_status(:pending) == 0
    end

    test "a comment someone else already moderated is just a refresh", %{held: held} do
      {:ok, view, _} = live(signed_in(person("admin")), "/admin/comments")
      {:ok, _} = Content.delete_comment(held)

      render_hook(view, "approve", %{"id" => held.id})
      render_hook(view, "approve", %{"id" => "not-a-uuid"})
      assert Process.alive?(view.pid)
    end

    test "members are turned away" do
      assert {:error, {kind, %{to: "/"}}} = live(signed_in(person("member")), "/admin/comments")
      assert kind in [:redirect, :live_redirect]
    end
  end
end
