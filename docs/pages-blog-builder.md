# Plan: the /pages and /blog builders

Status: **not started; this is the starting point.** Written 2026-10-25; the owner answered the first questions the same day (below).
The owner's words: the core keeps the traditional `/pages` and `/blog`, "which need to be
bolstered quite a bit as the build tool for both isn't production grade."

## What exists (measured)

| | Lines |
|---|---|
| `Bacon8Web.PageEditorLive` (the page editor) | 649 |
| `Bacon8Web.BlogEditorLive` (the post editor) | 663 |
| `Bacon8Web.PageLive` (public pages) and `PageLive.Index` | 382 |
| `Bacon8Web.BlogLive` (public blog) | 592 |
| `Bacon8Web.Components.BlockEditor` (the block builder) | 453 |
| Admin: `AdminLive.Pages`, `AdminLive.BlogManagement` | 605 (blog management) |
| Context and schemas: `Bacon8.Content`, `Content.Page`, `Post`, `Comment` | 252 and about 300 |

A page's body is JSON in the `pages.content` text column: rows, then columns (with a width),
then blocks. Block types the editor knows: text, html, quote, callout, divider, embed, api
and button, among others. The seven legal pages (terms, privacy, refunds, copyright, contact,
credits, gems) are seeded by a migration as unpublished placeholders, and the credits page is
edited by migrations (textures, MakeHuman), so **the JSON shape is a contract** other code
writes to. Do not change it without a migration.

## What is already known to be wrong (found by the tests)

The 34 tests in `test/bacon8/content_test.exs` pin the context. Writing them found, and
`37d84ea` fixed:

- publishing without an explicit `published_at` crashed (microseconds in a whole-second column);
- a draft with no body crashed on the `NOT NULL` column;
- renaming rewrote the URL, even when the editor sent the old slug back;
- `approve_comment` approved nothing (and `spam_comment` did nothing and was never called).

Still true and **not** yet looked at:

- **Comments have no moderation UI.** The model has `is_approved`; nothing in `lib/` or the
  plugins calls `approve_comment`. Whether comments are shown, and who approves them, is open.
- **No tests of the editors or the public pages** (they are LiveViews; none of the 3,000+
  lines is covered). The context is covered; the behaviour a visitor sees is not.
- **Nothing has been checked about the editors' own behaviour**: autosave, preview,
  validation messages, mobile, accessibility, image handling (`Content.list_user_media`
  carries a `rescue` fallback for a missing `folder_path` column, which says the schema and
  the database have drifted before).
- Slugs: a collision gives "has already been taken" and the user must pick another; there is
  no suffixing. The slug is cut at 100 characters for posts but not for pages.
- `Content.list_posts_by_type/1` and the `:post_type` filter are stubs ("not implemented in
  current schema").

## Decisions so far (owner, 2026-10-25)

- **Start with tests for the editors**, so the rebuild has a safety net.
- **Who writes:** admins, GMs and editors only. Members don't write pages or posts. (So there is no
  member-facing editor, and comment moderation is a staff job.)
- **Keep the rows, columns and blocks model.** Every existing page keeps working, and no
  content migration is needed.

## Still to ask

1. **What is wrong in daily use?** The most useful input is a list of what annoyed the owner in the
   editors; it decides the order better than an audit.
2. **What does "production grade" need to include?** A suggested list to pick from: revisions and
   undo; scheduled publishing; SEO fields and a sitemap that follows published pages; an image
   library with alt text; preview before publishing; categories and tags on posts; an RSS feed;
   comment moderation with spam control.
3. **Is the blog per-site content only**, or may games (plugins) post to it (patch notes)?

## Suggested order

1. Tests for the LiveViews that matter (the editors' save, publish and error paths, and
   the public pages' draft/published rules), so the rebuild has a safety net, as the forum
   got.
2. Fix what the owner listed in question 1.
3. Add the production-grade items the owner picked in question 4, one at a time, each with
   tests and a deploy.
