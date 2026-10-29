// The doc as plain HTML, sent alongside the JSON on every change (`html` in editor-change; the
// server keeps the JSON and renders it itself, render_blocks/1). Kept close to the old editor's.

import { Block, Doc, safeUrl } from './model';
import { esc, videoPreview } from './render';

export function docToHtml(doc: Doc): string {
  return doc.rows
    .map((r) => {
      const inner = r.columns.map((c) => `<div class="content-column">${c.blocks.map(blockToHtml).join('')}</div>`).join('');
      return r.columns.length > 1 ? `<div class="content-row columns-${r.columns.length}">${inner}</div>` : inner;
    })
    .join('');
}

export function blockToHtml(b: Block): string {
  const s = b.settings || {};
  switch (b.type) {
    case 'text':
      return b.content || '';
    case 'heading':
      return `<h${s.level || 2}>${esc(b.content)}</h${s.level || 2}>`;
    case 'image':
      return b.content ? `<figure><img src="${esc(b.content)}" alt="${esc(s.decorative ? '' : s.alt || '')}">${s.caption ? `<figcaption>${esc(s.caption)}</figcaption>` : ''}</figure>` : '';
    case 'gallery':
      return (b.media || []).length ? `<div class="gallery">${(b.media || []).map((m) => `<figure><img src="${esc(m.url)}" alt="${esc(m.alt || '')}"></figure>`).join('')}</div>` : '';
    case 'video':
      return b.content ? videoPreview(b.content) : '';
    case 'audio':
      return b.content ? `<audio controls src="${esc(b.content)}"></audio>` : '';
    case 'file':
      return b.content ? `<a href="${esc(b.content)}" download>${esc(s.filename || 'Download file')}</a>` : '';
    case 'button':
      return `<p><a class="content-button" href="${esc(safeUrl(s.url) || '#')}">${esc(b.content)}</a></p>`;
    case 'quote':
      return `<blockquote>${esc(b.content)}${s.author ? `<cite>${esc(s.author)}</cite>` : ''}</blockquote>`;
    case 'callout':
      return `<div class="callout callout-${esc(s.calloutType || 'info')}">${esc(b.content)}</div>`;
    case 'code':
      return `<pre><code>${esc(b.content)}</code></pre>`;
    case 'html':
    case 'embed':
      return b.content || '';
    case 'divider':
      return '<hr>';
    default:
      return '';
  }
}
