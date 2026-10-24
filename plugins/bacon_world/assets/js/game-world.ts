// The game half of the world hook (world-character-ui-scene.ts spreads these methods
// into WorldCharacterUIScene, so `this` is the hook): fighting with either hand,
// creatures, looting, the inventory, levels, the EverQuest-style windows and the
// combat log, and the sounds that go with them.
//
// Swings are Black Desert style: with mouse-look on, the left button swings the left
// hand and the right button the right (a two-hander: quick and heavy); held, they
// keep swinging as the weapon's delay allows. The animation plays at once; the
// server (BaconWorldWeb.GameEvents) decides what was hit and replies. Everyone
// else sees the swing ("zone_swing"); a swing at a player flagged for PvP (both
// flagged) lands as "pvp_hit", and anyone's health changes arrive as "zone_hp".
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { GameUI } from './game-ui';
import { item, money, moneyWords, setCatalog } from './items';
import { MobsView, type MobEntry, type MobEvent } from './mobs-view';
import { conColor, playerColor } from './nameplates';
import { NpcsView, NPC_COLOR } from './npcs-view';
import { gearKey, type Gear } from './wardrobe';
import { WorldDressing } from './world-dressing';

const U = UNITS_PER_METRE;
const LOOT_RANGE = 4.2 * U; // a little inside the server's 4.5 m
const TRADE_RANGE = 5.6 * U; // a little inside BaconWorld.Merchants.reach/0 (6 m)
const FIST = { dmg: 3, dly: 9 };

type Hand = 'left' | 'right';

function reply(hook: any, event: string, payload: any, fallback: any = { ok: false }): Promise<any> {
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

export const GameWorld = {
  // ---------------------------------------------------------------- set up

  /** The windows (player, target, hotbar, inventory, loot), in the overlay layer. */
  initGameUI(this: any, layer: HTMLElement) {
    try {
      setCatalog(JSON.parse(this.el.dataset.itemCatalog || '{}'));
    } catch {
      setCatalog({});
    }
    this.gameUI = new GameUI(layer, {
      move: (from: string, to: string) => void this.inventoryAction('inventory_move', { from, to }),
      equip: (slot: string) => void this.inventoryAction('inventory_equip', { slot }),
      unequip: (slot: string) => void this.inventoryAction('inventory_unequip', { slot }),
      destroy: (slot: string) => void this.inventoryAction('inventory_destroy', { slot }),
      lootTake: (index: number) => void this.lootTake(index),
      lootAll: () => void this.lootAll(),
      lootClose: () => this.closeLoot(),
      buy: (itemId: string) => void this.merchantBuy(itemId),
      sell: (slot: string) => void this.merchantSell(slot),
      merchantClose: () => this.endTrade(),
      cast: (slug: string) => this.castSpell(slug),
      pvp: () => (this.pushEvent('toggle_pvp', {}) as any)?.catch?.(() => {}),
      sound: () => {
        this.audio?.toggle();
        this.updateHUD();
      },
      windows: (open: boolean) => {
        if (open) this.controller?.releasePointerLock();
        if (open) this.audio?.play('bag_open', 0.5);
      },
    });
  },

  /** Entering the world: creatures, what we carry and hold, our level. */
  initGame(this: any) {
    const cp = this.state?.currentPlayer;
    if (!cp || !this.scene || !this.nameplates) return;
    this.progress = cp.progress || { level: cp.level || 1, xp: 0, xp_next: 100 };
    this.inventory = cp.inventory || { items: [], coins: 0, bag_slots: 24 };
    this.gameUI?.setInventory(this.inventory);
    this.applyLocalGear(cp.gear || {});
    this.nextSwing = { left: 0, right: 0, both: 0 };
    this.lootingId = null;
    if (this.audio) this.audio.voice = cp.appearance?.body === 'female' ? 'f' : 'm';
    this.audio?.setAmbience(true);
    if (!this.npcsView) {
      this.npcsView = new NpcsView(this.humanFactory, this.nameplates);
      this.scene.add(this.npcsView.group);
    }
    if (!this.mobsView) {
      this.mobsView = new MobsView(this.humanFactory, this.characterManager.weapons, this.nameplates, () => ({
        id: this.state?.currentPlayer?.character_id ?? null,
        level: this.progress?.level ?? 1,
        targetId: this.targetId,
      }));
      this.mobsView.onEvent = (e: MobEvent, m: MobEntry | undefined) => this.onMobEvent(e, m);
      this.mobsView.onSwingLanded = (e: MobEvent, m: MobEntry) => this.onMobSwingLanded(e, m);
      this.scene.add(this.mobsView.group);
    }
    void reply(this, 'fetch_mobs', {}, { mobs: [], camps: [], merchants: [] }).then((res: any) => {
      if (!this.mobsView) return;
      this.mobsView.setAll(res.mobs || []);
      this.camps = res.camps || [];
      const people = () => [...(this.dressing ? this.dressing.colliders() : this.worldColliders.filter((c: any) => !c.npc)), ...(this.npcsView?.colliders() || []).map((c: any) => ({ ...c, npc: true }))];
      void this.npcsView?.setAll(res.merchants || []).then(() => (this.worldColliders = people()));
      if (this.dressing && this.camps.length) void this.dressing.addCamps(this.camps).then(() => {
        if (this.dressing) this.worldColliders = people();
      });
    });
    this.updateHUD();
  },

  teardownGame(this: any) {
    if (this.lootingId) this.closeLoot();
    this.gameUI?.closeMerchant(false);
    this.tradingWith = null;
    this.mobsView?.clear();
    if (this.mobsView && this.scene) this.scene.remove(this.mobsView.group);
    this.mobsView = null;
    this.npcsView?.clear();
    if (this.npcsView && this.scene) this.scene.remove(this.npcsView.group);
    this.npcsView = null;
    this.audio?.setAmbience(false);
  },

  // ---------------------------------------------------------------- per frame

  tickGame(this: any, dt: number) {
    this.mobsView?.update(dt);
    this.npcsView?.update(dt, this.targetId);
    const me = this.localCharacter();
    if (!me) return;
    // Walking away from a merchant ends the trade.
    if (this.tradingWith) {
      const n = this.npcsView?.get(this.tradingWith);
      if (!n || Math.hypot(me.mesh.position.x - n.x, me.mesh.position.z - n.z) > TRADE_RANGE * 1.15) this.gameUI?.closeMerchant();
      else this.npcsView?.faceWhileTrading(this.tradingWith, me.mesh.position.x, me.mesh.position.z);
    }
    // Held mouse buttons keep swinging when the hand is ready.
    if (this.controller && !this.isDead) {
      const now = performance.now();
      for (const hand of ['left', 'right'] as Hand[]) {
        if (this.controller.isAttackHeld(hand) && now >= this.swingReadyAt(hand)) this.meleeAttack(hand);
      }
    }
    // Walking away from a corpse closes the loot window.
    if (this.lootingId) {
      const m = this.mobsView?.get(this.lootingId);
      if (!m || m.sink >= 0 || me.mesh.position.distanceTo(m.root.position) > LOOT_RANGE * 1.4) this.closeLoot();
    }
    // The target window follows its creature's health.
    this.refreshTargetSoon = (this.refreshTargetSoon || 0) - dt;
    if (this.refreshTargetSoon <= 0) {
      this.refreshTargetSoon = 0.25;
      this.refreshTarget();
      // Nature: campfire nearby, day or night.
      if (this.audio && this.ambientLight) {
        const p = me.mesh.position;
        const fire = Math.hypot(p.x - 22 * U, p.z + 2 * U);
        this.audio.setCampfire(1 - Math.min(1, fire / (14 * U)));
        this.audio.setDaylight((this.ambientLight.intensity - 0.04) / 0.81);
      }
    }
  },

  localCharacter(this: any) {
    const id = this.state?.currentPlayer?.character_id;
    return id ? this.characterManager?.getAllCharacters().get(id) : null;
  },

  // ---------------------------------------------------------------- swinging

  // What each hand holds, and how fast it swings.
  handItem(this: any, hand: Hand) {
    const gear = this.localGear || { main: null, off: null };
    const main = item(gear.main);
    if (main?.hands === 2) return { id: gear.main, def: main, two: true };
    const id = hand === 'right' ? gear.main : gear.off;
    return { id, def: item(id), two: false };
  },

  swingReadyAt(this: any, hand: Hand): number {
    const h = this.handItem(hand);
    return h.two ? this.nextSwing?.both || 0 : this.nextSwing?.[hand] || 0;
  },

  meleeAttack(this: any, hand: Hand) {
    if (this.isDead || !this.controller || !this.state?.currentPlayer) return;
    const myId = this.state.currentPlayer.character_id;
    const now = performance.now();
    if (now < this.swingReadyAt(hand)) return;
    const h = this.handItem(hand);
    const heavy = h.two && hand === 'right';
    const dly = (h.def?.dly ?? FIST.dly) * 100 * (heavy ? 1.4 : 1);
    if (h.two) this.nextSwing.both = now + dly;
    else this.nextSwing[hand] = now + dly;
    this.gameUI?.cooldown(h.two ? 'left' : hand, dly);
    if (h.two) this.gameUI?.cooldown('right', dly);

    // A swing goes where you look.
    this.controller.faceCamera(1400);
    const animator = this.characterManager?.getAnimator(myId);
    const info = animator?.attack(hand, heavy, dly / 1000);
    const hitIn = (info?.hitIn ?? 0.25) * 1000;
    setTimeout(() => this.audio?.play('swing', heavy ? 1 : 0.8, 0, heavy ? 0.85 : 1), Math.max(0, hitIn - 120));
    if (Math.random() < (heavy ? 0.8 : 0.35)) this.audio?.say('attack', 0.55);
    // PvP numbers (broadcast to the zone, ours included) show at the impact too.
    this.pvpShowAt = now + hitIn - 40;

    const target = this.targetId && (this.mobsView?.get(this.targetId) || this.isOtherPlayer(this.targetId)) ? this.targetId : null;
    void reply(this, 'melee_attack', { hand, heading: this.controller.getYaw(), heavy, target_id: target }).then((res: any) => {
      if (!res?.ok) return;
      setTimeout(() => this.showHits(res.hits || []), Math.max(0, hitIn - 40));
      if (res.progress) this.applyProgress(res.progress);
    });
  },

  isOtherPlayer(this: any, id: string): boolean {
    return id !== this.state?.currentPlayer?.character_id && !!this.characterManager?.getAllCharacters().get(id);
  },

  // Someone else swung: their arm moves on our screen too.
  onRemoteSwing(this: any, p: any) {
    if (!p?.character_id || p.character_id === this.state?.currentPlayer?.character_id) return;
    const animator = this.characterManager?.getAnimator(p.character_id);
    const info = animator?.attack(p.hand === 'left' ? 'left' : 'right', !!p.heavy, (p.delay_ms || 900) / 1000);
    if (!info) return;
    const d = this.distanceToCharacter(p.character_id);
    setTimeout(() => this.audio?.play('swing', p.heavy ? 0.9 : 0.7, d, p.heavy ? 0.85 : 1), Math.max(0, info.hitIn * 1000 - 120));
  },

  // A PvP swing landed or missed (the target's LiveView already applied the damage).
  onPvpHit(this: any, h: any) {
    if (!h?.target_id) return;
    const myId = this.state?.currentPlayer?.character_id;
    const mine = h.attacker_id === myId;
    const onMe = h.target_id === myId;
    const delay = mine ? Math.max(0, (this.pvpShowAt || 0) - performance.now()) : 200;
    setTimeout(() => {
      const target = this.characterManager?.getAllCharacters().get(h.target_id);
      const d = this.distanceToCharacter(h.target_id);
      if (h.hit) {
        if (target && (mine || onMe)) {
          const color = onMe ? '#FF6A5A' : h.crit ? '#FFD84A' : '#FFFFFF';
          this.showFloatingDamage(target.mesh.position.clone(), String(h.damage), color, h.crit ? 1.35 : 1);
        }
        this.audio?.play('hit_bone', 0.9, d);
        if (onMe) {
          this.characterManager?.getAnimator(myId)?.hit();
          this.audio?.say('hurt', 0.8);
          this.combatLog(`${h.attacker_name || 'Someone'} hits YOU for ${h.damage} points of damage.`, '#FF8A7A');
        } else {
          this.characterManager?.getAnimator(h.target_id)?.hit();
          if (mine) this.combatLog(h.crit ? `You score a critical hit! (${h.damage})` : `You hit ${h.target_name || 'them'} for ${h.damage} points of damage.`, h.crit ? '#FFD84A' : '#E8E8E8');
        }
      } else if (mine) {
        if (target) this.showFloatingDamage(target.mesh.position.clone(), 'miss', '#A0A0A0', 0.85);
        this.combatLog(`You try to hit ${h.target_name || 'them'}, but miss!`, '#A0A0A0');
      } else if (onMe) {
        this.combatLog(`${h.attacker_name || 'Someone'} tries to hit YOU, but misses!`, '#A0A0A0');
      }
    }, delay);
  },

  // Someone's health changed: the target window follows it; a death and a respawn show.
  onZoneHp(this: any, p: any) {
    if (!p?.character_id) return;
    const myId = this.state?.currentPlayer?.character_id;
    const list = this.state?.onlineCharacters;
    const i = list ? list.findIndex((c: any) => c.character_id === p.character_id) : -1;
    if (i >= 0) list[i] = { ...list[i], hp: p.hp, max_hp: p.max_hp, dead: p.state === 'dead' };
    if (p.character_id !== myId) {
      if (p.state === 'dead') {
        this.characterManager?.playCharacterAnimation(p.character_id, 'death', false);
        const body = (this.appearanceCache?.get(p.character_id) as any)?.body;
        this.audio?.say('death', 0.7, this.distanceToCharacter(p.character_id), body === 'female' ? 'f' : 'm');
        if (p.character_id === this.targetId) {
          const name = list?.[i]?.character_name || 'Your target';
          this.combatLog(`${name} has been slain!`, '#FFE58A');
        }
      } else if (p.state === 'alive') {
        this.characterManager?.playCharacterAnimation(p.character_id, 'idle');
      }
    }
    if (p.character_id === this.targetId) this.refreshTarget();
  },

  // Our swing landed: numbers over the creatures, sounds, the combat log.
  showHits(this: any, hits: any[]) {
    for (const hit of hits) {
      const m = this.mobsView?.get(hit.id);
      if (!m) continue;
      const pos = m.root.position.clone();
      if (hit.hit) {
        this.showFloatingDamage(pos, String(hit.damage), hit.crit ? '#FFD84A' : '#FFFFFF', hit.crit ? 1.35 : 1);
        this.audio?.play('hit_bone', 0.9);
        this.combatLog(hit.crit ? `You score a critical hit! (${hit.damage})` : `You hit ${m.view.name} for ${hit.damage} points of damage.`, hit.crit ? '#FFD84A' : '#E8E8E8');
      } else {
        this.showFloatingDamage(pos, 'miss', '#A0A0A0', 0.85);
        this.combatLog(`You try to hit ${m.view.name}, but miss!`, '#A0A0A0');
      }
      if (hit.killed) {
        this.audio?.play('bone_break', 1);
        setTimeout(() => this.audio?.play('bone_collapse', 0.8), 260);
        this.combatLog(`You have slain ${m.view.name}!`, '#FFE58A');
      }
      // Hitting something you hadn't targeted targets it.
      if (!this.targetId || !this.mobsView?.get(this.targetId) || this.mobsView.get(this.targetId)?.view.state === 'dead') {
        if (!hit.killed) this.setTarget(hit.id);
      }
    }
    this.refreshTarget();
  },

  applyProgress(this: any, p: any) {
    const before = this.progress?.level ?? 1;
    this.progress = { ...this.progress, ...p };
    if (p.gained > 0) this.combatLog(p.levels_gained > 0 ? 'You gain experience!!' : 'You gain experience!', '#E8D27A');
    if ((p.levels_gained ?? 0) > 0 || (p.level ?? before) > before) {
      this.gameUI?.announce(`You have gained a level! Welcome to level ${p.level}!`);
      this.combatLog(`You have gained a level! Welcome to level ${p.level}!`, '#FFE58A');
      if (p.skill_points) this.combatLog(`You have ${p.skill_points} skill point${p.skill_points === 1 ? '' : 's'} to spend when the skill tree opens.`, '#C8B67A');
      this.audio?.play('level_up', 1);
      const cp = this.state?.currentPlayer;
      if (cp) {
        cp.max_hp = p.max_hp;
        cp.hp = p.max_hp;
        cp.max_mp = p.max_mp;
        cp.mp = p.max_mp;
        cp.level = p.level;
      }
    }
    this.updateHUD();
  },

  // ---------------------------------------------------------------- creatures

  onMobEvent(this: any, e: MobEvent, m: MobEntry | undefined) {
    const myId = this.state?.currentPlayer?.character_id;
    const me = this.localCharacter();
    const dist = m && me ? me.mesh.position.distanceTo(m.root.position) : 0;
    switch (e.t) {
      case 'damaged':
        // Others' hits on a creature: just the sound, if near.
        if (e.by !== myId && (e.damage ?? 0) > 0) this.audio?.play('hit_bone', 0.7, dist);
        break;
      case 'died':
        if (e.killer !== myId) {
          this.audio?.play('bone_break', 0.8, dist);
          setTimeout(() => this.audio?.play('bone_collapse', 0.6, dist), 260);
        }
        break;
      case 'aggro':
        if (e.target === myId && m) this.combatLog(`${capital(m.view.name)} notices you!`, '#FF9B7A');
        break;
    }
    if (e.id && e.id === this.targetId) this.refreshTarget();
  },

  // A creature's swing reached its impact frame.
  onMobSwingLanded(this: any, e: MobEvent, m: MobEntry) {
    const myId = this.state?.currentPlayer?.character_id;
    const me = this.localCharacter();
    if (e.target === myId && me) {
      if (e.hit) {
        this.showFloatingDamage(me.mesh.position.clone(), String(e.damage), '#FF5A4A', 1.1);
        this.combatLog(`${capital(m.view.name)} hits YOU for ${e.damage} points of damage.`, '#FF7A6A');
        this.audio?.play('hit_flesh', 1);
        if (Math.random() < 0.7) setTimeout(() => this.audio?.say('hurt', 0.75), 60);
        this.characterManager?.getAnimator(myId)?.hit();
      } else {
        this.combatLog(`${capital(m.view.name)} tries to hit YOU, but misses!`, '#B8B8B8');
        this.audio?.play('swing', 0.6);
      }
    } else {
      const victim = e.target ? this.characterManager?.getAllCharacters().get(e.target) : null;
      const d = me && victim ? me.mesh.position.distanceTo(victim.mesh.position) : 30;
      this.audio?.play(e.hit ? 'hit_flesh' : 'swing', 0.7, d);
      if (e.hit && e.target) this.characterManager?.getAnimator(e.target)?.hit();
    }
  },

  // ---------------------------------------------------------------- targeting

  /** Targets a character or a creature (null clears). */
  setTarget(this: any, id: string | null) {
    this.targetId = id;
    this.refreshTarget();
  },

  refreshTarget(this: any) {
    const id = this.targetId;
    if (!id || !this.gameUI) {
      this.gameUI?.setTarget(null);
      return;
    }
    const npc = this.npcsView?.get(id);
    if (npc) {
      this.gameUI.setTarget({ kind: 'npc', name: npc.name, sub: npc.title ? `<${npc.title}>` : undefined, color: NPC_COLOR, hpPct: 100 });
      return;
    }
    const m = this.mobsView?.get(id);
    if (m) {
      const lvl = this.progress?.level ?? 1;
      const dead = m.view.state === 'dead';
      this.gameUI.setTarget({
        kind: 'mob',
        name: m.view.name,
        color: dead ? '#B9B2A6' : conColor(m.view.level - lvl, lvl),
        level: m.view.level,
        hpPct: m.view.max_hp ? (m.view.hp / m.view.max_hp) * 100 : 0,
        corpse: dead,
      });
      return;
    }
    const p = this.state?.onlineCharacters?.find((c: any) => c.character_id === id);
    if (!p) {
      this.gameUI.setTarget(null);
      return;
    }
    this.gameUI.setTarget({
      kind: 'player',
      name: p.character_name || 'Player',
      color: playerColor(p.pvp === true),
      level: p.level,
      hpPct: p.max_hp ? (p.hp / p.max_hp) * 100 : 100,
    });
  },

  /** Tab: the nearest creatures first, then players. */
  tabCycleTarget(this: any) {
    const me = this.localCharacter();
    if (!me) return;
    const p = me.mesh.position;
    const ids: string[] = (this.mobsView?.living(p.x, p.z, 40 * U) || []).map((e: MobEntry) => e.view.id);
    for (const c of this.state?.onlineCharacters || []) {
      if (c.character_id !== this.state?.currentPlayer?.character_id) ids.push(c.character_id);
    }
    if (!ids.length) {
      this.setTarget(null);
      return;
    }
    const i = ids.indexOf(this.targetId);
    this.setTarget(ids[(i + 1) % ids.length]);
  },

  /** The creature under a ray (or null). */
  pickMob(this: any, raycaster: THREE.Raycaster): string | null {
    return this.mobsView?.pick(raycaster) ?? null;
  },

  /** The villager (merchant) under a ray (or null). */
  pickNpc(this: any, raycaster: THREE.Raycaster): string | null {
    return this.npcsView?.pick(raycaster) ?? null;
  },

  /**
   * R: interact. The targeted person if they're in reach, else the nearest one; a merchant
   * opens their wares. (Doors and other things you use will hang off this key too.)
   */
  interact(this: any) {
    const me = this.localCharacter();
    if (!me || this.isDead) return;
    const p = me.mesh.position;
    let id: string | null = this.targetId && this.npcsView?.get(this.targetId) ? this.targetId : null;
    if (id) {
      const n = this.npcsView.get(id);
      if (Math.hypot(p.x - n.x, p.z - n.z) > TRADE_RANGE) id = null;
    }
    id = id || this.npcsView?.nearest(p.x, p.z, TRADE_RANGE) || null;
    if (!id) {
      this.combatLog('There is no one close enough to talk to.', '#B8B8B8');
      return;
    }
    if (this.tradingWith === id) {
      this.gameUI?.closeMerchant();
      return;
    }
    this.setTarget(id);
    void this.openMerchant(id);
  },

  // ---------------------------------------------------------------- merchants

  /** Opens a merchant (EverQuest: right-click them). */
  async openMerchant(this: any, npcId: string) {
    const n = this.npcsView?.get(npcId);
    const me = this.localCharacter();
    if (!n || !me || this.isDead) return;
    if (Math.hypot(me.mesh.position.x - n.x, me.mesh.position.z - n.z) > TRADE_RANGE) {
      this.combatLog(`You are too far away to trade with ${n.name}.`, '#B8B8B8');
      return;
    }
    const res = await reply(this, 'merchant_open', { id: npcId });
    if (!res.ok) {
      this.combatLog(res.error || "They won't trade with you right now.", '#B8B8B8');
      return;
    }
    this.tradingWith = npcId;
    if (this.lootingId) this.closeLoot();
    this.combatLog(`${n.name} says, 'Welcome, ${this.state?.currentPlayer?.name || 'traveller'}! Have a look around.'`, '#8FD3FF');
    this.gameUI?.openMerchant(res.merchant, res.stock || []);
    this.audio?.play('bag_open', 0.5);
  },

  async merchantBuy(this: any, itemId: string) {
    if (!this.tradingWith) return;
    const res = await reply(this, 'merchant_buy', { id: this.tradingWith, item_id: itemId });
    if (res.inventory) {
      this.inventory = res.inventory;
      this.gameUI?.setInventory(this.inventory);
    }
    if (!res.ok) {
      this.combatLog(res.error || "You can't buy that.", '#FF9B7A');
      return;
    }
    this.combatLog(`You give ${moneyWords(res.price)} to ${this.npcsView?.get(this.tradingWith)?.name || 'the merchant'}.`, '#F0D77A');
    this.combatLog(`You receive ${item(res.bought)?.name || res.bought}.`, '#9FE39F');
    this.audio?.play('coins', 0.8);
  },

  async merchantSell(this: any, slot: string) {
    if (!this.tradingWith) return;
    const res = await reply(this, 'merchant_sell', { id: this.tradingWith, slot });
    if (res.inventory) {
      this.inventory = res.inventory;
      this.gameUI?.setInventory(this.inventory);
    }
    if (!res.ok) {
      this.combatLog(res.error || "You can't sell that.", '#FF9B7A');
      return;
    }
    this.combatLog(`You receive ${moneyWords(res.price)} for ${res.quantity > 1 ? `${res.quantity} ` : 'the '}${item(res.sold)?.name || res.sold}.`, '#F0D77A');
    this.audio?.play('coins', 0.8);
  },

  endTrade(this: any) {
    this.tradingWith = null;
    this.npcsView?.faceWhileTrading(null);
  },

  // ---------------------------------------------------------------- looting

  /** Opens a corpse (EverQuest: right-click it, or press G near one). */
  async openLoot(this: any, mobId: string) {
    const m = this.mobsView?.get(mobId);
    const me = this.localCharacter();
    if (!m || !me || this.isDead) return;
    if (me.mesh.position.distanceTo(m.root.position) > LOOT_RANGE) {
      this.combatLog('You are too far away to loot that corpse.', '#B8B8B8');
      return;
    }
    if (this.lootingId && this.lootingId !== mobId) this.closeLoot();
    const res = await reply(this, 'loot_open', { mob_id: mobId });
    if (!res.ok) {
      this.combatLog(res.error || "You can't loot that.", '#B8B8B8');
      return;
    }
    this.lootingId = mobId;
    this.characterManager?.getAnimator(this.state.currentPlayer.character_id)?.oneShot('PickUp_Table', { upperOnly: true });
    if (res.coins > 0) {
      this.combatLog(`You receive ${moneyWords(res.coins)} from the corpse.`, '#F0D77A');
      this.audio?.play('coins', 0.9);
      if (this.inventory) {
        this.inventory = { ...this.inventory, coins: res.total_coins };
        this.gameUI?.setInventory(this.inventory);
      }
    }
    this.gameUI?.openLoot(`${m.view.name}'s corpse`, res.items || []);
  },

  async lootTake(this: any, index: number) {
    if (!this.lootingId) return;
    const res = await reply(this, 'loot_take', { mob_id: this.lootingId, index });
    this.afterLoot(res);
  },

  async lootAll(this: any) {
    if (!this.lootingId) return;
    const res = await reply(this, 'loot_all', { mob_id: this.lootingId });
    this.afterLoot(res);
  },

  afterLoot(this: any, res: any) {
    for (const it of res.taken || []) {
      const name = item(it.item_id)?.name || it.item_id;
      this.combatLog(`--You have looted ${it.quantity > 1 ? `${it.quantity} ` : 'a '}${name}.--`, '#9FE39F');
    }
    if ((res.taken || []).length) this.audio?.play('loot', 0.8);
    if (res.error) this.combatLog(res.error, '#FF9B7A');
    if (res.inventory) {
      this.inventory = res.inventory;
      this.gameUI?.setInventory(this.inventory);
    }
    if (res.items) {
      if (res.items.length === 0 && !res.error) this.closeLoot();
      else this.gameUI?.updateLoot(res.items);
    }
  },

  closeLoot(this: any) {
    const id = this.lootingId;
    this.lootingId = null;
    this.gameUI?.closeLoot(false);
    if (id) void reply(this, 'loot_close', { mob_id: id });
  },

  lootNearest(this: any) {
    const me = this.localCharacter();
    const c = me ? this.mobsView?.nearestCorpse(me.mesh.position.x, me.mesh.position.z, LOOT_RANGE) : null;
    if (c) void this.openLoot(c.view.id);
    else this.combatLog('There is no corpse close enough to loot.', '#B8B8B8');
  },

  // ---------------------------------------------------------------- inventory and gear

  async inventoryAction(this: any, event: string, payload: any) {
    const res = await reply(this, event, payload);
    if (res.inventory) {
      this.inventory = res.inventory;
      this.gameUI?.setInventory(this.inventory);
    }
    if (!res.ok && res.error) this.combatLog(res.error, '#FF9B7A');
    if (res.ok && res.gear) {
      const before = this.localGear || {};
      this.applyLocalGear(res.gear);
      const hands = before.main !== res.gear.main || before.off !== res.gear.off;
      if (gearKey(before) !== gearKey(res.gear)) this.audio?.play(hands && (res.gear.main || res.gear.off) ? 'draw' : 'equip', 0.7);
    } else if (res.ok) {
      this.audio?.play('click', 0.5);
    }
  },

  /** What we hold and wear: the models, the stance, the clothes, the hotbar. */
  applyLocalGear(this: any, gear: Gear) {
    const myId = this.state?.currentPlayer?.character_id;
    this.localGear = { ...gear, main: gear.main ?? null, off: gear.off ?? null };
    if (myId) void this.characterManager?.setGear(myId, this.localGear);
    this.gameUI?.setHands(this.localGear.off, this.localGear.main);
  },

  /** Other players' weapons and clothes, from presence or a zone_gear push. */
  applyRemoteGear(this: any, id: string, gear: any) {
    if (!gear || id === this.state?.currentPlayer?.character_id || !this.characterManager?.getAllCharacters().has(id)) return;
    if (gearKey(this.characterManager.getGear(id)) === gearKey(gear)) return;
    void this.characterManager.setGear(id, gear);
  },

  // ---------------------------------------------------------------- HUD

  updateHUD(this: any) {
    const cp = this.state?.currentPlayer;
    if (!cp || !this.gameUI) return;
    const p = this.progress || {};
    this.gameUI.setPlayer({
      name: cp.name || 'You',
      level: p.level ?? cp.level ?? 1,
      hp: cp.hp ?? 0,
      maxHp: cp.max_hp ?? 0,
      mp: cp.mp ?? 0,
      maxMp: cp.max_mp ?? 0,
      xp: p.xp ?? 0,
      xpNext: p.xp_next ?? 0,
      pvp: !!cp.pvp_flagged,
      sound: !!this.audio?.enabled,
    });
  },

  /** A line in the chat log, coloured like EverQuest's combat text. */
  combatLog(this: any, text: string, color = '#E8E8E8') {
    if (!this.chatPanel) return;
    const log = this.chatPanel.querySelector('[data-chat-log="true"]') as HTMLDivElement | null;
    if (!log) return;
    const entry = document.createElement('div');
    entry.className = 'leading-tight';
    entry.style.color = color;
    entry.textContent = text;
    log.appendChild(entry);
    log.scrollTop = log.scrollHeight;
    while (log.childElementCount > 60) log.removeChild(log.firstElementChild as Node);
  },

  /** Footstep surface under a point: the cobbled plaza, the dirt paths, or grass. */
  surfaceAt(this: any, x: number, z: number): 'stone' | 'gravel' | 'grass' {
    return WorldDressing.surfaceAt(x / U, z / U);
  },

  /** Coins in words for the inventory and chat. */
  moneyText(copper: number): string {
    return money(copper);
  },
};

function capital(s: string): string {
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}
