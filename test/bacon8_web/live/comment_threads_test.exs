defmodule Bacon8Web.CommentThreadsTest do
  # Replies, staff notices about waiting comments, and members editing or deleting their own.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.{Content, Notifications}

  @endpoint Bacon8Web.Endpoint

  setup do
    {:ok, post} = Content.create_post(person("admin"), %{title: "Thread", content: "<p>x</p>", is_published: true, published_at: ~U[2026-03-01 10:00:00Z]})
    author = person("member")
    {:ok, first} = Content.submit_comment(author, post, "First comment")
    {:ok, first} = Content.approve_comment(first)
    %{post: post, author: author, first: first}
  end

  describe "replies" do
    test "a member replies under a comment, and the author is told", %{post: post, author: author, first: first} do
      {:ok, view, _} = live(signed_in(person("editor")), "/blog/#{post.slug}")

      view |> element(~s(#comment-#{first.id} button[phx-click=reply_to])) |> render_click()
      html = view |> form("#reply-form", %{"comment" => "Good point", "parent_id" => first.id}) |> render_submit()

      assert html =~ "Good point"
      [reply] = Content.list_approved_comments(post.id) |> Enum.filter(& &1.parent_id)
      assert reply.parent_id == first.id

      [note] = Notifications.list_user_notifications(author.id)
      assert note.type == "reply"
      assert note.metadata["path"] == "/blog/#{post.slug}#comment-#{reply.id}"
    end

    test "answering a reply hangs from the comment it answers (one level)", %{post: post, first: first} do
      editor = person("editor")
      {:ok, reply} = Content.submit_comment(editor, post, "reply one", first.id)
      {:ok, again} = Content.submit_comment(editor, post, "reply two", reply.id)

      assert again.parent_id == first.id
    end

    test "can't reply to a hidden comment or one from another post", %{post: post} do
      editor = person("editor")
      {:ok, other} = Content.create_post(editor, %{title: "Other", content: "x", is_published: true, published_at: ~U[2026-03-02 10:00:00Z]})
      {:ok, held} = Content.submit_comment(person("member"), other, "waiting")

      assert {:error, :not_found} = Content.submit_comment(editor, post, "x", held.id)
      assert {:error, :not_found} = Content.submit_comment(editor, post, "x", Ecto.UUID.generate())
      assert {:error, :not_found} = Content.submit_comment(editor, post, "x", "not-a-uuid")
    end

    test "a held reply tells the author only once it is approved", %{post: post, author: author, first: first} do
      {:ok, reply} = Content.submit_comment(person("member"), post, "a held reply", first.id)
      assert Notifications.list_user_notifications(author.id) == []

      {:ok, _} = Content.approve_comment(reply)
      assert [%{type: "reply"}] = Notifications.list_user_notifications(author.id)
    end

    test "replies show under their comment, and not alone", %{post: post, first: first} do
      {:ok, _} = Content.submit_comment(person("editor"), post, "a visible reply", first.id)
      {:ok, _view, html} = live(build_conn(), "/blog/#{post.slug}")

      assert html =~ "a visible reply"
      assert html =~ "Comments <span class=\"text-gray-400 text-base\">(2)</span>"
    end
  end

  describe "staff notices" do
    test "staff get one notice while comments are waiting, not one per comment", %{post: post} do
      gm = person("gm")
      member = person("member")

      {:ok, _} = Content.submit_comment(member, post, "waiting one")
      {:ok, _} = Content.submit_comment(member, post, "waiting two")

      assert [%{title: "A comment is waiting for approval", metadata: %{"path" => "/admin/comments"}}] =
               Notifications.list_user_notifications(gm.id)

      assert Notifications.list_user_notifications(member.id) == []
    end

    test "a new notice comes once the earlier one was read", %{post: post} do
      gm = person("gm")
      member = person("member")
      {:ok, _} = Content.submit_comment(member, post, "waiting one")
      [note] = Notifications.list_user_notifications(gm.id)
      Notifications.mark_as_read(note)

      {:ok, _} = Content.submit_comment(member, post, "waiting two")
      assert length(Notifications.list_user_notifications(gm.id)) == 2
    end

    test "comments shown at once tell nobody", %{post: post} do
      gm = person("gm")
      {:ok, _} = Content.submit_comment(person("editor"), post, "shown right away")
      assert Notifications.list_user_notifications(gm.id) == []
    end
  end

  describe "a member's own comment" do
    test "can be edited, and says so", %{post: post, author: author, first: first} do
      {:ok, view, _} = live(signed_in(author), "/blog/#{post.slug}")

      view |> element(~s(#comment-#{first.id} button[phx-click=edit_comment])) |> render_click()
      html = view |> form("#edit-form-#{first.id}", %{"comment" => "First comment, fixed"}) |> render_submit()

      assert html =~ "First comment, fixed"
      assert html =~ "(edited)"
      assert Content.get_comment!(first.id).is_approved
    end

    test "an edit that adds links sends it back to waiting", %{author: author, first: first} do
      {:ok, edited} = Content.edit_own_comment(author, first.id, "buy http://a.example http://b.example http://c.example")

      refute edited.is_approved
      assert Content.count_comments_by_status(:pending) == 1
    end

    test "can be deleted, with its replies", %{post: post, author: author, first: first} do
      {:ok, reply} = Content.submit_comment(person("editor"), post, "a reply", first.id)
      {:ok, view, _} = live(signed_in(author), "/blog/#{post.slug}")

      view |> element(~s(#comment-#{first.id} > div button[phx-click=delete_comment])) |> render_click()

      assert Content.list_approved_comments(post.id) == []
      assert_raise Ecto.NoResultsError, fn -> Content.get_comment!(reply.id) end
    end

    test "nobody else's comment can be changed", %{post: post, first: first} do
      other = person("member")

      assert {:error, :not_found} = Content.edit_own_comment(other, first.id, "hijacked")
      assert {:error, :not_found} = Content.delete_own_comment(other, first.id)
      assert {:error, :not_found} = Content.delete_own_comment(nil, first.id)
      assert {:error, :not_found} = Content.edit_own_comment(other, "not-a-uuid", "x")
      assert Content.get_comment!(first.id).content == "First comment"

      {:ok, view, html} = live(signed_in(other), "/blog/#{post.slug}")
      refute html =~ "edit_comment"
      render_hook(view, "delete_comment", %{"id" => first.id})
      assert Content.get_comment!(first.id)
    end

    test "a comment marked spam can't be edited back into view", %{author: author, first: first} do
      {:ok, _} = Content.mark_spam(first)
      assert {:error, :not_found} = Content.edit_own_comment(author, first.id, "innocent now")
    end
  end
end
