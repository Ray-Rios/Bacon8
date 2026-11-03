// /admin/bacon_world/world (2026-11-02): one zone's heightmap with what stands on it. The LiveView
// (BaconWorldWeb.Admin.WorldLive) puts the picture's URL and the nodes in data attributes; this draws
// them on a canvas and shows a node's details while the pointer is over it.
//
// Zoom (owner: "we need to be able to zoom into the map to inspect the nodes"): the mouse wheel zooms
// about the pointer (1x to 32x), dragging pans, double-click resets, and the +, - and reset buttons do
// the same. Past 2x the 2048 px picture (`detail`, made on the server the first time) replaces the
// 512 px one. Nodes keep their size on screen, so a crowded spot spreads out as you zoom in.

interface ZoneNode {
  id: string;
  kind: 'binding' | 'npc' | 'mob' | 'object';
  label: string;
  x: number;
  y: number | null;
  z: number;
  info: Record<string, unknown>;
}

interface MapInfo {
  image: string;
  detail?: string;
  size_m: number;
  x0: number;
  z0: number;
}

const COLOURS: Record<string, string> = { binding: '#7fdcff', npc: '#ffd36b', mob: '#ff6b6b', object: '#c9c9c9' };
const RADIUS: Record<string, number> = { binding: 6, npc: 5, mob: 5, object: 3 };
const MAX_ZOOM = 32;

export const BaconWorldZoneMap = {
  mounted(this: any) {
    this.canvas = document.createElement('canvas');
    this.canvas.style.cssText = 'width:100%;display:block;border-radius:8px;cursor:grab;touch-action:none';
    this.tip = document.createElement('div');
    this.tip.style.cssText =
      'position:absolute;pointer-events:none;display:none;z-index:10;max-width:320px;padding:6px 8px;border-radius:6px;' +
      'background:rgba(10,14,22,.95);border:1px solid #3b4a63;color:#e5edf7;font:12px/1.35 ui-sans-serif,system-ui;white-space:pre-wrap';
    const bar = document.createElement('div');
    bar.style.cssText = 'position:absolute;right:8px;top:8px;display:flex;gap:4px;z-index:11';
    const button = (label: string, title: string, fn: () => void) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = label;
      b.title = title;
      b.style.cssText =
        'min-width:28px;height:28px;padding:0 6px;border-radius:6px;background:rgba(10,14,22,.85);border:1px solid #3b4a63;color:#e5edf7;font:600 14px ui-sans-serif,system-ui';
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        fn();
      });
      bar.appendChild(b);
    };
    button('+', 'Zoom in', () => this.zoomAt(2, this.width() / 2, this.width() / 2));
    button('−', 'Zoom out', () => this.zoomAt(0.5, this.width() / 2, this.width() / 2));
    button('1:1', 'Whole zone (or double-click)', () => this.resetView());
    this.zoomLabel = document.createElement('span');
    this.zoomLabel.style.cssText = 'align-self:center;padding:0 6px;color:#e5edf7;font:12px ui-sans-serif,system-ui;text-shadow:0 1px 2px #000';
    bar.appendChild(this.zoomLabel);

    // the canvas lives in a child LiveView leaves alone (phx-update="ignore"); the data attributes on this element change
    this.host = (this.el.querySelector('[data-canvas-host]') as HTMLElement | null) || this.el;
    this.host.style.position = 'relative';
    this.host.replaceChildren(this.canvas, this.tip, bar);

    this.scale = 1;
    this.tx = 0;
    this.ty = 0;
    this.img = new Image();
    this.img.onload = () => this.draw();
    this.detailImg = null;

    this.canvas.addEventListener('wheel', (e: WheelEvent) => {
      e.preventDefault();
      const r = this.canvas.getBoundingClientRect();
      this.zoomAt(e.deltaY < 0 ? 1.25 : 0.8, e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });
    this.canvas.addEventListener('pointerdown', (e: PointerEvent) => {
      this.drag = { x: e.clientX, y: e.clientY, tx: this.tx, ty: this.ty, moved: false };
      this.canvas.setPointerCapture(e.pointerId);
      this.canvas.style.cursor = 'grabbing';
    });
    this.canvas.addEventListener('pointermove', (e: PointerEvent) => {
      if (this.drag) {
        const dx = e.clientX - this.drag.x;
        const dy = e.clientY - this.drag.y;
        if (Math.abs(dx) + Math.abs(dy) > 2) this.drag.moved = true;
        this.tx = this.drag.tx + dx;
        this.ty = this.drag.ty + dy;
        this.clampView();
        this.draw();
        this.tip.style.display = 'none';
      } else {
        this.hover(e);
      }
    });
    const end = (e: PointerEvent) => {
      if (this.drag) this.canvas.releasePointerCapture?.(e.pointerId);
      this.drag = null;
      this.canvas.style.cursor = 'grab';
    };
    this.canvas.addEventListener('pointerup', end);
    this.canvas.addEventListener('pointercancel', end);
    this.canvas.addEventListener('dblclick', () => this.resetView());
    this.canvas.addEventListener('mouseleave', () => {
      this.tip.style.display = 'none';
      this.hot = null;
      this.draw();
    });
    this.onResize = () => this.draw();
    window.addEventListener('resize', this.onResize);
    this.load();
  },

  updated(this: any) {
    this.load();
  },

  destroyed(this: any) {
    window.removeEventListener('resize', this.onResize);
  },

  width(this: any): number {
    return Math.max(200, this.host.clientWidth || this.el.clientWidth);
  },

  load(this: any) {
    let next: MapInfo | null = null;
    try {
      next = JSON.parse(this.el.dataset.map || 'null') as MapInfo | null;
      this.nodes = JSON.parse(this.el.dataset.nodes || '[]') as ZoneNode[];
    } catch {
      this.nodes = [];
    }
    this.filter = new Set((this.el.dataset.kinds || 'binding,npc,mob,object').split(','));
    const changed = !this.info || !next || this.info.image !== next.image;
    this.info = next;
    if (changed) {
      this.detailImg = null;
      this.resetView(false);
      if (this.info) this.img.src = this.info.image;
    }
    this.draw();
  },

  resetView(this: any, redraw = true) {
    this.scale = 1;
    this.tx = 0;
    this.ty = 0;
    if (redraw) this.draw();
  },

  // zoom by `f` keeping the point (px, py) on the canvas where it is
  zoomAt(this: any, f: number, px: number, py: number) {
    const s = Math.min(MAX_ZOOM, Math.max(1, this.scale * f));
    const k = s / this.scale;
    this.tx = px - (px - this.tx) * k;
    this.ty = py - (py - this.ty) * k;
    this.scale = s;
    this.clampView();
    if (s > 2) this.wantDetail();
    this.draw();
  },

  clampView(this: any) {
    const w = this.width();
    const m = w * this.scale;
    this.tx = Math.min(0, Math.max(w - m, this.tx));
    this.ty = Math.min(0, Math.max(w - m, this.ty));
  },

  // the 2048 px picture, loaded once the map is zoomed in
  wantDetail(this: any) {
    if (this.detailImg || !this.info?.detail) return;
    const img = new Image();
    img.onload = () => this.draw();
    img.src = this.info.detail;
    this.detailImg = img;
  },

  // node (zone metres) -> canvas pixels
  toPx(this: any, n: { x: number; z: number }, w: number): [number, number] {
    const i = this.info as MapInfo;
    return [this.tx + ((n.x - i.x0) / i.size_m) * w * this.scale, this.ty + ((n.z - i.z0) / i.size_m) * w * this.scale];
  },

  draw(this: any) {
    const w = this.width();
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.round(w * dpr);
    this.canvas.height = Math.round(w * dpr);
    this.canvas.style.height = `${w}px`;
    const ctx = this.canvas.getContext('2d') as CanvasRenderingContext2D;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#0b1220';
    ctx.fillRect(0, 0, w, w);
    const pic = this.scale > 2 && this.detailImg?.complete && this.detailImg.naturalWidth ? this.detailImg : this.img;
    if (pic.complete && pic.naturalWidth) {
      ctx.imageSmoothingEnabled = this.scale < 8;
      ctx.drawImage(pic, this.tx, this.ty, w * this.scale, w * this.scale);
    }
    if (this.zoomLabel) this.zoomLabel.textContent = this.scale > 1.01 ? `${this.scale.toFixed(this.scale < 10 ? 1 : 0)}×` : '';
    if (!this.info) return;
    for (const n of this.nodes as ZoneNode[]) {
      if (!this.filter.has(n.kind)) continue;
      const [px, py] = this.toPx(n, w);
      if (px < -10 || py < -10 || px > w + 10 || py > w + 10) continue;
      const r = RADIUS[n.kind] || 4;
      ctx.beginPath();
      ctx.arc(px, py, this.hot === n ? r + 3 : r, 0, Math.PI * 2);
      ctx.fillStyle = COLOURS[n.kind] || '#fff';
      ctx.fill();
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = 'rgba(0,0,0,.8)';
      ctx.stroke();
      // close in, names beside the nodes
      if (this.scale >= 6) {
        ctx.font = '11px ui-sans-serif,system-ui';
        ctx.fillStyle = 'rgba(255,255,255,.9)';
        ctx.strokeStyle = 'rgba(0,0,0,.85)';
        ctx.lineWidth = 3;
        ctx.strokeText(n.label, px + r + 3, py + 4);
        ctx.fillText(n.label, px + r + 3, py + 4);
      }
    }
  },

  hover(this: any, e: PointerEvent | MouseEvent) {
    if (!this.info) return;
    const rect = this.canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const w = rect.width;
    let best: ZoneNode | null = null;
    let bd = 10;
    for (const n of this.nodes as ZoneNode[]) {
      if (!this.filter.has(n.kind)) continue;
      const [px, py] = this.toPx(n, w);
      const d = Math.hypot(px - mx, py - my);
      if (d < bd) {
        bd = d;
        best = n;
      }
    }
    const i = this.info as MapInfo;
    const zx = i.x0 + ((mx - this.tx) / (w * this.scale)) * i.size_m;
    const zz = i.z0 + ((my - this.ty) / (w * this.scale)) * i.size_m;
    if (best !== this.hot) {
      this.hot = best;
      this.draw();
    }
    const lines = best
      ? [
          `${best.label}`,
          `${best.kind} · x ${best.x.toFixed(1)} · z ${best.z.toFixed(1)}${best.y != null ? ` · y ${best.y.toFixed(1)}` : ''} m`,
          ...Object.entries(best.info || {}).map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`),
        ]
      : [`x ${zx.toFixed(0)} · z ${zz.toFixed(0)} m`];
    this.tip.textContent = lines.join('\n');
    this.tip.style.display = 'block';
    const left = Math.min(mx + 14, w - 220);
    this.tip.style.left = `${Math.max(0, left)}px`;
    this.tip.style.top = `${my + 14}px`;
  },
};
