defmodule Bacon8.DriveTest do
  use Bacon8.DataCase, async: true

  alias Bacon8.{Accounts, Drive, Entitlements, Storage}
  alias Bacon8.Drive.Usage

  @gib 1_073_741_824

  defp add!(user, folder_id, contents, name) do
    {:ok, file} = Drive.add_file(user, folder_id, tmp_upload(contents), name)
    file
  end

  describe "folders and files" do
    test "upload, list, dedupe names, nested folders and breadcrumbs" do
      user = user_fixture()
      {:ok, photos} = Drive.create_folder(user, nil, "Photos")
      {:ok, y2026} = Drive.create_folder(user, photos.id, "2026")

      a = add!(user, y2026.id, "hello", "a.txt")
      b = add!(user, y2026.id, "hello again", "a.txt")
      assert a.name == "a.txt"
      assert b.name == "a (1).txt"

      {:ok, listing} = Drive.list_folder(user, y2026.id)
      assert Enum.map(listing.files, & &1.name) == ["a (1).txt", "a.txt"]
      assert Enum.map(listing.breadcrumbs, & &1.name) == ["Photos", "2026"]
      assert Drive.resolve_path(user, ["Photos", "2026"]) == {:ok, y2026.id}
      assert Drive.resolve_path(user, ["Photos", ".."]) == {:error, :not_found}
    end

    test "identical content is stored once" do
      user = user_fixture()
      f1 = add!(user, nil, "same bytes", "one.bin")
      f2 = add!(user, nil, "same bytes", "two.bin")
      assert f1.blob_sha256 == f2.blob_sha256
      assert Storage.exists?(f1.blob_sha256)
    end

    test "usage tracks adds and deletes, including whole folder trees" do
      user = user_fixture()
      {:ok, dir} = Drive.create_folder(user, nil, "dir")
      {:ok, sub} = Drive.create_folder(user, dir.id, "sub")
      add!(user, dir.id, "12345", "x")
      add!(user, sub.id, "1234567890", "y")
      assert %{bytes_used: 15, file_count: 2} = Drive.summary(user)

      {:ok, %{deleted_files: 2, freed_bytes: 15}} = Drive.delete_folder(user, dir.id)
      assert %{bytes_used: 0, file_count: 0} = Drive.summary(user)
    end

    test "a folder cannot be moved into its own subtree" do
      user = user_fixture()
      {:ok, a} = Drive.create_folder(user, nil, "a")
      {:ok, b} = Drive.create_folder(user, a.id, "b")
      assert {:error, :cannot_move_into_itself} = Drive.move_folder(user, a.id, b.id)
    end

    test "users cannot see or touch each other's folders and files" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, folder} = Drive.create_folder(alice, nil, "private")
      file = add!(alice, folder.id, "secret", "s.txt")

      assert {:error, :not_found} = Drive.list_folder(bob, folder.id)
      assert {:error, :not_found} = Drive.delete_file(bob, file.id)
      assert {:error, :not_found} = Drive.delete_folder(bob, folder.id)
      assert {:error, :not_found} = Drive.add_file(bob, folder.id, tmp_upload("x"), "x")
      refute Drive.can_read?(bob, file, :id)
      refute Drive.can_read?(nil, file, :id)
    end

    test "active-content types are refused" do
      user = user_fixture()
      for name <- ~w(page.html logo.svg app.js) do
        assert {:error, :file_type_not_allowed} = Drive.add_file(user, nil, tmp_upload("<x>"), name)
      end
    end
  end

  describe "My Uploads helpers" do
    test "list_all_files/2 spans folders and filters by type; delete_files/2 frees space and ignores others' ids" do
      user = user_fixture()
      other = user_fixture()
      {:ok, dir} = Drive.create_folder(user, nil, "deep")
      png = add!(user, dir.id, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3>>, "pic.png")
      txt = add!(user, nil, "plain words", "notes.txt")
      theirs = add!(other, nil, "not yours", "x.txt")

      assert {:ok, all} = Drive.list_all_files(user)
      assert Enum.sort(Enum.map(all, & &1.id)) == Enum.sort([png.id, txt.id])
      assert {:ok, [%{id: id}]} = Drive.list_all_files(user, "image")
      assert id == png.id
      assert {:ok, [%{id: other_id}]} = Drive.list_all_files(user, "other")
      assert other_id == txt.id

      assert {:ok, 1} = Drive.delete_files(user, [txt.id, theirs.id, "not-a-uuid"])
      assert %{file_count: 1, bytes_used: size} = Drive.summary(user)
      assert size == png.size
      assert %{file_count: 1} = Drive.summary(other)
    end
  end

  describe "quota" do
    test "members are limited to the free 1 GB" do
      user = user_fixture()
      Repo.insert!(%Usage{user_id: user.id, bytes_used: @gib - 3, file_count: 1})

      assert {:error, :quota_exceeded} = Drive.add_file(user, nil, tmp_upload("four"), "f")
      assert {:ok, _} = Drive.add_file(user, nil, tmp_upload("abc"), "g")
    end

    test "single uploads are capped by role (members 25 MB)" do
      user = user_fixture()
      big = :binary.copy(<<0>>, 25 * 1_048_576 + 1)
      assert {:error, :too_large} = Drive.add_file(user, nil, tmp_upload(big), "big.bin")
      assert {:ok, _} = Drive.add_file(user_fixture(role: "editor"), nil, tmp_upload(big), "big.bin")
    end

    test "a storage tier replaces the free tier" do
      user = user_fixture()
      {:ok, _} = Entitlements.grant(user, %{kind: "storage_tier", key: "small", quantity: 10, source_type: "admin"})
      assert Drive.quota_bytes(user) == 10 * @gib
    end

    test "admins are unlimited" do
      assert Drive.quota_bytes(user_fixture(role: "admin")) == :unlimited
    end

    test "guests and banned users cannot store or be granted storage" do
      for role <- ~w(guest banned) do
        user = user_fixture(role: role)
        assert Drive.quota_bytes(user) == 0
        assert {:error, :no_storage} = Drive.add_file(user, nil, tmp_upload("x"), "x")
        assert {:error, :not_eligible} =
                 Entitlements.grant(user, %{kind: "storage_tier", key: "small", quantity: 10, source_type: "order"})
      end
    end
  end

  describe "sharing" do
    test "private -> link -> private; the link stops working when revoked or reset" do
      owner = user_fixture()
      stranger = user_fixture()
      file = add!(owner, nil, "share me", "s.txt")
      refute Drive.can_read?(stranger, file, :id)

      {:ok, linked} = Drive.set_visibility(owner, file.id, "link")
      assert is_binary(linked.share_token)
      assert Drive.get_file_by_share_token(linked.share_token).id == file.id
      assert Drive.can_read?(nil, linked, :share)
      # A link is not a public listing: /files/:id still refuses strangers.
      refute Drive.can_read?(nil, linked, :id)

      {:ok, reset} = Drive.reset_share_link(owner, file.id)
      assert reset.share_token != linked.share_token
      assert Drive.get_file_by_share_token(linked.share_token) == nil

      {:ok, private} = Drive.set_visibility(owner, file.id, "private")
      assert private.share_token == nil
      assert Drive.get_file_by_share_token(reset.share_token) == nil
    end

    test "public files are readable by anyone by id" do
      owner = user_fixture()
      file = add!(owner, nil, "hello world", "p.txt")
      {:ok, public} = Drive.set_visibility(owner, file.id, "public")
      assert Drive.can_read?(nil, public, :id)
    end
  end

  describe "role changes (Accounts.change_role/3)" do
    test "becoming guest locks the drive and revokes tiers; restoring unlocks" do
      user = user_fixture()
      file = add!(user, nil, "keep me", "k.txt")
      {:ok, _} = Drive.set_visibility(user, file.id, "public")
      {:ok, _} = Entitlements.grant(user, %{kind: "storage_tier", key: "xl", quantity: 100, source_type: "admin"})

      {:ok, guest} = Accounts.change_role(user, "guest")
      summary = Drive.summary(guest)
      assert summary.locked?
      assert DateTime.diff(summary.purge_after, DateTime.utc_now(), :day) in 29..30
      assert Entitlements.active(guest, "storage_tier") == []

      # Locked: the owner can do nothing and the public file is no longer public.
      assert {:error, :locked} = Drive.list_folder(guest, nil)
      refute Drive.can_read?(nil, Drive.get_file(file.id), :id)
      # Staff can still read for moderation.
      assert Drive.can_read?(user_fixture(role: "admin"), Drive.get_file(file.id), :id)

      {:ok, member} = Accounts.change_role(guest, "member")
      refute Drive.summary(member).locked?
      assert {:ok, %{files: [_]}} = Drive.list_folder(member, nil)
      # Tiers are not restored: back on the free tier.
      assert Drive.quota_bytes(member) == @gib
    end

    test "after 30 days the purge deletes the files and frees the space" do
      user = user_fixture()
      add!(user, nil, "doomed", "d.txt")
      {:ok, banned} = Accounts.change_role(user, "banned")

      # Not yet due.
      assert Drive.purge_due() == []

      later = DateTime.add(DateTime.utc_now(), 31 * 86_400, :second)
      assert Drive.purge_due(later) == [banned.id]
      assert %{bytes_used: 0, file_count: 0, locked?: true} = Drive.summary(banned)
    end

    test "restoring the role before the purge cancels it" do
      user = user_fixture()
      add!(user, nil, "saved", "s.txt")
      {:ok, guest} = Accounts.change_role(user, "guest")
      {:ok, _member} = Accounts.change_role(guest, "member")

      later = DateTime.add(DateTime.utc_now(), 31 * 86_400, :second)
      assert Drive.purge_due(later) == []
      assert %{file_count: 1} = Drive.summary(user)
    end
  end

  describe "blob GC" do
    test "removes bodies no file references, after the grace period" do
      user = user_fixture()
      file = add!(user, nil, "orphan soon", "o.txt")
      {:ok, _} = Drive.delete_file(user, file.id)

      # Still within the grace period.
      assert Drive.gc_blobs(3600) == 0
      assert Storage.exists?(file.blob_sha256)

      assert Drive.gc_blobs(-1) == 1
      refute Storage.exists?(file.blob_sha256)
    end

    test "never removes a body that is still referenced" do
      user = user_fixture()
      file = add!(user, nil, "still here", "h.txt")
      assert Drive.gc_blobs(-1) == 0
      assert Storage.exists?(file.blob_sha256)
    end
  end
end
