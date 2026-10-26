defmodule Bacon8.Content.SchedulingAndRevisionsTest do
  # Drafts that go live by themselves, and earlier versions that can be put back.
  use Bacon8.DataCase, async: true

  alias Bacon8.Content
  alias Bacon8.Content.{Revision, Revisions}
  alias Bacon8.Repo

  setup do
    author = user_fixture(%{is_admin: true})
    {:ok, post} = Content.create_post(author, %{title: "First title", content: "<p>first</p>"})
    %{author: author, post: post}
  end

  defp past, do: DateTime.utc_now() |> DateTime.add(-120, :second) |> DateTime.truncate(:second)
  defp future, do: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

  describe "scheduled publishing" do
    test "a draft whose time has come is published, and the time is cleared", %{post: post} do
      {:ok, post} = Content.update_post(post, %{scheduled_at: past()})
      refute post.is_published

      assert Content.publish_due() == 1

      post = Content.get_post!(post.id)
      assert post.is_published
      assert post.published_at
      assert is_nil(post.scheduled_at)
    end

    test "a draft whose time hasn't come stays a draft", %{post: post} do
      {:ok, _} = Content.update_post(post, %{scheduled_at: future()})

      assert Content.publish_due() == 0
      refute Content.get_post!(post.id).is_published
    end

    test "pages are scheduled the same way" do
      {:ok, page} = Content.create_page(%{title: "Later", slug: "later-page", content: "<p>x</p>", scheduled_at: past()})

      assert Content.publish_due() == 1
      assert Content.get_page!(page.id).is_published
    end

    test "a scheduled draft with no body is left a draft, unscheduled, instead of failing forever", %{author: author} do
      {:ok, empty} = Content.create_post(author, %{title: "Empty", slug: "empty-one", scheduled_at: past()})
      {:ok, empty} = Content.update_post(empty, %{content: ""})

      assert Content.publish_due() == 0
      empty = Content.get_post!(empty.id)
      refute empty.is_published
      assert is_nil(empty.scheduled_at)
    end

    test "publishing by hand clears the schedule", %{post: post} do
      {:ok, post} = Content.update_post(post, %{scheduled_at: future()})
      {:ok, post} = Content.update_post(post, %{is_published: true})

      assert is_nil(post.scheduled_at)
    end

    test "the editor's own time format is accepted", %{post: post} do
      {:ok, post} = Content.update_post(post, %{scheduled_at: "2031-10-27T09:30"})
      assert post.scheduled_at == ~U[2031-10-27 09:30:00Z]

      {:ok, post} = Content.update_post(post, %{scheduled_at: ""})
      assert is_nil(post.scheduled_at)
    end
  end

  describe "revisions" do
    test "an edit keeps the version before it", %{post: post} do
      {:ok, _} = Content.update_post(post, %{content: "<p>second</p>"})

      assert [%Revision{content: "<p>first</p>", title: "First title"}] = Revisions.list(:post, post.id)
    end

    test "a second edit within five minutes keeps nothing more", %{post: post} do
      {:ok, post} = Content.update_post(post, %{content: "<p>second</p>"})
      {:ok, _} = Content.update_post(post, %{content: "<p>third</p>"})

      assert [_one] = Revisions.list(:post, post.id)
    end

    test "an edit after five minutes keeps the version it replaced", %{post: post} do
      {:ok, post} = Content.update_post(post, %{content: "<p>second</p>"})
      Repo.update_all(Revision, set: [inserted_at: DateTime.utc_now() |> DateTime.add(-600, :second) |> DateTime.truncate(:second)])

      {:ok, _} = Content.update_post(post, %{content: "<p>third</p>"})

      assert ["<p>second</p>", "<p>first</p>"] = Revisions.list(:post, post.id) |> Enum.map(& &1.content)
    end

    test "saving without changing the words keeps nothing", %{post: post} do
      {:ok, _} = Content.update_post(post, %{meta_description: "just a description"})
      assert Revisions.list(:post, post.id) == []
    end

    test "an empty body is not worth keeping", %{author: author} do
      {:ok, blank} = Content.create_post(author, %{title: "Untitled", slug: "blank-one"})
      {:ok, _} = Content.update_post(blank, %{content: "<p>now there is something</p>"})

      assert Revisions.list(:post, blank.id) == []
    end

    test "restoring puts the words back and keeps the current version", %{author: author, post: post} do
      {:ok, edited} = Content.update_post(post, %{title: "Second title", content: "<p>second</p>"})
      [rev] = Revisions.list(:post, post.id)

      assert {:ok, restored} = Revisions.restore(edited, rev.id, author.id)
      assert restored.title == "First title"
      assert restored.content == "<p>first</p>"
      assert Enum.any?(Revisions.list(:post, post.id), &(&1.content == "<p>second</p>"))
    end

    test "only this record's own versions can be restored", %{author: author, post: post} do
      {:ok, other} = Content.create_post(author, %{title: "Other", content: "<p>other</p>"})
      {:ok, _} = Content.update_post(other, %{content: "<p>other, edited</p>"})
      [foreign] = Revisions.list(:post, other.id)

      assert {:error, :not_found} = Revisions.restore(post, foreign.id)
      assert {:error, :not_found} = Revisions.restore(post, "not-a-uuid")
    end

    test "pages have versions too", %{} do
      {:ok, page} = Content.create_page(%{title: "A page", slug: "a-page-rev", content: "<p>one</p>"})
      {:ok, _} = Content.update_page(page, %{content: "<p>two</p>"})

      assert [%{content: "<p>one</p>"}] = Revisions.list(:page, page.id)
    end

    test "at most fifty are kept, the oldest going first", %{post: post} do
      base = DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)

      for n <- 1..52 do
        Repo.insert!(%Revision{kind: "post", record_id: post.id, title: "t", content: "<p>v#{n}</p>", inserted_at: DateTime.add(base, n, :second)})
      end

      Revisions.keep(post)

      revisions = Revisions.list(:post, post.id)
      assert length(revisions) == 50
      refute Enum.any?(revisions, &(&1.content in ["<p>v1</p>", "<p>v2</p>", "<p>v3</p>"]))
      assert Enum.any?(revisions, &(&1.content == "<p>v52</p>"))
    end

    test "deleting the record deletes its versions", %{post: post} do
      {:ok, post} = Content.update_post(post, %{content: "<p>second</p>"})
      assert Revisions.list(:post, post.id) != []

      {:ok, _} = Content.delete_post(post)
      assert Revisions.list(:post, post.id) == []
    end
  end
end
