Moved word for word from BACON8.md (§7) on 2026-11-19; BACON8.md keeps a short summary and links here.

## 7. User storage and the file explorer

### Status: deployed 2026-10-15

The legacy import found nothing to move: production's `user_files` and `user_folders`
tables were empty, so the drive started clean. (The 19 `user_media` rows are blog, page
and chat images, which stay where they are by design.)

Before this milestone there were two storage systems that didn't know about each other:
Arc `UserFile` rows and the desktop explorer writing raw files under `uploads/users/<id>/`.
Uploads to My Files never saved, because the explorer only saved uploads for the old
`user://` paths, and refreshes never happened, because of invariant 13. Both are fixed.

### Design

**The database is the only source of truth**; `Bacon8.Storage` stores bodies by SHA-256
and nothing else.

| Table | Purpose |
|---|---|
| `drive_blobs` | one row per distinct SHA-256; `last_referenced_at` protects in-flight uploads from GC |
| `drive_folders` | tree per owner (`parent_id` nil = root); sibling names unique |
| `drive_files` | name, folder, blob, size, sniffed `content_type`, `visibility` (private / link / public), `share_token`, `legacy_ref` |
| `drive_usage` | per-user `bytes_used` / `file_count` (row-locked for every change), `locked_at`, `purge_after` |
| `entitlements` | grants; storage tiers are `kind: "storage_tier"`, `quantity` = GB (§8) |

| Module | Role |
|---|---|
| `Bacon8.Drive` | folders, files, upload (`add_file/5`), sharing, `can_read?/3`, lock/unlock, purge, blob GC |
| `Bacon8.Drive.Plans` | tiers and prices (decisions log) |
| `Bacon8.Drive.Policy` | pure quota and permission rules |
| `Bacon8.Drive.Sniff` | magic-byte type detection; only recognised types are ever served inline |
| `Bacon8.Drive.Janitor` | hourly: purge expired 30-day holds, GC unreferenced blobs; one node at a time via a Postgres advisory lock |
| `Bacon8.Storage` / `Storage.Local` | adapter behaviour; local blobs at `<root>/aa/bb/<sha>`; `DRIVE_STORAGE_ROOT` overrides the root |
| `Bacon8Web.DriveController` | `GET /files/:id` and `GET /s/:token`; nosniff, sandbox CSP (except PDF), inline only for recognised media, single-range requests |
| `Bacon8.Entitlements` | `grant/2` (refuses storage tiers for ineligible users), `active/2`, `revoke_all/3` |

**Concurrency.** Every change to a user's total locks their `drive_usage` row first, so
two uploads can't both pass the quota check. An upload upserts its blob row (taking the
row lock and bumping `last_referenced_at`) *before* making sure the body is on disk; GC
selects blobs `FOR UPDATE SKIP LOCKED` and deletes bodies inside its transaction. Either
the upload waits and rewrites the body, or GC skips that blob.

**Over quota** (after a tier lapses, or after the import): files are kept and stay
readable, and new uploads are refused until usage is back under the quota.

**Known gaps in this milestone**

- A crash between writing a body and committing can leave an unreferenced body on disk
  with no row, which GC never sees. This is rare; an occasional disk sweep can be added.
- No rename/move UI yet in the explorer (the context supports both).
- Thumbnails aren't generated for drive images; the explorer shows icons.

### Explorer

Drives: **My Files** (the user's drive, navigated by folder names: `/my-files/Photos/2026`)
and **Public** (still the legacy `uploads/public` directory, staff-writable, holding site
assets). Each My Files row has a visibility selector and, when shared, a click-to-copy
link. (The old `user://`, `root://` and `public://` code paths in `DesktopLive` were deleted on 2026-10-29.)

### The legacy import

`Bacon8.Drive.Import` and `mix drive.import` (moving the old `user_files`/`user_folders` into the drive) were
deleted on 2026-10-29, with the tables themselves (migration `20261029130000` drops each only if it is empty). Another install that still has legacy
rows should run the import from an older checkout (`git show 7ba5cb4:lib/bacon8/drive/import.ex`) first.

---

