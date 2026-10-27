// Mounts (BaconWorld.Mounts): dragons and the Kraken you ride, drawn under their riders.
//
// A mount's `model` picks its rig: "dragon" (dragon-view.ts) or "kraken" (kraken-view.ts, it
// swims: the controller gives it `swim_speed` in deep water, and the rig swims there, heaving
// itself along on land). Mounts fight: playMove() shows a move ("claw", "fire", "lash",
// "maelstrom"; game-world.ts sends "mount_attack"), on the rider's screen and everyone's.
//
// The server says who rides what ("mounts_fetch", "mount_summon", the zone presence's
// `mount`, "zone_mount"); this puts the dragon (dragon-view.ts, the boss's model scaled
// down and tinted) under the rider's root, seats the rider on its saddle bone each frame
// and sits them astride (CharacterAnimator.setRiding, HumanInstance.setRiding). The local
// rider's controller gets the mount's speeds (character-controller.ts setMount); a
// dragon flies when its rider does (the controller locally, motion bit 4 for others).
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { DragonFactory, DragonRig, FireBreath, type DragonColors } from './dragon-view';
import { KrakenFactory, KrakenRig, Maelstrom } from './kraken-view';
import type { CharacterModelManager } from './model-manager';

export interface MountSpec {
  id: string;
  name: string;
  summary?: string;
  scale: number;
  ground_speed: number;
  fly_speed: number;
  flies: boolean;
  /** "dragon" (default) or "kraken". */
  model?: string;
  swims?: boolean;
  swim_speed?: number;
  colors?: DragonColors;
  /** The moves on the left and right attack buttons while riding. */
  attacks?: Record<string, { move: string; name: string; reach: number; dly: number }>;
}

type Rig = DragonRig | KrakenRig;

// Each move: its clip on the dragon (or one-shot on the kraken) and when the blow lands (s).
const DRAGON_MOVES: Record<string, { clip: string; hitIn: number }> = { claw: { clip: 'Claw', hitIn: 0.55 }, fire: { clip: 'Breath', hitIn: 1.0 } };
const KRAKEN_MOVES: Record<string, { clip: string; hitIn: number }> = { lash: { clip: 'lash', hitIn: 0.55 }, maelstrom: { clip: 'maelstrom', hitIn: 0.5 } };

// The sitting clip's seat (the pelvis) is this high above the feet: the rider's root goes
// that far below the saddle.
const SEAT_DROP_M = 0.52;

interface Ridden {
  mountId: string;
  rig: Rig | null;
  loading: boolean;
  fire?: FireBreath | null;
  whirl?: Maelstrom | null;
}

export class MountSystem {
  catalog: Record<string, MountSpec> = {};
  owned: string[] = [];
  private riders = new Map<string, Ridden>();
  private dragons = new DragonFactory();
  private krakens = new KrakenFactory();
  /** Where effects go (the scene), and the water's height under a point (the whirlpool). */
  fxParent: THREE.Object3D | null = null;
  surfaceAt: ((x: number, z: number) => number) | null = null;
  private seat = new THREE.Vector3();
  /** A mount's wing beats and footfalls (lobby-audio.ts kinds), from where its rider is. */
  onSound: ((kind: string, at: THREE.Vector3, gain: number, characterId: string) => void) | null = null;

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
    const kraken = spec?.model === 'kraken';
    const rig: Rig | null = kraken ? await this.krakens.create(spec?.scale ?? 0.3) : await this.dragons.create(spec?.scale ?? 0.38, spec?.colors);
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
    // a drake is a third the boss's size: lighter beats and steps
    rig.onCycle = (kind: string, strength: number) =>
      this.onSound?.(kind === 'wing' ? 'wing_flap' : kind === 'stroke' ? 'kraken_stroke' : 'dragon_step', ch.mesh.position, strength * (kind === 'wing' ? 0.55 : 0.35), characterId);
    cm?.getAnimator(characterId)?.setRiding(true);
    cm?.getHuman(characterId)?.setRiding(true);
  }

  private clear(characterId: string) {
    const r = this.riders.get(characterId);
    this.riders.delete(characterId);
    r?.rig?.dispose();
    r?.fire?.dispose();
    r?.whirl?.dispose();
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

  /**
   * A mount's move (BaconWorld.Mounts `attacks`): the rig plays it, with its fire or its
   * whirlpool. Returns when the blow lands (seconds), or null if `characterId` rides nothing.
   */
  playMove(characterId: string, move: string): number | null {
    const r = this.riders.get(characterId);
    const rig = r?.rig;
    if (!r || !rig) return null;
    const U = UNITS_PER_METRE;
    if (rig instanceof KrakenRig) {
      const m = KRAKEN_MOVES[move] ?? KRAKEN_MOVES.lash;
      const d = rig.play(m.clip);
      if (move === 'maelstrom' && this.fxParent) {
        if (!r.whirl) {
          const root = rig.root;
          r.whirl = new Maelstrom(this.fxParent, root, 7.5 * U, () => {
            const p = root.getWorldPosition(new THREE.Vector3());
            return this.surfaceAt ? this.surfaceAt(p.x, p.z) : p.y;
          });
        }
        r.whirl.start(d + 0.6);
      }
      this.onSound?.(move === 'maelstrom' ? 'kraken_roar' : 'kraken_growl', rig.root.getWorldPosition(new THREE.Vector3()), 0.7, characterId);
      return m.hitIn;
    }
    const m = DRAGON_MOVES[move] ?? DRAGON_MOVES.claw;
    rig.play(m.clip, { rate: move === 'fire' ? 1.3 : 1.15 });
    if (move === 'fire' && this.fxParent) {
      const head = rig.model.getObjectByName('head');
      if (!r.fire && rig.mouth && head) r.fire = new FireBreath(this.fxParent, rig.mouth, head, 10 * U, 1.2 * U);
      setTimeout(() => r.fire?.start(1.1), 600);
      this.onSound?.('dragon_breath', rig.root.getWorldPosition(new THREE.Vector3()), 0.6, characterId);
    } else {
      this.onSound?.('dragon_growl', rig.root.getWorldPosition(new THREE.Vector3()), 0.45, characterId);
    }
    return m.hitIn / (move === 'fire' ? 1.3 : 1.15);
  }

  /** Per frame, after the characters moved: mounts animate, riders sit on them. `deep` says
   * whether a point is deep water (a kraken swims there). */
  update(dt: number, flying: (characterId: string) => boolean, deep?: (x: number, z: number) => boolean) {
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
      if (rig instanceof KrakenRig) rig.inWater = !!deep?.(ch.mesh.position.x, ch.mesh.position.z);
      rig.update(dt);
      r.fire?.update(dt);
      r.whirl?.update(dt);
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
