defmodule Bacon8.ModerationTest do
  # Trust & safety (2026-11-03): reports and takedown requests, hiding at once, keeping evidence,
  # blocked hashes on every upload path, the public form and the admin queue.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.{Drive, Moderation, Storage}
  alias Bacon8.Moderation.{BlockedHash, Hold, Report}

  @endpoint Bacon8Web.Endpoint

  defp shared_file(user, contents \\ "a picture") do
    {:ok, file} = Drive.add_file(user, nil, tmp_upload(contents), "pic.png")
    {:ok, file} = Drive.set_visibility(user, file.id, "link")
    file
  end

  describe "reports" do
    test "a report of a shared file names the file, its owner and its hash; ordinary ones don't hide it" do
      owner = user_fixture()
      file = shared_file(owner)

      {:ok, r} = Moderation.create_report(%{kind: "report", category: "spam", subject_url: "https://example.test/s/#{file.share_token}", details: "ads"})
      assert {r.subject_type, r.subject_id, r.subject_owner_id} == {"drive_file", file.id, owner.id}
      assert r.subject_snapshot["sha256"] == file.blob_sha256
      assert r.priority == 3 and is_nil(r.due_at)
      assert Drive.can_read?(nil, Drive.get_file(file.id), :share)
    end

    test "sexual content involving a minor: urgent, hidden at once from everyone, staff included" do
      owner = user_fixture()
      admin = person("admin")
      file = shared_file(owner)

      {:ok, r} = Moderation.create_report(%{kind: "report", category: "csam", subject_url: "/s/#{file.share_token}"})
      assert r.priority == 0 and r.due_at
      f = Drive.get_file(file.id)
      refute Drive.can_read?(nil, f, :share)
      refute Drive.can_read?(owner, f, :id)
      refute Drive.can_read?(admin, f, :id)
    end

    test "a TAKE IT DOWN request needs a signature, the statement and a way to reach them; it's due in 48 hours" do
      assert {:error, cs} = Moderation.create_report(%{kind: "ncii_takedown", category: "ncii", subject_url: "/s/whatever"})
      assert %{signature: [_ | _], sworn: [_ | _], reporter_email: [_ | _]} = errors_on(cs)

      file = shared_file(user_fixture())

      {:ok, r} =
        Moderation.create_report(%{kind: "ncii_takedown", category: "ncii", subject_url: "/s/#{file.share_token}", reporter_name: "A Person", reporter_email: "a@example.test", signature: "A Person", sworn: true})

      assert_in_delta DateTime.diff(r.due_at, DateTime.utc_now()), 48 * 3600, 60
      refute Drive.can_read?(nil, Drive.get_file(file.id), :share)
    end

    test "a report needs to say where the thing is" do
      assert {:error, cs} = Moderation.create_report(%{kind: "report", category: "spam"})
      assert %{subject_url: [_ | _]} = errors_on(cs)
    end
  end

  describe "acting on a report" do
    test "keep evidence & remove: a year's hold, the body kept from the GC, the hash blocked everywhere" do
      owner = user_fixture()
      admin = person("admin")
      file = shared_file(owner, "evidence bytes")
      {:ok, r} = Moderation.create_report(%{kind: "report", category: "csam", subject_url: "/s/#{file.share_token}"})

      {:ok, r} = Moderation.act(r, "preserve_remove", admin)
      assert [%Hold{sha256: sha} = hold] = Repo.all(Hold)
      assert sha == file.blob_sha256
      assert DateTime.diff(hold.preserve_until, DateTime.utc_now()) > 360 * 86_400
      assert hold.evidence["account"]["id"] == owner.id
      assert Repo.get(BlockedHash, sha)
      assert Moderation.blocked_hash?(sha)
      assert sha in Moderation.held_shas()

      # the same bytes can't be uploaded again, by anyone
      assert {:error, :blocked} = Drive.add_file(user_fixture(), nil, tmp_upload("evidence bytes"), "again.png")
      assert Moderation.blocked_file?(tmp_upload("evidence bytes"))

      # banning before keeping evidence is refused for a child-abuse report; after, it works
      assert {:ok, _} = Moderation.act(r, "ban_owner", admin)
      assert Bacon8.Repo.get(Bacon8.Accounts.User, owner.id).role == "banned"

      {:ok, r} = Moderation.act(r, "ncmec_reported", admin, %{"ncmec_report_id" => "123456789"})
      assert r.ncmec_report_id == "123456789"
      {:ok, r} = Moderation.act(r, "resolve", admin, %{"note" => "reported and banned"})
      assert r.status == "actioned"
      assert Enum.map(r.actions, & &1.action) == ~w(reported preserve_remove ban_owner ncmec_reported resolve)
    end

    test "a child-abuse report's poster can't be banned before the evidence is kept" do
      owner = user_fixture()
      file = shared_file(owner)
      {:ok, r} = Moderation.create_report(%{kind: "report", category: "csam", subject_url: "/s/#{file.share_token}"})
      assert {:error, msg} = Moderation.act(r, "ban_owner", person("admin"))
      assert msg =~ "evidence"
    end

    test "garbage collection keeps a held body after its file is deleted" do
      owner = user_fixture()
      admin = person("admin")
      file = shared_file(owner, "held body")
      {:ok, r} = Moderation.create_report(%{kind: "report", category: "threat", subject_url: "/s/#{file.share_token}"})
      {:ok, _} = Moderation.act(r, "preserve_remove", admin)
      {:ok, _} = Moderation.act(Moderation.get_report(r.id), "remove", admin)
      refute Drive.get_file(file.id)
      Repo.update_all(Bacon8.Drive.Blob, set: [last_referenced_at: ~U[2000-01-01 00:00:00.000000Z]])
      Drive.gc_blobs(0)
      assert Storage.exists?(file.blob_sha256)
    end

    test "restore shows a hidden file again; dismiss closes the report" do
      owner = user_fixture()
      admin = person("admin")
      file = shared_file(owner)
      {:ok, r} = Moderation.create_report(%{kind: "report", category: "ncii", subject_url: "/s/#{file.share_token}"})
      refute Drive.can_read?(nil, Drive.get_file(file.id), :share)
      {:ok, r} = Moderation.act(r, "restore", admin)
      assert Drive.can_read?(nil, Drive.get_file(file.id), :share)
      {:ok, r} = Moderation.act(r, "dismiss", admin, %{"note" => "consensual, the reporter is the poster"})
      assert r.status == "dismissed"
    end

    test "uploads anywhere refuse a blocked file" do
      path = tmp_upload("known bad")
      :ok = Moderation.block_hash(Storage.sha256_file(path), "test", person("admin"))
      entry = %{client_name: "x.png", client_size: 9, client_type: "image/png"}
      assert {:error, _} = Bacon8.Uploads.upload_file(user_fixture(), path, entry, context: "avatar")
    end
  end

  describe "pages" do
    test "anyone can report from /report, and the admins hear about it" do
      admin = person("admin")
      file = shared_file(user_fixture())
      {:ok, view, _} = live(build_conn(), "/report")

      view
      |> form("form[phx-submit=submit]", %{r: %{category: "harassment", subject_url: "/s/#{file.share_token}", details: "they keep posting this"}})
      |> render_submit()

      assert render(view) =~ "Thank you"
      assert [%Report{category: "harassment"}] = Repo.all(Report)
      assert Repo.exists?(from n in Bacon8.Notifications.UserNotification, where: n.user_id == ^admin.id and n.source_kind == "moderation_report")
    end

    test "the admin queue opens, shows a report and acts on it" do
      admin = person("admin")
      file = shared_file(user_fixture())
      {:ok, r} = Moderation.create_report(%{kind: "report", category: "spam", subject_url: "/s/#{file.share_token}"})
      conn = signed_in(admin)

      for tab <- ~w(open actioned dismissed blocked holds), do: assert({:ok, _, _} = live(conn, "/admin/moderation?tab=#{tab}"))

      {:ok, view, html} = live(conn, "/admin/moderation?id=#{r.id}")
      assert html =~ "pic.png"
      view |> element("button", "Block its files") |> render_click()
      assert Moderation.blocked_hash?(file.blob_sha256)
    end

    test "a member can't open the queue" do
      assert {:error, {_redirect, _}} = live(signed_in(person("member")), "/admin/moderation")
    end
  end
end
