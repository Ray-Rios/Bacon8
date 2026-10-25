// The stable (the stablemaster, BaconWorld.Merchants kind "stable"): every mount, which
// ones you own, the one you ride (M). Choose another of yours, or follow a link to buy
// one in the Bacon Store. In the game's window style (game-ui.ts' .bwg).
import { makeMovable } from './window-drag';

export interface StableData {
  stable: { id: string; name: string; title?: string };
  catalog: Record<string, { id: string; name: string; summary?: string; colors?: Record<string, string>; flies?: boolean; fly_speed?: number; ground_speed?: number }>;
  order: string[];
  owned: string[];
  chosen: string | null;
  riding: string | null;
  store: Record<string, string>;
}

const CSS = `
.bwg .stb{left:16px;top:70px;width:360px;max-width:calc(100% - 24px);display:none}
.bwg .stb .list{padding:6px 8px;display:flex;flex-direction:column;gap:6px}
.bwg .stb .row{display:flex;align-items:center;gap:10px;padding:6px;border:1px solid #3b3226;border-radius:3px;background:rgba(255,255,255,.02)}
.bwg .stb .row.on{border-color:#c9a65e;background:rgba(201,166,94,.1)}
.bwg .stb .sw{width:40px;height:40px;border-radius:50%;flex:none;box-shadow:inset 0 0 0 2px rgba(0,0,0,.5),0 1px 2px #000;display:flex;align-items:center;justify-content:center;font-size:22px}
.bwg .stb .nm{flex:1;min-width:0}.bwg .stb .nm b{display:block;color:#f0d77a;font-size:12px}.bwg .stb .nm span{font-size:10px;color:#a8997a}
.bwg .stb a.btn{text-decoration:none}
.bwg .stb .ft{padding:6px 10px 8px;font-size:10px;color:#a8997a;border-top:1px solid #4b3f2b}
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

export class StableWindow {
  private el: HTMLElement;
  private style: HTMLStyleElement;
  private data: StableData | null = null;
  private unmove: () => void;

  constructor(root: HTMLElement, private onChoose: (mountId: string) => void, private onClose: () => void) {
    this.style = document.createElement('style');
    this.style.textContent = CSS;
    document.head.appendChild(this.style);
    this.el = h('div', { class: 'w stb' });
    root.appendChild(this.el);
    this.unmove = makeMovable(this.el, 'stable');
  }

  get isOpen() {
    return this.el.style.display === 'block';
  }

  open(data: StableData) {
    this.data = data;
    this.render();
    this.el.style.display = 'block';
  }

  update(patch: Partial<StableData>) {
    if (!this.data) return;
    Object.assign(this.data, patch);
    this.render();
  }

  close() {
    if (!this.isOpen) return;
    this.el.style.display = 'none';
    this.onClose();
  }

  dispose() {
    this.unmove();
    this.el.remove();
    this.style.remove();
  }

  private render() {
    const d = this.data!;
    const rows = d.order.map((id) => {
      const m = d.catalog[id];
      if (!m) return null;
      const owned = d.owned.includes(id);
      const chosen = d.chosen === id || (!d.chosen && owned && d.owned[0] === id);
      const c = m.colors || {};
      const swatch = h('div', { class: 'sw', style: { background: `radial-gradient(circle at 35% 30%, ${c.belly || '#d9a55c'}, ${c.scales || '#a8341a'} 60%, ${c.membrane || '#3a1008'})` } }, '🐉');
      const action = owned
        ? chosen
          ? h('span', { class: 'btn on', style: { cursor: 'default' } }, d.riding === id ? 'Riding' : 'Your mount')
          : h('button', { class: 'btn', onclick: () => this.onChoose(id) }, 'Ride this one')
        : h('a', { class: 'btn', href: d.store[id] || '/store', target: '_blank', rel: 'noopener' }, 'Buy');
      return h('div', { class: 'row' + (chosen ? ' on' : '') }, swatch,
        h('div', { class: 'nm' }, h('b', {}, m.name), h('span', {}, `${m.summary || ''}${m.flies ? ` Flies at ${m.fly_speed} m/s.` : ''}`)),
        action);
    });
    this.el.replaceChildren(
      h('div', { class: 't' }, h('b', {}, `${d.stable.name}${d.stable.title ? `, ${d.stable.title}` : ''}`), h('span', { class: 'x', onclick: () => this.close() }, '✕')),
      h('div', { class: 'list' }, ...rows),
      h('div', { class: 'ft' }, d.owned.length ? 'Press M to ride your mount; double-tap Space to fly.' : 'You have no mounts yet: they are sold in the Bacon Store.'));
  }
}
