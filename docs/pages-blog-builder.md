# Pages and blog: how the builder works

The core keeps the traditional `/pages` and `/blog`. Only admins, GMs and editors write them (members comment).
Pages and posts are edited **in place**, on the public address, with the page builder (last section). The admin
screens (`/admin/pages`, `/admin/blog-management`) list, start, publish, schedule and delete; staff with the
`:content` area reach them (`Bacon8.Permissions`; `admin_access_test.exs` guards every other admin route).

## The pieces

| | Where |
|---|---|
| Public pages and in-place editing | `Bacon8Web.PageLive` (`/pages/:slug`), `BlogLive` (`/blog/:slug`); both hand their editing events to `Bacon8Web.InPlaceEditing` |
| Shared editing events (media, body, autosave) | `Bacon8Web.ContentEditing` (`lib/bacon8_web/live/content_editing.ex`) |
| Admin lists | `AdminLive.Pages`, `AdminLive.BlogManagement` |
| The editing screen and settings panel | `Components.EditorShell`, `Components.ContentSettings` |
| The editor (JavaScript) | `assets/js/page_builder/`; `block_editor_library.ts` (the image library window) and `block_editor_columns.ts` |
| Public rendering of blocks | `Components.BlockEditor` |
| Context and schemas | `Bacon8.Content`, `Page`, `Post`, `Comment`, `Content.InlineMedia`, `Content.Library`, `Content.Revisions`, `Content.Publisher` |

A page's body is JSON in the `pages.content` text column: rows, then columns (with a width), then blocks. Block
types the editor knows: text, html, quote, callout, divider, embed, api and button, among others. The seven legal
pages (terms, privacy, refunds, copyright, contact, credits, gems) are seeded by a migration as unpublished
placeholders, and the credits page is edited by migrations (textures, MakeHuman), so **the JSON shape is a contract**
other code writes to. Do not change it without a migration.

## Security (found by the tests, 2026-10-25, and fixed)

- **Drafts are for staff only** (admins, GMs, editors). Everyone else is sent to the blog; a slug nobody has does the
  same instead of crashing.
- **Uploads and removals are confined.** The inline media handlers had two path-traversal holes (the temp file was
  named from the client's file name; "remove" joined any `/uploads/public/...` URL without resolving `..`). Both now
  go through `Bacon8.Content.InlineMedia` and `Bacon8.SafePath`: a page can remove only its own uploads, an upload
  over 25 MB is refused, and `store/2` refuses types a browser runs (BACON8.md invariant 4).
  `Uploads.delete_file/1` and `file_exists?/1` are confined too.
- A second session attacked `remove/2` and it held; the review found gaps elsewhere (avatars, chat channel icons,
  `.rss`/`.atom` served inline), now fixed (see BACON8.md's decisions log).

## Tests

| File | Covers |
|---|---|
| `test/bacon8/content_test.exs` | the context: slugs, publishing, drafts, listing, comments |
| `test/bacon8/safe_path_test.exs` | `SafePath`: resolve, inside?, filename, active content (it guards every upload) |
| `test/bacon8/content/inline_media_test.exs` | storing and removing inline media, with hostile names and URLs; refused types; size |
| `test/bacon8/uploads_paths_test.exs` | URL to path, delete, exists, all confined; never the drive's blobs |
| `test/bacon8_web/plugs/uploads_guard_test.exs` | what `/uploads` serves inline and what it sandboxes |
| `test/bacon8_web/live/page_live_test.exs`, `blog_live_test.exs` | who sees what; the edit button; editing in place; media events |
| `test/bacon8_web/live/admin_pages_test.exs`, `admin_blog_management_test.exs` | access; starting, listing, publishing, scheduling, deleting |
| `test/bacon8_web/live/in_place_editing_test.exs`, `content_editing_test.exs` | settings, publishing, schedule, versions, deleting, featured image, the library in the editor |
| `test/bacon8/content/library_test.exs`, `plugin_posts_test.exs` | the image library; posts from plugins |
| `test/bacon8_web/live/page_builder_test.exs`, `assets/js/__tests__/page_builder_model.test.ts` | the page builder (server side; the editor's model) |
| `test/bacon8_web/controllers/editor_media_controller_test.exs` | the HTTP upload |

## Not covered, or open

- The editor's rendering of every block type and `render_blocks/1` are lightly tested. The seeded legal pages and
  the credits migrations depend on the JSON shape.
- The social share component and `PageLive.Index`.
- Slugs: a collision says "has already been taken" and the user chooses another (posts cut the slug at 100
  characters, pages don't). `Content.list_posts_by_type/1` and the `:post_type` filter are stubs.
- `Content.list_user_media/1` carries a `rescue` for a missing `folder_path` column: the schema and the database
  have drifted before.

## One builder (2026-10-26)

The four screens now share **one implementation of the editor's events**, `Bacon8Web.ContentEditing`
(`lib/bacon8_web/live/content_editing.ex`): media upload and removal (through `Content.InlineMedia`, per-record
folders), the body the editor sends, and autosave for the admin screens. `PageLive` and `BlogLive` lost their
copies of the media handlers.

Found while merging: **the admin screens never handled the editor's events.** `/admin/pages` had no clause for
`editor-change`, `editor-autosave` or the media events (the block editor pushes them as you type), and
`/admin/blog-management` swallowed them in a catch-all, so **pictures and files dropped into the editor there
silently went nowhere**. Both now handle them.

To give an upload somewhere to live, **a new page or post is created as a saved draft the moment you press New**
(`Content.create_draft/2`: "Untitled", a free slug). Cancelling a draft you started and never wrote in deletes it
(`Content.untouched_draft?/1`, only the one started in that session). The slug follows the first real title
(`Content.slug_for_save/3`), but never a slug someone typed or one a published page lives at.
`Bacon8.Content.Slugs.free/2` is the shared "never collides" slug (plugin posts use it too). Autosave on the admin
screens saves only unpublished records, so a live page changes when its editor presses Save or Publish.
Tests: `test/bacon8_web/live/content_editing_test.exs`.

**One editing UI (2026-10-26, the owner's choice: edit in place everywhere).** Pages and posts are edited
where they are shown: `/pages/:slug` and `/blog/:slug`, opened with "Edit Page"/"Edit Post" or `?edit=1`. The
admin screens (`/admin/pages`, `/admin/blog-management`) only **list, start, publish/unpublish, schedule and
delete**: their forms are gone; "New page/post" makes a draft and opens it in place; "Edit" is a link to the same.
`Bacon8Web.InPlaceEditing` holds every editing event for both LiveViews (each has one clause handing the
`InPlaceEditing.events()` to it); `Components.ContentSettings` draws the toolbar and the settings panel (title,
address, summary, search description, template/category or tags, featured image, share buttons, schedule,
Publish now/Unpublish, earlier versions, Delete).

What is saved when: a **draft** autosaves as you type. A **published** page or post is never changed behind the
editor's back: typing is kept in the session ("Not saved yet. The live page changes when you press Save"), and
Save & Exit, Save settings or Publish writes it; Cancel throws it away. (Before, the in-place editors autosaved
straight onto the live page and the toolbar's Cancel said "Changes discarded" while discarding nothing.) A just-
started draft nobody wrote in is deleted on Cancel. Changing the address reopens the page at the new one.

Retired with the admin forms: the media-picker window and the featured-image upload field of the admin form (the
settings panel has a file field and the image library instead). `MediaPickerComponent` (deleted 2026-10-29) was used by blog
management.

## The image library (2026-10-26)

`Bacon8.Content.Library` (+ `content_images`): every picture added to a page or post by `InlineMedia.store/3` is
recorded (url, name, sha256, size, who). The block editor's empty image block has "Choose from the image library";
the gallery has "From the library" (several pictures per visit); the settings panel's featured image has the same
picker. `block_editor_library.ts` draws the window (search by file name, 40 at a time, "Show more") and asks the
server with `library-list` (a LiveView reply); `library-use` **copies** the chosen picture into this page's own
folder (`Library.use_image/3`), so deleting the first page, which deletes its folder, never breaks the second.
The same picture (same sha256) is listed once. `Library.sync_from_disk/0` runs whenever the library is opened: it
adds pictures that predate the table (scanning `uploads/public/pages|blog/*`, skipping `thumb_*`/`transcoded_*`)
and forgets rows whose file is gone. Only staff can list or use it. Not done: deleting from the library, alt text
stored with a picture, the Drive's files (`user_media`) or other contexts (avatars, chat), a picture picker
for the text block's inline images.

## Production-grade items the owner picked (2026-10-26)

Chosen from the list: SEO, image alt text, RSS and comment moderation. All built and tested.

- **Image alt text.** Each image block has an alt text field (amber until filled in) and a *Decorative* switch
  (empty alt on purpose). `Bacon8.Content.Audit.images_missing_alt/1` counts pictures without alt text (blocks,
  galleries, old HTML); `/admin/pages` and `/admin/blog-management` show "N images without alt text" on each row.
- **SEO.** `Bacon8Web.Seo` gives every page and post a description (meta description, else excerpt, else the
  body's first words, at most 160 characters), a canonical address, a preview image (featured image, else the
  first picture) and `noindex` for drafts. The root layout turns those into canonical, Open Graph and Twitter
  tags; before this every page said "The kitchen sink." `/sitemap.xml` is built from published pages and posts
  (`SeoController`; the hand-written file is gone). Not done: structured data (JSON-LD), per-page keywords UI.
- **RSS.** `/blog/feed.xml`: the 20 newest published posts, escaped, the author's display name only, the body
  in CDATA; advertised in every page's head.
- **Comments.** The blog had no way to comment at all. Now signed-in members with a verified email can comment
  under a post (`Bacon8Web.Components.Comments`, `Content.submit_comment/3`). Rules in `Content.Moderation`:
  staff are approved at once; more than two links holds a comment; a member with an approved comment is approved
  at once; everyone else's first comment waits. At most 5 comments an hour and no immediate repeats. Comments are
  plain text. `/admin/comments` (admins, GMs, editors) has Waiting / Approved / Spam tabs, approve, spam, delete,
  approve all and delete all spam. `comments.is_spam` is new (spam is kept on record, shown nowhere).
  Replies (one level deep; the person answered is notified once the reply shows), one unread "comment waiting"
  notice for staff at a time (`Content.CommentNotices`), and members can edit or delete their own comment (an edit
  goes through the rules again; `comments.edited_at`). Deleting a comment deletes its replies. Not done: replies
  by email, a member seeing their own held comment.

## Scheduling, earlier versions, own held comments (2026-10-26)

- **Scheduled publishing.** `posts.scheduled_at` / `pages.scheduled_at`: a draft with a time goes live by itself.
  The editors have a "Schedule" box (UTC); *Save* keeps the draft until then, *Publish* publishes at once and clears
  the time. `Bacon8.Content.Publisher` (a GenServer, every node, guarded by a Postgres advisory lock) calls
  `Content.publish_due/0` each minute; a scheduled record that can't be published (no body) is left a draft with the
  time cleared. Disabled in tests (`config :bacon8, Bacon8.Content.Publisher, enabled: false`). Lists show "Goes live ...".
- **Earlier versions.** `content_revisions` (`Content.Revisions`): `update_page/2` and `update_post/2` keep the
  version *before* a save that changed the title, excerpt or body, at most one per record per five minutes (the editors
  autosave every few seconds), at most 50 per record, none for an empty body. The editors list them under "Earlier
  versions"; Restore keeps the current version first, so a restore can be undone. Deleting a record deletes its versions.
  Not done: comparing two versions side by side; restoring the schedule/featured image/tags (words only).
- **Own held comments.** A member sees their own comment that still waits for a moderator, marked "Only you can see it".

## Posts from plugins and games

`Bacon8.Content.post_from_plugin(plugin_slug, %{title:, body: [...], excerpt:, tags:}, publish: true, author: user)`
(`lib/bacon8/content/plugin_posts.ex`). The owner approved this on 2026-10-25 (patch notes, announcements).
The body is a list of `{:heading, text}`, `{:paragraph, text}` and `{:list, [text]}`; all text is HTML-escaped,
so a game can put player names in a post safely. It makes a **draft** unless `publish: true`, authored by the
given user or the oldest admin, tagged with the plugin's slug, with a numbered slug if the title is taken.
Staff edit it afterwards in the block editor like any post. Tests: `test/bacon8/content/plugin_posts_test.exs`.

## The page builder (2026-10-28)

The owner: the editor "needs to be the star of the show", redone "with mobile first in mind", "subtle reactive
components, but minimalistic. A few + buttons or gear icons", "simple ways to create cells, rows, columns to help keep
content centered and well maintained", and creating a page or post should be quick and easy.

**Where.** `assets/js/page_builder/`: `model.ts` (the data and every change to it, pure and tested:
`assets/js/__tests__/page_builder_model.test.ts`), `templates.ts` (the starters), `render.ts` (the canvas and the
sheets as HTML), `ui.ts` (the sheet and the formatting bar), `html.ts` (the HTML sent beside the JSON), `hook.ts`
(the LiveView hook, still called `BlockEditor`, and `AutoGrow` for the title). Styles: `assets/css/page_builder.css`.
The editing screen: `Bacon8Web.Components.EditorShell`, shown by `PageLive` and `BlogLive` while editing.
The old editor (`block_editor_hook.ts`) was deleted 2026-10-29; `block_editor_library.ts` and `block_editor_columns.ts` stay.

**What it does.**

- **New page / New post** in the start menu (staff with the `:content` area): a draft, opened in the editor
  (`DesktopLive` "new_content"). The admin lists' New buttons still work too.
- **An empty page offers starters**: Blank, Article, Landing page, Gallery, Announcement, and for posts Patch notes.
  Each is ordinary rows of placeholder blocks.
- **The editing screen** is full screen: a slim bar (close, Draft/Live and how saving is going, Undo, Redo, phone-width
  preview, the settings gear, Done/Save, Publish), the title typed in place (`update_title`; a new draft's "Untitled"
  shows as an empty box), the address under it (tap: settings), then the page. The settings panel
  (`ContentSettings.settings/1`, unchanged) slides in from the right, or up from the bottom on a phone.
- **Rows**: a + between rows (faint until hovered; always there on touch) adds a block or a row of 2, 3 or 4
  columns. A row's gear: column layout in one tap (1, ½+½, ⅓+⅔, ⅔+⅓, three, ¼+½+¼, four; fewer columns move the
  blocks into the last one kept, never lose them), width (narrow 600, normal 760, wide 1100, full), spacing, background
  (none, glass, tint, dark), line up (top/middle; for one column, text left/centre), Up, Down, Copy, Delete. With a
  mouse the line between two columns drags to resize them, and rows and blocks drag by their handle.
- **Cells**: an empty cell shows its own +.
- **Blocks**: tap to select; the gear has the block's own options and Up, Down, Copy, Delete; text-like blocks can be
  turned into each other. Text is typed in place. Selecting words shows a small bar (bold, italic, link, heading,
  smaller heading, list, numbered list, quote, plain); on a phone it sits above the keyboard. "# ", "## ", "- ",
  "1. " and "> " at the start of a line make a heading, a list or a quote; "/" in an empty paragraph opens the add
  sheet; Enter after a heading or button starts a paragraph; Backspace in an empty paragraph removes it. Pasting
  brings words, never styles. The font, size and colour pickers are gone (pages stay consistent; old pages keep their
  formatting). Pictures: upload (a phone offers the camera), the library, or a link; dropped or pasted files become
  picture, gallery, video, audio or file blocks where they land. A picture without alt text shows "Add alt text".
  **Since 2026-10-29 uploads go by HTTP** (`POST /editor/media`, `Bacon8Web.EditorMediaController`: the session
  signs it in, the CSRF token guards it, staff only, 25 MB at most, the same checks as `InlineMedia.store/3`), and a
  photo is shrunk in the browser to 2560 px on its long side first (a JPEG; PNGs keep their transparency; GIFs are
  sent as they are). The old way, base64 inside the `block-media-upload` LiveView event, made a phone photo one
  WebSocket frame of several megabytes: the connection dropped, the picture never arrived, and a page opened with
  the Edit button came back closed (the server still handles the event, for library pictures and old clients).
  The editor puts `?edit=1` in the address while it is open (and tells LiveView, which rejoins with its own copy of
  the address), so a dropped connection comes back editing, and it re-sends its words when the connection returns
  (a published page's unsaved words live in the LiveView until Save). "Uploading…" and an upload's error are never
  saved (`model.withoutTransient/1`).
- **Undo and Redo** (also Ctrl/Cmd+Z, Shift+Z, Y): whole-page snapshots, one step per burst of typing.
- **New block: Button** (label typed on it; link, look and place in its gear). The editor refuses links that aren't
  http(s), mailto, a path here or #, and so does the server (`BlockEditor.safe_href/1`).

**The saved format** is unchanged and only grew (the contract above): rows may have `settings` `width`, `space`,
`background`, `align`; images `settings.size` (`small`/`medium`/`full`); the `button` block. New rows always carry a
`width`, and the public render wraps only such rows in `<section class="content-section ...">`
(`BlockEditor.section_classes/1`, known values only), so every page saved before renders exactly as it did. Heading
levels are clamped to 1-6 on render (a saved level went straight into the tag before). Styles for the public side:
`.content-section`, `.content-button`, `figure.img-small/medium` in `app.css`. Tests:
`test/bacon8_web/live/page_builder_test.exs`.

**Not done yet**: drag to reorder on touch screens (Up/Down in the gear instead), per-picture alt text in a gallery,
image links, the text block's inline pictures, comparing versions.
