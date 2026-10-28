/**
 * Whether a mouse press landed on something people read or copy: text itself, or a content panel.
 * The page-wide camera controller must leave those presses alone, because calling preventDefault on
 * the press stops the browser from starting a text selection. Only presses on the empty background
 * (and on nothing readable) rotate the camera.
 *
 * Takes the bare minimum of an element, so it can be tested without a DOM.
 */
export interface TargetLike {
  tagName?: string;
  childNodes?: ArrayLike<{ nodeType: number; textContent: string | null }>;
  closest?: (selector: string) => unknown;
}

// Elements whose whole point is words.
const TEXT_TAGS = new Set(['P', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'LI', 'DT', 'DD', 'TD', 'TH', 'PRE', 'CODE', 'BLOCKQUOTE', 'SPAN', 'STRONG', 'EM', 'B', 'I', 'SMALL', 'LABEL', 'FIGCAPTION']);

// Where content lives: the page's glass panels, articles, app windows, anything marked selectable.
const CONTENT = '.auth-glass-panel, .glass-dark, .desktop-window, article, .prose, [data-selectable]';

export function isTextTarget(target: TargetLike | null | undefined): boolean {
  if (!target) return false;
  if (target.tagName && TEXT_TAGS.has(target.tagName.toUpperCase())) return true;

  // text sitting directly in the element under the pointer
  const nodes = target.childNodes ? Array.from(target.childNodes) : [];
  if (nodes.some((n) => n.nodeType === 3 && (n.textContent || '').trim() !== '')) return true;

  return typeof target.closest === 'function' && !!target.closest(CONTENT);
}
