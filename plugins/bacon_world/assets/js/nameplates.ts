// Names over heads, EverQuest style: outlined text in the world, no box, coloured
// by what the name belongs to (players, and creatures by how tough they are to
// you), the target's name brighter. A corpse keeps its name ("a skeleton's corpse").
//
// The plates are sprites in one group, placed from their character's position in
// the same frame that frame is drawn, so they never trail behind a moving
// character (the old DOM labels used the previous frame's camera, and lagged).
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';

export interface PlateInfo {
  name: string;
  /** A second, smaller line (a guild, "Level 3", ...). */
  sub?: string;
  /** CSS colour of the name. */
  color: string;
}

/** EverQuest's con colours, by the creature's level minus yours. */
export function conColor(levelDiff: number, yourLevel: number): string {
  if (levelDiff >= 3) return '#FF4A3D'; // red: much tougher
  if (levelDiff >= 1) return '#FFE14A'; // yellow
  if (levelDiff === 0) return '#FFFFFF'; // white: even
  // Below you: blue, then light blue, then green, then grey (no experience). At
  // low levels one or two below is still blue (BaconWorld.Progression.con/2 agrees).
  const greenAt = Math.max(2, Math.ceil(yourLevel * 0.25) + 1);
  if (-levelDiff >= greenAt + 2) return '#9A9A9A';
  if (-levelDiff >= greenAt) return '#5CE25C';
  if (-levelDiff >= Math.max(1, greenAt - 1) && yourLevel > 8) return '#7FD8FF';
  return '#4F86FF';
}

/** Players' names: Bacon8's blue, and red while PvP is on. */
export const PLAYER_COLOR = '#247DF1';
export const PVP_COLOR = '#E62929';

export function playerColor(pvp: boolean): string {
  return pvp ? PVP_COLOR : PLAYER_COLOR;
}

const NAME_PX = 46;
const SUB_PX = 32;
const PAD = 10;
// Old-school EverQuest's names: a plain, bold Arial-style sans with a dark outline.
const FONT = 'Arial, "Liberation Sans", Helvetica, sans-serif';
// World height of one name line near the camera; further away a plate grows to
// stay readable, up to FAR_GROW times, and past MAX_DISTANCE it is hidden.
const LINE_M = 0.15;
const GROW_FROM_M = 9;
const FAR_GROW = 2.6;
const MAX_DISTANCE_M = 75;

class Plate {
  readonly sprite: THREE.Sprite;
  private readonly canvas: HTMLCanvasElement;
  private readonly texture: THREE.CanvasTexture;
  private readonly material: THREE.SpriteMaterial;
  private key = '';
  private aspect = 1;
  private lines = 1;
  /** Feet-to-plate height in world units. */
  height = 2.4 * UNITS_PER_METRE;
  host: THREE.Object3D;
  target = false;

  constructor(host: THREE.Object3D) {
    this.host = host;
    this.canvas = document.createElement('canvas');
    this.texture = new THREE.CanvasTexture(this.canvas);
    this.texture.colorSpace = THREE.SRGBColorSpace;
    this.texture.minFilter = THREE.LinearFilter;
    this.texture.generateMipmaps = false;
    // Drawn over everything (as in EverQuest), so a name never disappears into a head,
    // a hat or the corpse it belongs to.
    this.material = new THREE.SpriteMaterial({ map: this.texture, transparent: true, depthWrite: false, depthTest: false });
    this.sprite = new THREE.Sprite(this.material);
    this.sprite.center.set(0.5, 0);
    this.sprite.renderOrder = 10;
    // Clicks pick characters, not their names.
    this.sprite.raycast = () => {};
  }

  set(info: PlateInfo, target: boolean) {
    const key = `${info.name}|${info.sub || ''}|${info.color}|${target ? 1 : 0}`;
    if (key === this.key) return;
    this.key = key;
    this.target = target;
    const ctx = this.canvas.getContext('2d')!;
    const nameFont = `700 ${NAME_PX}px ${FONT}`;
    const subFont = `400 ${SUB_PX}px ${FONT}`;
    ctx.font = nameFont;
    let w = ctx.measureText(info.name).width;
    if (info.sub) {
      ctx.font = subFont;
      w = Math.max(w, ctx.measureText(info.sub).width);
    }
    this.lines = info.sub ? 2 : 1;
    const width = Math.ceil(w + PAD * 2);
    const height = Math.ceil(NAME_PX * 1.3 + (info.sub ? SUB_PX * 1.25 : 0) + PAD);
    this.canvas.width = width;
    this.canvas.height = height;
    ctx.clearRect(0, 0, width, height);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.lineJoin = 'round';
    const draw = (text: string, font: string, y: number, color: string, outline: number) => {
      ctx.font = font;
      ctx.lineWidth = outline;
      ctx.strokeStyle = 'rgba(0,0,0,0.92)';
      ctx.strokeText(text, width / 2, y);
      ctx.fillStyle = color;
      ctx.fillText(text, width / 2, y);
    };
    // The name, and under it the second line (EverQuest puts <Guild> there).
    draw(info.name, nameFont, PAD / 2, info.color, target ? 9 : 7);
    if (info.sub) draw(info.sub, subFont, PAD / 2 + NAME_PX * 1.3, 'rgba(225,232,245,0.92)', 6);
    this.texture.needsUpdate = true;
    this.texture.dispose(); // a new size needs a new GPU texture
    this.aspect = width / height;
  }

  place(camera: THREE.Camera, tmp: THREE.Vector3) {
    const h = this.host;
    this.sprite.position.set(h.position.x, h.position.y + this.height, h.position.z);
    const d = tmp.copy(this.sprite.position).sub(camera.position).length();
    const far = MAX_DISTANCE_M * UNITS_PER_METRE;
    this.sprite.visible = h.visible !== false && d < far;
    if (!this.sprite.visible) return;
    const grow = Math.min(FAR_GROW, Math.max(1, d / (GROW_FROM_M * UNITS_PER_METRE)));
    const lineH = LINE_M * UNITS_PER_METRE * grow * (this.target ? 1.12 : 1);
    const totalH = lineH * (this.lines === 2 ? 1 + SUB_PX / NAME_PX : 1) * 1.3;
    this.sprite.scale.set(totalH * this.aspect, totalH, 1);
    // Fade out over the last fifth of the range.
    this.material.opacity = Math.min(1, (far - d) / (far * 0.2));
  }

  dispose() {
    this.texture.dispose();
    this.material.dispose();
  }
}

export class Nameplates {
  readonly group = new THREE.Group();
  private plates = new Map<string, Plate>();
  private tmp = new THREE.Vector3();

  constructor() {
    this.group.name = 'Nameplates';
  }

  /**
   * Shows (or updates) the name over `host`. `height` is feet-to-name in world
   * units; leave it out to keep the last one.
   */
  set(id: string, host: THREE.Object3D, info: PlateInfo, opts: { height?: number; target?: boolean } = {}) {
    let plate = this.plates.get(id);
    if (!plate) {
      plate = new Plate(host);
      this.plates.set(id, plate);
      this.group.add(plate.sprite);
    }
    plate.host = host;
    if (opts.height !== undefined) plate.height = opts.height;
    plate.set(info, !!opts.target);
  }

  has(id: string): boolean {
    return this.plates.has(id);
  }

  remove(id: string) {
    const plate = this.plates.get(id);
    if (!plate) return;
    this.group.remove(plate.sprite);
    plate.dispose();
    this.plates.delete(id);
  }

  /** Removes every plate whose id isn't in `keep`. */
  prune(keep: Set<string>) {
    for (const id of [...this.plates.keys()]) if (!keep.has(id)) this.remove(id);
  }

  /** Call once a frame, after everything has moved and before rendering. */
  update(camera: THREE.Camera) {
    this.plates.forEach((p) => p.place(camera, this.tmp));
  }

  clear() {
    for (const id of [...this.plates.keys()]) this.remove(id);
  }
}

/** Feet-to-name height for a character root: Bacon8 humans from their scale, others from their bounds. */
export function plateHeight(root: THREE.Object3D, isHuman: boolean): number {
  if (isHuman) return root.scale.y * 1.8 + 0.28 * UNITS_PER_METRE;
  const box = new THREE.Box3().setFromObject(root);
  const h = isFinite(box.max.y) ? box.max.y - root.position.y : 2 * UNITS_PER_METRE;
  return Math.max(0.6 * UNITS_PER_METRE, h) + 0.28 * UNITS_PER_METRE;
}
