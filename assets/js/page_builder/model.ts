// The page builder's data: rows of columns (cells) of blocks, saved as JSON in pages.content /
// posts.content. This shape is a contract (docs/pages-blog-builder.md): the server renders it
// (Bacon8Web.Components.BlockEditor.render_blocks/1), migrations write it (the legal pages, the
// credits page), and pages saved by the old editor must keep working. New keys are only ever
// added (row settings width/space/background/align, image size, the button block), never renamed.
//
// Everything here is pure (no DOM) and tested: assets/js/__tests__/page_builder_model.test.ts.

export type BlockType =
  | 'text' | 'heading' | 'image' | 'gallery' | 'video' | 'audio' | 'file' | 'button'
  | 'quote' | 'callout' | 'divider' | 'code' | 'html' | 'embed' | 'api';

export interface MediaItem { id: string; url: string; type: string; filename?: string; caption?: string; alt?: string }
export interface Block { id: string; type: BlockType; content: any; settings?: Record<string, any>; media?: MediaItem[] }
export interface Column { id: string; width: string; blocks: Block[] }
export interface RowSettings { width?: 'narrow' | 'normal' | 'wide' | 'full'; space?: 's' | 'm' | 'l'; background?: 'none' | 'glass' | 'tint' | 'dark'; align?: 'top' | 'center'; [k: string]: any }
export interface Row { id: string; columns: Column[]; settings?: RowSettings }
export interface Doc { rows: Row[]; version: number }

let counter = 0;
export const newId = (prefix = 'b'): string =>
  `${prefix}-${Date.now().toString(36)}-${(counter++).toString(36)}${Math.random().toString(36).slice(2, 6)}`;

// ------------------------------------------------------------------ reading what was saved

/** A doc from what pages.content holds: block JSON, old HTML (one text block), or nothing. */
export function parseDoc(raw: string | null | undefined): Doc {
  const text = (raw || '').trim();
  if (!text) return { rows: [], version: 1 };
  try {
    const parsed = JSON.parse(text);
    if (parsed && Array.isArray(parsed.rows)) return normalise(parsed);
  } catch {
    /* not JSON: HTML from before the block editor */
  }
  return { rows: [row([textBlock(text)])], version: 1 };
}

/** Fills in what older saves may lack (ids, widths, block lists) without changing anything else. */
export function normalise(doc: any): Doc {
  const rows: Row[] = (doc.rows || []).filter(Boolean).map((r: any) => {
    const cols: Column[] = (Array.isArray(r.columns) && r.columns.length ? r.columns : [{ blocks: [] }]).map((c: any) => ({
      ...c,
      id: c.id || newId('c'),
      width: typeof c.width === 'string' && c.width ? c.width : 'full',
      blocks: (Array.isArray(c.blocks) ? c.blocks : []).filter(Boolean).map((b: any) => ({ ...b, id: b.id || newId() })),
    }));
    return { ...r, id: r.id || newId('r'), columns: cols };
  });
  return { ...doc, rows, version: doc.version || 1 };
}

/** True when there is nothing in it worth keeping (an empty page: offer the starters). */
export function isEmpty(doc: Doc): boolean {
  return doc.rows.every((r) => r.columns.every((c) => c.blocks.every((b) => blockIsEmpty(b))));
}

export function blockIsEmpty(b: Block): boolean {
  if (b.type === 'divider') return false;
  if (b.type === 'gallery') return !(b.media && b.media.length);
  const c = typeof b.content === 'string' ? b.content.replace(/<br\s*\/?>/gi, '').replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').trim() : b.content;
  return !c;
}

// ------------------------------------------------------------------ making things

export const DEFAULTS: Record<BlockType, () => Partial<Block>> = {
  text: () => ({ content: '' }),
  heading: () => ({ content: '', settings: { level: 2 } }),
  image: () => ({ content: '', settings: { size: 'full' } }),
  gallery: () => ({ content: '', media: [], settings: { displayMode: 'grid' } }),
  video: () => ({ content: '' }),
  audio: () => ({ content: '' }),
  file: () => ({ content: '' }),
  button: () => ({ content: 'Get started', settings: { url: '', style: 'primary', align: 'center' } }),
  quote: () => ({ content: '', settings: { author: '' } }),
  callout: () => ({ content: '', settings: { calloutType: 'info' } }),
  divider: () => ({ content: '' }),
  code: () => ({ content: '', settings: { language: '' } }),
  html: () => ({ content: '' }),
  embed: () => ({ content: '' }),
  api: () => ({ content: '' }),
};

export function block(type: BlockType, over: Partial<Block> = {}): Block {
  const d = DEFAULTS[type]();
  return { id: newId(), type, content: '', ...d, ...over, settings: { ...(d.settings || {}), ...(over.settings || {}) } };
}

export const textBlock = (html = ''): Block => block('text', { content: html });

/** A row holding `blocks` in one column, or `perColumn` (one list per column). */
export function row(blocks: Block[] = [], settings: RowSettings = {}, perColumn?: Block[][]): Row {
  const lists = perColumn || [blocks];
  const widths = equalWidths(lists.length);
  // new rows say their width (rows saved before 2026-10-28 have none and keep the page's full width)
  return { id: newId('r'), columns: lists.map((bs, i) => ({ id: newId('c'), width: widths[i], blocks: bs })), settings: { width: 'normal', ...settings } };
}

export function equalWidths(n: number): string[] {
  if (n <= 1) return ['full'];
  const w = Math.round((100 / n) * 100) / 100;
  return Array.from({ length: n }, () => `${w}%`);
}

// The column layouts offered by a row's gear, as relative parts.
export const LAYOUTS: Record<string, number[]> = {
  '1': [1],
  '1-1': [1, 1],
  '1-2': [1, 2],
  '2-1': [2, 1],
  '1-1-1': [1, 1, 1],
  '1-2-1': [1, 2, 1],
  '1-1-1-1': [1, 1, 1, 1],
};

export function layoutWidths(parts: number[]): string[] {
  if (parts.length <= 1) return ['full'];
  const total = parts.reduce((a, b) => a + b, 0);
  return parts.map((p) => `${Math.round((p / total) * 10000) / 100}%`);
}

/** Which of LAYOUTS a row is in now (by its widths), or null when it was resized by hand. */
export function layoutOf(r: Row): string | null {
  const got = r.columns.map((c) => widthNumber(c.width, r.columns.length));
  for (const [name, parts] of Object.entries(LAYOUTS)) {
    if (parts.length !== got.length) continue;
    const want = layoutWidths(parts).map((w) => widthNumber(w, parts.length));
    if (want.every((w, i) => Math.abs(w - got[i]) < 1.5)) return name;
  }
  return null;
}

/** A column's width as a percentage number ("50%", "1/2", "full"). */
export function widthNumber(w: string, count: number): number {
  if (!w || w === 'full') return count <= 1 ? 100 : 100 / count;
  if (w.endsWith('%')) return parseFloat(w) || 100 / count;
  const m = w.match(/^(\d+)\/(\d+)$/);
  if (m) return (parseInt(m[1]) / parseInt(m[2])) * 100;
  return 100 / count;
}

// ------------------------------------------------------------------ finding things

export interface Where { r: number; c: number; b: number }

export function findBlock(doc: Doc, id: string): (Where & { block: Block }) | null {
  for (let r = 0; r < doc.rows.length; r++)
    for (let c = 0; c < doc.rows[r].columns.length; c++) {
      const b = doc.rows[r].columns[c].blocks.findIndex((x) => x.id === id);
      if (b >= 0) return { r, c, b, block: doc.rows[r].columns[c].blocks[b] };
    }
  return null;
}

export function findColumn(doc: Doc, id: string): { r: number; c: number } | null {
  for (let r = 0; r < doc.rows.length; r++) {
    const c = doc.rows[r].columns.findIndex((x) => x.id === id);
    if (c >= 0) return { r, c };
  }
  return null;
}

export const rowIndex = (doc: Doc, id: string): number => doc.rows.findIndex((r) => r.id === id);

// ------------------------------------------------------------------ changing things
// Every change returns a new doc (the old one stays as it was, for undo).

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x));

export function insertRow(doc: Doc, at: number, r: Row): Doc {
  const d = clone(doc);
  d.rows.splice(Math.max(0, Math.min(at, d.rows.length)), 0, r);
  return d;
}

export function removeRow(doc: Doc, id: string): Doc {
  const d = clone(doc);
  d.rows = d.rows.filter((r) => r.id !== id);
  return d;
}

export function moveRow(doc: Doc, id: string, by: number): Doc {
  const i = rowIndex(doc, id);
  const j = i + by;
  if (i < 0 || j < 0 || j >= doc.rows.length) return doc;
  const d = clone(doc);
  const [r] = d.rows.splice(i, 1);
  d.rows.splice(j, 0, r);
  return d;
}

/** Moves row `id` to just before row index `before` (or to the end). */
export function moveRowTo(doc: Doc, id: string, before: number): Doc {
  const i = rowIndex(doc, id);
  if (i < 0) return doc;
  const d = clone(doc);
  const [r] = d.rows.splice(i, 1);
  d.rows.splice(before > i ? before - 1 : before, 0, r);
  return d;
}

export function duplicateRow(doc: Doc, id: string): Doc {
  const i = rowIndex(doc, id);
  if (i < 0) return doc;
  const copy = freshIds(clone(doc.rows[i]));
  return insertRow(doc, i + 1, copy);
}

export function setRowSettings(doc: Doc, id: string, settings: RowSettings): Doc {
  const d = clone(doc);
  const r = d.rows.find((x) => x.id === id);
  if (r) r.settings = { ...(r.settings || {}), ...settings };
  return d;
}

/**
 * Gives row `id` the column layout `name` (LAYOUTS). Fewer columns than before: the blocks of the
 * columns that go are moved into the last one kept, so nothing is ever lost by a layout change.
 */
export function setLayout(doc: Doc, id: string, name: string): Doc {
  const parts = LAYOUTS[name];
  if (!parts) return doc;
  const d = clone(doc);
  const r = d.rows.find((x) => x.id === id);
  if (!r) return doc;
  const widths = layoutWidths(parts);
  while (r.columns.length < parts.length) r.columns.push({ id: newId('c'), width: 'full', blocks: [] });
  if (r.columns.length > parts.length) {
    const gone = r.columns.splice(parts.length);
    const keep = r.columns[parts.length - 1];
    for (const g of gone) keep.blocks.push(...g.blocks);
  }
  r.columns.forEach((c, i) => (c.width = widths[i]));
  return d;
}

/** Sets the widths of two neighbouring columns (dragging the line between them), in percent. */
export function resizeColumns(doc: Doc, rowId: string, left: number, leftPercent: number): Doc {
  const d = clone(doc);
  const r = d.rows.find((x) => x.id === rowId);
  if (!r || left < 0 || left + 1 >= r.columns.length) return doc;
  const n = r.columns.length;
  const a = widthNumber(r.columns[left].width, n);
  const b = widthNumber(r.columns[left + 1].width, n);
  const pair = a + b;
  const min = 12;
  const na = Math.max(min, Math.min(pair - min, Math.round(leftPercent * 2) / 2));
  r.columns[left].width = `${na}%`;
  r.columns[left + 1].width = `${Math.round((pair - na) * 100) / 100}%`;
  return d;
}

/** Puts `b` into column `colId` at `at` (end when undefined). */
export function insertBlock(doc: Doc, colId: string, b: Block, at?: number): Doc {
  const d = clone(doc);
  const w = findColumn(d, colId);
  if (!w) return doc;
  const list = d.rows[w.r].columns[w.c].blocks;
  list.splice(at === undefined ? list.length : Math.max(0, Math.min(at, list.length)), 0, b);
  return d;
}

export function insertBlockAfter(doc: Doc, afterId: string, b: Block): Doc {
  const w = findBlock(doc, afterId);
  if (!w) return doc;
  return insertBlock(doc, doc.rows[w.r].columns[w.c].id, b, w.b + 1);
}

export function updateBlock(doc: Doc, id: string, patch: Partial<Block>): Doc {
  const d = clone(doc);
  const w = findBlock(d, id);
  if (!w) return doc;
  const b = d.rows[w.r].columns[w.c].blocks[w.b];
  if ('content' in patch) b.content = patch.content;
  if (patch.settings) b.settings = { ...(b.settings || {}), ...patch.settings };
  if (patch.media) b.media = patch.media;
  if (patch.type) b.type = patch.type;
  return d;
}

/** In place, for typing: no copy, no history step (the hook records typing in bursts). */
export function setContentInPlace(doc: Doc, id: string, content: any): boolean {
  const w = findBlock(doc, id);
  if (!w) return false;
  w.block.content = content;
  return true;
}

export function removeBlock(doc: Doc, id: string): Doc {
  const d = clone(doc);
  const w = findBlock(d, id);
  if (!w) return doc;
  d.rows[w.r].columns[w.c].blocks.splice(w.b, 1);
  return d;
}

export function duplicateBlock(doc: Doc, id: string): Doc {
  const w = findBlock(doc, id);
  if (!w) return doc;
  return insertBlockAfter(doc, id, freshIds(clone(w.block)));
}

/** Up or down within its column; at the top or bottom of a column it moves to the row before or after. */
export function moveBlock(doc: Doc, id: string, by: number): Doc {
  const w = findBlock(doc, id);
  if (!w) return doc;
  const d = clone(doc);
  const list = d.rows[w.r].columns[w.c].blocks;
  const j = w.b + by;
  if (j >= 0 && j < list.length) {
    const [b] = list.splice(w.b, 1);
    list.splice(j, 0, b);
    return d;
  }
  const r2 = w.r + (by < 0 ? -1 : 1);
  if (r2 < 0 || r2 >= d.rows.length) return doc;
  const [b] = list.splice(w.b, 1);
  const cols = d.rows[r2].columns;
  const target = cols[Math.min(w.c, cols.length - 1)].blocks;
  if (by < 0) target.push(b);
  else target.unshift(b);
  return d;
}

/** Drag and drop: block `id` into column `colId`, before block index `at`. */
export function moveBlockTo(doc: Doc, id: string, colId: string, at: number): Doc {
  const w = findBlock(doc, id);
  const t = findColumn(doc, colId);
  if (!w || !t) return doc;
  const d = clone(doc);
  const [b] = d.rows[w.r].columns[w.c].blocks.splice(w.b, 1);
  let i = at;
  if (w.r === t.r && w.c === t.c && w.b < at) i -= 1;
  const list = d.rows[t.r].columns[t.c].blocks;
  list.splice(Math.max(0, Math.min(i, list.length)), 0, b);
  return d;
}

/** Empty rows (every cell empty of blocks) go; used after moves. Keeps at least nothing. */
export function dropEmptyRows(doc: Doc): Doc {
  const d = clone(doc);
  d.rows = d.rows.filter((r) => r.columns.some((c) => c.blocks.length > 0));
  return d;
}

function freshIds<T extends Row | Block>(x: T): T {
  const any = x as any;
  if (any.columns) {
    any.id = newId('r');
    for (const c of any.columns) {
      c.id = newId('c');
      c.blocks = c.blocks.map((b: Block) => freshIds(b));
    }
  } else {
    any.id = newId();
    if (any.media) any.media = any.media.map((m: MediaItem) => ({ ...m, id: newId('m') }));
  }
  return x;
}

// ------------------------------------------------------------------ undo

/** Undo and redo over whole docs, kept as JSON. */
export class History {
  private past: string[] = [];
  private future: string[] = [];
  constructor(private limit = 100) {}
  record(doc: Doc) {
    const s = JSON.stringify(doc);
    if (this.past[this.past.length - 1] === s) return;
    this.past.push(s);
    if (this.past.length > this.limit) this.past.shift();
    this.future = [];
  }
  undo(current: Doc): Doc | null {
    const prev = this.past.pop();
    if (!prev) return null;
    this.future.push(JSON.stringify(current));
    return JSON.parse(prev);
  }
  redo(current: Doc): Doc | null {
    const next = this.future.pop();
    if (!next) return null;
    this.past.push(JSON.stringify(current));
    return JSON.parse(next);
  }
  get canUndo() { return this.past.length > 0; }
  get canRedo() { return this.future.length > 0; }
}

// ------------------------------------------------------------------ text helpers

/** What a line typed at the start of a paragraph turns into ("# " a heading, "- " a list...). */
export function shortcutFor(lineStart: string): { command: string; value?: string; strip: number } | null {
  const rules: Array<[RegExp, string, string | undefined]> = [
    [/^#{1}\s$/, 'formatBlock', 'h2'],
    [/^#{2,3}\s$/, 'formatBlock', 'h3'],
    [/^[-*]\s$/, 'insertUnorderedList', undefined],
    [/^1[.)]\s$/, 'insertOrderedList', undefined],
    [/^>\s$/, 'formatBlock', 'blockquote'],
  ];
  for (const [re, command, value] of rules) if (re.test(lineStart)) return { command, value, strip: lineStart.length };
  return null;
}

/** A link a button may point at: http(s), mailto, a path on this site, or #. Anything else is refused. */
export function safeUrl(url: string): string {
  const u = (url || '').trim();
  if (!u) return '';
  if (/^(https?:\/\/|mailto:)/i.test(u)) return u;
  if (/^\/(?!\/)/.test(u) || u.startsWith('#')) return u;
  if (/^[a-z0-9.-]+\.[a-z]{2,}(\/|$)/i.test(u)) return `https://${u}`;
  return '';
}

/** Plain text from pasted HTML, keeping paragraphs and line breaks (pastes never bring styles). */
export function pasteToHtml(text: string): string {
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return text
    .replace(/\r\n?/g, '\n')
    .split(/\n{2,}/)
    .map((p) => `<p>${esc(p).replace(/\n/g, '<br>')}</p>`)
    .join('');
}
