defmodule Bacon8.Content.ModerationTest do
  # Who may comment, and which comments wait for a moderator.
  use Bacon8.DataCase, async: true

  alias Bacon8.Content
  alias Bacon8.Content.Moderation

  defp member, do: %{role: "member", is_admin: false}

  describe "decide/3 (the rules)" do
    test "staff are approved at once, even with links" do
      for user <- [%{role: "admin", is_admin: true}, %{role: "gm", is_admin: false}, %{role: "editor", is_admin: false}, %{role: "member", is_admin: true}] do
        assert Moderation.decide(user, "see http://a.example http://b.example http://c.example http://d.example", 0) == :approved
      end
    end

    test "a member's first comment waits" do
      assert Moderation.decide(member(), "Nice post", 0) == :pending
    end

    test "a member with an approved comment is approved at once" do
      assert Moderation.decide(member(), "Nice post", 1) == :approved
    end

    test "more than two links hold even a known member's comment" do
      assert Moderation.decide(member(), "a http://1.example b http://2.example", 3) == :approved
      assert Moderation.decide(member(), "http://1.example http://2.example www.3.example", 3) == :pending
    end

    test "counts http, https and www addresses" do
      assert Moderation.link_count("none here") == 0
      assert Moderation.link_count("http://a.example and HTTPS://b.example and www.c.example/x?y=1") == 3
      assert Moderation.link_count(nil) == 0
    end
  end

  describe "Content.submit_comment/3" do
    setup do
      author = user_fixture(%{is_admin: true})
      {:ok, post} = Content.create_post(author, %{title: "Open post", content: "x", is_published: true, published_at: ~U[2026-03-01 10:00:00Z]})
      member = user_fixture(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      %{post: post, member: member}
    end

    test "a first comment is held and not public", %{post: post, member: member} do
      assert {:ok, %{is_approved: false, is_spam: false} = comment} = Content.submit_comment(member, post, "  First!  ")
      assert comment.content == "First!"
      assert Content.list_approved_comments(post.id) == []
      assert Content.count_comments_by_status(:pending) == 1
    end

    test "once a comment is approved the next ones show at once", %{post: post, member: member} do
      {:ok, first} = Content.submit_comment(member, post, "First")
      {:ok, _} = Content.approve_comment(first)

      assert {:ok, %{is_approved: true}} = Content.submit_comment(member, post, "Second")
      assert [_, _] = Content.list_approved_comments(post.id)
    end

    test "a moderator's own comment shows at once", %{post: post} do
      gm = user_fixture(%{role: "gm", email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      assert {:ok, %{is_approved: true}} = Content.submit_comment(gm, post, "Official word")
    end

    test "needs a verified email, a signed-in user and a published post", %{post: post, member: member} do
      unverified = user_fixture(%{email_verified_at: nil})
      assert {:error, :not_allowed} = Content.submit_comment(unverified, post, "hi")
      assert {:error, :not_allowed} = Content.submit_comment(nil, post, "hi")

      {:ok, draft} = Content.create_post(member, %{title: "Draft", content: "x"})
      assert {:error, :not_allowed} = Content.submit_comment(member, draft, "hi")
    end

    test "refuses empty and over-long comments", %{post: post, member: member} do
      assert {:error, %Ecto.Changeset{}} = Content.submit_comment(member, post, "   ")
      assert {:error, %Ecto.Changeset{}} = Content.submit_comment(member, post, String.duplicate("x", 5001))
    end

    test "refuses the same words twice, and more than the hourly limit", %{post: post, member: member} do
      assert {:ok, _} = Content.submit_comment(member, post, "same words")
      assert {:error, :duplicate} = Content.submit_comment(member, post, "same words")

      for n <- 2..Moderation.rate_limit(), do: assert({:ok, _} = Content.submit_comment(member, post, "comment #{n}"))
      assert {:error, :rate_limited} = Content.submit_comment(member, post, "one too many")
    end

    test "spam is kept but shown nowhere, and can be approved back", %{post: post, member: member} do
      {:ok, comment} = Content.submit_comment(member, post, "buy now")
      {:ok, spam} = Content.mark_spam(comment)

      assert spam.is_spam and not spam.is_approved
      assert Content.list_approved_comments(post.id) == []
      assert Content.count_comments_by_status(:pending) == 0
      assert Content.count_comments_by_status(:spam) == 1
      assert [%{id: id}] = Content.list_comments_by_status(:spam)
      assert id == comment.id

      {:ok, back} = Content.approve_comment(spam)
      assert back.is_approved and not back.is_spam
    end
  end
end
