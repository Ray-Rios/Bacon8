defmodule Bacon8.ContentTest do
  # /pages and /blog: the two things the core keeps. These pin what the page and
  # post builders rely on (slugs, publishing, drafts, listing, counts) and
  # the comment model underneath the blog, so the builders can be rebuilt
  # without changing what the site does.
  use Bacon8.DataCase, async: true

  import Bacon8.ForumFixtures, only: [user: 0, user: 1]

  alias Bacon8.Content
  alias Bacon8.Content.{Page, Post}

  defp title, do: "Title #{System.unique_integer([:positive])}"

  defp post_fixture(user, attrs \\ %{}) do
    {:ok, post} = Content.create_post(user, Map.merge(%{title: title(), content: "body"}, Map.new(attrs)))
    post
  end

  defp page_fixture(attrs \\ %{}) do
    {:ok, page} = Content.create_page(Map.merge(%{title: title(), content: "body"}, Map.new(attrs)))
    page
  end

  # Posts and pages are listed newest first, but their timestamps are whole seconds.
  defp backdate(%mod{id: id}, seconds) do
    at = DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(r in mod, where: r.id == ^id), set: [inserted_at: at])
  end

  describe "post slugs" do
    test "come from the title: lower case, no punctuation, dashes" do
      post = post_fixture(user(), %{title: "Hello,   World! It's 2026"})
      assert post.slug == "hello-world-its-2026"
    end

    test "are cut at 100 characters" do
      post = post_fixture(user(), %{title: String.duplicate("word ", 40)})
      assert String.length(post.slug) <= 100
    end

    test "an explicit slug is kept" do
      assert post_fixture(user(), %{title: "Anything", slug: "my-own"}).slug == "my-own"
    end

    test "are unique" do
      u = user()
      post_fixture(u, %{slug: "taken"})
      assert {:error, cs} = Content.create_post(u, %{title: title(), content: "x", slug: "taken"})
      assert %{slug: ["has already been taken"]} = errors_on(cs)
    end

    test "renaming a post doesn't move its URL" do
      post = post_fixture(user(), %{slug: "stable-url"})
      {:ok, renamed} = Content.update_post(post, %{title: "A completely new title", slug: post.slug})
      assert renamed.slug == "stable-url"
    end

    test "renaming it without sending the slug doesn't either" do
      post = post_fixture(user(), %{slug: "stable-url-2"})
      {:ok, renamed} = Content.update_post(post, %{title: "Another new title"})
      assert renamed.slug == "stable-url-2"
    end
  end

  describe "publishing a post" do
    test "a draft needs nothing but a user, so a half-written post saves" do
      # (the table won't take a NULL body, so it is saved empty)
      assert {:ok, %Post{is_published: false, content: ""}} = Content.create_post(user(), %{title: "Half"})
    end

    test "publishing needs a title and content" do
      assert {:error, cs} = Content.create_post(user(), %{is_published: true})
      assert %{title: ["can't be blank"], content: ["can't be blank"]} = errors_on(cs)
    end

    test "sets published_at the first time, and unpublishing clears it" do
      u = user()
      post = post_fixture(u, %{is_published: true})
      assert %DateTime{} = post.published_at

      {:ok, draft} = Content.update_post(post, %{is_published: false})
      assert draft.published_at == nil

      {:ok, again} = Content.update_post(draft, %{is_published: true})
      assert %DateTime{} = again.published_at
    end

    test "an explicit published_at is respected, and saving again doesn't move it" do
      at = ~U[2026-01-02 03:04:05Z]
      post = post_fixture(user(), %{is_published: true, published_at: at})
      assert post.published_at == at

      {:ok, saved} = Content.update_post(post, %{content: "edited"})
      assert saved.published_at == at
    end

    test "limits: a 200-character title, 500-character excerpt, 160-character description" do
      u = user()
      assert {:error, cs} = Content.create_post(u, %{title: String.duplicate("a", 201)})
      assert %{title: [_]} = errors_on(cs)
      assert {:error, cs} = Content.create_post(u, %{title: "t", excerpt: String.duplicate("a", 501)})
      assert %{excerpt: [_]} = errors_on(cs)
      assert {:error, cs} = Content.create_post(u, %{title: "t", meta_description: String.duplicate("a", 161)})
      assert %{meta_description: [_]} = errors_on(cs)
    end
  end

  describe "listing and counting posts" do
    test "published and draft lists, newest first, with the author loaded" do
      u = user()
      old = post_fixture(u, %{is_published: true})
      newer = post_fixture(u, %{is_published: true})
      draft = post_fixture(u)
      backdate(old, 100)

      assert Enum.map(Content.list_published_posts(), & &1.id) == [newer.id, old.id]
      assert [%{id: id, user: %{id: uid}}] = Content.list_posts_by_status(:draft)
      assert id == draft.id and uid == u.id
      assert length(Content.list_posts()) == 3
    end

    test "filters by status and by author together" do
      a = user()
      b = user()
      mine = post_fixture(a, %{is_published: true})
      post_fixture(a)
      post_fixture(b, %{is_published: true})

      assert [%{id: id}] = Content.list_posts_with_filters(status: :published, user_id: a.id)
      assert id == mine.id
      assert length(Content.list_posts_with_filters(user_id: a.id)) == 2
      assert length(Content.list_posts_with_filters([])) == 3
    end

    test "recent posts are the newest published ones, up to the limit" do
      u = user()
      posts = for n <- 1..4, do: post_fixture(u, %{is_published: true}) |> tap(&backdate(&1, 100 - n * 10))
      post_fixture(u)

      recent = Content.get_recent_posts(2)
      assert Enum.map(recent, & &1.id) == [Enum.at(posts, 3).id, Enum.at(posts, 2).id]
    end

    test "counts agree with the lists" do
      u = user()
      post_fixture(u, %{is_published: true})
      post_fixture(u, %{is_published: true})
      post_fixture(u)

      assert Content.count_posts() == 3
      assert Content.count_posts_by_status(:published) == 2
      assert Content.count_posts_by_status(:draft) == 1
    end

    test "fetching by slug, and by an id that doesn't exist" do
      post = post_fixture(user(), %{slug: "findable"})
      assert Content.get_post_by_slug!("findable").id == post.id
      assert Content.get_post!(post.id).user
      assert_raise Ecto.NoResultsError, fn -> Content.get_post_by_slug!("missing") end
      assert_raise Ecto.NoResultsError, fn -> Content.get_post!(Ecto.UUID.generate()) end
    end

    test "deleting a post removes it, and its comments with it" do
      post = post_fixture(user(), %{is_published: true})
      {:ok, _} = Content.create_comment(%{content: "nice", post_id: post.id})

      assert {:ok, _} = Content.delete_post(post)
      assert Content.count_posts() == 0
      assert Content.count_comments() == 0
    end
  end

  describe "comments" do
    setup do
      %{post: post_fixture(user(), %{is_published: true})}
    end

    test "need content and a post", %{post: post} do
      assert {:error, cs} = Content.create_comment(%{})
      assert %{content: ["can't be blank"], post_id: ["can't be blank"]} = errors_on(cs)
      assert {:ok, comment} = Content.create_comment(%{content: "hi", post_id: post.id})
      refute comment.is_approved
    end

    test "an email must look like one, and the post must exist", %{post: post} do
      assert {:error, cs} = Content.create_comment(%{content: "hi", post_id: post.id, author_email: "nope"})
      assert %{author_email: ["must be a valid email"]} = errors_on(cs)

      assert {:error, cs} = Content.create_comment(%{content: "hi", post_id: Ecto.UUID.generate()})
      assert %{post_id: [_]} = errors_on(cs)
    end

    test "are limited to 5000 characters", %{post: post} do
      assert {:error, _} = Content.create_comment(%{content: String.duplicate("a", 5001), post_id: post.id})
    end

    test "approving makes a comment public, and counts follow", %{post: post} do
      {:ok, c} = Content.create_comment(%{content: "hi", post_id: post.id})
      {:ok, _} = Content.create_comment(%{content: "pending", post_id: post.id})

      assert Content.list_approved_comments(post.id) == []
      assert Content.count_comments_by_status(:pending) == 2

      assert {:ok, %{is_approved: true}} = Content.approve_comment(c)
      assert [%{id: id}] = Content.list_approved_comments(post.id)
      assert id == c.id
      assert Content.count_comments_by_status(:approved) == 1
      assert Content.count_comments_by_status(:pending) == 1
      assert Content.count_comments() == 2
    end

    test "list_comments/1 can be limited to one post", %{post: post} do
      other = post_fixture(user())
      {:ok, _} = Content.create_comment(%{content: "here", post_id: post.id})
      {:ok, _} = Content.create_comment(%{content: "there", post_id: other.id})

      assert length(Content.list_comments()) == 2
      assert [%{content: "here"}] = Content.list_comments(post.id)
    end

    test "can reply to another comment", %{post: post} do
      {:ok, parent} = Content.create_comment(%{content: "parent", post_id: post.id})
      assert {:ok, child} = Content.create_comment(%{content: "child", post_id: post.id, parent_id: parent.id})
      assert child.parent_id == parent.id
    end
  end

  describe "page slugs and publishing" do
    test "the slug comes from the title" do
      assert page_fixture(%{title: "About  Us & Them!"}).slug == "about-us-them"
    end

    test "an explicit slug is kept, and slugs are unique" do
      slug = "kept-#{System.unique_integer([:positive])}"
      assert page_fixture(%{slug: slug}).slug == slug
      assert {:error, cs} = Content.create_page(%{title: title(), content: "x", slug: slug})
      assert %{slug: ["has already been taken"]} = errors_on(cs)
    end

    test "renaming a page doesn't move its URL" do
      slug = "stays-#{System.unique_integer([:positive])}"
      page = page_fixture(%{slug: slug})
      {:ok, renamed} = Content.update_page(page, %{title: "Our new privacy title", slug: slug})
      assert renamed.slug == slug

      {:ok, again} = Content.update_page(renamed, %{title: "Yet another title"})
      assert again.slug == slug
    end

    test "a draft needs only a title or nothing; publishing needs a title and content" do
      assert {:ok, %Page{is_published: false}} = Content.create_page(%{title: "Draft"})
      assert {:error, cs} = Content.create_page(%{is_published: true})
      assert %{title: ["can't be blank"], content: ["can't be blank"]} = errors_on(cs)
    end

    test "publishing sets published_at, unpublishing clears it" do
      page = page_fixture(%{is_published: true})
      assert %DateTime{} = page.published_at

      {:ok, draft} = Content.update_page(page, %{is_published: false})
      assert draft.published_at == nil
    end

    test "an explicit published_at wins, and a later save leaves it" do
      at = ~U[2026-02-03 04:05:06Z]
      page = page_fixture(%{is_published: true, published_at: at})
      assert page.published_at == at
      assert {:ok, %{published_at: ^at}} = Content.update_page(page, %{content: "edited"})
    end

    test "template types are a fixed set" do
      for t <- ~w(default landing full-width sidebar custom) do
        assert {:ok, %{template_type: ^t}} = Content.create_page(%{title: title(), template_type: t})
      end

      assert {:error, cs} = Content.create_page(%{title: title(), template_type: "mystery"})
      assert %{template_type: [_]} = errors_on(cs)
    end

    test "limits: 200-character title, 500 excerpt, 160 description, 255 keywords" do
      too_long = fn n -> String.duplicate("a", n) end
      assert {:error, _} = Content.create_page(%{title: too_long.(201)})
      assert {:error, _} = Content.create_page(%{title: "t", excerpt: too_long.(501)})
      assert {:error, _} = Content.create_page(%{title: "t", meta_description: too_long.(161)})
      assert {:error, _} = Content.create_page(%{title: "t", meta_keywords: too_long.(256)})
    end

    test "share buttons default on, with five platforms, uncoloured" do
      page = page_fixture()
      assert page.show_share_buttons
      assert page.share_platforms == ~w(twitter facebook linkedin reddit email)
      refute page.share_buttons_colored
    end
  end

  describe "finding and counting pages" do
    test "by slug, with nil for a slug that isn't there" do
      slug = "faq-#{System.unique_integer([:positive])}"
      page = page_fixture(%{slug: slug})
      assert Content.get_page_by_slug(slug).id == page.id
      assert Content.get_page_by_slug("nope") == nil
      assert Content.get_page!(page.id).id == page.id
    end

    test "lists and counts agree, and delete removes one" do
      # the legal placeholder pages are seeded by a migration, so count from there
      before = Content.count_pages()
      a = page_fixture()
      page_fixture()
      assert Content.count_pages() == before + 2
      assert length(Content.list_pages()) == before + 2

      assert {:ok, _} = Content.delete_page(a)
      assert Content.count_pages() == before + 1
    end
  end
end
