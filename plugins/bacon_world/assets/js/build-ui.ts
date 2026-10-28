// Build mode's window (2026-10-28, build-world.ts): everything this account may put in the world,
// searchable and sorted by kind, what the cursor holds (a creature spawn's count and spread, an
// NPC's name), and the keys. Admins also set, row by row, the lowest role that may place each
// thing (BaconWorld.Building rules). In the game's window style (game-ui.ts' .bwg).
import { makeMovable } from './window-drag';

export interface CatalogueEntry {
  id: string;
  name: string;
  category: string;
  kind: 'model' | 'mob' | 'npc';
  min_role: string;
  allowed: boolean;
  levels?: [number, number];
  boss?: boolean;
}

export interface HeldInfo {
  name: string;
  kind: 'model' | 'mob' | 'npc';
  isNew: boolean;
  data: Record<string, any>;
  snap: boolean;
  canSnap: boolean;
}

export interface BuildCallbacks {
  pick: (entry: CatalogueEntry) => void;
  rule: (asset: string, role: string) => void;
  data: (patch: Record<string, any>) => void;
  snap: (on: boolean) => void;
  cancel: () => void;
  close: () => void;
}

const CATEGORIES = ['All', 'Building', 'Props', 'Trees & plants', 'Rocks', 'Creatures', 'NPCs'];
const ICON: Record<string, string> = { Building: '🧱', Props: '📦', 'Trees & plants': '🌲', Rocks: '🪨', Creatures: '🐀', NPCs: '🧑' };

const CSS = `
.bwg .bld{right:16px;top:70px;width:330px;max-width:calc(100% - 24px);display:none;max-height:calc(100% - 150px);flex-direction:column}
.bwg .bld.open{display:flex}
.bwg .bld .srch{padding:6px 8px 4px;display:flex;gap:6px}
.bwg .bld input[type=text],.bwg .bld input[type=number]{flex:1;min-width:0;font:inherit;color:#e8dcc0;background:#0a0908;border:1px solid #4b3f2b;border-radius:2px;padding:3px 6px;user-select:text;-webkit-user-select:text}
.bwg .bld input:focus{outline:none;border-color:#c9a65e}
.bwg .bld .cats{display:flex;flex-wrap:wrap;gap:3px;padding:0 8px 6px}
.bwg .bld .cats .btn{font-size:9.5px;padding:1px 6px}
.bwg .bld .list{overflow:auto;flex:1;min-height:80px;padding:0 6px 6px;scrollbar-width:thin}
.bwg .bld .it{display:flex;align-items:center;gap:7px;padding:3px 5px;border-radius:2px;cursor:pointer;border:1px solid transparent}
.bwg .bld .it:hover{border-color:#6d5b3c;background:rgba(201,166,94,.08)}
.bwg .bld .it.sel{border-color:#c9a65e;background:rgba(201,166,94,.16)}
.bwg .bld .it.lock{opacity:.45;cursor:default}
.bwg .bld .it .ic{width:18px;text-align:center;flex:none}
.bwg .bld .it .nm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bwg .bld .it .rl{font-size:9px;color:#a8997a;text-transform:uppercase;letter-spacing:.05em}
.bwg .bld .it select{font:inherit;font-size:9.5px;color:#e8dcc0;background:#0a0908;border:1px solid #4b3f2b;border-radius:2px}
.bwg .bld .held{border-top:1px solid #4b3f2b;padding:6px 8px;display:none;flex-direction:column;gap:5px}
.bwg .bld .held.on{display:flex}
.bwg .bld .held b{color:#f0d77a}
.bwg .bld .held label{display:flex;align-items:center;gap:6px;font-size:11px}
.bwg .bld .held label span{width:64px;color:#cdbf9f}
.bwg .bld .keys{border-top:1px solid #4b3f2b;padding:5px 8px 7px;font-size:10px;color:#a8997a;line-height:1.45}
.bwg .bld .keys kbd{font:inherit;color:#e9cf8f}
.bwg .bld .empty{padding:10px;color:#a8997a;font-size:11px}
`;

function h(tag: string, attrs: Record<string, any> = {}, ...kids: Array<Node | string | null | undefined | false>): HTMLElement {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on') && typeof v === 'function') (el as any)[k] = v;
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const c of kids) if (c !== null && c !== undefined && c !== false) el.append(c);
  return el;
}

/** The catalogue entries matching a search and a category, allowed ones first (pure; tested). */
export function filterCatalogue(list: CatalogueEntry[], query: string, category: string, showLocked: boolean): CatalogueEntry[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  return list
    .filter((e) => (category === 'All' || e.category === category) && (showLocked || e.allowed))
    .filter((e) => {
      const hay = `${e.name} ${e.category} ${e.id}`.toLowerCase();
      return words.every((w) => hay.includes(w));
    })
    .sort((a, b) => Number(b.allowed) - Number(a.allowed) || CATEGORIES.indexOf(a.category) - CATEGORIES.indexOf(b.category) || a.name.localeCompare(b.name));
}

export class BuildWindow {
  readonly el: HTMLElement;
  private style: HTMLStyleElement;
  private search: HTMLInputElement;
  private cats: HTMLElement;
  private list: HTMLElement;
  private heldEl: HTMLElement;
  private keys: HTMLElement;
  private catalogue: CatalogueEntry[] = [];
  private category = 'All';
  private showLocked = false;
  private admin = false;
  private roles: string[] = [];
  private role = '';
  private selected: string | null = null;
  private unmove: () => void;

  constructor(root: HTMLElement, private cb: BuildCallbacks) {
    this.style = document.createElement('style');
    this.style.textContent = CSS;
    document.head.appendChild(this.style);
    this.search = h('input', { type: 'text', placeholder: 'Search (barrel, wall, goblin...)' }) as HTMLInputElement;
    this.search.oninput = () => this.renderList();
    // typing stays in the box; ` and Esc still leave build mode
    this.search.onkeydown = (e: KeyboardEvent) => {
      e.stopPropagation();
      if (e.code === 'Backquote') {
        e.preventDefault();
        this.cb.close();
      } else if (e.key === 'Escape') {
        this.search.blur();
      } else if (e.key === 'Enter') {
        const first = filterCatalogue(this.catalogue, this.search.value, this.category, this.showLocked).find((x) => x.allowed);
        if (first) this.choose(first);
        this.search.blur();
      }
    };
    this.cats = h('div', { class: 'cats' });
    this.list = h('div', { class: 'list' });
    this.heldEl = h('div', { class: 'held' });
    this.keys = h('div', { class: 'keys' });
    this.el = h('div', { class: 'w bld' },
      h('div', { class: 't' }, h('b', {}, 'Build'), h('span', { class: 'x', onclick: () => this.cb.close() }, '✕')),
      h('div', { class: 'srch' }, this.search),
      this.cats, this.list, this.heldEl, this.keys);
    // the list scrolls with the wheel, not the camera
    this.el.addEventListener('wheel', (e) => e.stopPropagation(), { passive: true });
    root.appendChild(this.el);
    this.unmove = makeMovable(this.el, 'build');
  }

  get isOpen(): boolean {
    return this.el.classList.contains('open');
  }

  open(data: { catalogue: CatalogueEntry[]; admin: boolean; roles: string[]; role: string }) {
    this.catalogue = data.catalogue || [];
    this.admin = !!data.admin;
    this.roles = data.roles || [];
    this.role = data.role || '';
    this.showLocked = this.admin;
    this.el.classList.add('open');
    this.render();
  }

  close() {
    this.el.classList.remove('open');
    this.selected = null;
  }

  /** An entry's rule changed (this admin, or the reply). */
  setRule(asset: string, role: string, allowed?: boolean) {
    const e = this.catalogue.find((x) => x.id === asset);
    if (!e) return;
    e.min_role = role;
    if (allowed !== undefined) e.allowed = allowed;
    this.renderList();
  }

  entry(asset: string): CatalogueEntry | undefined {
    return this.catalogue.find((x) => x.id === asset);
  }

  /** What the cursor holds (null: nothing). */
  setHeld(info: HeldInfo | null) {
    this.selected = info && info.isNew ? this.selected : null;
    if (!info) {
      this.heldEl.classList.remove('on');
      this.heldEl.replaceChildren();
      this.renderList();
      return;
    }
    const kids: Array<HTMLElement | null> = [h('div', {}, info.isNew ? 'Placing ' : 'Moving ', h('b', {}, info.name))];
    if (info.kind === 'mob') {
      const count = h('input', { type: 'number', min: 1, max: 12, step: 1, value: info.data.count ?? 1 }) as HTMLInputElement;
      const radius = h('input', { type: 'number', min: 0, max: 40, step: 0.5, value: info.data.radius ?? 0 }) as HTMLInputElement;
      const send = () => this.cb.data({ count: Math.max(1, Math.min(12, Math.round(Number(count.value) || 1))), radius: Math.max(0, Math.min(40, Number(radius.value) || 0)) });
      for (const i of [count, radius]) {
        i.onchange = send;
        i.onkeydown = (e: KeyboardEvent) => e.stopPropagation();
      }
      kids.push(h('label', {}, h('span', {}, 'How many'), count), h('label', {}, h('span', {}, 'Spread (m)'), radius));
    }
    if (info.kind === 'npc') {
      const name = h('input', { type: 'text', maxlength: 40, placeholder: '(their own name)', value: info.data.name ?? '' }) as HTMLInputElement;
      name.onchange = () => this.cb.data({ name: name.value });
      name.onkeydown = (e: KeyboardEvent) => e.stopPropagation();
      kids.push(h('label', {}, h('span', {}, 'Name'), name));
    }
    if (info.canSnap) {
      const snap = h('input', { type: 'checkbox' }) as HTMLInputElement;
      snap.checked = info.snap;
      snap.onchange = () => this.cb.snap(snap.checked);
      kids.push(h('label', {}, snap, 'Snap to the 1.5 m grid and right angles (hold Alt to ignore)'));
    }
    kids.push(h('div', { class: 'row' }, h('button', { class: 'btn', onclick: () => this.cb.cancel() }, info.isNew ? 'Put it away' : 'Put it back')));
    this.heldEl.replaceChildren(...kids.filter(Boolean) as HTMLElement[]);
    this.heldEl.classList.add('on');
  }

  focusSearch() {
    this.search.focus();
    this.search.select();
  }

  dispose() {
    this.unmove();
    this.el.remove();
    this.style.remove();
  }

  // ----------------------------------------------------------------

  private choose(e: CatalogueEntry) {
    if (!e.allowed) return;
    this.selected = e.id;
    this.renderList();
    this.cb.pick(e);
  }

  private render() {
    this.cats.replaceChildren(
      ...CATEGORIES.map((c) => h('button', { class: 'btn' + (c === this.category ? ' on' : ''), onclick: () => { this.category = c; this.render(); } }, c)),
      ...(this.admin ? [] : [h('button', { class: 'btn' + (this.showLocked ? ' on' : ''), title: 'Show what your role may not place', onclick: () => { this.showLocked = !this.showLocked; this.render(); } }, '🔒')])
    );
    this.renderList();
    this.keys.innerHTML =
      '<kbd>Click</kbd> something placed to pick it up, <kbd>click</kbd> again to set it down (<kbd>Shift</kbd>: place another). ' +
      'Holding it: <kbd>right button</kbd> turns it gently (<kbd>Shift</kbd>: the other way), <kbd>wheel</kbd> or <kbd>Q</kbd>/<kbd>E</kbd> in steps, ' +
      '<kbd>PgUp</kbd>/<kbd>PgDn</kbd> raise and lower (<kbd>Shift</kbd>: a storey), <kbd>[</kbd>/<kbd>]</kbd> size. ' +
      '<kbd>Right-click</kbd> something to remove it; <kbd>Ctrl+Z</kbd> undoes. <kbd>Esc</kbd> drops what you hold; <kbd>`</kbd> leaves build mode.' +
      (this.role ? ` <span style="color:#cdbf9f">You build as ${this.role}.</span>` : '');
  }

  private renderList() {
    const rows = filterCatalogue(this.catalogue, this.search.value, this.category, this.showLocked).map((e) => {
      const kids: Array<HTMLElement | string> = [h('span', { class: 'ic' }, ICON[e.category] || '•'), h('span', { class: 'nm', title: e.id }, e.name + (e.levels ? ` (${e.levels[0] === e.levels[1] ? e.levels[0] : `${e.levels[0]}-${e.levels[1]}`})` : ''))];
      if (this.admin) {
        const sel = h('select', { title: 'Who may place, move and remove this' }, ...this.roles.map((r) => h('option', { value: r, selected: r === e.min_role }, r))) as HTMLSelectElement;
        sel.onclick = (ev) => ev.stopPropagation();
        sel.onchange = () => this.cb.rule(e.id, sel.value);
        kids.push(sel);
      } else {
        kids.push(h('span', { class: 'rl' }, e.allowed ? '' : `🔒 ${e.min_role}`));
      }
      return h('div', { class: 'it' + (e.allowed ? '' : ' lock') + (this.selected === e.id ? ' sel' : ''), onclick: () => this.choose(e) }, ...kids);
    });
    this.list.replaceChildren(...(rows.length ? rows : [h('div', { class: 'empty' }, this.catalogue.length ? 'Nothing matches.' : 'Loading...')]));
  }
}
