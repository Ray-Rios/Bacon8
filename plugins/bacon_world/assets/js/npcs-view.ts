// The village's people: merchants (BaconWorld.Merchants), drawn as Bacon8 humans dressed in
// what they wear, standing at their stalls with a name and a title over their heads. A
// right-click (cursor free) on one opens its merchant window (game-world.ts); while you
// trade, the merchant turns to face you.
import * as THREE from '../../../../assets/js/vendor/three';
import { CharacterAnimator } from './anim-driver';
import { UNITS_PER_METRE } from './controls-math';
import type { HumanFactory, HumanInstance } from './human-factory';
import type { Nameplates } from './nameplates';
import type { Gear } from './wardrobe';

const U = UNITS_PER_METRE;
export const NPC_COLOR = '#8FD3FF';

export interface NpcView {
  id: string;
  name: string;
  title?: string;
  /** "trader" (a shop) or "stable" (the stablemaster: stable-ui.ts). */
  kind?: string;
  x: number;
  z: number;
  face_x: number;
  face_z: number;
  appearance: unknown;
  gear: Gear;
}

interface NpcEntry {
  view: NpcView;
  root: THREE.Group;
  human: HumanInstance | null;
  mixer: THREE.AnimationMixer | null;
  animator: CharacterAnimator | null;
  proxy: THREE.Mesh;
  yaw: number;
  wantYaw: number;
}

const PROXY = new THREE.CylinderGeometry(0.4, 0.4, 1.8, 8).translate(0, 0.9, 0);
const PROXY_MAT = new THREE.MeshBasicMaterial({ visible: false });

/** The heading (rotation.y) that faces from (x, z) toward (tx, tz); the humans face +Z. */
export function faceToward(x: number, z: number, tx: number, tz: number): number {
  return Math.atan2(tx - x, tz - z);
}

export class NpcsView {
  readonly group = new THREE.Group();
  /** The ground under (x, z), scene units (terrain-world.ts sets it); null: flat at 0. */
  ground: ((x: number, z: number) => number) | null = null;
  private npcs = new Map<string, NpcEntry>();
  private facing: { id: string; x: number; z: number } | null = null;

  constructor(private humans: HumanFactory | null, private nameplates: Nameplates) {
    this.group.name = 'NPCs';
  }

  /** Replaces the zone's people with these. */
  async setAll(list: NpcView[]) {
    for (const id of [...this.npcs.keys()]) if (!list.some((n) => n.id === id)) this.remove(id);
    await Promise.all(list.map((v) => (this.npcs.has(v.id) ? Promise.resolve() : this.add(v))));
  }

  private async add(v: NpcView) {
    const root = new THREE.Group();
    root.name = `NPC_${v.id}`;
    root.position.set(v.x, 0, v.z);
    const yaw = faceToward(v.x, v.z, v.face_x, v.face_z);
    root.rotation.y = yaw;
    const proxy = new THREE.Mesh(PROXY, PROXY_MAT);
    proxy.scale.setScalar(U);
    proxy.userData.npcId = v.id;
    root.add(proxy);
    const e: NpcEntry = { view: v, root, human: null, mixer: null, animator: null, proxy, yaw, wantYaw: yaw };
    this.npcs.set(v.id, e);
    this.group.add(root);
    if (!this.humans) return;
    try {
      const human = await this.humans.create(v.appearance, 'female', v.gear);
      if (this.npcs.get(v.id) !== e) {
        human.dispose();
        return;
      }
      e.human = human;
      root.add(human.root);
      e.mixer = new THREE.AnimationMixer(human.root);
      e.animator = new CharacterAnimator(human.root, e.mixer, human.clips);
      e.animator.setMotion({ speed: 0, dirX: 0, dirZ: 1, grounded: true });
      void this.humans.loadAnimPacks(human.body).then((clips) => {
        if (this.npcs.get(v.id) === e) e.animator?.addClips(clips);
      });
    } catch (err) {
      console.warn('[npcs] could not build', v.id, err);
    }
  }

  private remove(id: string) {
    const e = this.npcs.get(id);
    if (!e) return;
    e.animator?.dispose();
    e.human?.dispose();
    this.group.remove(e.root);
    this.nameplates.remove(`npc:${id}`);
    this.npcs.delete(id);
  }

  clear() {
    for (const id of [...this.npcs.keys()]) this.remove(id);
  }

  /** While trading, the merchant turns to face the player (null: back to the plaza). */
  faceWhileTrading(id: string | null, x = 0, z = 0) {
    this.facing = id ? { id, x, z } : null;
  }

  update(dt: number, targetId: string | null = null) {
    for (const [id, e] of this.npcs) {
      const f = this.facing && this.facing.id === id ? this.facing : null;
      e.wantYaw = f ? faceToward(e.view.x, e.view.z, f.x, f.z) : faceToward(e.view.x, e.view.z, e.view.face_x, e.view.face_z);
      let d = e.wantYaw - e.yaw;
      d = Math.atan2(Math.sin(d), Math.cos(d));
      e.yaw += d * Math.min(1, dt * 4);
      e.root.rotation.y = e.yaw;
      if (this.ground) e.root.position.y = this.ground(e.root.position.x, e.root.position.z);
      e.animator?.update(dt);
      e.mixer?.update(dt);
      e.human?.postAnimate(dt, e.animator ? e.animator.freeHands() : undefined, e.animator ? e.animator.armSets() : undefined);
      this.nameplates.set(`npc:${id}`, e.root, { name: e.view.name, sub: e.view.title ? `<${e.view.title}>` : undefined, color: NPC_COLOR }, { height: 1.85 * U, target: targetId === id });
    }
  }

  get(id: string): NpcView | undefined {
    return this.npcs.get(id)?.view;
  }

  /** The nearest person within `range` world units of a point, or null. */
  nearest(x: number, z: number, range: number): string | null {
    let best: string | null = null;
    let bd = range;
    for (const [id, e] of this.npcs) {
      const d = Math.hypot(e.view.x - x, e.view.z - z);
      if (d <= bd) {
        bd = d;
        best = id;
      }
    }
    return best;
  }

  /** The person under a ray, or null. */
  pick(raycaster: THREE.Raycaster): string | null {
    const hit = raycaster.intersectObjects([...this.npcs.values()].map((e) => e.proxy), false)[0];
    return (hit?.object.userData.npcId as string) || null;
  }

  /** Circles (world units) players can't walk through. */
  colliders(): Array<{ kind: 'circle'; x: number; z: number; r: number }> {
    return [...this.npcs.values()].map((e) => ({ kind: 'circle' as const, x: e.view.x, z: e.view.z, r: 0.45 * U }));
  }
}
