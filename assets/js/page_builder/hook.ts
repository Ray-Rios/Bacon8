// The page builder (2026-10-28): the editor for pages and posts, made for a phone first.
// LiveView hook "BlockEditor" on Bacon8Web.Components.BlockEditor.block_editor/1. It talks to the
// server exactly as the old editor did (editor-change / editor-autosave with the JSON,
// block-media-upload, library-list / library-use; it hears block-media-uploaded / -error and
// update-editor-content), so Bacon8Web.InPlaceEditing and ContentEditing are unchanged.
//
// What the person sees: the page as it will look, with a + between rows (and in every empty
// cell) to add blocks or columns, a gear on whatever they tapped, typing straight onto the page,
// a small bar for bold/italic/links when words are selected, Undo/Redo, and a set of starters
// when the page is empty. Data operations: model.ts. Markup: render.ts. Sheet and bar: ui.ts.

import * as M from './model';
import { STARTERS, startersFor } from './templates';
import { addSheet, blockHtml, blockSheet, canvas, rowSheet, startersSheet } from './render';
import { docToHtml } from './html';
import { FormatBar, Sheet, caretToEnd, isPhone, pickFiles } from './ui';
import { openLibrary } from '../block_editor_library';

const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
// The server's limit (Bacon8.Content.InlineMedia, 25 MB).
const MAX_FILE = 25 * 1024 * 1024;
// Photos are shrunk in the browser before they're sent: a phone's 12-megapixel shot becomes a
// sharp 2560 px JPEG of a few hundred KB, which uploads in a moment on mobile data.
const MAX_SIDE = 2560;
const CALLOUTS = ['info', 'tip', 'success', 'warning', 'error'];

type Ctx = { mode: 'at'; at: number } | { mode: 'in'; col: string } | { mode: 'after'; block: string; replace?: boolean };

export const PageBuilder = {
  mounted(this: any) {
    this.kind = (this.el.dataset.kind || 'page') as 'page' | 'post';
    this.recordId = this.el.dataset.recordId || '';
    // The address says the editor is open (?edit=1), so if the connection drops (a phone switching
    // to its photo picker, a tunnel) the page comes back still editing instead of closing the editor.
    if (this.el.dataset.readonly !== 'true') setEditParam(true);
    this.autosaveDelay = parseInt(this.el.dataset.autosaveDelay || '5000');
    this.doc = M.parseDoc(this.el.dataset.initialContent);
    this.history = new M.History();
    this.selected = null as null | { kind: 'row' | 'block'; id: string };
    this.typingSince = 0;
    this.sheet = new Sheet();
    this.fmt = new FormatBar((cmd: string, value?: string) => this.format(cmd, value));
    this.el.innerHTML = `<div class="pb" data-kind="${this.kind}"><div class="pb-canvas" data-preview="auto"></div></div>`;
    this.canvas = this.el.querySelector('.pb-canvas');
    try {
      document.execCommand('defaultParagraphSeparator', false, 'p'); // Enter makes <p>, not <div>
    } catch { /* older browsers */ }
    this.render();
    this.listen();
    this.serverEvents();
    if (M.isEmpty(this.doc) && this.el.dataset.readonly !== 'true') this.offerStarters();
  },

  // The connection came back (LiveView keeps this element): the server may have lost what it was
  // holding unsaved, so send the editor's current state again.
  reconnected(this: any) {
    this.changed = true;
    this.flush();
  },

  destroyed(this: any) {
    if (this.el.dataset.readonly !== 'true' && !document.getElementById(this.el.id)) setEditParam(false);
    clearTimeout(this.changeTimer);
    clearTimeout(this.saveTimer);
    if (this.changed) this.flush();
    this.sheet.destroy();
    this.fmt.destroy();
    document.removeEventListener('selectionchange', this.onSelection);
    document.removeEventListener('keydown', this.onKey, true);
    document.removeEventListener('click', this.beforeSave, true);
    document.removeEventListener('submit', this.beforeSave, true);
    window.removeEventListener('pb:undo', this.onUndo);
    window.removeEventListener('pb:redo', this.onRedo);
    window.removeEventListener('pb:preview', this.onPreview);
    delete document.documentElement.dataset.pbUndo;
    delete document.documentElement.dataset.pbRedo;
  },

  // ---------------------------------------------------------------- drawing

  render(this: any, focus?: string) {
    this.canvas.innerHTML = canvas(this.doc);
    this.canvas.classList.toggle('is-blank', this.doc.rows.length === 0);
    this.applySelection();
    this.updateUndo();
    if (focus) this.focusBlock(focus);
  },

  // a single block redrawn (media arriving, a setting changed) without touching the rest
  renderBlock(this: any, id: string) {
    const w = M.findBlock(this.doc, id);
    const el = this.canvas.querySelector(`.pb-block[data-block="${id}"]`);
    if (!w || !el) return this.render();
    const tmp = document.createElement('div');
    tmp.innerHTML = blockHtml(w.block);
    const fresh = tmp.firstElementChild as HTMLElement;
    el.replaceWith(fresh);
    this.applySelection();
  },

  applySelection(this: any) {
    for (const el of Array.from(this.canvas.querySelectorAll('.is-selected')) as HTMLElement[]) el.classList.remove('is-selected');
    if (!this.selected) return;
    const s = this.selected;
    const el = this.canvas.querySelector(s.kind === 'row' ? `.pb-row[data-row="${s.id}"]` : `.pb-block[data-block="${s.id}"]`);
    if (!el) return;
    el.classList.add('is-selected');
    el.closest('.pb-row')?.classList.add('is-selected');
  },

  select(this: any, kind: 'row' | 'block', id: string) {
    this.selected = { kind, id };
    this.applySelection();
  },

  focusBlock(this: any, id: string) {
    this.select('block', id);
    const el = this.canvas.querySelector(`.pb-block[data-block="${id}"] [contenteditable], .pb-block[data-block="${id}"] textarea, .pb-block[data-block="${id}"] .pb-input`) as HTMLElement | null;
    if (el) {
      if (el.isContentEditable) caretToEnd(el);
      else el.focus();
    }
    const blk = this.canvas.querySelector(`.pb-block[data-block="${id}"]`) as HTMLElement | null;
    if (blk && blk.scrollIntoView) {
      const r = blk.getBoundingClientRect();
      if (r.top < 60 || r.bottom > window.innerHeight - 60) blk.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  },

  // ---------------------------------------------------------------- changing

  /** A structural change: remember where we were (undo), redraw, tell the server. */
  commit(this: any, next: M.Doc, focus?: string) {
    if (next === this.doc) return;
    this.history.record(this.doc);
    this.doc = next;
    this.typingSince = 0;
    this.render(focus);
    this.changedNow();
  },

  changedNow(this: any) {
    this.changed = true;
    clearTimeout(this.changeTimer);
    this.changeTimer = setTimeout(() => this.flush(), 250);
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.save(), this.autosaveDelay);
  },

  payload(this: any) {
    // "Uploading…" and an upload's error are this screen's state, not the page's: never saved.
    const doc = M.withoutTransient(this.doc);
    return { content: JSON.stringify(doc), html: docToHtml(doc), format: 'blocks' };
  },

  flush(this: any) {
    clearTimeout(this.changeTimer);
    if (!this.changed) return;
    this.changed = false;
    this.send('editor-change', this.payload());
  },

  save(this: any) {
    this.changed = false;
    const p = this.payload();
    this.send('editor-change', p);
    this.send('editor-autosave', p);
  },

  /** Sends to the server, or (no connection right now) keeps the change for `reconnected()` to send. */
  send(this: any, event: string, payload: any) {
    if (this.liveSocket && typeof this.liveSocket.isConnected === 'function' && !this.liveSocket.isConnected()) {
      this.changed = true;
      return;
    }
    try {
      const sent = this.pushEvent(event, payload);
      if (sent && typeof sent.catch === 'function') sent.catch(() => { this.changed = true; });
    } catch {
      this.changed = true;
    }
  },

  undo(this: any) {
    const prev = this.history.undo(this.doc);
    if (!prev) return;
    this.doc = M.normalise(prev);
    this.sheet.close();
    this.render();
    this.changedNow();
  },

  redo(this: any) {
    const next = this.history.redo(this.doc);
    if (!next) return;
    this.doc = M.normalise(next);
    this.sheet.close();
    this.render();
    this.changedNow();
  },

  updateUndo(this: any) {
    const ds = document.documentElement.dataset;
    if (this.history.canUndo) ds.pbUndo = '1'; else delete ds.pbUndo;
    if (this.history.canRedo) ds.pbRedo = '1'; else delete ds.pbRedo;
  },

  // ---------------------------------------------------------------- typing

  /** Typing changes the doc in place; one undo step per burst of typing. */
  typed(this: any, el: HTMLElement) {
    const id = el.dataset.block!;
    const field = el.dataset.edit || 'content';
    const now = Date.now();
    if (now - this.typingSince > 1500) this.history.record(this.doc);
    this.typingSince = now;
    let value: string;
    if (el.tagName === 'TEXTAREA') value = (el as HTMLTextAreaElement).value;
    else if (el.dataset.plain === '1') value = (el.innerText || '').replace(/\n+$/, '');
    else value = cleanHtml(el.innerHTML);
    const w = M.findBlock(this.doc, id);
    if (!w) return;
    if (field === 'content') w.block.content = value;
    else w.block.settings = { ...(w.block.settings || {}), [field]: value };
    el.classList.toggle('is-blank', !(el.innerText || '').trim());
    this.updateUndo();
    this.changedNow();
  },

  markdown(this: any, el: HTMLElement) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount || !sel.isCollapsed) return;
    const node = sel.anchorNode;
    if (!node || !el.contains(node)) return;
    // the text from the start of this paragraph (or list item) up to the caret
    const host = (node.nodeType === 3 ? node.parentElement : (node as HTMLElement)) as HTMLElement;
    let line: HTMLElement | null = host.closest('p,li,h2,h3,h4,blockquote,div');
    if (!line || !el.contains(line)) line = el;
    if (line.closest('li,h2,h3,h4,blockquote') && line !== el) return; // already formatted
    const r = document.createRange();
    r.setStart(line, 0);
    r.setEnd(node, sel.anchorOffset);
    const before = r.toString().replace(/\u00a0/g, ' ');
    const rule = M.shortcutFor(before);
    if (!rule) return;
    r.deleteContents();
    if (!(line.textContent || '').length && line !== el) line.innerHTML = '<br>';
    if (rule.command !== 'formatBlock' && line !== el) {
      // a list: the paragraph becomes its first item (execCommand would nest the list in the <p>)
      const list = document.createElement(rule.command === 'insertOrderedList' ? 'ol' : 'ul');
      const li = document.createElement('li');
      li.innerHTML = line.innerHTML || '<br>';
      list.append(li);
      line.replaceWith(list);
      const at = document.createRange();
      at.setStart(li, 0);
      at.collapse(true);
      sel.removeAllRanges();
      sel.addRange(at);
      return;
    }
    const caret = document.createRange();
    caret.setStart(line === el ? el : line, 0);
    caret.collapse(true);
    sel.removeAllRanges();
    sel.addRange(caret);
    document.execCommand(rule.command, false, rule.value ? `<${rule.value}>` : undefined);
  },

  format(this: any, cmd: string, value?: string) {
    const map: Record<string, [string, string?]> = {
      bold: ['bold'], italic: ['italic'], ul: ['insertUnorderedList'], ol: ['insertOrderedList'],
      h2: ['formatBlock', '<h2>'], h3: ['formatBlock', '<h3>'], quote: ['formatBlock', '<blockquote>'],
    };
    if (cmd === 'link') {
      const url = M.safeUrl(value || '');
      if (url) document.execCommand('createLink', false, url);
      else document.execCommand('unlink');
    } else if (cmd === 'clear') {
      document.execCommand('removeFormat');
      document.execCommand('formatBlock', false, '<p>');
      document.execCommand('unlink');
    } else if (cmd === 'h2' || cmd === 'h3' || cmd === 'quote') {
      const want = map[cmd][1]!.replace(/[<>]/g, '');
      const cur = String(document.queryCommandValue('formatBlock') || '').toLowerCase();
      document.execCommand('formatBlock', false, cur === want ? '<p>' : map[cmd][1]);
    } else if (map[cmd]) {
      document.execCommand(map[cmd][0], false, map[cmd][1]);
    }
    const ed = (window.getSelection()?.anchorNode as HTMLElement | null)?.parentElement?.closest?.('.pb-text') as HTMLElement | null;
    if (ed) this.typed(ed);
  },

  // ---------------------------------------------------------------- adding

  openAdd(this: any, ctx: Ctx, anchor: HTMLElement | null) {
    this.addCtx = ctx;
    this.sheet.show({
      anchor,
      html: addSheet(ctx.mode, this.kind),
      wide: true,
      onAct: (act: string, el: HTMLElement) => {
        if (act === 'pick-block') this.addBlock(el.dataset.type as M.BlockType);
        if (act === 'pick-columns') this.addColumns(parseInt(el.dataset.n || '2'));
      },
    });
  },

  addBlock(this: any, type: M.BlockType) {
    const ctx: Ctx = this.addCtx;
    const b = M.block(type);
    this.sheet.close();
    let next: M.Doc;
    if (ctx.mode === 'at') next = M.insertRow(this.doc, ctx.at, M.row([b]));
    else if (ctx.mode === 'in') next = M.insertBlock(this.doc, ctx.col, b);
    else {
      next = M.insertBlockAfter(this.doc, ctx.block, b);
      if (ctx.replace) next = M.removeBlock(next, ctx.block);
    }
    this.commit(next, b.id);
    if (type === 'image' && isPhone()) {
      /* on a phone, go straight to the camera / photos */
      this.upload(b.id, 'image');
    }
  },

  addColumns(this: any, n: number) {
    const ctx: Ctx = this.addCtx;
    this.sheet.close();
    if (ctx.mode !== 'at') return;
    const r = M.row([], {}, Array.from({ length: n }, () => []));
    this.commit(M.insertRow(this.doc, ctx.at, r));
    this.select('row', r.id);
  },

  offerStarters(this: any) {
    let picked = false;
    this.sheet.show({
      anchor: null,
      wide: true,
      html: startersSheet(startersFor(this.kind), this.kind),
      onAct: (act: string, el: HTMLElement) => {
        if (act !== 'starter') return;
        const s = STARTERS.find((x) => x.id === el.dataset.starter);
        picked = true;
        this.sheet.close();
        if (!s) return;
        const next = M.normalise(s.make());
        this.commit(next);
        const first = this.canvas.querySelector('[contenteditable]') as HTMLElement | null;
        if (first) {
          const id = first.dataset.block!;
          this.focusBlock(id);
        }
      },
      onClose: () => {
        if (picked) return;
        if (this.doc.rows.length === 0) this.commit(M.insertRow(this.doc, 0, M.row([M.textBlock('')])), undefined);
        const first = this.canvas.querySelector('[contenteditable]') as HTMLElement | null;
        if (first && !isPhone()) this.focusBlock(first.dataset.block!);
      },
    });
  },

  // ---------------------------------------------------------------- gears

  openRowGear(this: any, id: string, anchor: HTMLElement) {
    const r = this.doc.rows.find((x: M.Row) => x.id === id);
    if (!r) return;
    this.select('row', id);
    this.sheet.show({
      anchor,
      html: rowSheet(r),
      onAct: (act: string, el: HTMLElement) => {
        let next = this.doc;
        if (act === 'row-layout') next = M.setLayout(this.doc, id, el.dataset.layout!);
        else if (act === 'row-set') next = M.setRowSettings(this.doc, id, { [el.dataset.key!]: el.dataset.val });
        else if (act === 'row-move') next = M.moveRow(this.doc, id, parseInt(el.dataset.by!));
        else if (act === 'row-dup') next = M.duplicateRow(this.doc, id);
        else if (act === 'row-del') {
          this.sheet.close();
          return this.commit(M.removeRow(this.doc, id));
        }
        this.commit(next);
        this.select('row', id);
        const again = this.doc.rows.find((x: M.Row) => x.id === id);
        if (again) {
          this.sheet.anchor = this.canvas.querySelector(`.pb-row[data-row="${id}"] [data-act="row-gear"]`);
          this.sheet.update(rowSheet(again));
        }
      },
    });
  },

  openBlockGear(this: any, id: string, anchor: HTMLElement) {
    const w = M.findBlock(this.doc, id);
    if (!w) return;
    this.select('block', id);
    const refresh = () => {
      const again = M.findBlock(this.doc, id);
      if (!again) return this.sheet.close();
      this.sheet.anchor = this.canvas.querySelector(`.pb-block[data-block="${id}"] [data-act="block-gear"]`);
      this.sheet.update(blockSheet(again.block));
      this.linkHint();
    };
    this.sheet.show({
      anchor,
      html: blockSheet(w.block),
      onAct: (act: string, el: HTMLElement) => {
        if (act === 'block-set') {
          const key = el.dataset.key!;
          let val: any = el.dataset.val;
          if (key === 'level') val = parseInt(val);
          this.commit(M.updateBlock(this.doc, id, { settings: { [key]: val } }));
        } else if (act === 'block-turn') {
          const b = M.findBlock(this.doc, id)!.block;
          const to = el.dataset.val as M.BlockType;
          const text = toPlain(b);
          const content = to === 'text' ? (b.type === 'text' ? b.content : text ? `<p>${escHtml(text)}</p>` : '') : text;
          this.commit(M.updateBlock(this.doc, id, { type: to, content, settings: M.DEFAULTS[to]().settings || {} }));
        } else if (act === 'block-move') this.commit(M.moveBlock(this.doc, id, parseInt(el.dataset.by!)));
        else if (act === 'block-dup') this.commit(M.duplicateBlock(this.doc, id));
        else if (act === 'block-del') {
          this.sheet.close();
          return this.removeBlock(id);
        } else if (act === 'upload') return this.upload(id, el.dataset.kind || 'image');
        else if (act === 'library') return this.library(id, false);
        else if (act === 'library-gallery') return this.library(id, true);
        else if (act === 'gallery-add') return this.upload(id, 'gallery');
        else if (act === 'media-remove') {
          const b = M.findBlock(this.doc, id)!.block;
          if (b.content && /^\/uploads\//.test(b.content)) this.pushEvent('block-media-remove', { blockId: id, url: b.content });
          this.commit(M.updateBlock(this.doc, id, { content: '', settings: { alt: '', caption: '', filename: '' } }));
        }
        this.select('block', id);
        refresh();
      },
      onInput: (name: string, el: HTMLInputElement | HTMLTextAreaElement, ev: Event) => {
        if (name === 'alt') this.setQuiet(id, { alt: el.value });
        if (name === 'decorative') {
          this.commit(M.updateBlock(this.doc, id, { settings: { decorative: (el as HTMLInputElement).checked } }));
          refresh();
        }
        if (name === 'link') {
          const safe = M.safeUrl(el.value);
          this.setQuiet(id, { url: safe || '' });
          this.linkHint(el.value, safe);
          if (ev.type === 'keydown') this.sheet.close();
        }
      },
      onClose: () => this.renderBlock(id),
    });
    this.linkHint();
  },

  linkHint(this: any, raw?: string, safe?: string) {
    const hint = this.sheet.el.querySelector('[data-hint="link"]') as HTMLElement | null;
    if (!hint) return;
    if (raw === undefined) {
      hint.textContent = '';
      return;
    }
    hint.textContent = raw && !safe ? 'That link won’t work: use https://…, a page here such as /store, or an email (mailto:).' : safe && safe !== raw.trim() ? `Will link to ${safe}` : '';
  },

  /** A setting typed in the sheet: saved as you type, one undo step per burst, the block redrawn on close. */
  setQuiet(this: any, id: string, settings: Record<string, any>) {
    const now = Date.now();
    if (now - this.typingSince > 1500) this.history.record(this.doc);
    this.typingSince = now;
    const w = M.findBlock(this.doc, id);
    if (!w) return;
    w.block.settings = { ...(w.block.settings || {}), ...settings };
    this.updateUndo();
    this.changedNow();
  },

  removeBlock(this: any, id: string) {
    const w = M.findBlock(this.doc, id);
    if (!w) return;
    const col = this.doc.rows[w.r].columns[w.c];
    const prev = col.blocks[w.b - 1];
    let next = M.removeBlock(this.doc, id);
    // a row left with nothing in any cell goes too
    const r = next.rows[w.r];
    if (r && r.columns.every((c: M.Column) => c.blocks.length === 0) && r.columns.length === 1) next = M.removeRow(next, r.id);
    this.commit(next, prev ? prev.id : undefined);
  },

  // ---------------------------------------------------------------- media

  async upload(this: any, id: string, kind: string) {
    const accept = { image: 'image/*', gallery: 'image/*', video: 'video/*', audio: 'audio/*', file: '.pdf,.doc,.docx,.txt,.zip,.rar,.xlsx,.pptx' }[kind] || '*/*';
    const files = await pickFiles(accept, kind === 'gallery');
    if (!files.length) return;
    this.sheet.close();
    for (const f of files) this.sendFile(id, f, kind === 'gallery' ? 'gallery' : kind);
  },

  sendFile(this: any, id: string, file: File, mediaType: string) {
    if (file.size > MAX_FILE) return this.mediaError(id, 'That file is over 50 MB.');
    if ((mediaType === 'image' || mediaType === 'gallery') && !IMAGE_TYPES.includes(file.type)) return this.mediaError(id, 'Pictures can be JPEG, PNG, GIF or WebP.');
    const settings: Record<string, any> = { loading: true, error: '' };
    if (mediaType === 'file' || mediaType === 'audio') {
      settings.filename = file.name;
      settings.fileSize = file.size >= 1048576 ? `${(file.size / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(file.size / 1024))} KB`;
      settings.fileType = file.type === 'application/pdf' ? 'pdf' : /word/.test(file.type) ? 'word' : /zip|rar/.test(file.type) ? 'archive' : 'document';
    }
    const w = M.findBlock(this.doc, id);
    if (!w) return;
    w.block.settings = { ...(w.block.settings || {}), ...settings };
    this.renderBlock(id);
    const isImage = mediaType === 'image' || mediaType === 'gallery';
    (isImage ? shrinkPhoto(file) : Promise.resolve(file))
      .then((f) => postMedia(this.kind, this.recordId, f))
      .then(({ url, filename }) => this.mediaDone(id, url, mediaType, filename))
      .catch((e: Error) => this.mediaError(id, e.message || 'The upload failed.'));
  },

  /** An upload finished: the picture or file goes into its block (or its gallery). */
  mediaDone(this: any, blockId: string, url: string, mediaType: string, filename?: string, mediaId?: string) {
    const w = M.findBlock(this.doc, blockId);
    if (!w) return;
    const b = w.block;
    b.settings = { ...(b.settings || {}), loading: false, error: '' };
    if (mediaType === 'gallery') b.media = [...(b.media || []), { id: mediaId || M.newId('m'), url, type: 'image', filename }];
    else {
      b.content = url;
      if (filename) b.settings.filename = filename;
    }
    this.renderBlock(blockId);
    this.changedNow();
  },

  mediaError(this: any, id: string, error: string) {
    const w = M.findBlock(this.doc, id);
    if (!w) return;
    w.block.settings = { ...(w.block.settings || {}), loading: false, error };
    this.renderBlock(id);
  },

  library(this: any, id: string, gallery: boolean) {
    this.sheet.close();
    openLibrary({
      title: gallery ? 'Add pictures from the library' : 'Choose a picture',
      multiple: gallery,
      fetch: (query: string, offset: number) =>
        new Promise((resolve, reject) => {
          const t = setTimeout(() => reject(new Error('timeout')), 15000);
          this.pushEvent('library-list', { query, offset }, (reply: any) => {
            clearTimeout(t);
            resolve(reply);
          });
        }),
      onPick: (image: { url: string }) => {
        const w = M.findBlock(this.doc, id);
        if (w) {
          w.block.settings = { ...(w.block.settings || {}), loading: true, error: '' };
          this.renderBlock(id);
        }
        this.pushEvent('library-use', { blockId: id, url: image.url, mediaType: gallery ? 'gallery' : 'image' });
      },
    });
  },

  /** Files dropped or pasted: a block for each, after `afterId` or at the end of column `colId`. */
  dropFiles(this: any, files: File[], where: { col?: string; at?: number; after?: string }) {
    const blocks: M.Block[] = [];
    const sends: Array<[string, File, string]> = [];
    const images = files.filter((f) => IMAGE_TYPES.includes(f.type));
    if (images.length > 1) {
      const g = M.block('gallery');
      blocks.push(g);
      for (const f of images) sends.push([g.id, f, 'gallery']);
    } else if (images.length === 1) {
      const b = M.block('image');
      blocks.push(b);
      sends.push([b.id, images[0], 'image']);
    }
    for (const f of files.filter((x) => !IMAGE_TYPES.includes(x.type))) {
      const kind = f.type.startsWith('video/') ? 'video' : f.type.startsWith('audio/') ? 'audio' : 'file';
      const b = M.block(kind as M.BlockType);
      blocks.push(b);
      sends.push([b.id, f, kind]);
    }
    if (!blocks.length) return;
    let next = this.doc;
    if (where.after) {
      let after = where.after;
      for (const b of blocks) {
        next = M.insertBlockAfter(next, after, b);
        after = b.id;
      }
    } else if (where.col) {
      for (const b of blocks) next = M.insertBlock(next, where.col, b);
    } else {
      next = M.insertRow(next, where.at ?? next.rows.length, M.row(blocks));
    }
    this.commit(next);
    for (const [id, f, kind] of sends) this.sendFile(id, f, kind);
  },

  // ---------------------------------------------------------------- events

  listen(this: any) {
    const c = this.canvas as HTMLElement;

    c.addEventListener('click', (e: MouseEvent) => {
      const t = e.target as HTMLElement;
      const act = t.closest('[data-act]') as HTMLElement | null;
      if (act && c.contains(act)) {
        e.preventDefault();
        const a = act.dataset.act!;
        const blockId = act.dataset.block || (act.closest('.pb-block') as HTMLElement | null)?.dataset.block;
        if (a === 'add-at') return this.openAdd({ mode: 'at', at: parseInt(act.dataset.at!) }, act);
        if (a === 'add-in') return this.openAdd({ mode: 'in', col: act.dataset.col! }, act);
        if (a === 'row-gear') return this.openRowGear(act.dataset.row!, act);
        if (a === 'block-gear') return this.openBlockGear(blockId!, act);
        if (a === 'upload') return this.upload(blockId!, act.dataset.kind || 'image');
        if (a === 'library') return this.library(blockId!, false);
        if (a === 'gallery-add') return this.upload(blockId!, 'gallery');
        if (a === 'gallery-remove') {
          const w = M.findBlock(this.doc, blockId!);
          if (!w) return;
          const item = act.dataset.item!;
          this.pushEvent('block-media-remove', { blockId, itemId: item });
          return this.commit(M.updateBlock(this.doc, blockId!, { media: (w.block.media || []).filter((m: M.MediaItem) => m.id !== item) }));
        }
        if (a === 'callout-next') {
          const w = M.findBlock(this.doc, blockId!);
          const cur = CALLOUTS.indexOf(w?.block.settings?.calloutType || 'info');
          return this.commit(M.updateBlock(this.doc, blockId!, { settings: { calloutType: CALLOUTS[(cur + 1) % CALLOUTS.length] } }));
        }
        return;
      }
      const blk = t.closest('.pb-block') as HTMLElement | null;
      if (blk) return this.select('block', blk.dataset.block!);
      const row = t.closest('.pb-row') as HTMLElement | null;
      if (row) return this.select('row', row.dataset.row!);
      this.selected = null;
      this.applySelection();
    });

    c.addEventListener('focusin', (e: FocusEvent) => {
      const t = e.target as HTMLElement;
      const blk = t.closest('.pb-block') as HTMLElement | null;
      if (blk) this.select('block', blk.dataset.block!);
      // a text block emptied to nothing gets its paragraph back
      if (t.classList.contains('pb-text') && !t.firstElementChild) {
        t.innerHTML = '<p><br></p>';
        const r = document.createRange();
        r.setStart(t.firstElementChild!, 0);
        r.collapse(true);
        const sel = window.getSelection();
        sel?.removeAllRanges();
        sel?.addRange(r);
      }
    });

    c.addEventListener('input', (e: Event) => {
      const t = e.target as HTMLElement;
      if (t.dataset && t.dataset.edit) {
        if (t.classList.contains('pb-text')) this.markdown(t);
        this.typed(t);
      }
    });

    c.addEventListener('keydown', (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      const id = t.dataset && t.dataset.block;
      if (!id) return;
      // inputs inside empty media blocks: a link, then Enter
      if (t.dataset.actInput && e.key === 'Enter') {
        e.preventDefault();
        return this.mediaUrl(id, t as HTMLInputElement);
      }
      if (!t.isContentEditable) return;
      const empty = !(t.innerText || '').trim();
      if (e.key === '/' && empty && t.classList.contains('pb-text')) {
        e.preventDefault();
        return this.openAdd({ mode: 'after', block: id, replace: true }, t);
      }
      if (e.key === 'Enter' && !e.shiftKey && t.dataset.plain === '1' && t.dataset.edit === 'content' && !t.classList.contains('pb-quote-text') && !t.classList.contains('pb-callout-text')) {
        // Enter at the end of a heading or button starts a new paragraph after it
        e.preventDefault();
        const b = M.textBlock('');
        return this.commit(M.insertBlockAfter(this.doc, id, b), b.id);
      }
      if (e.key === 'Enter' && t.dataset.plain === '1' && t.dataset.edit !== 'content') e.preventDefault();
      if (e.key === 'Backspace' && empty && t.classList.contains('pb-text')) {
        const w = M.findBlock(this.doc, id);
        const total = this.doc.rows.reduce((n: number, r: M.Row) => n + r.columns.reduce((m: number, cc: M.Column) => m + cc.blocks.length, 0), 0);
        if (w && total > 1) {
          e.preventDefault();
          this.removeBlock(id);
        }
      }
    });

    c.addEventListener('paste', (e: ClipboardEvent) => {
      const t = e.target as HTMLElement;
      const ed = t.closest('[contenteditable]') as HTMLElement | null;
      const files = Array.from(e.clipboardData?.files || []);
      if (files.length && ed) {
        e.preventDefault();
        return this.dropFiles(files, { after: ed.dataset.block });
      }
      if (!ed) return;
      e.preventDefault();
      const text = e.clipboardData?.getData('text/plain') || '';
      if (ed.dataset.plain === '1') document.execCommand('insertText', false, text.replace(/\s*\n\s*/g, ' '));
      else document.execCommand('insertHTML', false, M.pasteToHtml(text));
    });

    // the formatting bar follows a selection inside a text block
    this.onSelection = () => {
      if (this.fmt.busy) return;
      const sel = window.getSelection();
      if (!sel || !sel.rangeCount || sel.isCollapsed) return this.fmt.hide();
      const node = sel.anchorNode as Node | null;
      const host = node && (node.nodeType === 3 ? node.parentElement : (node as HTMLElement));
      const ed = host && host.closest ? (host.closest('.pb-text') as HTMLElement | null) : null;
      if (!ed || !c.contains(ed)) return this.fmt.hide();
      this.fmt.showFor(sel.getRangeAt(0));
    };
    document.addEventListener('selectionchange', this.onSelection);

    // Ctrl/Cmd+Z, Shift+Z, Y. Escape lets go of the selection.
    this.onKey = (e: KeyboardEvent) => {
      if (!this.el.isConnected) return;
      const mod = e.metaKey || e.ctrlKey;
      if (mod && (e.key === 'z' || e.key === 'Z')) {
        if (!this.el.contains(document.activeElement) && document.activeElement !== document.body) return;
        e.preventDefault();
        return e.shiftKey ? this.redo() : this.undo();
      }
      if (mod && (e.key === 'y' || e.key === 'Y')) {
        e.preventDefault();
        return this.redo();
      }
      if (e.key === 'Escape' && this.sheet.open) return this.sheet.close();
      if (e.key === 'Escape') {
        this.selected = null;
        this.applySelection();
      }
    };
    document.addEventListener('keydown', this.onKey, true);

    // the top bar (Bacon8Web.Components.EditorShell) sends these
    this.onUndo = () => this.undo();
    this.onRedo = () => this.redo();
    this.onPreview = (e: CustomEvent) => {
      const v = (e.detail && e.detail.mode) || (this.canvas.dataset.preview === 'phone' ? 'auto' : 'phone');
      this.canvas.dataset.preview = v;
      document.documentElement.dataset.pbPreview = v;
    };
    window.addEventListener('pb:undo', this.onUndo);
    window.addEventListener('pb:redo', this.onRedo);
    window.addEventListener('pb:preview', this.onPreview);

    // Save, Publish and Done are outside the editor: send the latest words before their click.
    this.beforeSave = (e: Event) => {
      const t = e.target as Element | null;
      if (!t || !t.closest) return;
      if (t.closest('[phx-click="save_content"], [phx-click="set_published"], [data-pb-flush]') || (e.type === 'submit' && t.closest('#settings-form'))) this.flush();
    };
    document.addEventListener('click', this.beforeSave, true);
    document.addEventListener('submit', this.beforeSave, true);

    this.dragAndDrop();
    this.resizing();
  },

  mediaUrl(this: any, id: string, input: HTMLInputElement) {
    const kind = input.dataset.actInput;
    const v = input.value.trim();
    if (!v) return;
    if (kind === 'embed') return this.commit(M.updateBlock(this.doc, id, { content: v }));
    const w = M.findBlock(this.doc, id);
    if (!w) return;
    const url = M.safeUrl(v);
    if (!url) return this.mediaError(id, 'That link won’t work: it needs to start with https://');
    this.commit(M.updateBlock(this.doc, id, { content: url, settings: { error: '' } }));
  },

  // ---------------------------------------------------------------- drag and drop (mouse)

  dragAndDrop(this: any) {
    const c = this.canvas as HTMLElement;
    let dragging: null | { kind: 'row' | 'block'; id: string } = null;
    const marker = document.createElement('div');
    marker.className = 'pb-drop-line';
    let target: null | { col?: string; at: number } = null;

    const clear = () => {
      marker.remove();
      target = null;
      c.classList.remove('is-dragging');
    };

    c.addEventListener('dragstart', (e: DragEvent) => {
      const g = (e.target as HTMLElement).closest('[data-drag]') as HTMLElement | null;
      if (!g) return;
      dragging = { kind: g.dataset.drag as 'row' | 'block', id: (g.dataset.block || g.dataset.row)! };
      e.dataTransfer?.setData('text/plain', dragging.id);
      if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
      const el = g.closest(dragging.kind === 'row' ? '.pb-row' : '.pb-block') as HTMLElement;
      if (el && e.dataTransfer) e.dataTransfer.setDragImage(el, 20, 20);
      c.classList.add('is-dragging');
    });

    c.addEventListener('dragover', (e: DragEvent) => {
      const files = e.dataTransfer && Array.from(e.dataTransfer.types || []).includes('Files');
      if (!dragging && !files) return;
      e.preventDefault();
      if (dragging?.kind === 'row' || (!dragging && !(e.target as HTMLElement).closest('.pb-col'))) {
        // between rows
        const rows = Array.from(c.querySelectorAll('.pb-row')) as HTMLElement[];
        let at = rows.length;
        for (let i = 0; i < rows.length; i++) {
          const r = rows[i].getBoundingClientRect();
          if (e.clientY < r.top + r.height / 2) { at = i; break; }
        }
        target = { at };
        const ref = rows[at];
        if (ref) ref.before(marker);
        else c.querySelector('.pb-insert-end')?.before(marker);
        marker.className = 'pb-drop-line is-row';
        return;
      }
      const col = (e.target as HTMLElement).closest('.pb-col') as HTMLElement | null;
      if (!col) return;
      const blocks = (Array.from(col.querySelectorAll(':scope > .pb-block')) as HTMLElement[]).filter((b) => b.dataset.block !== dragging?.id);
      let at = blocks.length;
      for (let i = 0; i < blocks.length; i++) {
        const r = blocks[i].getBoundingClientRect();
        if (e.clientY < r.top + r.height / 2) { at = i; break; }
      }
      // index among all blocks of the column (the dragged one included) for moveBlockTo
      const all = Array.from(col.querySelectorAll(':scope > .pb-block')) as HTMLElement[];
      const ref = blocks[at];
      target = { col: col.dataset.col!, at: ref ? all.indexOf(ref) : all.length };
      if (ref) ref.before(marker);
      else col.querySelector(':scope > .pb-cell-add')?.before(marker);
      marker.className = 'pb-drop-line';
    });

    c.addEventListener('dragleave', (e: DragEvent) => {
      if (!c.contains(e.relatedTarget as Node)) marker.remove();
    });

    c.addEventListener('drop', (e: DragEvent) => {
      e.preventDefault();
      const t = target;
      const d = dragging;
      dragging = null;
      clear();
      if (!t) return;
      const files = Array.from(e.dataTransfer?.files || []);
      if (!d && files.length) return this.dropFiles(files, t.col ? { col: t.col } : { at: t.at });
      if (!d) return;
      if (d.kind === 'row') return this.commit(M.moveRowTo(this.doc, d.id, t.at));
      if (t.col) {
        let next = M.moveBlockTo(this.doc, d.id, t.col, t.at);
        next = dropEmptySingleRows(next);
        this.commit(next);
        this.select('block', d.id);
      } else {
        // a block dropped between rows becomes a row of its own
        const w = M.findBlock(this.doc, d.id);
        if (!w) return;
        let next = M.removeBlock(this.doc, d.id);
        next = M.insertRow(next, t.at - (w.r < t.at && rowWillVanish(this.doc, w) ? 1 : 0), M.row([w.block]));
        this.commit(dropEmptySingleRows(next));
      }
    });

    c.addEventListener('dragend', () => {
      dragging = null;
      clear();
    });
  },

  // ---------------------------------------------------------------- resizing columns (mouse)

  resizing(this: any) {
    const c = this.canvas as HTMLElement;
    c.addEventListener('pointerdown', (e: PointerEvent) => {
      const h = (e.target as HTMLElement).closest('.pb-resize') as HTMLElement | null;
      if (!h || e.button !== 0) return;
      e.preventDefault();
      const rowId = h.dataset.row!;
      const left = parseInt(h.dataset.left!);
      const cols = h.parentElement as HTMLElement;
      const colEls = Array.from(cols.querySelectorAll(':scope > .pb-col')) as HTMLElement[];
      const box = cols.getBoundingClientRect();
      const before = this.doc;
      const startLeftPx = colEls.slice(0, left).reduce((s: number, el: HTMLElement) => s + el.getBoundingClientRect().width, 0);
      const pair = colEls[left].getBoundingClientRect().width + colEls[left + 1].getBoundingClientRect().width;
      const pairPct = (pair / box.width) * 100;
      const r0 = this.doc.rows.find((x: M.Row) => x.id === rowId);
      const n = r0.columns.length;
      const startPct = M.widthNumber(r0.columns[left].width, n) + M.widthNumber(r0.columns[left + 1].width, n);
      h.setPointerCapture(e.pointerId);
      h.classList.add('is-active');
      let last = before;
      const move = (ev: PointerEvent) => {
        const x = ev.clientX - box.left - startLeftPx;
        const pct = (Math.max(0, Math.min(pair, x)) / pair) * startPct;
        last = M.resizeColumns(before, rowId, left, pct);
        const r = last.rows.find((x: M.Row) => x.id === rowId)!;
        colEls[left].style.setProperty('--w', r.columns[left].width);
        colEls[left + 1].style.setProperty('--w', r.columns[left + 1].width);
        void pairPct;
      };
      const up = () => {
        h.removeEventListener('pointermove', move);
        h.removeEventListener('pointerup', up);
        h.classList.remove('is-active');
        if (last !== before) {
          this.history.record(before);
          this.doc = last;
          this.render();
          this.changedNow();
        }
      };
      h.addEventListener('pointermove', move);
      h.addEventListener('pointerup', up);
    });
  },

  // ---------------------------------------------------------------- the server

  serverEvents(this: any) {
    this.handleEvent('update-editor-content', ({ content }: { content: string }) => {
      this.history.record(this.doc);
      this.doc = M.parseDoc(content);
      this.render();
    });
    // (library pictures still come this way: library-use answers like an upload)
    this.handleEvent('block-media-uploaded', ({ blockId, url, mediaType, filename, mediaId }: any) =>
      this.mediaDone(blockId, url, mediaType, filename, mediaId));
    this.handleEvent('block-media-error', ({ blockId, error }: any) => this.mediaError(blockId, error || 'The upload failed.'));
    this.handleEvent('block-image-uploaded', ({ blockId, url }: any) => {
      const w = M.findBlock(this.doc, blockId);
      if (!w) return;
      w.block.content = url;
      w.block.settings = { ...(w.block.settings || {}), loading: false };
      this.renderBlock(blockId);
      this.changedNow();
    });
  },
};

// ------------------------------------------------------------------ helpers

/** Adds or removes ?edit=1 in the address without a navigation (LiveView reads it on a remount). */
function setEditParam(on: boolean) {
  try {
    const u = new URL(window.location.href);
    if (on === (u.searchParams.get('edit') === '1')) return;
    if (on) u.searchParams.set('edit', '1');
    else u.searchParams.delete('edit');
    window.history.replaceState(window.history.state, '', u.toString());
    // LiveView rejoins after a dropped connection with the address it last navigated to, not the
    // browser's: tell it too, or a remount would open the page without ?edit=1 (the editor closed).
    (window as any).liveSocket?.main?.setHref?.(u.toString());
  } catch { /* an old browser: nothing to do */ }
}

/** Sends one file to /editor/media (Bacon8Web.EditorMediaController): `{url, filename}`, or throws with a message. */
async function postMedia(kind: string, recordId: string, file: File): Promise<{ url: string; filename: string }> {
  if (!recordId) throw new Error('Save a draft first.');
  const body = new FormData();
  body.append('kind', kind);
  body.append('id', recordId);
  body.append('file', file, file.name);
  const csrf = (document.querySelector("meta[name='csrf-token']") as HTMLMetaElement | null)?.content || '';
  let res: Response;
  try {
    res = await fetch('/editor/media', { method: 'POST', body, headers: { 'x-csrf-token': csrf, accept: 'application/json' }, credentials: 'same-origin' });
  } catch {
    throw new Error('No connection: try again.');
  }
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.url) throw new Error(json.error || (res.status === 413 ? 'That file is too big.' : 'The upload failed.'));
  return json;
}

/**
 * A photo bigger than MAX_SIDE on its long side (or over 4 MB) comes back as a MAX_SIDE JPEG; GIFs
 * (they may move) and small pictures come back untouched, as does anything the browser can't decode.
 */
export async function shrinkPhoto(file: File): Promise<File> {
  if (file.type === 'image/gif' || typeof createImageBitmap !== 'function') return file;
  let bmp: ImageBitmap;
  try {
    bmp = await createImageBitmap(file);
  } catch {
    return file;
  }
  const { w, h } = M.fitWithin(bmp.width, bmp.height, MAX_SIDE);
  if (w === bmp.width && file.size <= 4 * 1024 * 1024) {
    bmp.close();
    return file;
  }
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const g = c.getContext('2d');
  if (!g) return file;
  g.drawImage(bmp, 0, 0, w, h);
  bmp.close();
  // a PNG keeps its transparency; everything else becomes a JPEG
  const png = file.type === 'image/png';
  const blob: Blob | null = await new Promise((r) => c.toBlob(r, png ? 'image/png' : 'image/jpeg', 0.86));
  if (!blob || blob.size >= file.size) return file;
  const name = png ? file.name : file.name.replace(/\.[^.]+$/, '') + '.jpg';
  return new File([blob], name, { type: blob.type });
}

function rowWillVanish(doc: M.Doc, w: M.Where): boolean {
  const r = doc.rows[w.r];
  return r.columns.length === 1 && r.columns[0].blocks.length === 1;
}

/** A single-cell row emptied by a move goes; rows with several cells keep their empty cells. */
function dropEmptySingleRows(doc: M.Doc): M.Doc {
  const keep = doc.rows.filter((r) => !(r.columns.length === 1 && r.columns[0].blocks.length === 0));
  return keep.length === doc.rows.length ? doc : { ...doc, rows: keep };
}

function escHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function toPlain(b: M.Block): string {
  if (typeof b.content !== 'string') return '';
  if (b.type !== 'text') return b.content;
  const d = document.createElement('div');
  d.innerHTML = b.content;
  return (d.innerText || d.textContent || '').trim();
}

/** What a text block keeps: the markup its own bar makes, no styles, no scripts. */
export function cleanHtml(html: string): string {
  return html
    .replace(/<(script|style|iframe|object|embed)[\s\S]*?<\/\1>/gi, '')
    .replace(/\son\w+="[^"]*"/gi, '')
    .replace(/\son\w+='[^']*'/gi, '')
    .replace(/href\s*=\s*"\s*javascript:[^"]*"/gi, 'href="#"')
    .replace(/<div><br><\/div>/gi, '<p><br></p>')
    .replace(/^<br>$/i, '');
}

export default PageBuilder;

/**
 * AutoGrow: a textarea that grows with its text (the editor's title). Enter doesn't add a line:
 * it moves on to the page below.
 */
export const AutoGrow = {
  mounted(this: any) {
    const ta = this.el as HTMLTextAreaElement;
    const fit = () => {
      ta.style.height = 'auto';
      ta.style.height = `${ta.scrollHeight}px`;
    };
    this.fit = fit;
    ta.addEventListener('input', fit);
    ta.addEventListener('keydown', (e: KeyboardEvent) => {
      if (e.key !== 'Enter') return;
      e.preventDefault();
      ta.blur();
      const first = document.querySelector('.pb-canvas [contenteditable]') as HTMLElement | null;
      if (first) caretToEnd(first);
    });
    requestAnimationFrame(fit);
    window.addEventListener('resize', fit);
  },
  updated(this: any) {
    this.fit && this.fit();
  },
  destroyed(this: any) {
    window.removeEventListener('resize', this.fit);
  },
};
