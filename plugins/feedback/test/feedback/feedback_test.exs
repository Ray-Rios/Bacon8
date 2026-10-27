defmodule FeedbackTest do
  # Suggestions & Bugs (2026-10-27): who may do what, votes, the admin's moves, and Claude's
  # runner's side (token, claiming, reporting).
  use Bacon8.DataCase, async: false

  import Feedback.Fixtures

  alias Feedback.{Item, Shot}

  setup do
    {:ok, _} = Bacon8.Plugins.activate("feedback")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  describe "who" do
    test "members are signed-in active accounts that aren't guests or banned; admins always" do
      assert Feedback.member?(member())
      refute Feedback.member?(nil)
      refute Feedback.member?(guest())
      refute Feedback.member?(member(%{role: "banned"}))
      refute Feedback.member?(member(%{status: "disabled"}))
      assert Feedback.member?(admin())
    end

    test "the start menu icon is there for members and not for guests or anyone signed out" do
      assert [%{path: "/feedback", label: "Suggestions & Bugs"}] =
               Feedback.Plugin.desktop_apps(member())

      assert Feedback.Plugin.desktop_apps(guest()) == []
      assert Feedback.Plugin.desktop_apps(nil) == []

      assert Enum.any?(Bacon8.Plugins.desktop_apps(member()), &(&1.path == "/feedback"))
      refute Enum.any?(Bacon8.Plugins.desktop_apps(guest()), &(&1.path == "/feedback"))
    end

    test "a guest can neither write, read nor vote" do
      g = guest()

      assert {:error, :forbidden} =
               Feedback.create_item(g, %{
                 "kind" => "bug",
                 "area" => "site",
                 "title" => "Nope nope",
                 "body" => "Guests can't post."
               })

      i = item(member())
      assert Feedback.list_items(g) == []
      assert Feedback.get_item(i.id, g) == nil
      assert {:error, :forbidden} = Feedback.vote(i, g, 1)
    end
  end

  describe "writing" do
    test "a member posts with screenshots; their own vote counts" do
      me = member()

      i =
        item(me, %{"kind" => "bug", "title" => "The kraken wobbles"}, [
          {tmp_upload(png()), "C:\\Users\\me\\shot one.png"}
        ])

      assert i.number > 0
      assert i.status == "open" and i.score == 1
      [shot] = Repo.all(from(s in Shot, where: s.item_id == ^i.id))
      assert shot.content_type == "image/png" and shot.filename == "shot one.png"
      assert Bacon8.Storage.exists?(shot.sha256)
      assert shot.sha256 in Feedback.storage_refs()

      [listed] = Feedback.list_items(me)
      assert listed.id == i.id and listed.my_vote == 1
    end

    test "only pictures are taken, by their bytes" do
      assert {:error, :not_an_image} =
               Feedback.create_item(
                 member(),
                 %{
                   "kind" => "bug",
                   "area" => "site",
                   "title" => "Sneaky file",
                   "body" => "This one is not a picture."
                 },
                 [{tmp_upload("<script>alert(1)</script>"), "x.png"}]
               )

      assert Repo.aggregate(Item, :count) == 0
    end

    test "the text is checked" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Feedback.create_item(member(), %{
                 "kind" => "idea",
                 "area" => "Site!",
                 "title" => "x",
                 "body" => "short"
               })

      assert %{kind: _, area: _, title: _, body: _} = errors_on(cs)
    end

    test "the author edits and deletes while it's open; then only an admin can" do
      me = member()
      boss = admin()
      i = item(me)
      assert {:ok, i} = Feedback.update_item(i, me, %{"title" => "Dark mode everywhere"})
      assert i.title == "Dark mode everywhere"

      assert {:error, :forbidden} =
               Feedback.update_item(i, member(), %{"title" => "Someone else's"})

      {:ok, i} = Feedback.moderate(i, boss, "approve")
      assert {:error, :forbidden} = Feedback.update_item(i, me, %{"title" => "Too late now"})
      assert {:error, :forbidden} = Feedback.delete_item(i, me)

      assert {:ok, i} =
               Feedback.update_item(i, boss, %{"admin_note" => "Only the chat page, please."})

      assert i.admin_note == "Only the chat page, please."
    end
  end

  describe "votes" do
    test "up, down, change and take back; the score follows" do
      i = item(member())
      [a, b, c] = for _ <- 1..3, do: member()
      {:ok, _} = Feedback.vote(i, a, 1)
      {:ok, _} = Feedback.vote(i, b, 1)
      {:ok, i2} = Feedback.vote(i, c, -1)
      assert i2.score == 2 and i2.my_vote == -1
      {:ok, i2} = Feedback.vote(i, c, 1)
      assert i2.score == 4
      {:ok, i2} = Feedback.vote(i, a, 0)
      assert i2.score == 3 and i2.my_vote == nil
    end

    test "no votes on declined or duplicate items" do
      boss = admin()
      i = item(member())
      {:ok, i} = Feedback.moderate(i, boss, "reject", note: "Not for now")
      assert {:error, :forbidden} = Feedback.vote(i, member(), 1)
    end

    test "top-voted first; filters by kind and area" do
      me = member()
      low = item(me, %{"title" => "A small thing"})
      high = item(me, %{"title" => "A big thing", "kind" => "bug", "area" => "bacon_world"})
      {:ok, _} = Feedback.vote(high, member(), 1)

      assert [%{id: first}, %{id: second}] = Feedback.list_items(me)
      assert {first, second} == {high.id, low.id}
      assert [%{id: id}] = Feedback.list_items(me, kind: "bug")
      assert id == high.id
      assert [%{id: ^id}] = Feedback.list_items(me, area: "bacon_world")
      assert [%{id: small}] = Feedback.list_items(me, q: "small")
      assert small == low.id
    end
  end

  describe "admin moves" do
    test "approve, submit to Claude, take back; the author hears about it" do
      me = member()
      boss = admin()
      i = item(me)

      assert {:error, :forbidden} = Feedback.moderate(i, member(), "approve")
      assert {:error, {:not_from, "open"}} = Feedback.moderate(i, boss, "submit")

      {:ok, i} = Feedback.moderate(i, boss, "approve", note: "Good one")
      assert i.status == "approved" and i.approved_by_id == boss.id

      assert Enum.any?(
               Bacon8.Notifications.list_user_notifications(me.id),
               &(&1.source_id == i.id)
             )

      {:ok, i} = Feedback.moderate(i, boss, "submit")
      assert i.status == "queued" and i.submitted_by_id == boss.id
      {:ok, i} = Feedback.moderate(i, boss, "withdraw")
      assert i.status == "approved"

      events = Feedback.get_item(i.id, boss).events
      assert Enum.map(events, & &1.to_status) == ["open", "approved", "queued", "approved"]
    end

    test "a duplicate points at the original by its number" do
      boss = admin()
      original = item(member())
      copy = item(member())

      assert {:error, :no_such_original} =
               Feedback.moderate(copy, boss, "duplicate", of: "#99999")

      {:ok, copy} = Feedback.moderate(copy, boss, "duplicate", of: "##{original.number}")
      assert copy.duplicate_of_id == original.id
      {:ok, copy} = Feedback.moderate(copy, boss, "reopen")
      assert copy.status == "open" and is_nil(copy.duplicate_of_id)
    end

    test "two admins pressing at once: the second is told it changed" do
      boss = admin()
      i = item(member())
      {:ok, _} = Feedback.moderate(i, boss, "approve")
      # `i` is the stale copy, still "open"
      assert {:error, :stale} = Feedback.moderate(i, boss, "reject")
    end
  end

  describe "Claude's runner" do
    test "its token: made by an admin, shown once, kept only as a fingerprint, revocable" do
      boss = admin()
      assert {:error, :forbidden} = Feedback.new_agent_token(member())
      {:ok, token} = Feedback.new_agent_token(boss)
      assert String.starts_with?(token, "b8fb_")
      agent = Feedback.agent()
      refute agent.token_hash == token
      assert Feedback.agent_token_valid?(token)
      refute Feedback.agent_token_valid?(token <> "x")
      refute Feedback.agent_token_valid?(nil)

      {:ok, token2} = Feedback.new_agent_token(boss)
      refute Feedback.agent_token_valid?(token)
      assert Feedback.agent_token_valid?(token2)
      :ok = Feedback.revoke_agent_token(boss)
      refute Feedback.agent_token_valid?(token2)
    end

    test "it takes the oldest submitted item, one at a time, and never one that wasn't submitted" do
      me = member()
      boss = admin()
      open = item(me)
      _approved = item_at("approved", me, boss)
      assert Feedback.agent_next() == :empty

      first = item_at("queued", me, boss)
      second = item_at("queued", me, boss)

      assert {:ok, %{id: id, status: "in_progress"}} = Feedback.agent_next()
      assert id == first.id
      # busy with it: nothing new
      assert {:busy, %{id: ^id}} = Feedback.agent_next()
      assert Feedback.agent_item(second.id).status == "queued"
      assert Feedback.agent_item(open.id) == nil
    end

    test "paused: it takes nothing" do
      boss = admin()
      item_at("queued", member(), boss)
      {:ok, _} = Feedback.update_agent(boss, %{"paused" => "true"})
      assert {:paused, _} = Feedback.agent_next()
    end

    test "reports: ready waits for Deploy; Deploy hands it back; deployed is live and the author hears" do
      me = member()
      boss = admin()
      item_at("queued", me, boss)
      {:ok, i} = Feedback.agent_next()

      assert {:error, :bad_commit} =
               Feedback.agent_report(i.id, %{"status" => "ready", "commit" => "not a sha"})

      assert {:error, {:not_from, "in_progress"}} =
               Feedback.agent_report(i.id, %{"status" => "queued"})

      {:ok, i} =
        Feedback.agent_report(i.id, %{
          "status" => "ready",
          "summary" => "Added a dark theme to chat.",
          "commit" => "abc1234",
          "hold_reason" => "touches sign-in"
        })

      assert i.status == "ready" and i.commit_sha == "abc1234" and
               i.hold_reason == "touches sign-in"

      assert {:busy, %{status: "ready"}} = Feedback.agent_next()

      {:ok, i} = Feedback.moderate(i, boss, "deploy")
      assert {:busy, %{status: "deploying"}} = Feedback.agent_next()
      {:ok, i} = Feedback.agent_report(i.id, %{"status" => "deployed"})
      assert i.status == "deployed" and i.deployed_at
      assert Feedback.agent_next() == :empty
      assert Enum.any?(Bacon8.Notifications.list_user_notifications(me.id), &(&1.title =~ "live"))
      # live items are no longer the runner's to see
      assert Feedback.agent_item(i.id) == nil
    end

    test "with auto-deploy the runner reports deployed straight from in progress; a failure can be submitted again" do
      boss = admin()
      item_at("queued", member(), boss)
      {:ok, i} = Feedback.agent_next()

      {:ok, i} =
        Feedback.agent_report(i.id, %{"status" => "failed", "summary" => "The tests failed."})

      assert i.status == "failed"
      {:ok, i} = Feedback.moderate(i, boss, "submit")
      assert i.status == "queued"
      {:ok, i} = Feedback.agent_next()

      {:ok, i} =
        Feedback.agent_report(i.id, %{
          "status" => "deployed",
          "commit" => "0123456789abcdef0123456789abcdef01234567"
        })

      assert i.status == "deployed"
    end

    test "the view it gets has the text, the admin's notes and screenshot paths, not emails" do
      me = member(%{name: "Ray"})
      boss = admin()
      i = item(me, %{}, [{tmp_upload(png()), "a.png"}])
      {:ok, i} = Feedback.update_item(i, boss, %{"admin_note" => "Keep it small"})
      {:ok, i} = Feedback.moderate(i, boss, "approve")
      {:ok, _} = Feedback.moderate(i, boss, "submit")
      {:ok, i} = Feedback.agent_next()
      view = Feedback.agent_view(i, &("/shots/" <> &1.id))
      assert view.author == "Ray" and view.admin_note == "Keep it small"
      assert [%{url: "/shots/" <> _}] = view.shots
      refute inspect(view) =~ me.email
    end
  end

  test "a banned user's open items and votes go; items already taken up stay" do
    bad = member()
    boss = admin()
    open = item(bad)
    taken = item_at("approved", bad, boss)
    other = item(member())
    {:ok, _} = Feedback.vote(other, bad, 1)

    :ok = Feedback.Plugin.hub_event({:user_content_removed, bad.id})
    refute Repo.get(Item, open.id)
    assert Repo.get(Item, taken.id)
    assert Repo.get(Item, other.id).score == 1
  end
end
