// The page builder's floating pieces: the sheet (a bottom sheet on a phone, a small popover beside
// the button on a desktop) and the formatting bar for selected text (above the selection with a
// mouse; above the keyboard on a phone). Both live in document.body, outside LiveView's patches.

export const isPhone = (): boolean =>
  typeof window !== 'undefined' && !!window.matchMedia && window.matchMedia('(max-width: 640px), (pointer: coarse)').matches;

type ActHandler = (act: string, el: HTMLElement, ev: Event) => void;
type InputHandler = (name: string, el: HTMLInputElement | HTMLTextAreaElement, ev: Event) => void;

export class Sheet {
  el: HTMLElement;
  private backdrop: HTMLElement;
  private body: HTMLElement;
  private onAct: ActHandler | null = null;
  private onInput: InputHandler | null = null;
  private onClose: (() => void) | null = null;
  anchor: HTMLElement | null = null;
  open = false;

  constructor() {
    this.backdrop = document.createElement('div');
    this.backdrop.className = 'pb-backdrop';
    this.el = document.createElement('div');
    this.el.className = 'pb-sheet';
    this.el.setAttribute('role', 'dialog');
    this.el.innerHTML = '<div class="pb-sheet-handle"></div><div class="pb-sheet-body"></div>';
    this.body = this.el.querySelector('.pb-sheet-body') as HTMLElement;
    document.body.append(this.backdrop, this.el);
    this.backdrop.addEventListener('click', () => this.close());
    this.el.addEventListener('click', (e) => {
      const t = (e.target as HTMLElement).closest('[data-act]') as HTMLElement | null;
      if (t && this.onAct) this.onAct(t.dataset.act!, t, e);
    });
    const input = (e: Event) => {
      const t = e.target as HTMLInputElement;
      if (t.dataset && t.dataset.actInput && this.onInput) this.onInput(t.dataset.actInput, t, e);
    };
    this.el.addEventListener('input', input);
    this.el.addEventListener('change', input);
    this.el.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') this.close();
      const t = e.target as HTMLInputElement;
      if (e.key === 'Enter' && t.tagName === 'INPUT' && t.dataset.actInput && this.onInput) {
        e.preventDefault();
        this.onInput(t.dataset.actInput, t, e);
      }
    });
    this.outside = this.outside.bind(this);
    this.place = this.place.bind(this);
  }

  show(opts: { anchor?: HTMLElement | null; html: string; onAct: ActHandler; onInput?: InputHandler; onClose?: () => void; wide?: boolean }) {
    this.onAct = opts.onAct;
    this.onInput = opts.onInput || null;
    this.onClose = opts.onClose || null;
    this.anchor = opts.anchor || null;
    this.body.innerHTML = opts.html;
    this.el.classList.toggle('is-wide', !!opts.wide);
    this.el.classList.toggle('is-phone', isPhone());
    this.backdrop.classList.toggle('is-phone', isPhone());
    this.open = true;
    this.el.classList.add('is-open');
    this.backdrop.classList.add('is-open');
    this.place();
    setTimeout(() => document.addEventListener('pointerdown', this.outside, true), 0);
    window.addEventListener('resize', this.place);
    window.addEventListener('scroll', this.place, true);
  }

  update(html: string) {
    if (!this.open) return;
    const st = this.body.scrollTop;
    const focused = document.activeElement as HTMLElement | null;
    const keep = focused && this.el.contains(focused) ? focused.dataset.actInput : null;
    this.body.innerHTML = html;
    this.body.scrollTop = st;
    if (keep) {
      const again = this.body.querySelector(`[data-act-input="${keep}"]`) as HTMLInputElement | null;
      if (again) {
        again.focus();
        const n = again.value.length;
        try { again.setSelectionRange(n, n); } catch { /* checkbox */ }
      }
    }
    this.place();
  }

  close() {
    if (!this.open) return;
    this.open = false;
    this.el.classList.remove('is-open');
    this.backdrop.classList.remove('is-open');
    document.removeEventListener('pointerdown', this.outside, true);
    window.removeEventListener('resize', this.place);
    window.removeEventListener('scroll', this.place, true);
    const cb = this.onClose;
    this.onClose = null;
    if (cb) cb();
  }

  private outside(e: Event) {
    const t = e.target as Node;
    if (this.el.contains(t) || (this.anchor && this.anchor.contains(t))) return;
    if (isPhone()) return; // the backdrop handles it
    this.close();
  }

  private place() {
    if (!this.open) return;
    if (isPhone() || !this.anchor) {
      this.el.style.left = this.el.style.top = '';
      this.el.classList.toggle('is-center', !this.anchor && !isPhone());
      return;
    }
    const r = this.anchor.getBoundingClientRect();
    const w = this.el.offsetWidth;
    const h = this.el.offsetHeight;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    let left = Math.min(Math.max(8, r.left + r.width / 2 - w / 2), vw - w - 8);
    let top = r.bottom + 8;
    if (top + h > vh - 8) top = Math.max(8, r.top - h - 8);
    this.el.style.left = `${left}px`;
    this.el.style.top = `${top}px`;
  }

  destroy() {
    this.close();
    this.el.remove();
    this.backdrop.remove();
  }
}

// ------------------------------------------------------------------ the formatting bar

const FMT_BUTTONS: Array<[string, string, string]> = [
  ['bold', '<b>B</b>', 'Bold'],
  ['italic', '<i>I</i>', 'Italic'],
  ['link', '<svg viewBox="0 0 24 24"><path d="M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/></svg>', 'Link'],
  ['h2', 'H', 'Heading'],
  ['h3', '<small>H</small>', 'Smaller heading'],
  ['ul', '•', 'List'],
  ['ol', '1.', 'Numbered list'],
  ['quote', '❝', 'Quote'],
  ['clear', '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>', 'Plain text'],
];

export class FormatBar {
  el: HTMLElement;
  private linkMode = false;
  private savedRange: Range | null = null;
  constructor(private onCommand: (cmd: string, value?: string) => void) {
    this.el = document.createElement('div');
    this.el.className = 'pb-fmt';
    this.el.setAttribute('role', 'toolbar');
    this.renderButtons();
    document.body.append(this.el);
    // keep the selection when a button is pressed
    this.el.addEventListener('pointerdown', (e) => {
      if ((e.target as HTMLElement).tagName !== 'INPUT') e.preventDefault();
    });
    this.el.addEventListener('click', (e) => {
      const b = (e.target as HTMLElement).closest('button') as HTMLButtonElement | null;
      if (!b) return;
      const cmd = b.dataset.cmd!;
      if (cmd === 'link') return this.askLink();
      if (cmd === 'link-ok') return this.finishLink(true);
      if (cmd === 'link-cancel') return this.finishLink(false);
      this.onCommand(cmd);
      this.refreshState();
    });
    this.onViewport = this.onViewport.bind(this);
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', this.onViewport);
      window.visualViewport.addEventListener('scroll', this.onViewport);
    }
  }

  private renderButtons() {
    this.linkMode = false;
    this.el.innerHTML = FMT_BUTTONS.map(([c, l, t]) => `<button type="button" data-cmd="${c}" title="${t}" aria-label="${t}">${l}</button>`).join('');
  }

  private askLink() {
    const sel = window.getSelection();
    this.savedRange = sel && sel.rangeCount ? sel.getRangeAt(0).cloneRange() : null;
    this.linkMode = true;
    this.el.innerHTML = `<input type="text" class="pb-fmt-input" placeholder="Paste a link" inputmode="url" autocapitalize="off"><button type="button" data-cmd="link-ok" aria-label="Add link">✓</button><button type="button" data-cmd="link-cancel" aria-label="Cancel">✕</button>`;
    const input = this.el.querySelector('input') as HTMLInputElement;
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); this.finishLink(true); }
      if (e.key === 'Escape') { e.preventDefault(); this.finishLink(false); }
    });
    input.focus();
  }

  private finishLink(ok: boolean) {
    const input = this.el.querySelector('input') as HTMLInputElement | null;
    const url = input ? input.value : '';
    if (this.savedRange) {
      const sel = window.getSelection();
      sel?.removeAllRanges();
      sel?.addRange(this.savedRange);
    }
    this.renderButtons();
    if (ok) this.onCommand('link', url);
  }

  showFor(range: Range) {
    if (this.linkMode) return;
    this.el.classList.add('is-open');
    this.refreshState();
    if (isPhone()) {
      this.el.classList.add('is-docked');
      this.onViewport();
      return;
    }
    this.el.classList.remove('is-docked');
    const r = range.getBoundingClientRect();
    if (r.bottom < 60 || r.top > window.innerHeight) return this.el.classList.remove('is-open'); // scrolled away
    const w = this.el.offsetWidth;
    const left = Math.min(Math.max(8, r.left + r.width / 2 - w / 2), window.innerWidth - w - 8);
    const top = r.top - this.el.offsetHeight - 10;
    this.el.style.left = `${left}px`;
    this.el.style.top = `${top < 64 ? r.bottom + 10 : top}px`;
    this.el.style.bottom = '';
  }

  hide() {
    if (this.linkMode) return;
    this.el.classList.remove('is-open');
  }

  get isOpen() { return this.el.classList.contains('is-open'); }
  get busy() { return this.linkMode; }

  private refreshState() {
    for (const b of Array.from(this.el.querySelectorAll('button[data-cmd]')) as HTMLButtonElement[]) {
      const c = b.dataset.cmd!;
      let on = false;
      try {
        if (c === 'bold' || c === 'italic') on = document.queryCommandState(c);
        else if (c === 'ul') on = document.queryCommandState('insertUnorderedList');
        else if (c === 'ol') on = document.queryCommandState('insertOrderedList');
        else if (c === 'h2' || c === 'h3' || c === 'quote') {
          const v = String(document.queryCommandValue('formatBlock') || '').toLowerCase();
          on = v === (c === 'quote' ? 'blockquote' : c);
        }
      } catch { /* not in an editable */ }
      b.classList.toggle('on', on);
    }
  }

  // On a phone the bar sits just above the on-screen keyboard.
  private onViewport() {
    if (!this.el.classList.contains('is-docked')) return;
    const vv = window.visualViewport;
    const bottom = vv ? Math.max(0, window.innerHeight - (vv.height + vv.offsetTop)) : 0;
    this.el.style.left = '';
    this.el.style.top = '';
    this.el.style.bottom = `${bottom}px`;
  }

  destroy() {
    if (window.visualViewport) {
      window.visualViewport.removeEventListener('resize', this.onViewport);
      window.visualViewport.removeEventListener('scroll', this.onViewport);
    }
    this.el.remove();
  }
}

/** Opens the system's file picker (on a phone: camera or photos for pictures). */
export function pickFiles(accept: string, multiple = false): Promise<File[]> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.multiple = multiple;
    input.style.display = 'none';
    document.body.append(input);
    input.addEventListener('change', () => {
      resolve(Array.from(input.files || []));
      input.remove();
    });
    input.click();
  });
}

/** Puts the caret at the end of an editable element. */
export function caretToEnd(el: HTMLElement) {
  el.focus();
  const sel = window.getSelection();
  if (!sel) return;
  const r = document.createRange();
  r.selectNodeContents(el);
  r.collapse(false);
  sel.removeAllRanges();
  sel.addRange(r);
}
