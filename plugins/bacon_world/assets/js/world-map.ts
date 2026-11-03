// The player's minimap and world map (2026-11-02, owner: "now that we have more zones to explore,
// players need a map and a mini-map with a way to tell what way is north").
//
// Minimap (top right): a circle of the zone's shaded picture around the player, north up, with an
// "N" on its rim, an arrow for where the camera looks, and dots for what's near: creatures (red),
// NPCs (gold), other players (white). Click it, or press N, for the map.
//
// Map (N): the whole zone, the player and the same dots, and the eight zones around it with their
// names (greyed when they have no ground yet): walk off an edge to go there.
//
// Pictures: the zone's 512 px preview (/models/World/Zones/<terrain>_preview.png, the server's
// "zone_info"). North is -z, the picture's top row.

export interface ZoneInfo {
  number: number | null;
  name: string | null;
  preview: string | null;
  neighbours: Array<{ dx: number; dz: number; number: number; name: string; ready: boolean; preview: string | null }>;
}

/** The zone's frame (scene units): the heightfield's x0, z0, size. */
export interface MapFrame {
  x0: number;
  z0: number;
  size: number;
}

export interface MapDot {
  x: number;
  z: number;
  kind: 'mob' | 'npc' | 'player' | 'dead';
}

const DOT: Record<MapDot['kind'], string> = { mob: '#ff5a4f', npc: '#ffd36b', player: '#ffffff', dead: '#8a8a8a' };
const MINI = 168; // px
const MINI_SPAN_M = 360; // metres across the minimap

export class WorldMap {
  readonly el: HTMLDivElement;
  private mini: HTMLCanvasElement;
  private miniLabel: HTMLDivElement;
  private big: HTMLDivElement;
  private bigCanvas: HTMLCanvasElement;
  private bigTitle: HTMLDivElement;
  private img = new Image();
  private neighbourImgs = new Map<string, HTMLImageElement>();
  private info: ZoneInfo | null = null;
  open = false;

  constructor(parent: HTMLElement, private unitsPerMetre: number) {
    this.el = document.createElement('div');
    this.el.style.cssText = 'position:absolute;inset:0;pointer-events:none;z-index:6';

    this.mini = document.createElement('canvas');
    this.mini.width = this.mini.height = MINI * (window.devicePixelRatio || 1);
    this.mini.style.cssText =
      `position:absolute;right:14px;top:14px;width:${MINI}px;height:${MINI}px;border-radius:50%;pointer-events:auto;cursor:pointer;` +
      'box-shadow:0 0 0 2px rgba(233,207,143,.85),0 6px 18px rgba(0,0,0,.6)';
    this.mini.title = 'Map (N)';
    this.mini.addEventListener('click', () => this.toggle());
    this.miniLabel = document.createElement('div');
    this.miniLabel.style.cssText =
      `position:absolute;right:14px;top:${MINI + 20}px;width:${MINI}px;text-align:center;color:#e9cf8f;` +
      'font:600 12px "Trebuchet MS",Arial,sans-serif;text-shadow:0 1px 2px #000';

    this.big = document.createElement('div');
    this.big.style.cssText =
      'position:absolute;inset:0;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.55);pointer-events:auto;z-index:7';
    this.big.addEventListener('click', (e) => {
      if (e.target === this.big) this.toggle(false);
    });
    const panel = document.createElement('div');
    panel.style.cssText =
      'position:relative;padding:10px;border-radius:6px;background:rgba(17,15,13,.96);border:1px solid #6d5b3c;box-shadow:0 10px 30px rgba(0,0,0,.6)';
    this.bigTitle = document.createElement('div');
    this.bigTitle.style.cssText = 'color:#e9cf8f;font:600 14px "Trebuchet MS",Arial,sans-serif;margin:0 0 8px;display:flex;justify-content:space-between;gap:16px';
    this.bigCanvas = document.createElement('canvas');
    this.bigCanvas.style.cssText = 'display:block;border-radius:4px';
    panel.append(this.bigTitle, this.bigCanvas);
    this.big.appendChild(panel);

    this.el.append(this.mini, this.miniLabel, this.big);
    parent.appendChild(this.el);
  }

  setZone(info: ZoneInfo) {
    this.info = info;
    if (info.preview) this.img.src = info.preview;
    this.neighbourImgs.clear();
    for (const n of info.neighbours) {
      if (!n.preview) continue;
      const im = new Image();
      im.src = n.preview;
      this.neighbourImgs.set(`${n.dx},${n.dz}`, im);
    }
    this.miniLabel.textContent = info.name || '';
  }

  toggle(open?: boolean) {
    this.open = open ?? !this.open;
    this.big.style.display = this.open ? 'flex' : 'none';
  }

  dispose() {
    this.el.remove();
  }

  /**
   * Redraws (a few times a second is plenty). `me`: the player (scene units); `facing`: radians,
   * the camera's heading (0 = looking north, -z; clockwise positive).
   */
  draw(frame: MapFrame | null, me: { x: number; z: number } | null, facing: number, dots: MapDot[]) {
    this.drawMini(frame, me, facing, dots);
    if (this.open) this.drawBig(frame, me, facing, dots);
  }

  private drawMini(frame: MapFrame | null, me: { x: number; z: number } | null, facing: number, dots: MapDot[]) {
    const dpr = window.devicePixelRatio || 1;
    const c = this.mini.getContext('2d') as CanvasRenderingContext2D;
    const W = MINI;
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.clearRect(0, 0, W, W);
    c.save();
    c.beginPath();
    c.arc(W / 2, W / 2, W / 2, 0, Math.PI * 2);
    c.clip();
    c.fillStyle = '#0d1a14';
    c.fillRect(0, 0, W, W);
    const U = this.unitsPerMetre;
    if (frame && me) {
      // pixels per scene unit: the minimap shows MINI_SPAN_M metres across
      const k = W / (MINI_SPAN_M * U);
      const ox = W / 2 - (me.x - frame.x0) * k;
      const oz = W / 2 - (me.z - frame.z0) * k;
      if (this.img.complete && this.img.naturalWidth) c.drawImage(this.img, ox, oz, frame.size * k, frame.size * k);
      // beyond the zone's edge: darker
      c.fillStyle = 'rgba(0,0,0,.45)';
      c.fillRect(0, 0, W, Math.max(0, oz));
      c.fillRect(0, oz + frame.size * k, W, W);
      c.fillRect(0, 0, Math.max(0, ox), W);
      c.fillRect(ox + frame.size * k, 0, W, W);
      for (const d of dots) {
        const px = W / 2 + (d.x - me.x) * k;
        const pz = W / 2 + (d.z - me.z) * k;
        if (px < -4 || pz < -4 || px > W + 4 || pz > W + 4) continue;
        this.dot(c, px, pz, d.kind, 2.6);
      }
    }
    c.restore();
    this.arrow(c, W / 2, W / 2, facing, 8);
    // north on the rim
    c.font = '700 13px "Trebuchet MS",Arial,sans-serif';
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    c.lineWidth = 3;
    c.strokeStyle = 'rgba(0,0,0,.85)';
    c.fillStyle = '#ff6b5a';
    c.strokeText('N', W / 2, 10);
    c.fillText('N', W / 2, 10);
  }

  private drawBig(frame: MapFrame | null, me: { x: number; z: number } | null, facing: number, dots: MapDot[]) {
    const dpr = window.devicePixelRatio || 1;
    const side = Math.max(240, Math.min(window.innerWidth, window.innerHeight) - 120);
    const cell = side / 3;
    if (this.bigCanvas.width !== Math.round(side * dpr)) {
      this.bigCanvas.width = this.bigCanvas.height = Math.round(side * dpr);
      this.bigCanvas.style.width = this.bigCanvas.style.height = `${side}px`;
    }
    const n = this.info?.number;
    this.bigTitle.innerHTML = '';
    const t = document.createElement('span');
    t.textContent = `${this.info?.name || 'This zone'}${n != null ? `  ·  zone ${n}` : ''}`;
    const hint = document.createElement('span');
    hint.style.cssText = 'color:#8d7d5e;font-weight:400;font-size:12px';
    hint.textContent = 'N or click outside to close · walk off an edge to cross';
    this.bigTitle.append(t, hint);

    const c = this.bigCanvas.getContext('2d') as CanvasRenderingContext2D;
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.fillStyle = '#0b0f0d';
    c.fillRect(0, 0, side, side);
    // the eight around: their pictures, greyed, with names
    c.font = '600 13px "Trebuchet MS",Arial,sans-serif';
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    for (const nb of this.info?.neighbours || []) {
      const x = (nb.dx + 1) * cell;
      const y = (nb.dz + 1) * cell;
      const im = this.neighbourImgs.get(`${nb.dx},${nb.dz}`);
      if (im?.complete && im.naturalWidth) {
        c.globalAlpha = 0.45;
        c.drawImage(im, x, y, cell, cell);
        c.globalAlpha = 1;
      } else {
        c.fillStyle = '#141a17';
        c.fillRect(x + 1, y + 1, cell - 2, cell - 2);
      }
      c.lineWidth = 3;
      c.strokeStyle = 'rgba(0,0,0,.9)';
      c.fillStyle = nb.ready ? '#e9e2cf' : '#7c766a';
      const label = `${nb.name}${nb.ready ? '' : ' (unexplored)'}`;
      c.strokeText(label, x + cell / 2, y + cell / 2);
      c.fillText(label, x + cell / 2, y + cell / 2);
    }
    // this zone
    if (this.img.complete && this.img.naturalWidth) c.drawImage(this.img, cell, cell, cell, cell);
    c.strokeStyle = '#e9cf8f';
    c.lineWidth = 2;
    c.strokeRect(cell, cell, cell, cell);
    if (frame) {
      const k = cell / frame.size;
      for (const d of dots) this.dot(c, cell + (d.x - frame.x0) * k, cell + (d.z - frame.z0) * k, d.kind, 2.5);
      if (me) this.arrow(c, cell + (me.x - frame.x0) * k, cell + (me.z - frame.z0) * k, facing, 9);
    }
    // the compass
    c.font = '700 16px "Trebuchet MS",Arial,sans-serif';
    c.lineWidth = 3;
    c.strokeStyle = 'rgba(0,0,0,.9)';
    for (const [l, x, y] of [['N', side / 2, 12], ['S', side / 2, side - 12], ['W', 12, side / 2], ['E', side - 12, side / 2]] as const) {
      c.fillStyle = l === 'N' ? '#ff6b5a' : '#e9cf8f';
      c.strokeText(l, x, y);
      c.fillText(l, x, y);
    }
  }

  private dot(c: CanvasRenderingContext2D, x: number, y: number, kind: MapDot['kind'], r: number) {
    c.beginPath();
    c.arc(x, y, r, 0, Math.PI * 2);
    c.fillStyle = DOT[kind];
    c.fill();
    c.lineWidth = 1;
    c.strokeStyle = 'rgba(0,0,0,.8)';
    c.stroke();
  }

  // the player: an arrow pointing where the camera looks (0 = north, up the map)
  private arrow(c: CanvasRenderingContext2D, x: number, y: number, facing: number, size: number) {
    c.save();
    c.translate(x, y);
    c.rotate(facing);
    c.beginPath();
    c.moveTo(0, -size);
    c.lineTo(size * 0.65, size * 0.75);
    c.lineTo(0, size * 0.35);
    c.lineTo(-size * 0.65, size * 0.75);
    c.closePath();
    c.fillStyle = '#7fdcff';
    c.fill();
    c.lineWidth = 1.5;
    c.strokeStyle = '#06222c';
    c.stroke();
    c.restore();
  }
}
