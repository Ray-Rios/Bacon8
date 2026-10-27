// Fishing (2026-10-26): with a fishing pole in hand, stand at the water's edge facing the water
// and press R to cast. A fish bites a few seconds later (the server keeps the clock:
// BaconWorldWeb.FishingEvents): the bobber is pulled under, and R reels it in, quickly. What you
// catch goes in your bags; any merchant buys it. Old Bram, on the Millpond's east bank, sells the
// poles. The water itself is water.ts; this is the game's side, mixed into the hook like
// game-world.ts.
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { item } from './items';
import { FishingView, WaterView, castSpot, lakeColliders, nearWater, waterNameAt, waterYAt, type WaterLayout } from './water';

const U = UNITS_PER_METRE;
const POLE = 'fishing_pole';

function reply(hook: any, event: string, payload: object, fallback: any = { ok: false }): Promise<any> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(fallback), 5000);
    try {
      hook.pushEvent(event, payload, (res: any) => {
        clearTimeout(timer);
        resolve(res ?? fallback);
      });
    } catch {
      clearTimeout(timer);
      resolve(fallback);
    }
  });
}

const NO_CATCH: Record<string, string> = {
  early: 'You reel in too soon. Nothing was biting.',
  late: 'Too slow! The fish got away.',
  slipped: 'The fish slipped off the hook!',
  moved: 'You wandered off, and your line came in empty.',
  none: 'You reel in an empty line.',
};

export const FishingWorld = {
  /** The water arrived (fetch_mobs): draw it, and keep people out of the lakes. */
  initWater(this: any, layout: WaterLayout) {
    if (!layout || !this.scene) return;
    this.water = layout;
    // the terrain's water (terrain-world.ts sets it again if the terrain loads after this)
    layout.terrain = this.heightfield || null;
    this.waterView?.dispose();
    this.waterView = new WaterView(layout);
    (this.dressing?.group.parent || this.scene).add(this.waterView.group);
    this.fishingView = this.fishingView || new FishingView(this.scene);
  },

  /** The lakes as colliders, for the movement (game-world.ts adds them to the village's). */
  waterColliders(this: any): any[] {
    return this.water ? lakeColliders(this.water) : [];
  },

  holdingPole(this: any): boolean {
    const id = this.state?.currentPlayer?.character_id;
    return !!id && this.characterManager?.getGear(id)?.main === POLE;
  },

  /** Where the rod's end is (where the line hangs), or the hand's height when there is no rod. */
  rodTip(this: any): THREE.Vector3 | null {
    const me = this.localCharacter();
    if (!me) return null;
    let tip: THREE.Object3D | undefined;
    me.mesh.traverse((o: any) => {
      if (!tip && o.name === 'RodTip') tip = o;
    });
    if (tip) return tip.getWorldPosition(new THREE.Vector3());
    return me.mesh.position.clone().add(new THREE.Vector3(0, 1.4 * U, 0));
  },

  /**
   * R: reel in when a line is out; cast when holding a pole by water. Returns false when R
   * should do what it otherwise does (talk to someone).
   */
  fishKey(this: any): boolean {
    if (this.fishing) {
      void this.reelIn();
      return true;
    }
    if (!this.water || !this.holdingPole()) return false;
    const me = this.localCharacter();
    if (!me) return false;
    const p = me.mesh.position;
    const near = nearWater(this.water, p.x, p.z, this.water.bank);
    if (!near) {
      // with a pole in hand away from water, R still talks to people (Old Bram sells poles)
      if (this.npcsView?.nearest(p.x, p.z, 6 * U)) return false;
      this.combatLog("You need to stand at the water's edge to fish.", '#B8B8B8');
      return true;
    }
    const yaw = me.mesh.rotation.y;
    const spot = castSpot(this.water, p.x, p.z, Math.sin(yaw), Math.cos(yaw));
    if (!spot) {
      this.combatLog('Face the water to cast your line.', '#B8B8B8');
      return true;
    }
    void this.castLine(spot);
    return true;
  },

  async castLine(this: any, spot: { x: number; z: number; kind: 'lake' | 'ocean' }) {
    if (this.fishingBusy) return;
    this.fishingBusy = true;
    const res = await reply(this, 'fish_cast', { x: spot.x, z: spot.z });
    this.fishingBusy = false;
    if (!res.ok) {
      this.combatLog(res.error || "You can't fish here.", '#B8B8B8');
      return;
    }
    const me = this.localCharacter();
    if (!me) return;
    this.fishing = { from: me.mesh.position.clone(), kind: spot.kind, bite: false };
    this.characterManager?.getAnimator(this.state.currentPlayer.character_id)?.oneShot('Staff_Bonk', { upperOnly: true });
    const where = res.name || (this.water && waterNameAt(this.water, spot.x, spot.z)) || (spot.kind === 'lake' ? 'the lake' : 'the sea');
    this.combatLog(`You cast your line into ${where}.`, '#9FD8FF');
    // the bobber leaves the rod as the swing comes forward
    setTimeout(() => {
      if (!this.fishing) return;
      const tip = this.rodTip();
      if (tip && this.water) this.fishingView?.cast(tip, spot.x, spot.z, waterYAt(this.water, spot.x, spot.z));
    }, 320);
  },

  /** The server: a fish has taken the bait. */
  onFishBite(this: any) {
    if (!this.fishing) return;
    this.fishing.bite = true;
    this.fishingView?.bite();
    this.audio?.play('sw_drip', 1, 0, 0.7);
    this.combatLog('Something tugs at your line! Press R to reel it in.', '#FFE58A');
    this.gameUI?.announce?.('Something is biting! (R)');
  },

  /** The server: nobody reeled in in time. */
  onFishEscaped(this: any) {
    if (!this.fishing) return;
    this.fishing = null;
    this.fishingView?.reel();
    this.combatLog('The fish took your bait and got away.', '#B8B8B8');
  },

  async reelIn(this: any) {
    if (!this.fishing) return;
    this.fishing = null;
    this.fishingView?.reel();
    const res = await reply(this, 'fish_reel', {}, { ok: false, result: 'none' });
    const name = item(res.item_id)?.name || res.item_id;
    if (res.ok && res.result === 'caught') {
      this.combatLog(`You caught ${/^[aeiou]/i.test(name) ? 'an' : 'a'} ${name}!`, '#9FE39F');
      this.audio?.play('loot', 0.9);
      if (res.inventory) {
        this.inventory = res.inventory;
        this.gameUI?.setInventory(this.inventory);
      }
      const me = this.localCharacter();
      if (me) this.showFloatingDamage?.(me.mesh.position.clone(), name, '#9FE39F', 1.0);
    } else if (res.result === 'full') {
      this.combatLog(`You caught ${name}, but your bags are full; you let it go.`, '#FF9B7A');
    } else {
      this.combatLog(NO_CATCH[res.result] || NO_CATCH.none, '#B8B8B8');
    }
  },

  /** Brings the line in without asking for a catch (moved away, put the pole down, left the world). */
  stopFishing(this: any, say?: string) {
    if (!this.fishing) return;
    this.fishing = null;
    this.fishingView?.reel();
    void reply(this, 'fish_stop', {});
    if (say) this.combatLog(say, '#B8B8B8');
  },

  tickFishing(this: any, dt: number) {
    this.waterView?.tick(dt);
    if (!this.fishingView) return;
    if (this.fishing) {
      const me = this.localCharacter();
      if (!me || this.isDead || !this.holdingPole()) this.stopFishing('You reel in your line.');
      else if (me.mesh.position.distanceTo(this.fishing.from) > 1.2 * U) this.stopFishing('You walk off and reel in your line.');
    }
    const landed = this.fishingView.active && this.fishingView.update(dt, this.rodTip());
    if (landed) this.audio?.play('sw_drip', 0.8);
  },

  teardownFishing(this: any) {
    this.fishing = null;
    this.fishingView?.dispose();
    this.fishingView = null;
    this.waterView?.dispose();
    this.waterView = null;
  },
};
