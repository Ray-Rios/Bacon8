// The skill tree in the world: the windows (skills-ui.ts), casting, the keys, and how
// spells look (spell-fx.ts). Mixed into the scene hook like game-world.ts.
//
// Keys: K the skill tree; Q E F Z X the skills on them; 1-0 the spell bar's first row,
// Shift+1-0 its second. A spell with a cast time is interrupted by moving. The server
// decides everything (BaconWorldWeb.SkillEvents): "cast" starts it, "cast_result" says
// how it went, "zone_cast" shows everyone's casts (ours too).
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { SpellFx } from './spell-fx';
import { SKILL_KEYS, SkillsUI, type SkillsData } from './skills-ui';
import type { MobEntry, MobEvent } from './mobs-view';

const U = UNITS_PER_METRE;

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

const FAIL: Record<string, string> = {
  interrupted: 'Your spell is interrupted.',
  cancelled: 'You stop casting.',
  no_mana: "You don't have enough mana.",
  out_of_range: 'Your target is out of range.',
  no_target: 'Your target is gone.',
  dead: 'You die before the spell is done.',
  mobs_unavailable: 'Nothing happens.',
};

const CAST_COLOR: Record<string, string> = { recall: '#7ab8ff', heal: '#7dff8f', fireball: '#ff8a2a', root: '#7be05a' };

export const SkillsWorld = {
  /** After the game windows: the skill tree, the spell bar, the skill slots. */
  initSkills(this: any) {
    if (!this.gameUI || !this.scene) return;
    this.spellFx = this.spellFx || new SpellFx(this.scene);
    this.castGlows = new Map<string, { stop(): void }>();
    this.spins = [];
    this.casting = null;
    if (!this.skillsUI) {
      this.skillsUI = new SkillsUI(this.gameUI.root, {
        learn: (node: string) => void this.learnNode(node),
        cast: (id: string) => this.castAbility(id),
        assign: (slot: string, id: string | null) => this.assignSlot(slot, id),
        windows: (open: boolean) => {
          if (open) this.controller?.releasePointerLock();
        },
      });
      this.gameUI.setSkillSlots((key: string) => this.skillsUI.skillSlot(key));
    }
    const cp = this.state?.currentPlayer;
    if (cp?.skills) this.applySkills(cp.skills);
    else void reply(this, 'skills_fetch', {}).then((res: any) => res?.ok && this.applySkills(res));
  },

  teardownSkills(this: any) {
    this.spellFx?.clear();
    this.castGlows?.forEach((g: any) => g.stop());
    this.castGlows?.clear();
    this.skillsUI?.castStop();
    this.casting = null;
  },

  applySkills(this: any, data: SkillsData) {
    const before: string[] = this.skillsData?.abilities || [];
    this.skillsData = data;
    this.skillsUI?.set(data);
    this.gameUI?.refreshHotbar();
    for (const id of data.abilities) {
      if (before.length && !before.includes(id)) this.combatLog(`You have learned ${data.catalog[id]?.name || id}!`, '#9FD8FF');
    }
  },

  toggleSkills(this: any) {
    this.skillsUI?.toggle();
  },

  async learnNode(this: any, node: string) {
    const res = await reply(this, 'skill_learn', { node });
    if (!res.ok) {
      this.combatLog(res.error || "You can't learn that right now.", '#B8B8B8');
      return;
    }
    this.audio?.play('level_up', 0.5);
    this.applySkills(res);
  },

  assignSlot(this: any, slot: string, id: string | null) {
    if (!this.skillsUI) return;
    this.skillsUI.setSlot(slot, id);
    this.gameUI?.refreshHotbar();
    void reply(this, 'hotbar_set', { hotbars: this.skillsUI.hotbars });
  },

  /** Q..X, 1-0, Shift+1-0 and K. True when the key was ours. */
  skillKey(this: any, event: KeyboardEvent): boolean {
    if (!this.skillsUI || event.ctrlKey || event.metaKey || event.altKey) return false;
    if (event.code === 'KeyK') {
      this.toggleSkills();
      return true;
    }
    const letter = event.code.startsWith('Key') ? event.code.slice(3) : '';
    if (SKILL_KEYS.includes(letter) && !event.shiftKey) {
      const id = this.skillsUI.hotbars.skills[letter];
      if (id) this.castAbility(id);
      return true;
    }
    const m = /^Digit(\d)$/.exec(event.code);
    if (m) {
      const n = m[1] === '0' ? 9 : Number(m[1]) - 1;
      const id = this.skillsUI.spellAt((event.shiftKey ? 10 : 0) + n);
      if (id) this.castAbility(id);
      return true;
    }
    return false;
  },

  // ---------------------------------------------------------------- casting

  castAbility(this: any, id: string) {
    const a = this.skillsData?.catalog?.[id];
    const cp = this.state?.currentPlayer;
    if (!a || !cp || this.isDead) return;
    if (this.casting) {
      this.combatLog('You are already casting.', '#B8B8B8');
      return;
    }
    const wait = this.skillsUI.readyIn(id);
    if (wait > 0) {
      this.combatLog(`${a.name} isn't ready yet (${Math.ceil(wait / 1000)} s).`, '#B8B8B8');
      return;
    }
    if ((a.mp || 0) > (cp.mp ?? 0)) {
      this.combatLog("You don't have enough mana.", '#B8B8B8');
      return;
    }
    const myId = cp.character_id;
    if (this.mounts?.mountOf(myId) && a.effect?.type !== 'recall') {
      this.combatLog("You can't do that from the saddle. Press M to climb down.", '#B8B8B8');
      return;
    }
    let target: string | null = null;
    if (a.target === 'enemy') {
      const m = this.targetId && this.mobsView?.get(this.targetId);
      if (!m || m.view.state === 'dead') {
        this.combatLog('You need a target (Tab, or click a creature).', '#B8B8B8');
        return;
      }
      target = this.targetId;
    } else if (a.target === 'friendly') {
      target = this.targetId && this.isOtherPlayer(this.targetId) ? this.targetId : myId;
    }
    if (target && a.target === 'enemy') this.controller?.faceCamera?.(1200);
    const me = this.localCharacter();
    void reply(this, 'cast', { ability: id, target_id: target, heading: this.controller?.getYaw?.() ?? 0 }).then((res: any) => {
      if (!res.ok) {
        this.combatLog(res.error || "You can't do that right now.", '#B8B8B8');
        return;
      }
      if (res.cast_ms > 0) {
        this.casting = { id, from: me ? me.mesh.position.clone() : null };
        this.skillsUI.castStart(a.name, res.cast_ms);
      }
    });
  },

  /** Per frame: the effects, a cast interrupted by moving, mana on the bar, spins. */
  tickSkills(this: any, dt: number) {
    this.spellFx?.update(dt);
    if (this.skillsUI && this.state?.currentPlayer) this.skillsUI.setMana(this.state.currentPlayer.mp ?? 0);
    if (this.casting?.from) {
      const me = this.localCharacter();
      if (me && me.mesh.position.distanceTo(this.casting.from) > 0.5 * U) {
        this.casting = null;
        this.skillsUI.castStop(FAIL.interrupted);
        void reply(this, 'cast_cancel', {});
      }
    }
    this.spins = (this.spins || []).filter((s: any) => {
      s.t += dt;
      const k = Math.min(1, s.t / 0.5);
      s.model.rotation.y = k * Math.PI * 2;
      if (k >= 1) s.model.rotation.y = 0;
      return k < 1;
    });
  },

  /** How our cast went (BaconWorldWeb.SkillEvents "cast_result"). */
  onCastResult(this: any, p: any) {
    const a = this.skillsData?.catalog?.[p.ability];
    const name = a?.name || p.ability;
    this.casting = null;
    if (!p.ok) {
      this.skillsUI?.castStop(FAIL[p.reason] || 'Your spell fizzles.');
      if (p.reason !== 'cancelled') this.combatLog(FAIL[p.reason] || `Your ${name} fizzles.`, '#B8B8B8');
      return;
    }
    this.skillsUI?.castStop();
    this.skillsUI?.cooldown(p.ability, p.cooldown_ms || 0);
    if (p.hits) {
      if (p.ability === 'spin_attack' && p.hits.length === 0) this.combatLog('Your spin attack hits nothing.', '#A0A0A0');
      this.showHits(p.hits);
    }
    if (p.progress) this.applyProgress(p.progress);
    const myId = this.state?.currentPlayer?.character_id;
    if (a?.effect?.type === 'heal') {
      const who = p.target && p.target !== myId ? this.state?.onlineCharacters?.find((c: any) => c.character_id === p.target)?.character_name || 'them' : 'yourself';
      this.combatLog(`You heal ${who} for ${p.amount} hit points.`, '#7DFF8F');
    }
    if (a?.effect?.type === 'recall') this.combatLog('You recall to your bind point.', '#9FD8FF');
    if (a?.effect?.type === 'root') {
      const m = this.mobsView?.get(p.target);
      if (m) this.combatLog(`${m.view.name}'s feet are bound by roots.`, '#7BE05A');
    }
  },

  /** Anyone's cast (ours included): animations and effects. */
  onZoneCast(this: any, p: any) {
    const ch = this.characterManager?.getAllCharacters().get(p.character_id);
    const anim = this.characterManager?.getAnimator(p.character_id);
    const stopGlow = () => {
      this.castGlows?.get(p.character_id)?.stop();
      this.castGlows?.delete(p.character_id);
    };
    switch (p.phase) {
      case 'begin':
        if (ch) {
          stopGlow();
          this.castGlows.set(p.character_id, this.spellFx.casting(ch.mesh, CAST_COLOR[p.ability] || '#ffd27a'));
          anim?.oneShot('Spell_Simple_Enter', { upperOnly: true, rate: 0.8 });
        }
        break;
      case 'cancel':
        stopGlow();
        break;
      case 'launch': {
        stopGlow();
        if (!ch) break;
        anim?.oneShot('Spell_Simple_Shoot', { upperOnly: true });
        const from = ch.mesh.position.clone().add(new THREE.Vector3(0, 1.35 * U, 0));
        const fwd = new THREE.Vector3(Math.sin(ch.mesh.rotation.y), 0, Math.cos(ch.mesh.rotation.y)).multiplyScalar(0.45 * U);
        from.add(fwd);
        const target = () => {
          const m: MobEntry | undefined = this.mobsView?.get(p.target);
          if (!m) return null;
          const hgt = m.dragon ? 3.2 * (m.view.scale || 1) : 1.1;
          return m.root.position.clone().add(new THREE.Vector3(0, hgt * U, 0));
        };
        const dist = target()?.distanceTo(from) ?? 0;
        this.spellFx.projectile(from, target, p.travel_ms || 400);
        this.audio?.play('swing', 0.6, dist, 0.6);
        break;
      }
      case 'land':
        stopGlow();
        if (p.ability === 'recall') {
          if (p.from) this.spellFx.recall(new THREE.Vector3(p.from[0], p.from[1], p.from[2]));
          if (p.to) setTimeout(() => this.spellFx?.recall(new THREE.Vector3(p.to[0], p.to[1], p.to[2])), 150);
        } else if (p.ability === 'heal') {
          anim?.oneShot('Spell_Simple_Shoot', { upperOnly: true });
          const t = this.characterManager?.getAllCharacters().get(p.target);
          if (t) this.spellFx.heal(t.mesh);
        } else if (ch) {
          anim?.oneShot('Spell_Simple_Shoot', { upperOnly: true });
        }
        break;
      case 'spin':
        if (ch) {
          this.spellFx.spin(ch.mesh);
          anim?.oneShot('Sword_Regular_C', { upperOnly: true, rate: 1.3 });
          const human = this.characterManager?.getHuman(p.character_id);
          if (human?.model) this.spins.push({ model: human.model, t: 0 });
          this.audio?.play('swing', 1.0, 0, 0.8);
        }
        break;
    }
  },

  /** A creature was rooted (mob event "rooted"): vines for as long as it lasts. */
  onMobRooted(this: any, e: MobEvent, m: MobEntry | undefined) {
    if (!m || !this.spellFx) return;
    const r = m.dragon ? 3.0 * (m.view.scale || 1) : 0.7;
    this.spellFx.root(m.root, (e as any).ms || 6000, r);
  },
};
