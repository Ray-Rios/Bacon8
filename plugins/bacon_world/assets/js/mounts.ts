// Mounts (BaconWorld.Mounts): dragons you ride, drawn under their riders.
//
// The server says who rides what ("mounts_fetch", "mount_summon", the zone presence's
// `mount`, "zone_mount"); this puts the dragon (dragon-view.ts, the boss's model scaled
// down and tinted) under the rider's root, seats the rider on its saddle bone each frame
// and sits them astride (CharacterAnimator.setRiding, HumanInstance.setRiding). The local
// rider's controller gets the mount's speeds (character-controller.ts setMount); a
// dragon flies when its rider does (the controller locally, motion bit 4 for others).
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { DragonFactory, DragonRig, type DragonColors } from './dragon-view';
import type { CharacterModelManager } from './model-manager';

export interface MountSpec {
  id: string;
  name: string;
  summary?: string;
  scale: number;
  ground_speed: number;
  fly_speed: number;
  flies: boolean;
  colors?: DragonColors;
}

// The sitting clip's seat (the pelvis) is this high above the feet: the rider's root goes
// that far below the saddle.
const SEAT_DROP_M = 0.52;

interface Ridden {
  mountId: string;
  rig: DragonRig | null;
  loading: boolean;
}

export class MountSystem {
  catalog: Record<string, MountSpec> = {};
  owned: string[] = [];
  private riders = new Map<string, Ridden>();
  private dragons = new DragonFactory();
  private seat = new THREE.Vector3();

  constructor(private characters: () => CharacterModelManager | null) {}

  setCatalog(catalog: Record<string, MountSpec> | null | undefined, owned?: string[]) {
    if (catalog) this.catalog = catalog;
    if (owned) this.owned = owned;
  }

  mountOf(characterId: string): string | null {
    return this.riders.get(characterId)?.mountId ?? null;
  }

  spec(id: string | null | undefined): MountSpec | null {
    return (id && this.catalog[id]) || null;
  }

  /** Puts `characterId` on `mountId` (null: off). Safe to call again with the same value. */
  async set(characterId: string, mountId: string | null): Promise<void> {
    const cur = this.riders.get(characterId);
    if ((cur?.mountId ?? null) === mountId) return;
    if (cur) this.clear(characterId);
    if (!mountId) return;
    const spec = this.spec(mountId);
    const entry: Ridden = { mountId, rig: null, loading: true };
    this.riders.set(characterId, entry);
    const rig = await this.dragons.create(spec?.scale ?? 0.38, spec?.colors);
    if (this.riders.get(characterId) !== entry) {
      rig?.dispose();
      return;
    }
    entry.rig = rig;
    entry.loading = false;
    const cm = this.characters();
    const ch = cm?.getAllCharacters().get(characterId);
    if (!rig || !ch) return;
    ch.mesh.add(rig.root);
    cm?.getAnimator(characterId)?.setRiding(true);
    cm?.getHuman(characterId)?.setRiding(true);
  }

  private clear(characterId: string) {
    const r = this.riders.get(characterId);
    this.riders.delete(characterId);
    r?.rig?.dispose();
    const cm = this.characters();
    cm?.getAnimator(characterId)?.setRiding(false);
    const h = cm?.getHuman(characterId);
    h?.setRiding(false);
    h?.setSeat(null);
  }

  /** A character left: drop its mount. */
  forget(characterId: string) {
    if (this.riders.has(characterId)) this.clear(characterId);
  }

  /** The rider's head height above their feet (scene units), for the camera. */
  pivotFor(mountId: string): number {
    const s = this.spec(mountId)?.scale ?? 0.38;
    return (5.0 * s + 1.25) * UNITS_PER_METRE;
  }

  /** Per frame, after the characters moved: dragons animate, riders sit on them. */
  update(dt: number, flying: (characterId: string) => boolean) {
    const cm = this.characters();
    for (const [id, r] of this.riders) {
      const rig = r.rig;
      if (!rig) continue;
      const ch = cm?.getAllCharacters().get(id);
      if (!ch) {
        this.clear(id);
        continue;
      }
      if (rig.root.parent !== ch.mesh) ch.mesh.add(rig.root);
      // a human's root is scaled to its height: the dragon keeps its own size
      const k = ch.mesh.scale.x || 1;
      rig.root.scale.setScalar(1 / k);
      rig.flying = flying(id);
      rig.update(dt);
      const human = cm?.getHuman(id);
      if (human && rig.saddle) {
        rig.saddle.getWorldPosition(this.seat);
        this.seat.y -= SEAT_DROP_M * UNITS_PER_METRE;
        ch.mesh.worldToLocal(this.seat);
        human.setSeat(this.seat);
      }
    }
  }

  clearAll() {
    for (const id of [...this.riders.keys()]) this.clear(id);
  }
}
