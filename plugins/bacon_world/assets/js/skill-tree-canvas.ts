// The skill tree drawn as SVG (BaconWorld.SkillTree's shape: nodes in rings around the
// start, edges between them), shared by the in-game skill window (skills-ui.ts, K) and
// the admin editor (skill-tree-editor.ts, /admin/bacon_world/skills). It pans (drag the
// background) and zooms (wheel); the caller decides how each node looks (its state)
// and what clicks and drags do.

export interface TreeNode { id: string; x: number; y: number; ability: string | null }
export interface Tree { start: string; nodes: TreeNode[]; edges: Array<[string, string]> }
export interface Ability {
  id: string;
  name: string;
  kind: 'spell' | 'skill' | 'buff';
  icon: string;
  summary: string;
  mp?: number;
  cast_ms?: number;
  cooldown_ms?: number;
  target?: string;
  range_m?: number;
  effect?: { type: string; stat?: string; amount?: number; ms?: number };
}
export type Catalog = Record<string, Ability>;
export type NodeState = 'learned' | 'available' | 'locked' | 'edit' | 'selected';

/** Glyphs for the abilities' icons (Abilities `icon`), and the colour of each kind. */
export const ICONS: Record<string, string> = {
  recall: '🏠',
  heal: '✚',
  fireball: '🔥',
  root: '🌿',
  spin: '🌀',
  hp: '❤',
  mp: '💧',
  might: '💪',
  arcana: '✨',
};
export const KIND_COLORS: Record<string, [string, string]> = {
  spell: ['#3b6fd8', '#14285a'],
  skill: ['#c2492f', '#4a160c'],
  buff: ['#c9a442', '#4a3a10'],
  none: ['#55504a', '#1c1a17'],
};

/** An ability's icon as HTML (a coloured disc with its glyph), for slots and palettes. */
export function iconHTML(a: Ability | null | undefined, size = 38): string {
  const [c1, c2] = KIND_COLORS[a?.kind || 'none'];
  const glyph = a ? ICONS[a.icon] || a.name.slice(0, 1) : '';
  const fs = Math.round(size * 0.55);
  const color = a?.icon === 'heal' ? '#7CFF8A' : '#fff';
  return `<div style="width:${size}px;height:${size}px;border-radius:50%;display:flex;align-items:center;justify-content:center;background:radial-gradient(circle at 35% 30%,${c1},${c2});box-shadow:inset 0 0 0 2px rgba(0,0,0,.45),0 1px 2px #000;font-size:${fs}px;line-height:1;color:${color};text-shadow:0 1px 2px #000">${glyph}</div>`;
}

const SVGNS = 'http://www.w3.org/2000/svg';
function s(tag: string, attrs: Record<string, string | number> = {}): SVGElement {
  const el = document.createElementNS(SVGNS, tag) as SVGElement;
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, String(v));
  return el;
}

export interface CanvasOptions {
  /** Pixels per ring. */
  ring?: number;
  state(node: TreeNode): NodeState;
  onNodeDown?(node: TreeNode, e: PointerEvent): void;
  onNodeClick?(node: TreeNode, e: MouseEvent): void;
  onNodeHover?(node: TreeNode | null, e: MouseEvent | null): void;
  onBackgroundDblClick?(x: number, y: number, e: MouseEvent): void;
  onBackgroundClick?(e: MouseEvent): void;
}

export class TreeCanvas {
  readonly svg: SVGSVGElement;
  private layer: SVGGElement;
  private tree: Tree = { start: 'n0', nodes: [], edges: [] };
  private catalog: Catalog = {};
  private zoom = 1;
  private pan = { x: 0, y: 0 };
  private ring: number;
  private dragging: { x: number; y: number; px: number; py: number; moved: boolean } | null = null;

  constructor(private host: HTMLElement, private opts: CanvasOptions) {
    this.ring = opts.ring ?? 92;
    this.svg = s('svg', { width: '100%', height: '100%' }) as SVGSVGElement;
    this.svg.style.display = 'block';
    this.svg.style.touchAction = 'none';
    this.svg.style.cursor = 'grab';
    const defs = s('defs');
    defs.innerHTML =
      '<radialGradient id="bwtgl"><stop offset="0" stop-color="#ffe9a6" stop-opacity=".55"/><stop offset="1" stop-color="#ffe9a6" stop-opacity="0"/></radialGradient>' +
      '<radialGradient id="bwtga"><stop offset="0" stop-color="#8dff9a" stop-opacity=".45"/><stop offset="1" stop-color="#8dff9a" stop-opacity="0"/></radialGradient>';
    this.svg.appendChild(defs);
    this.layer = s('g') as SVGGElement;
    this.svg.appendChild(this.layer);
    host.appendChild(this.svg);
    this.svg.addEventListener('wheel', (e) => {
      e.preventDefault();
      const r = this.svg.getBoundingClientRect();
      const mx = e.clientX - r.left - r.width / 2 - this.pan.x;
      const my = e.clientY - r.top - r.height / 2 - this.pan.y;
      const z0 = this.zoom;
      this.zoom = Math.min(3, Math.max(0.3, this.zoom * Math.exp(-e.deltaY * 0.0015)));
      this.pan.x -= mx * (this.zoom / z0 - 1);
      this.pan.y -= my * (this.zoom / z0 - 1);
      this.applyView();
    }, { passive: false });
    this.svg.addEventListener('pointerdown', (e) => {
      if ((e.target as Element).closest('[data-node]')) return;
      this.dragging = { x: e.clientX, y: e.clientY, px: this.pan.x, py: this.pan.y, moved: false };
      this.svg.setPointerCapture(e.pointerId);
      this.svg.style.cursor = 'grabbing';
    });
    this.svg.addEventListener('pointermove', (e) => {
      if (!this.dragging) return;
      const dx = e.clientX - this.dragging.x, dy = e.clientY - this.dragging.y;
      if (Math.abs(dx) + Math.abs(dy) > 3) this.dragging.moved = true;
      this.pan.x = this.dragging.px + dx;
      this.pan.y = this.dragging.py + dy;
      this.applyView();
    });
    const end = (e: PointerEvent) => {
      if (!this.dragging) return;
      const moved = this.dragging.moved;
      this.dragging = null;
      this.svg.style.cursor = 'grab';
      if (!moved && !(e.target as Element).closest?.('[data-node]')) this.opts.onBackgroundClick?.(e);
    };
    this.svg.addEventListener('pointerup', end);
    this.svg.addEventListener('pointercancel', end);
    this.svg.addEventListener('dblclick', (e) => {
      if ((e.target as Element).closest('[data-node]')) return;
      const p = this.toTree(e.clientX, e.clientY);
      this.opts.onBackgroundDblClick?.(p.x, p.y, e);
    });
    new ResizeObserver(() => this.applyView()).observe(host);
  }

  set(tree: Tree, catalog: Catalog) {
    this.tree = tree;
    this.catalog = catalog;
    this.render();
  }

  /** Screen point -> tree coordinates (rings; +y up). */
  toTree(clientX: number, clientY: number): { x: number; y: number } {
    const r = this.svg.getBoundingClientRect();
    return {
      x: (clientX - r.left - r.width / 2 - this.pan.x) / (this.ring * this.zoom),
      y: -(clientY - r.top - r.height / 2 - this.pan.y) / (this.ring * this.zoom),
    };
  }

  /** The node under a screen point, if any. */
  nodeAt(clientX: number, clientY: number): TreeNode | null {
    const el = document.elementFromPoint(clientX, clientY)?.closest?.('[data-node]');
    const id = el?.getAttribute('data-node');
    return (id && this.tree.nodes.find((n) => n.id === id)) || null;
  }

  centre() {
    this.pan = { x: 0, y: 0 };
    this.zoom = 1;
    this.applyView();
  }

  private applyView() {
    const r = this.host.getBoundingClientRect();
    this.layer.setAttribute('transform', `translate(${r.width / 2 + this.pan.x},${r.height / 2 + this.pan.y}) scale(${this.zoom})`);
  }

  render() {
    const R = this.ring;
    const byId = new Map(this.tree.nodes.map((n) => [n.id, n]));
    const states = new Map(this.tree.nodes.map((n) => [n.id, this.opts.state(n)]));
    this.layer.replaceChildren();
    // faint rings
    const maxR = Math.max(1, ...this.tree.nodes.map((n) => Math.ceil(Math.hypot(n.x, n.y))));
    for (let i = 1; i <= maxR; i++) this.layer.appendChild(s('circle', { cx: 0, cy: 0, r: i * R, fill: 'none', stroke: 'rgba(201,166,94,.07)', 'stroke-width': 1 }));
    for (const [a, b] of this.tree.edges) {
      const na = byId.get(a), nb = byId.get(b);
      if (!na || !nb) continue;
      const sa = states.get(a), sb = states.get(b);
      const lit = sa === 'learned' && sb === 'learned';
      const open = (sa === 'learned' && sb === 'available') || (sb === 'learned' && sa === 'available');
      this.layer.appendChild(s('line', {
        x1: na.x * R, y1: -na.y * R, x2: nb.x * R, y2: -nb.y * R,
        stroke: lit ? '#e2c071' : open ? '#5fae6a' : 'rgba(150,130,100,.35)',
        'stroke-width': lit ? 5 : open ? 3.5 : 3,
        'stroke-linecap': 'round',
      }));
    }
    for (const n of this.tree.nodes) {
      const st = states.get(n.id)!;
      const a = n.ability ? this.catalog[n.ability] : null;
      const g = s('g', { transform: `translate(${n.x * R},${-n.y * R})`, 'data-node': n.id }) as SVGGElement;
      g.style.cursor = 'pointer';
      const big = n.id === this.tree.start ? 30 : a ? 24 : 12;
      if (st === 'learned') g.appendChild(s('circle', { r: big + 16, fill: 'url(#bwtgl)' }));
      if (st === 'available') g.appendChild(s('circle', { r: big + 14, fill: 'url(#bwtga)', class: 'bwt-pulse' }));
      const [c1, c2] = KIND_COLORS[a?.kind || 'none'];
      const gradId = `bwtk_${(a?.kind || 'none')}`;
      if (!this.svg.querySelector(`#${gradId}`)) {
        const gr = s('radialGradient', { id: gradId, cx: '35%', cy: '30%' });
        gr.appendChild(s('stop', { offset: 0, 'stop-color': c1 }));
        gr.appendChild(s('stop', { offset: 1, 'stop-color': c2 }));
        this.svg.querySelector('defs')!.appendChild(gr);
      }
      const ringColour = st === 'learned' ? '#f0d27a' : st === 'available' ? '#7be08a' : st === 'selected' ? '#ffffff' : st === 'edit' ? '#9a8a6a' : '#4a4234';
      g.appendChild(s('circle', { r: big, fill: `url(#${gradId})`, stroke: ringColour, 'stroke-width': st === 'locked' ? 2 : 3.5, opacity: st === 'locked' ? 0.55 : 1 }));
      if (a) {
        const t = s('text', { 'text-anchor': 'middle', 'dominant-baseline': 'central', 'font-size': Math.round(big * 1.05), fill: a.icon === 'heal' ? '#7CFF8A' : '#fff', opacity: st === 'locked' ? 0.5 : 1 });
        t.textContent = ICONS[a.icon] || a.name.slice(0, 1);
        (t as any).style.pointerEvents = 'none';
        g.appendChild(t);
      }
      g.addEventListener('pointerdown', (e) => this.opts.onNodeDown?.(n, e as PointerEvent));
      g.addEventListener('click', (e) => this.opts.onNodeClick?.(n, e as MouseEvent));
      g.addEventListener('mouseenter', (e) => this.opts.onNodeHover?.(n, e as MouseEvent));
      g.addEventListener('mousemove', (e) => this.opts.onNodeHover?.(n, e as MouseEvent));
      g.addEventListener('mouseleave', () => this.opts.onNodeHover?.(null, null));
      this.layer.appendChild(g);
    }
    this.applyView();
  }
}

/** The CSS the canvas's pulse uses (added once by whoever shows a canvas). */
export const TREE_CSS = `@keyframes bwtpulse{0%,100%{opacity:.35}50%{opacity:1}}.bwt-pulse{animation:bwtpulse 1.6s ease-in-out infinite}`;

/**
 * Drags an ability with the pointer (a ghost of its icon follows the cursor) and
 * reports the element it was dropped on (`[data-drop]`, or null). Used to put
 * abilities on the hotbars and, in the editor, onto nodes.
 */
export function dragAbility(a: Ability, e: PointerEvent, onDrop: (target: Element | null, x: number, y: number) => void) {
  const ghost = document.createElement('div');
  ghost.innerHTML = iconHTML(a, 40);
  Object.assign(ghost.style, { position: 'fixed', left: '0', top: '0', pointerEvents: 'none', zIndex: '100', opacity: '0.9', transform: `translate(${e.clientX - 20}px,${e.clientY - 20}px)` });
  document.body.appendChild(ghost);
  const move = (ev: PointerEvent) => {
    ghost.style.transform = `translate(${ev.clientX - 20}px,${ev.clientY - 20}px)`;
  };
  const up = (ev: PointerEvent) => {
    window.removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', up);
    ghost.remove();
    const under = document.elementFromPoint(ev.clientX, ev.clientY);
    onDrop(under?.closest?.('[data-drop]') || under || null, ev.clientX, ev.clientY);
  };
  window.addEventListener('pointermove', move);
  window.addEventListener('pointerup', up);
}

/** An ability's tooltip lines. */
export function abilityLines(a: Ability): string[] {
  const lines = [a.summary];
  if (a.kind === 'buff') return lines;
  const bits: string[] = [];
  if (a.mp) bits.push(`${a.mp} mana`);
  bits.push(a.cast_ms ? `${(a.cast_ms / 1000).toFixed(1)} s cast` : 'instant');
  if (a.cooldown_ms) bits.push(`${Math.round(a.cooldown_ms / 1000)} s recast`);
  if (a.range_m) bits.push(`${a.range_m} m`);
  lines.push(bits.join(' · '));
  lines.push(a.kind === 'spell' ? 'Spell: drag it onto the spell bar.' : 'Skill: drag it onto Q, E, F, Z or X.');
  return lines;
}
