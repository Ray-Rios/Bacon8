// The skill tree window (K), the spell bar (two rows of ten: 1-0 and Shift+1-0) and the
// cast bar, in the game's window style (game-ui.ts' .bwg). Skills go on the hotbar's
// Q E F Z X slots, which game-ui.ts draws with `skillSlot` from here.
//
// Abilities are dragged from the tree (learned spells and skills) onto a slot; a slot's
// ability drags to another slot (they swap) or right-click clears it. The server keeps
// the bars (BaconWorld.Skills `hotbars`).
import { makeMovable } from './window-drag';
import {
  TREE_CSS,
  TreeCanvas,
  abilityLines,
  dragAbility,
  iconHTML,
  type Ability,
  type Catalog,
  type Tree,
  type TreeNode,
} from './skill-tree-canvas';

export interface Hotbars { skills: Record<string, string>; spells: Array<string | null> }
export interface SkillsData {
  catalog: Catalog;
  tree: Tree;
  learned: string[];
  points: number;
  abilities: string[];
  hotbars: Hotbars;
}

export interface SkillsUICallbacks {
  learn(nodeId: string): void;
  cast(abilityId: string): void;
  /** A slot ('spell:3', 'skill:Q') now holds this ability (null: emptied). */
  assign(slot: string, abilityId: string | null): void;
  windows(open: boolean): void;
}

export const SKILL_KEYS = ['Q', 'E', 'F', 'Z', 'X'];
export const SPELL_KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

const CSS = `
${TREE_CSS}
.bwg .skw > .t{cursor:move}
.bwg .skw{will-change:transform;contain:layout paint;left:50%;top:50%;transform:translate(-50%,-50%);width:640px;height:560px;max-width:calc(100% - 24px);max-height:calc(100% - 24px);display:none;flex-direction:column}
.bwg .skw .cv{flex:1;position:relative;background:radial-gradient(circle at 50% 50%,#1b1712,#0b0a08 70%);overflow:hidden}
.bwg .skw .ft{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:6px 10px;font-size:11px;color:#a8997a;border-top:1px solid #4b3f2b}
.bwg .skw .pts{color:#7be08a;font-weight:700}
.bwg .spb{right:12px;bottom:12px;padding:5px 6px 6px;display:flex;flex-direction:column;gap:4px}
.bwg .spb .rowx{display:flex;gap:3px}
.bwg .spb .s{width:38px;height:38px}
.bwg .s .ab{pointer-events:none;display:flex}
.bwg .s.dim .ab{filter:grayscale(.8) brightness(.6)}
.bwg .s.drop-hot{box-shadow:inset 0 0 0 2px #7be08a}
.bwg .cbar{left:50%;bottom:118px;transform:translateX(-50%);width:260px;padding:4px 8px 6px;display:none;pointer-events:none}
.bwg .cbar .nm{text-align:center;font-size:11px;color:#e9cf8f;margin-bottom:2px}
.bwg .cbar .bar{height:10px}.bwg .cbar .bar i{background:linear-gradient(#f2c45a,#a2741a)}
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

export class SkillsUI {
  private style: HTMLStyleElement;
  private win: HTMLElement;
  private canvasHost: HTMLElement;
  private footer: HTMLElement;
  private title: HTMLElement;
  private titleBar!: HTMLElement;
  private bar: HTMLElement;
  private castBar: HTMLElement;
  private tip: HTMLElement;
  private canvas: TreeCanvas;
  private data: SkillsData | null = null;
  private cool = new Map<string, { start: number; ms: number }>();
  private mp = Infinity;
  private unmovable: Array<() => void> = [];
  private castTimer: number | null = null;

  constructor(private root: HTMLElement, private cb: SkillsUICallbacks) {
    this.style = document.createElement('style');
    this.style.textContent = CSS;
    document.head.appendChild(this.style);
    this.title = h('span', {}, 'Skills');
    const titleBar = h('div', { class: 't' }, this.title, h('span', { class: 'x', title: 'Close (K)', onclick: () => this.close() }, '✕'));
    this.titleBar = titleBar;
    this.win = h('div', { class: 'w skw' }, titleBar);
    this.canvasHost = h('div', { class: 'cv' });
    this.footer = h('div', { class: 'ft' });
    this.win.append(this.canvasHost, this.footer);
    this.bar = h('div', { class: 'w spb' });
    this.castBar = h('div', { class: 'w cbar' });
    this.tip = h('div', { class: 'tip' });
    root.append(this.win, this.bar, this.castBar, this.tip);
    // The window moves by its title bar only: a drag on the tree pans the tree (2026-10-26: a drag
    // anywhere moved the window and panned the tree at once, and it stuttered along)
    this.unmovable = [makeMovable(this.win, 'skills', this.titleBar), makeMovable(this.bar, 'spellbar')];
    this.canvas = new TreeCanvas(this.canvasHost, {
      ring: 96,
      state: (n) => this.stateOf(n),
      onNodeClick: (n) => this.clickNode(n),
      onNodeDown: (n, e) => this.dragFromNode(n, e),
      onNodeHover: (n, e) => this.hoverNode(n, e),
    });
    this.renderBar();
  }

  dispose() {
    this.unmovable.forEach((f) => f());
    this.win.remove();
    this.bar.remove();
    this.castBar.remove();
    this.tip.remove();
    this.style.remove();
  }

  // ---------------------------------------------------------------- data

  set(data: SkillsData) {
    this.data = data;
    this.canvas.set(data.tree, data.catalog);
    this.title.replaceChildren('Skills ', h('b', {}, data.points > 0 ? `· ${data.points} point${data.points === 1 ? '' : 's'} to spend` : ''));
    this.footer.replaceChildren(
      h('span', {}, h('span', { class: 'pts' }, String(data.points)), ` skill point${data.points === 1 ? '' : 's'} left · one each level`),
      h('span', {}, 'Click a glowing node to learn it · drag spells and skills to your bars · wheel to zoom'));
    this.renderBar();
  }

  ability(id: string | null | undefined): Ability | null {
    return (id && this.data?.catalog[id]) || null;
  }

  get hotbars(): Hotbars {
    return this.data?.hotbars || { skills: {}, spells: Array(20).fill(null) };
  }

  // ---------------------------------------------------------------- window

  get isOpen() {
    return this.win.style.display === 'flex';
  }

  toggle() {
    if (this.isOpen) this.close();
    else this.open();
  }

  open() {
    this.win.style.display = 'flex';
    this.canvas.render();
    this.cb.windows(true);
  }

  close() {
    this.win.style.display = 'none';
    this.hideTip();
  }

  private stateOf(n: TreeNode) {
    const d = this.data!;
    if (d.learned.includes(n.id)) return 'learned' as const;
    const joined = d.tree.edges.some(([a, b]) => (a === n.id && d.learned.includes(b)) || (b === n.id && d.learned.includes(a)));
    return joined && d.points > 0 ? ('available' as const) : ('locked' as const);
  }

  private clickNode(n: TreeNode) {
    if (this.stateOf(n) === 'available') this.cb.learn(n.id);
  }

  private dragFromNode(n: TreeNode, e: PointerEvent) {
    const a = this.ability(n.ability);
    if (!a || a.kind === 'buff' || this.stateOf(n) !== 'learned') return;
    e.stopPropagation();
    const sx = e.clientX, sy = e.clientY;
    const start = (ev: PointerEvent) => {
      if (Math.hypot(ev.clientX - sx, ev.clientY - sy) < 6) return;
      window.removeEventListener('pointermove', start);
      this.hideTip();
      dragAbility(a, ev, (el) => this.dropOn(el, a.id, null));
    };
    window.addEventListener('pointermove', start);
    window.addEventListener('pointerup', () => window.removeEventListener('pointermove', start), { once: true });
  }

  private hoverNode(n: TreeNode | null, e: MouseEvent | null) {
    if (!n || !e || !this.data) return this.hideTip();
    const a = this.ability(n.ability);
    const st = this.stateOf(n);
    const joined = this.data.tree.edges.some(([x, y]) => (x === n.id && this.data!.learned.includes(y)) || (y === n.id && this.data!.learned.includes(x)));
    const status =
      st === 'learned' ? (a && a.kind !== 'buff' ? 'Learned. Drag it to a bar.' : 'Learned.')
        : st === 'available' ? 'Click to learn (1 skill point).'
          : joined ? 'You need a skill point: you earn one each level.' : 'Learn a node joined to it first.';
    this.showTip(e, a ? `${a.name} <span style="color:#a8997a;font-weight:400">(${a.kind})</span>` : 'A path', [...(a ? abilityLines(a) : ['Leads further out.']), status]);
  }

  // ---------------------------------------------------------------- the bars

  /** The Q..X slot for game-ui.ts' hotbar. */
  skillSlot(key: string): HTMLElement {
    const id = this.hotbars.skills[key] || null;
    return this.slot(`skill:${key}`, key, id, 44);
  }

  private renderBar() {
    const spells = this.hotbars.spells;
    const row = (r: number) =>
      h('div', { class: 'rowx' }, ...SPELL_KEYS.map((k, i) => this.slot(`spell:${r * 10 + i}`, r ? `⇧${k}` : k, spells[r * 10 + i] || null, 38)));
    this.bar.replaceChildren(row(0), row(1));
    this.repaintCooldowns();
  }

  private slot(slot: string, key: string, id: string | null, size: number): HTMLElement {
    const a = this.ability(id);
    const el = h('div', { class: 's hov' + (a && (a.mp || 0) > this.mp ? ' dim' : ''), 'data-drop': slot, 'data-hot': slot.startsWith('skill:') ? key : undefined, 'data-ab': id || undefined },
      a ? h('div', { class: 'ab' }) : null,
      h('span', { class: 'k' }, key),
      h('div', { class: 'cd' }));
    if (a) (el.querySelector('.ab') as HTMLElement).innerHTML = iconHTML(a, size - 8);
    el.onclick = () => id && this.cb.cast(id);
    el.oncontextmenu = (e) => {
      e.preventDefault();
      if (id) this.cb.assign(slot, null);
    };
    el.onmouseenter = (e) => (a ? this.showTip(e, a.name, abilityLines(a).slice(0, 2).concat(['Right-click to clear.'])) : this.showTip(e, slot.startsWith('skill') ? 'Skill slot' : 'Spell slot', [slot.startsWith('skill') ? 'Drag a skill here from the skill tree (K).' : 'Drag a spell here from the skill tree (K).']));
    el.onmousemove = (e) => this.moveTip(e);
    el.onmouseleave = () => this.hideTip();
    el.onpointerdown = (e) => {
      if (!a || e.button !== 0) return;
      const sx = e.clientX, sy = e.clientY;
      const start = (ev: PointerEvent) => {
        if (Math.hypot(ev.clientX - sx, ev.clientY - sy) < 6) return;
        window.removeEventListener('pointermove', start);
        this.hideTip();
        dragAbility(a, ev, (drop) => this.dropOn(drop, a.id, slot));
      };
      window.addEventListener('pointermove', start);
      window.addEventListener('pointerup', () => window.removeEventListener('pointermove', start), { once: true });
    };
    return el;
  }

  /** An ability let go over `el`: onto a slot of the right kind (from `from`, they swap). */
  private dropOn(el: Element | null, id: string, from: string | null) {
    const to = el?.closest?.('[data-drop]')?.getAttribute('data-drop');
    const a = this.ability(id);
    if (!to || !a) return;
    if ((to.startsWith('spell:') && a.kind !== 'spell') || (to.startsWith('skill:') && a.kind !== 'skill')) return;
    if (to === from) return;
    const there = this.slotValue(to);
    this.cb.assign(to, id);
    if (from) this.cb.assign(from, there);
  }

  slotValue(slot: string): string | null {
    const [kind, k] = slot.split(':');
    return kind === 'spell' ? this.hotbars.spells[Number(k)] || null : this.hotbars.skills[k] || null;
  }

  /** Puts an ability in a slot locally (the caller tells the server). */
  setSlot(slot: string, id: string | null) {
    if (!this.data) return;
    const [kind, k] = slot.split(':');
    const bars = this.data.hotbars;
    // an ability lives in one slot of a bar
    if (id) {
      if (kind === 'spell') bars.spells = bars.spells.map((x) => (x === id ? null : x));
      else for (const key of Object.keys(bars.skills)) if (bars.skills[key] === id) delete bars.skills[key];
    }
    if (kind === 'spell') bars.spells[Number(k)] = id;
    else if (id) bars.skills[k] = id;
    else delete bars.skills[k];
    this.renderBar();
  }

  /** The ability on a spell bar key (row 0: 1-0, row 1: Shift+1-0). */
  spellAt(index: number): string | null {
    return this.hotbars.spells[index] || null;
  }

  /** Greys out spells you can't afford. */
  setMana(mp: number) {
    if (mp === this.mp) return;
    this.mp = mp;
    this.renderBar();
  }

  /** An ability's recast, on every slot holding it. */
  cooldown(id: string, ms: number) {
    if (ms <= 0) return;
    this.cool.set(id, { start: performance.now(), ms });
    this.repaintCooldowns();
  }

  readyIn(id: string): number {
    const c = this.cool.get(id);
    return c ? Math.max(0, c.start + c.ms - performance.now()) : 0;
  }

  private repainting = false;
  private repaintCooldowns() {
    if (this.repainting) return;
    this.repainting = true;
    const step = () => {
      let any = false;
      for (const el of Array.from(this.root.querySelectorAll('[data-ab]')) as HTMLElement[]) {
        const c = this.cool.get(el.getAttribute('data-ab')!);
        const cd = el.querySelector('.cd') as HTMLElement | null;
        if (!cd) continue;
        const t = c ? (performance.now() - c.start) / c.ms : 1;
        if (t >= 1) cd.style.background = '';
        else {
          any = true;
          const deg = Math.round(t * 360);
          cd.style.background = `conic-gradient(transparent 0deg ${deg}deg, rgba(0,0,0,.62) ${deg}deg 360deg)`;
        }
      }
      if (any) requestAnimationFrame(step);
      else this.repainting = false;
    };
    requestAnimationFrame(step);
  }

  // ---------------------------------------------------------------- casting

  castStart(name: string, ms: number) {
    this.castStop();
    const fill = h('i', { style: { width: '0%' } });
    this.castBar.replaceChildren(h('div', { class: 'nm' }, name), h('div', { class: 'bar' }, fill));
    this.castBar.style.display = 'block';
    const start = performance.now();
    const step = () => {
      const t = Math.min(1, (performance.now() - start) / ms);
      fill.style.width = `${t * 100}%`;
      if (t < 1) this.castTimer = requestAnimationFrame(step);
      else this.castTimer = null;
    };
    this.castTimer = requestAnimationFrame(step);
  }

  castStop(note?: string) {
    if (this.castTimer) cancelAnimationFrame(this.castTimer);
    this.castTimer = null;
    if (note && this.castBar.style.display === 'block') {
      const nm = this.castBar.querySelector('.nm');
      if (nm) nm.textContent = note;
      setTimeout(() => (this.castBar.style.display = 'none'), 700);
    } else this.castBar.style.display = 'none';
  }

  // ---------------------------------------------------------------- tooltip

  private showTip(e: MouseEvent, title: string, lines: string[]) {
    this.tip.innerHTML = `<b>${title}</b>${lines.map((l) => `<div>${l}</div>`).join('')}`;
    this.tip.style.display = 'block';
    this.moveTip(e);
  }

  private moveTip(e: MouseEvent) {
    const w = this.tip.offsetWidth, hgt = this.tip.offsetHeight;
    this.tip.style.left = `${Math.min(window.innerWidth - w - 8, e.clientX + 14)}px`;
    this.tip.style.top = `${Math.max(8, e.clientY - hgt - 10)}px`;
  }

  private hideTip() {
    this.tip.style.display = 'none';
  }
}
