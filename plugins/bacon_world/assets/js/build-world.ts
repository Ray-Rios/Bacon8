// Build mode (2026-10-28), mixed into the hook like game-world.ts. ` (the key left of 1) turns it
// on and off. With it on the cursor is free and a window lists what this account may place
// (build-ui.ts); the server decides everything (BaconWorld.Building, BaconWorldWeb.BuildEvents).
//
//   pick from the list        the thing rides under the cursor as a ghost (green: allowed)
//   left click                sets it down (Shift: and pick up another of the same)
//   left click on a placed    picks it up (if your role may place that kind of thing)
//   right button, held        turns what you hold, gently (Shift: the other way)
//   wheel, Q / E              turn it in steps; PgUp / PgDn raise and lower; [ ] size
//   right click (no drag)     removes the thing under the cursor; Ctrl+Z puts it back
//   Esc                       puts down nothing: what you held goes back; again: leave
//
// Right-dragging still steers and left-dragging still turns the camera (the owner: right-button
// steering stays). Creature spawns and NPCs are placed the same way: a GM picks up a goblin (or
// its marker) to move its spawn, right-clicks it to remove it.
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { BuildWindow, type CatalogueEntry } from './build-ui';
import { PlacedView, isModel, type Placement } from './placed-view';

const U = UNITS_PER_METRE;
const TURN_RATE = Math.PI / 4; // radians a second while the right button is held: gentle
const STEP = Math.PI / 12; // 15 degrees a wheel notch or Q/E press
const GRID = 1.5;
const STOREY = 3;
const UNDO_MS = 5 * 60_000;

function reply(hook: any, event: string, payload: object, fallback: any = { ok: false, error: 'No answer from the server.' }): Promise<any> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(fallback), 6000);
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

interface Held {
  /** The placement being moved, or null for a new one from the list. */
  id: string | null;
  asset: string;
  name: string;
  kind: 'model' | 'mob' | 'npc';
  rot: number;
  lift: number;
  scale: number;
  data: Record<string, any>;
  /** Where the cursor caught it, so it doesn't jump to the cursor (metres). */
  grab: { x: number; z: number };
  ghost: THREE.Object3D;
  before: Placement | null;
  at: { x: number; y: number; z: number } | null;
}

type Undo = { t: number } & ({ kind: 'placed'; id: string } | { kind: 'moved'; before: Placement } | { kind: 'deleted'; p: Placement });

/** Snaps a building piece to the kit's half-cell grid and right angles (pure; tested). */
export function snapPiece(x: number, z: number, rot: number): { x: number; z: number; rot: number } {
  const q = Math.PI / 2;
  return { x: Math.round(x / GRID) * GRID, z: Math.round(z / GRID) * GRID, rot: (((Math.round(rot / q) * q) % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI) };
}

/**
 * Where a ray first meets the ground (scene units): marched in steps, then halved down to a
 * centimetre. `ground(x, z)` is the height there. Null when it misses within `far` (pure; tested).
 */
export function rayGround(origin: { x: number; y: number; z: number }, dir: { x: number; y: number; z: number }, ground: (x: number, z: number) => number, far: number, step: number): { x: number; y: number; z: number } | null {
  const at = (t: number) => ({ x: origin.x + dir.x * t, y: origin.y + dir.y * t, z: origin.z + dir.z * t });
  const above = (t: number) => {
    const p = at(t);
    return p.y - ground(p.x, p.z);
  };
  if (above(0) < 0) return null;
  let t0 = 0;
  for (let t = step; t <= far; t += step) {
    if (above(t) <= 0) {
      let a = t0, b = t;
      for (let i = 0; i < 24 && b - a > 0.01; i++) {
        const m = (a + b) / 2;
        if (above(m) > 0) a = m;
        else b = m;
      }
      const p = at(b);
      return { x: p.x, y: ground(p.x, p.z), z: p.z };
    }
    t0 = t;
  }
  return null;
}

export const BuildWorld = {
  /** The placements arrived with the creatures (fetch_mobs): draw them, wall them in. */
  initPlaced(this: any, list: Placement[]) {
    if (!this.scene) return;
    if (!this.placedView) {
      const dressing = this.dressing;
      const source = {
        template: (name: string) => dressing?.template?.(name) ?? null,
        ready: () => dressing?.ready?.() ?? Promise.resolve(),
      };
      this.placedView = new PlacedView(source);
      this.placedView.ground = (x: number, z: number) => this.groundAt(x * U, z * U) / U;
      this.placedView.onColliders = () => this.rebuildColliders?.();
      // the village's group is in metres (scaled); without one, a scaled group of our own
      if (dressing?.group) dressing.group.add(this.placedView.group);
      else {
        const g = new THREE.Group();
        g.scale.setScalar(U);
        g.add(this.placedView.group);
        (this.worldGroup || this.scene).add(g);
      }
    }
    void this.placedView.setAll(list || []);
    for (const p of list || []) if (p.npc) void this.npcsView?.put(p.npc);
  },

  teardownBuild(this: any) {
    this.buildExit?.();
    this.placedView?.group.parent?.remove(this.placedView.group);
    this.placedView = null;
    this.buildWindow?.dispose();
    this.buildWindow = null;
    this.buildUndo = [];
  },

  /** Someone placed or changed something (the server's broadcast, our own changes too). */
  onBuildPlaced(this: any, p: Placement) {
    if (this.buildHeld?.id === p.id) return; // we're carrying it: our drop will say where it is
    this.placedView?.put(p);
    if (p.npc) void this.npcsView?.put(p.npc);
  },

  onBuildRemoved(this: any, payload: { id: string; asset: string }) {
    if (this.buildHeld?.id === payload.id) this.buildDropHeld(false);
    this.placedView?.remove(payload.id);
    if (payload.asset?.startsWith('npc:')) {
      this.npcsView?.drop(`p:${payload.id}`);
      if (this.targetId === `p:${payload.id}`) this.setTarget?.(null);
    }
  },

  /** The village's, the people's, the water's and the placed things' colliders, together. */
  rebuildColliders(this: any) {
    if (!this.worldColliders) return;
    const base = this.dressing ? this.dressing.colliders() : this.worldColliders.filter((c: any) => !c.npc && !c.placed && c.kind !== 'ellipse');
    const npcs = (this.npcsView?.colliders() || []).map((c: any) => ({ ...c, npc: true }));
    const placed = (this.placedView?.colliders() || []).map((c: any) => ({ ...c, placed: true }));
    this.worldColliders = [...base, ...npcs, ...(this.waterColliders?.() || []), ...placed];
  },

  // ---------------------------------------------------------------- on and off

  async toggleBuild(this: any) {
    if (this.buildMode) this.buildExit();
    else await this.buildEnter();
  },

  async buildEnter(this: any) {
    if (this.buildMode || this.isDead || !this.gameUI) return;
    this.buildMode = true;
    this.controller?.releasePointerLock();
    if (!this.buildWindow) {
      this.buildWindow = new BuildWindow(this.gameUI.root, {
        pick: (e: CatalogueEntry) => this.buildHoldNew(e),
        rule: (asset: string, role: string) => void this.buildSetRule(asset, role),
        data: (patch: Record<string, any>) => this.buildSetData(patch),
        snap: (on: boolean) => {
          this.buildSnap = on;
          this.buildRefreshHeld();
        },
        cancel: () => this.buildDropHeld(true),
        close: () => this.buildExit(),
      });
      this.buildSnap = true;
    }
    this.buildWindow.open({ catalogue: [], admin: false, roles: [], role: '' });
    this.placedView?.setMarkers(true);
    this.buildMoveHandler = this.buildMoveHandler || ((e: PointerEvent) => this.buildPointer(e));
    this.renderer?.domElement.addEventListener('pointermove', this.buildMoveHandler);
    this.combatLog('Build mode. Pick something from the list, or click something placed to move it. ` to leave.', '#9FE39F');
    const res = await reply(this, 'build_open', {});
    if (!this.buildMode) return;
    if (!res.ok) {
      this.combatLog(res.error || "You can't build right now.", '#FF9B7A');
      this.buildExit();
      return;
    }
    this.buildInfo = res;
    this.buildWindow.open(res);
    if (!res.catalogue?.some((e: CatalogueEntry) => e.allowed)) this.combatLog('Your role may not place anything here yet.', '#B8B8B8');
  },

  buildExit(this: any) {
    if (!this.buildMode) return;
    this.buildDropHeld(true);
    this.buildMode = false;
    this.buildWindow?.close();
    this.placedView?.setMarkers(false);
    if (this.buildMoveHandler) this.renderer?.domElement.removeEventListener('pointermove', this.buildMoveHandler);
    this.buildHover = null;
    this.combatLog('You leave build mode.', '#B8B8B8');
  },

  // ---------------------------------------------------------------- holding

  buildHoldNew(this: any, e: CatalogueEntry) {
    if (!this.placedView) return;
    this.buildDropHeld(true);
    const me = this.localCharacter?.();
    const data = e.kind === 'mob' ? { count: e.boss ? 1 : 3, radius: e.boss ? 0 : 4 } : {};
    const ghost = this.placedView.ghost(e.id, data);
    this.placedView.group.add(ghost);
    this.buildHeld = {
      id: null, asset: e.id, name: e.name, kind: e.kind, rot: me ? me.mesh.rotation.y + Math.PI : 0, lift: 0, scale: 1, data,
      grab: { x: 0, z: 0 }, ghost, before: null, at: null,
    } as Held;
    this.buildRefreshHeld();
    this.buildPointer(this.lastBuildPointer);
  },

  /** Picks up a placement (with what the cursor was over when it caught it). */
  buildPickUp(this: any, id: string, at: { x: number; z: number } | null) {
    const p: Placement | null = this.placedView?.get(id);
    if (!p) return;
    const entry = this.buildWindow?.entry(p.asset);
    if (entry && !entry.allowed) {
      this.combatLog(`Only a ${entry.min_role} or higher may move ${entry.name.toLowerCase()}.`, '#FF9B7A');
      return;
    }
    this.buildDropHeld(true);
    const kind = isModel(p.asset) ? 'model' : p.asset.startsWith('mob:') ? 'mob' : 'npc';
    const ghost = this.placedView.ghost(p.asset, p.data);
    this.placedView.group.add(ghost);
    this.placedView.setHidden(id, true);
    if (kind === 'npc') this.npcsView?.setHidden(`p:${id}`, true);
    const ground = this.placedView.ground(p.x, p.z);
    this.buildHeld = {
      id, asset: p.asset, name: entry?.name || p.asset, kind, rot: p.rot, lift: p.y - ground, scale: p.scale, data: { ...p.data },
      grab: at ? { x: p.x - at.x, z: p.z - at.z } : { x: 0, z: 0 }, ghost, before: { ...p }, at: { x: p.x, y: p.y, z: p.z },
    } as Held;
    this.placedView.pose(ghost, { x: p.x, y: p.y, z: p.z, rot: p.rot, scale: p.scale });
    this.buildRefreshHeld();
  },

  /** Lets go of what the cursor holds; `putBack`: a picked-up placement goes back where it was. */
  buildDropHeld(this: any, putBack: boolean) {
    const held: Held | null = this.buildHeld;
    if (!held) return;
    held.ghost.parent?.remove(held.ghost);
    if (held.id) {
      this.placedView?.setHidden(held.id, false);
      if (held.kind === 'npc') this.npcsView?.setHidden(`p:${held.id}`, false);
      if (putBack && held.before) this.placedView?.put(held.before);
    }
    this.buildHeld = null;
    this.buildRotating = 0;
    this.buildWindow?.setHeld(null);
    void putBack;
  },

  buildRefreshHeld(this: any) {
    const held: Held | null = this.buildHeld;
    if (!held) return this.buildWindow?.setHeld(null);
    this.buildWindow?.setHeld({ name: held.name, kind: held.kind, isNew: !held.id, data: held.data, snap: !!this.buildSnap, canSnap: held.asset.startsWith('K_') });
    if (held.kind === 'mob') this.placedView?.poseMarker(held.ghost, { id: 'ghost', asset: held.asset, x: 0, y: 0, z: 0, rot: 0, scale: 1, data: held.data });
    this.buildPose();
  },

  buildSetData(this: any, patch: Record<string, any>) {
    const held: Held | null = this.buildHeld;
    if (!held) return;
    held.data = { ...held.data, ...patch };
    this.buildRefreshHeld();
  },

  /** Where the held thing would stand now (metres), snapped if asked. */
  buildSpot(this: any, alt = false): { x: number; y: number; z: number; rot: number; scale: number } | null {
    const held: Held | null = this.buildHeld;
    if (!held || !held.at) return null;
    let x = held.at.x, z = held.at.z, rot = held.rot;
    if (this.buildSnap && held.asset.startsWith('K_') && !alt) ({ x, z, rot } = snapPiece(x, z, rot));
    const y = this.placedView.ground(x, z) + held.lift;
    return { x, y, z, rot, scale: held.scale };
  },

  buildPose(this: any) {
    const held: Held | null = this.buildHeld;
    const spot = this.buildSpot(this.buildAlt);
    if (!held || !spot) return;
    this.placedView.pose(held.ghost, spot);
    if (held.kind === 'mob') held.ghost.scale.setScalar(1);
    const entry = this.buildWindow?.entry(held.asset);
    const ok = !entry || entry.allowed;
    (held.ghost.userData.ghostMat as THREE.MeshBasicMaterial | undefined)?.color.set(ok ? '#7CFF8A' : '#FF6A55');
  },

  // ---------------------------------------------------------------- the mouse

  /** The cursor moved (build mode only): the held thing follows it over the ground. */
  buildPointer(this: any, e: PointerEvent | MouseEvent | null) {
    if (!e) return;
    this.lastBuildPointer = e;
    this.buildAlt = e.altKey;
    const held: Held | null = this.buildHeld;
    if (!held) return;
    const g = this.buildGroundUnder(e);
    if (!g) return;
    held.at = { x: g.x + held.grab.x, y: 0, z: g.z + held.grab.z };
    this.buildPose();
  },

  /** The ground under the cursor (metres), or null. */
  buildGroundUnder(this: any, e: MouseEvent): { x: number; z: number } | null {
    if (!this.camera || !this.renderer) return null;
    const rect = this.renderer.domElement.getBoundingClientRect();
    const ndc = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.camera);
    const hit = rayGround(ray.ray.origin, ray.ray.direction, (x: number, z: number) => this.groundAt(x, z), 400 * U, 0.5 * U);
    return hit ? { x: hit.x / U, z: hit.z / U } : null;
  },

  /** The placement under the cursor: a model or marker, a placed NPC, a placed spawn's creature. */
  buildPickAt(this: any, e: MouseEvent): string | null {
    if (!this.camera || !this.renderer || !this.placedView) return null;
    const rect = this.renderer.domElement.getBoundingClientRect();
    const ndc = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.camera);
    const own = this.placedView.pick(ray);
    if (own) return own;
    const npc: string | null = this.npcsView?.pick(ray) ?? null;
    if (npc?.startsWith('p:')) return npc.slice(2);
    const mob: string | null = this.mobsView?.pick(ray) ?? null;
    if (mob?.startsWith('p:')) return mob.split(':')[1] || null;
    return null;
  },

  /** True when build mode takes this press or wheel from the camera (the controller asks). */
  buildTakesMouse(this: any, e: MouseEvent): boolean {
    if (!this.buildMode || !this.buildHeld) return false;
    if (e.type === 'wheel') {
      const w = e as WheelEvent;
      this.buildHeld.rot += Math.sign(w.deltaY) * STEP;
      this.buildPose();
      return true;
    }
    // the right button turns what is held, instead of steering
    if (e.button === 2) {
      this.buildRotating = e.shiftKey ? -1 : 1;
      return true;
    }
    return false;
  },

  /** A left click in build mode (not the end of a camera drag): true when it was ours. */
  buildLeftClick(this: any, e: MouseEvent): boolean {
    if (!this.buildMode) return false;
    if (this.buildHeld) {
      void this.buildCommit(e.shiftKey);
      return true;
    }
    const id = this.buildPickAt(e);
    if (id) {
      this.buildPickUp(id, this.buildGroundUnder(e));
      return true;
    }
    // nothing of ours: keep the usual click (targeting)
    return false;
  },

  /** A right button press or release in build mode (handleRightButton): true when it was ours. */
  buildRightButton(this: any, e: MouseEvent): boolean {
    if (!this.buildMode) return false;
    if (e.type === 'mousedown') {
      this.buildRmb = { x: e.clientX, y: e.clientY, t: performance.now() };
      return true;
    }
    const down = this.buildRmb;
    this.buildRmb = null;
    if (this.buildRotating) {
      this.buildRotating = 0;
      return true;
    }
    if (this.buildHeld) return true;
    // a click, not a steering drag: remove what's under it
    if (!down || performance.now() - down.t > 350 || Math.hypot(e.clientX - down.x, e.clientY - down.y) > 6) return true;
    const id = this.buildPickAt(e);
    if (id) void this.buildDelete(id);
    return true;
  },

  // ---------------------------------------------------------------- keys

  /** Keys in the world: ` toggles; in build mode the holding keys. True when it was ours. */
  buildKey(this: any, e: KeyboardEvent): boolean {
    if (e.code === 'Backquote' && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault();
      void this.toggleBuild();
      return true;
    }
    if (!this.buildMode) return false;
    const held: Held | null = this.buildHeld;
    if ((e.ctrlKey || e.metaKey) && e.code === 'KeyZ') {
      e.preventDefault();
      void this.buildUndoLast();
      return true;
    }
    if (e.code === 'Slash' && !this.isTyping?.()) {
      // "/" still opens chat
      return false;
    }
    if (e.code === 'KeyF' && e.ctrlKey) return false;
    if (e.code === 'Enter' && !held) return false;
    if (!held) {
      if (e.code === 'KeyB' || (e.key === 'f' && e.shiftKey)) {
        this.buildWindow?.focusSearch();
        e.preventDefault();
        return true;
      }
      // the skill keys do nothing in build mode (Q E F Z X)
      return ['KeyQ', 'KeyE', 'KeyF', 'KeyZ', 'KeyX'].includes(e.code);
    }
    switch (e.code) {
      case 'KeyQ':
        held.rot -= STEP;
        break;
      case 'KeyE':
        held.rot += STEP;
        break;
      case 'PageUp':
        held.lift += e.shiftKey ? STOREY : 0.25;
        break;
      case 'PageDown':
        held.lift -= e.shiftKey ? STOREY : 0.25;
        break;
      case 'BracketLeft':
        held.scale = Math.max(0.5, Math.round((held.scale - 0.1) * 10) / 10);
        break;
      case 'BracketRight':
        held.scale = Math.min(2, Math.round((held.scale + 0.1) * 10) / 10);
        break;
      case 'Delete':
      case 'Backspace': {
        const id = held.id;
        this.buildDropHeld(true);
        if (id) void this.buildDelete(id);
        break;
      }
      case 'Enter':
        void this.buildCommit(e.shiftKey);
        break;
      case 'KeyF':
      case 'KeyZ':
      case 'KeyX':
        break;
      default:
        return false;
    }
    e.preventDefault();
    this.buildPose();
    return true;
  },

  /** Esc in build mode: drop what is held, else leave. True when it was ours. */
  buildEscape(this: any): boolean {
    if (!this.buildMode) return false;
    if (this.buildHeld) this.buildDropHeld(true);
    else this.buildExit();
    return true;
  },

  // ---------------------------------------------------------------- per frame

  tickBuild(this: any, dt: number) {
    if (!this.buildMode) return;
    const held: Held | null = this.buildHeld;
    if (held && this.buildRotating) {
      held.rot += this.buildRotating * TURN_RATE * dt;
      this.buildPose();
    }
    // the spawn markers' names
    if (this.nameplates && this.placedView) {
      for (const p of this.placedView.all() as Placement[]) {
        if (isModel(p.asset)) continue;
        const marker = this.placedView.markerOf(p.id);
        if (!marker || !marker.visible) continue;
        const entry = this.buildWindow?.entry(p.asset);
        const name = p.asset.startsWith('mob:') ? `${entry?.name || p.asset.slice(4)}${(p.data?.count || 1) > 1 ? ` x${p.data.count}` : ''}` : p.npc?.name || entry?.name || 'NPC';
        this.nameplates.set(`build:${p.id}`, marker, { name, sub: p.asset.startsWith('mob:') ? '<spawn>' : '<NPC>', color: p.asset.startsWith('mob:') ? '#FF9B7A' : '#8FD3FF' }, { height: 3.1 * U });
      }
    }
  },

  /** The marker names to keep (the hook prunes the rest). */
  buildPlateIds(this: any): string[] {
    if (!this.buildMode || !this.placedView) return [];
    return (this.placedView.all() as Placement[]).filter((p) => !isModel(p.asset)).map((p) => `build:${p.id}`);
  },

  // ---------------------------------------------------------------- the server

  async buildCommit(this: any, again: boolean) {
    const held: Held | null = this.buildHeld;
    const spot = this.buildSpot(this.buildAlt);
    if (!held || !spot || this.buildBusy) return;
    this.buildBusy = true;
    const payload = { asset: held.asset, x: spot.x, y: spot.y, z: spot.z, rot: spot.rot, scale: spot.scale, data: held.data };
    if (held.id) {
      const id = held.id;
      const before = held.before;
      // set it down at once; the server's word follows
      this.buildDropHeld(false);
      if (before) this.placedView?.put({ ...before, ...payload, id });
      const res = await reply(this, 'build_move', { id, ...payload });
      this.buildBusy = false;
      if (!res.ok) {
        if (before) this.placedView?.put(before);
        this.combatLog(res.error || "That can't go there.", '#FF9B7A');
        return;
      }
      this.placedView?.put(res.placement);
      if (res.placement.npc) void this.npcsView?.put(res.placement.npc);
      if (before) this.buildRemember({ kind: 'moved', before });
      this.audio?.play('click', 0.5);
      return;
    }
    const res = await reply(this, 'build_place', payload);
    this.buildBusy = false;
    if (!res.ok) {
      this.combatLog(res.error || "That can't go there.", '#FF9B7A');
      return;
    }
    this.placedView?.put(res.placement);
    if (res.placement.npc) void this.npcsView?.put(res.placement.npc);
    this.buildRemember({ kind: 'placed', id: res.placement.id });
    this.audio?.play('click', 0.6);
    // Shift: another of the same, turned the same way
    if (!again) this.buildDropHeld(false);
  },

  async buildDelete(this: any, id: string) {
    const p: Placement | null = this.placedView?.get(id);
    const entry = p ? this.buildWindow?.entry(p.asset) : null;
    if (entry && !entry.allowed) {
      this.combatLog(`Only a ${entry.min_role} or higher may remove ${entry.name.toLowerCase()}.`, '#FF9B7A');
      return;
    }
    const res = await reply(this, 'build_delete', { id });
    if (!res.ok) {
      this.combatLog(res.error || "That can't be removed.", '#FF9B7A');
      return;
    }
    this.onBuildRemoved({ id, asset: res.placement.asset });
    this.buildRemember({ kind: 'deleted', p: res.placement });
    this.combatLog(`Removed ${entry?.name?.toLowerCase() || 'it'}. Ctrl+Z puts it back.`, '#B8B8B8');
    this.audio?.play('click', 0.4);
  },

  async buildSetRule(this: any, asset: string, role: string) {
    const res = await reply(this, 'build_rule', { asset, role });
    if (!res.ok) {
      this.combatLog(res.error || "That rule can't be set.", '#FF9B7A');
      return;
    }
    this.buildWindow?.setRule(asset, res.role);
    this.combatLog(`${this.buildWindow?.entry(asset)?.name || asset}: ${res.role}s and above may place it now.`, '#9FE39F');
  },

  buildRemember(this: any, u: Omit<Undo, 't'>) {
    const now = performance.now();
    this.buildUndo = [...(this.buildUndo || []).filter((x: Undo) => now - x.t < UNDO_MS), { ...u, t: now }].slice(-25);
  },

  async buildUndoLast(this: any) {
    const now = performance.now();
    const list: Undo[] = (this.buildUndo || []).filter((x: Undo) => now - x.t < UNDO_MS);
    const u = list.pop();
    this.buildUndo = list;
    if (!u) {
      this.combatLog('Nothing to undo.', '#B8B8B8');
      return;
    }
    let res: any;
    if (u.kind === 'placed') res = await reply(this, 'build_delete', { id: u.id });
    else if (u.kind === 'moved') res = await reply(this, 'build_move', { ...u.before });
    else res = await reply(this, 'build_place', { asset: u.p.asset, x: u.p.x, y: u.p.y, z: u.p.z, rot: u.p.rot, scale: u.p.scale, data: u.p.data });
    if (!res?.ok) {
      this.combatLog(res?.error || "That can't be undone.", '#FF9B7A');
      return;
    }
    if (u.kind === 'placed') this.onBuildRemoved({ id: u.id, asset: res.placement.asset });
    else {
      this.placedView?.put(res.placement);
      if (res.placement.npc) void this.npcsView?.put(res.placement.npc);
    }
    this.combatLog('Undone.', '#B8B8B8');
  },
};
