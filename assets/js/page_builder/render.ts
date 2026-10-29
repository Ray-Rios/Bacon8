// The page builder's canvas, as HTML strings (the hook puts them in and wires them up). Rows look
// the way they will on the page: the same widths, spacing and backgrounds as the public render
// (Bacon8Web.Components.BlockEditor.render_blocks/1, the .content-section classes in app.css).

import { Block, Column, Doc, Row, layoutOf } from './model';

export const esc = (s: any): string =>
  String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

export const ICON: Record<string, string> = {
  plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
  gear: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
  grip: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="6" r="1.2"/><circle cx="15" cy="6" r="1.2"/><circle cx="9" cy="12" r="1.2"/><circle cx="15" cy="12" r="1.2"/><circle cx="9" cy="18" r="1.2"/><circle cx="15" cy="18" r="1.2"/></svg>',
  up: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M6 11l6-6 6 6"/></svg>',
  down: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M6 13l6 6 6-6"/></svg>',
  copy: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h8"/></svg>',
  trash: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>',
  image: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 9"/></svg>',
  close: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  link: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/></svg>',
};

// What the + sheet offers, in order (the first row of them is what most pages are made of).
export const BLOCK_MENU: Array<{ type: string; label: string; icon: string; hint: string }> = [
  { type: 'text', label: 'Text', icon: '¶', hint: 'Paragraphs, lists, links' },
  { type: 'heading', label: 'Heading', icon: 'H', hint: 'A section title' },
  { type: 'image', label: 'Picture', icon: '🖼', hint: 'Upload, camera or library' },
  { type: 'button', label: 'Button', icon: '▭', hint: 'A link people press' },
  { type: 'gallery', label: 'Gallery', icon: '▦', hint: 'Several pictures' },
  { type: 'quote', label: 'Quote', icon: '❝', hint: 'Words worth repeating' },
  { type: 'callout', label: 'Callout', icon: '💡', hint: 'A highlighted note' },
  { type: 'divider', label: 'Divider', icon: '—', hint: 'A line between parts' },
  { type: 'video', label: 'Video', icon: '▶', hint: 'YouTube, Vimeo or a file' },
  { type: 'audio', label: 'Audio', icon: '♪', hint: 'A sound or song' },
  { type: 'file', label: 'File', icon: '📎', hint: 'Something to download' },
  { type: 'code', label: 'Code', icon: '</>', hint: 'Monospaced, with copy' },
  { type: 'html', label: 'HTML', icon: '◇', hint: 'Your own markup' },
  { type: 'embed', label: 'Embed', icon: '⧉', hint: 'Paste embed code' },
];

const CALLOUT_ICON: Record<string, string> = { info: 'ℹ️', warning: '⚠️', success: '✅', error: '⛔', tip: '💡' };

export function canvas(doc: Doc): string {
  const rows = doc.rows.map((r, i) => inserter(i) + rowHtml(r)).join('');
  return `${rows}${inserter(doc.rows.length, true)}`;
}

function inserter(at: number, end = false): string {
  return end
    ? `<div class="pb-insert pb-insert-end" data-at="${at}"><button type="button" class="pb-add-big" data-act="add-at" data-at="${at}">${ICON.plus}<span>Add a block</span></button></div>`
    : `<div class="pb-insert" data-at="${at}"><button type="button" class="pb-plus" data-act="add-at" data-at="${at}" aria-label="Add here" title="Add here">${ICON.plus}</button></div>`;
}

export function rowClasses(r: Row): string {
  const s = r.settings || {};
  return [`w-${s.width || 'legacy'}`, `sp-${s.space || 'm'}`, `bg-${s.background || 'none'}`, `al-${s.align || 'top'}`].join(' ');
}

function rowHtml(r: Row): string {
  const n = r.columns.length;
  const cols = r.columns.map((c, i) => colHtml(c, r, i)).join('');
  return `<section class="pb-row ${rowClasses(r)} cols-${n}" data-row="${r.id}" data-layout="${layoutOf(r) || 'custom'}">
    <div class="pb-tools pb-row-tools">
      <button type="button" class="pb-tool pb-grip" draggable="true" data-drag="row" data-row="${r.id}" aria-label="Drag the row" title="Drag to move">${ICON.grip}</button>
      <button type="button" class="pb-tool" data-act="row-gear" data-row="${r.id}" aria-label="Row settings" title="Row settings">${ICON.gear}</button>
    </div>
    <div class="pb-cols" style="--n:${n}">${cols}</div>
  </section>`;
}

function colHtml(c: Column, r: Row, i: number): string {
  const n = r.columns.length;
  const w = n > 1 ? `--w:${widthCss(c.width, n)}` : '';
  const blocks = c.blocks.map((b) => blockHtml(b)).join('');
  const resize = i < n - 1 ? `<div class="pb-resize" data-row="${r.id}" data-left="${i}" title="Drag to resize"><i></i></div>` : '';
  return `<div class="pb-col${c.blocks.length ? '' : ' is-empty'}" data-col="${c.id}" style="${w}">
      ${blocks}
      <button type="button" class="pb-cell-add" data-act="add-in" data-col="${c.id}" aria-label="Add to this cell">${ICON.plus}${c.blocks.length ? '' : '<span>Add</span>'}</button>
    </div>${resize}`;
}

function widthCss(w: string, n: number): string {
  if (!w || w === 'full') return `${100 / n}%`;
  if (w.endsWith('%')) return w;
  const m = w.match(/^(\d+)\/(\d+)$/);
  return m ? `${(parseInt(m[1]) / parseInt(m[2])) * 100}%` : `${100 / n}%`;
}

export function blockHtml(b: Block): string {
  return `<div class="pb-block t-${b.type}" data-block="${b.id}">
    <div class="pb-tools pb-block-tools">
      <button type="button" class="pb-tool pb-grip" draggable="true" data-drag="block" data-block="${b.id}" aria-label="Drag the block" title="Drag to move">${ICON.grip}</button>
      <button type="button" class="pb-tool" data-act="block-gear" data-block="${b.id}" aria-label="Block settings" title="Settings">${ICON.gear}</button>
    </div>
    <div class="pb-body">${bodyHtml(b)}</div>
  </div>`;
}

function editable(cls: string, html: string, ph: string, id: string, field = 'content', plain = true): string {
  const blank = !html.replace(/<br\s*\/?>/gi, '').replace(/<\/?p>/gi, '').replace(/&nbsp;/g, '').trim();
  // a text block always holds at least one paragraph, so headings and lists have something to work on
  if (!plain && blank) html = '<p><br></p>';
  else if (!plain && !/^\s*<(p|h[1-6]|ul|ol|blockquote|div|figure|table|pre)\b/i.test(html)) html = `<p>${html}</p>`;
  return `<div class="${cls}${blank ? ' is-blank' : ''}" contenteditable="true" spellcheck="true" data-edit="${field}" data-plain="${plain ? 1 : 0}" data-block="${id}" data-ph="${esc(ph)}">${html}</div>`;
}

function bodyHtml(b: Block): string {
  const s = b.settings || {};
  const id = b.id;
  switch (b.type) {
    case 'text':
      return editable('pb-text', b.content || '', 'Type here, or press / to add something', id, 'content', false);
    case 'heading': {
      const lvl = Math.min(4, Math.max(1, parseInt(s.level) || 2));
      return editable(`pb-heading h${lvl}`, esc(b.content || ''), 'Heading', id);
    }
    case 'image':
      if (s.loading) return `<div class="pb-empty is-busy"><span class="pb-spin"></span>Uploading…</div>`;
      if (!b.content) return emptyMedia(id, 'image', s.error);
      return `<figure class="pb-figure size-${esc(s.size || 'full')}">
          <img src="${esc(b.content)}" alt="${esc(s.decorative ? '' : s.alt || '')}" draggable="false">
          ${editable('pb-caption', esc(s.caption || ''), 'Add a caption', id, 'caption')}
        </figure>
        ${s.alt || s.decorative ? '' : `<button type="button" class="pb-chip warn" data-act="block-gear" data-block="${id}">Add alt text</button>`}`;
    case 'gallery': {
      const items = b.media || [];
      const thumbs = items
        .map((m) => `<figure class="pb-thumb"><img src="${esc(m.url)}" alt="${esc(m.alt || '')}" draggable="false"><button type="button" class="pb-x" data-act="gallery-remove" data-block="${id}" data-item="${esc(m.id)}" aria-label="Remove">${ICON.close}</button></figure>`)
        .join('');
      const busy = s.loading ? '<div class="pb-thumb is-busy"><span class="pb-spin"></span></div>' : '';
      return `<div class="pb-gallery mode-${esc(s.displayMode || 'grid')}">${thumbs}${busy}
        <button type="button" class="pb-thumb pb-thumb-add" data-act="gallery-add" data-block="${id}">${ICON.plus}<span>Pictures</span></button></div>
        ${s.error ? `<p class="pb-err">${esc(s.error)}</p>` : ''}`;
    }
    case 'video':
      if (s.loading) return `<div class="pb-empty is-busy"><span class="pb-spin"></span>Uploading…</div>`;
      if (!b.content) return emptyMedia(id, 'video', s.error);
      return `<div class="pb-video">${videoPreview(b.content)}<div class="pb-shield"></div></div>`;
    case 'audio':
      if (s.loading) return `<div class="pb-empty is-busy"><span class="pb-spin"></span>Uploading…</div>`;
      if (!b.content) return emptyMedia(id, 'audio', s.error);
      return `<div class="pb-audio"><audio controls preload="metadata" src="${esc(b.content)}"></audio><span>${esc(s.filename || '')}</span></div>`;
    case 'file':
      if (s.loading) return `<div class="pb-empty is-busy"><span class="pb-spin"></span>Uploading…</div>`;
      if (!b.content) return emptyMedia(id, 'file', s.error);
      return `<div class="pb-file"><span class="pb-file-ic">📎</span><span class="pb-file-name">${esc(s.filename || b.content.split('/').pop())}</span><span class="pb-file-size">${esc(s.fileSize || '')}</span></div>`;
    case 'button': {
      const url = s.url || '';
      return `<div class="pb-button-row align-${esc(s.align || 'center')}">
          <span class="content-button content-button-${esc(s.style || 'primary')}">${editable('pb-button-label', esc(b.content || ''), 'Button text', id)}</span>
        </div>
        <button type="button" class="pb-chip${url ? '' : ' warn'}" data-act="block-gear" data-block="${id}">${ICON.link}<span>${url ? esc(url) : 'Add a link'}</span></button>`;
    }
    case 'quote':
      return `<blockquote class="pb-quote">${editable('pb-quote-text', esc(b.content || ''), 'A quote worth repeating', id)}${editable('pb-quote-author', esc(s.author || ''), '— who said it', id, 'author')}</blockquote>`;
    case 'callout': {
      const t = s.calloutType || 'info';
      return `<div class="callout callout-${esc(t)} pb-callout"><button type="button" class="pb-callout-ic" data-act="callout-next" data-block="${id}" title="Change">${CALLOUT_ICON[t] || 'ℹ️'}</button>${editable('pb-callout-text', esc(b.content || ''), 'A note to stand out', id)}</div>`;
    }
    case 'divider':
      return '<hr class="content-divider pb-divider">';
    case 'code':
      return `<div class="pb-code"><span class="pb-code-lang">${esc(s.language || 'code')}</span><textarea class="pb-area mono" data-edit="content" data-block="${id}" spellcheck="false" placeholder="Paste or type code">${esc(b.content || '')}</textarea></div>`;
    case 'html':
      return s.previewMode === 'preview'
        ? `<div class="pb-html-preview">${b.content || '<p class="pb-muted">Nothing yet</p>'}</div><div class="pb-shield"></div>`
        : `<textarea class="pb-area mono" data-edit="content" data-block="${id}" spellcheck="false" placeholder="&lt;div&gt;Your HTML&lt;/div&gt;">${esc(b.content || '')}</textarea>`;
    case 'embed':
      return b.content
        ? `<div class="pb-html-preview">${b.content}</div><div class="pb-shield"></div>`
        : `<div class="pb-empty"><input type="text" class="pb-input" data-act-input="embed" data-block="${id}" placeholder="Paste the embed code or a link, then press Enter"></div>`;
    case 'api':
      return `<div class="pb-empty"><strong>API data</strong><span class="pb-muted">${esc(b.content || '')}</span><span class="pb-muted">Shown on the page as last fetched.</span></div>`;
    default:
      return `<div class="pb-empty pb-muted">${esc(b.type)}</div>`;
  }
}

function emptyMedia(id: string, kind: 'image' | 'video' | 'audio' | 'file', error?: string): string {
  const what = { image: 'a picture', video: 'a video', audio: 'a sound', file: 'a file' }[kind];
  const lib = kind === 'image' ? `<button type="button" class="pb-pill" data-act="library" data-block="${id}">From the library</button>` : '';
  const url = kind === 'file' ? '' : `<input type="text" class="pb-input" data-act-input="url" data-block="${id}" placeholder="${kind === 'video' ? 'Or paste a YouTube or Vimeo link' : 'Or paste a link'}, then press Enter">`;
  return `<div class="pb-empty" data-drop="${kind}" data-block="${id}">
      <button type="button" class="pb-empty-main" data-act="upload" data-kind="${kind}" data-block="${id}">${kind === 'image' ? ICON.image : ICON.plus}<span>Add ${what}</span></button>
      <div class="pb-empty-more">${lib}${url}</div>
      ${error ? `<p class="pb-err">${esc(error)}</p>` : ''}
    </div>`;
}

export function videoPreview(url: string): string {
  const yt = url.match(/(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([\w-]{6,})/);
  if (yt) return `<iframe src="https://www.youtube.com/embed/${yt[1]}" loading="lazy" allowfullscreen></iframe>`;
  const vm = url.match(/vimeo\.com\/(\d+)/);
  if (vm) return `<iframe src="https://player.vimeo.com/video/${vm[1]}" loading="lazy" allowfullscreen></iframe>`;
  return `<video controls preload="metadata" src="${esc(url)}"></video>`;
}

// ------------------------------------------------------------------ the sheets' contents

export function addSheet(mode: 'at' | 'in' | 'after', kind: 'page' | 'post'): string {
  const cols =
    mode === 'at'
      ? `<div class="pb-sheet-sec"><h4>Columns</h4><div class="pb-layouts">${[2, 3, 4]
          .map((n) => `<button type="button" class="pb-layout" data-act="pick-columns" data-n="${n}">${layoutIcon(Array(n).fill(1))}<span>${n} columns</span></button>`)
          .join('')}</div></div>`
      : '';
  const items = BLOCK_MENU.map(
    (m) => `<button type="button" class="pb-pick" data-act="pick-block" data-type="${m.type}"><span class="pb-pick-ic">${m.icon}</span><span class="pb-pick-l">${m.label}</span><span class="pb-pick-h">${m.hint}</span></button>`,
  ).join('');
  return `<div class="pb-sheet-sec"><h4>Add a block</h4><div class="pb-picks">${items}</div></div>${cols}`;
}

export function layoutIcon(parts: number[]): string {
  const total = parts.reduce((a, b) => a + b, 0);
  let x = 1;
  const rects = parts
    .map((p) => {
      const w = (p / total) * 30 - 1.5;
      const r = `<rect x="${x.toFixed(1)}" y="2" width="${w.toFixed(1)}" height="16" rx="2"/>`;
      x += w + 1.5;
      return r;
    })
    .join('');
  return `<svg viewBox="0 0 32 20" class="pb-lay-ic" aria-hidden="true">${rects}</svg>`;
}

function seg(name: string, current: string, options: Array<[string, string]>, act = 'row-set'): string {
  return `<div class="pb-seg" role="group">${options
    .map(([v, l]) => `<button type="button" class="${v === current ? 'on' : ''}" data-act="${act}" data-key="${name}" data-val="${v}">${l}</button>`)
    .join('')}</div>`;
}

function actions(scope: 'row' | 'block'): string {
  return `<div class="pb-actions">
    <button type="button" data-act="${scope}-move" data-by="-1">${ICON.up}<span>Up</span></button>
    <button type="button" data-act="${scope}-move" data-by="1">${ICON.down}<span>Down</span></button>
    <button type="button" data-act="${scope}-dup">${ICON.copy}<span>Copy</span></button>
    <button type="button" class="danger" data-act="${scope}-del">${ICON.trash}<span>Delete</span></button>
  </div>`;
}

export function rowSheet(r: Row): string {
  const s = r.settings || {};
  const cur = layoutOf(r) || '';
  const layouts = Object.entries({ '1': [1], '1-1': [1, 1], '1-2': [1, 2], '2-1': [2, 1], '1-1-1': [1, 1, 1], '1-2-1': [1, 2, 1], '1-1-1-1': [1, 1, 1, 1] })
    .map(([k, parts]) => `<button type="button" class="pb-layout${k === cur ? ' on' : ''}" data-act="row-layout" data-layout="${k}" aria-label="${k.replace(/-/g, ' + ')}">${layoutIcon(parts)}</button>`)
    .join('');
  return `<div class="pb-sheet-sec"><h4>Columns</h4><div class="pb-layouts">${layouts}</div></div>
    <div class="pb-sheet-sec"><h4>Width</h4>${seg('width', s.width || 'legacy', [['narrow', 'Narrow'], ['normal', 'Normal'], ['wide', 'Wide'], ['full', 'Full']])}</div>
    <div class="pb-sheet-sec"><h4>Spacing</h4>${seg('space', s.space || 'm', [['s', 'Tight'], ['m', 'Normal'], ['l', 'Roomy']])}</div>
    <div class="pb-sheet-sec"><h4>Background</h4>${seg('background', s.background || 'none', [['none', 'None'], ['glass', 'Glass'], ['tint', 'Tint'], ['dark', 'Dark']])}</div>
    ${r.columns.length > 1
      ? `<div class="pb-sheet-sec"><h4>Line up</h4>${seg('align', s.align || 'top', [['top', 'Top'], ['center', 'Middle']])}</div>`
      : `<div class="pb-sheet-sec"><h4>Text</h4>${seg('align', s.align || 'top', [['top', 'Left'], ['center', 'Centre']])}</div>`}
    ${actions('row')}`;
}

export function blockSheet(b: Block): string {
  const s = b.settings || {};
  let own = '';
  switch (b.type) {
    case 'heading':
      own = `<div class="pb-sheet-sec"><h4>Size</h4>${seg('level', String(s.level || 2), [['1', 'Title'], ['2', 'Large'], ['3', 'Medium'], ['4', 'Small']], 'block-set')}</div>`;
      break;
    case 'image':
      own = `<div class="pb-sheet-sec"><h4>Size</h4>${seg('size', s.size || 'full', [['small', 'Small'], ['medium', 'Medium'], ['full', 'Full']], 'block-set')}</div>
        <div class="pb-sheet-sec"><h4>Alt text</h4><textarea class="pb-input" rows="2" data-act-input="alt" placeholder="What's in the picture, for people who can't see it"${s.decorative ? ' disabled' : ''}>${esc(s.alt || '')}</textarea>
        <label class="pb-check"><input type="checkbox" data-act-input="decorative"${s.decorative ? ' checked' : ''}> Decorative only (no description)</label></div>
        ${b.content ? `<div class="pb-sheet-sec"><div class="pb-row-btns"><button type="button" class="pb-pill" data-act="upload" data-kind="image">Replace</button><button type="button" class="pb-pill" data-act="library">From the library</button><button type="button" class="pb-pill" data-act="media-remove">Remove picture</button></div></div>` : ''}`;
      break;
    case 'gallery':
      own = `<div class="pb-sheet-sec"><h4>Show as</h4>${seg('displayMode', s.displayMode || 'grid', [['grid', 'Grid'], ['masonry', 'Masonry'], ['carousel', 'Slides']], 'block-set')}</div>
        <div class="pb-sheet-sec"><div class="pb-row-btns"><button type="button" class="pb-pill" data-act="gallery-add">Upload pictures</button><button type="button" class="pb-pill" data-act="library-gallery">From the library</button></div></div>`;
      break;
    case 'button':
      own = `<div class="pb-sheet-sec"><h4>Link</h4><input type="text" class="pb-input" data-act-input="link" value="${esc(s.url || '')}" placeholder="https://… or /store" inputmode="url" autocapitalize="off"><p class="pb-hint" data-hint="link"></p></div>
        <div class="pb-sheet-sec"><h4>Look</h4>${seg('style', s.style || 'primary', [['primary', 'Solid'], ['ghost', 'Outline']], 'block-set')}</div>
        <div class="pb-sheet-sec"><h4>Place</h4>${seg('align', s.align || 'center', [['left', 'Left'], ['center', 'Centre'], ['right', 'Right']], 'block-set')}</div>`;
      break;
    case 'callout':
      own = `<div class="pb-sheet-sec"><h4>Kind</h4>${seg('calloutType', s.calloutType || 'info', [['info', 'ℹ️'], ['tip', '💡'], ['success', '✅'], ['warning', '⚠️'], ['error', '⛔']], 'block-set')}</div>`;
      break;
    case 'code':
      own = `<div class="pb-sheet-sec"><h4>Language</h4>${seg('language', s.language || '', [['', 'Plain'], ['elixir', 'Elixir'], ['javascript', 'JS'], ['typescript', 'TS'], ['python', 'Python'], ['html', 'HTML'], ['css', 'CSS'], ['sql', 'SQL'], ['bash', 'Shell']], 'block-set')}</div>`;
      break;
    case 'html':
      own = `<div class="pb-sheet-sec"><h4>Show</h4>${seg('previewMode', s.previewMode || 'edit', [['edit', 'Code'], ['preview', 'Preview']], 'block-set')}</div>`;
      break;
    case 'video':
    case 'audio':
    case 'file':
    case 'embed':
      own = b.content ? `<div class="pb-sheet-sec"><div class="pb-row-btns"><button type="button" class="pb-pill" data-act="media-remove">Remove and choose again</button></div></div>` : '';
      break;
  }
  const turn = ['text', 'heading', 'quote', 'callout'].includes(b.type)
    ? `<div class="pb-sheet-sec"><h4>Turn into</h4>${seg('type', b.type, [['text', 'Text'], ['heading', 'Heading'], ['quote', 'Quote'], ['callout', 'Callout']], 'block-turn')}</div>`
    : '';
  return own + turn + actions('block');
}

export function startersSheet(list: Array<{ id: string; name: string; blurb: string; icon: string }>, kind: 'page' | 'post'): string {
  return `<div class="pb-starters">
    <h3>How do you want to start this ${kind}?</h3>
    <div class="pb-starter-grid">${list
      .map((s) => `<button type="button" class="pb-starter" data-act="starter" data-starter="${s.id}"><span class="pb-starter-ic">${s.icon}</span><strong>${esc(s.name)}</strong><span>${esc(s.blurb)}</span></button>`)
      .join('')}</div>
  </div>`;
}
