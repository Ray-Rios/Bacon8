// What spells and skills look like (skills-world.ts plays them): a glow while casting,
// school-coloured projectiles, AoE novas and storms, frontal cones, chain lightning arcs,
// protective barriers, combat buffs, dashes/leaps/blinks, weapon slashes, taunts, healing
// sparkles, roots around a creature's feet, the swirl of Recall, and the ring of a spin
// attack. Additive particles and pooled lights; everything cleans itself up. Positions
// are world (scene) units.
import * as THREE from '../../../../assets/js/vendor/three';
import { LightPool } from './light-pool';
import { UNITS_PER_METRE } from './controls-math';

const U = UNITS_PER_METRE;

type Fx = { update(dt: number): boolean; dispose(): void };

export const FX_SCHOOL_COLOR: Record<string, string> = {
  fire: '#ff7a1a',
  frost: '#5cd6ff',
  storm: '#a478ff',
  arcane: '#d06bff',
  holy: '#ffd95e',
  nature: '#62e66c',
  shadow: '#9448eb',
  blood: '#ff3344',
  earth: '#c99359',
  water: '#38b6ff',
  blade: '#d4dde8',
  berserk: '#ff4d2e',
  blunt: '#d9a76a',
  polearm: '#60b5ff',
  rogue: '#9d75e6',
  archery: '#82d959',
  shield: '#f0c44d',
  monk: '#f5ad52',
  warlord: '#f0483a',
  survival: '#75b85a',
};

export function schoolColor(school?: string, fallback = '#ff8a2a'): string {
  return (school && FX_SCHOOL_COLOR[school]) || fallback;
}

let dotTexture: THREE.Texture | null = null;
function dot(): THREE.Texture {
  if (dotTexture) return dotTexture;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const grd = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  grd.addColorStop(0, 'rgba(255,255,255,1)');
  grd.addColorStop(0.35, 'rgba(255,255,255,.55)');
  grd.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grd;
  g.fillRect(0, 0, 64, 64);
  dotTexture = new THREE.CanvasTexture(c);
  return dotTexture;
}

// Materials are made once and kept, never disposed: disposing the last material of a kind makes
// three.js drop its shader, which is then built again, mid-game, the next time a spell lands.
const _sparkMats = new Map<number, THREE.PointsMaterial>();
function sparkMaterial(size: number): THREE.PointsMaterial {
  let m = _sparkMats.get(size);
  if (!m) {
    m = new THREE.PointsMaterial({ size: size * U, map: dot(), vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true });
    _sparkMats.set(size, m);
  }
  return m;
}

/** A pool of additive particles: each has a position, velocity, life and colour. */
class Sparks {
  readonly points: THREE.Points;
  private pos: Float32Array;
  private col: Float32Array;
  private vel: Float32Array;
  private life: Float32Array;
  private max: Float32Array;
  private base: Float32Array;
  private next = 0;

  constructor(private n: number, size: number, private drag = 0.9, private gravity = 0) {
    this.pos = new Float32Array(n * 3);
    this.col = new Float32Array(n * 3);
    this.vel = new Float32Array(n * 3);
    this.life = new Float32Array(n);
    this.max = new Float32Array(n);
    this.base = new Float32Array(n * 3);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(this.col, 3));
    this.points = new THREE.Points(geo, sparkMaterial(size));
    this.points.frustumCulled = false;
  }

  emit(p: THREE.Vector3, v: THREE.Vector3, life: number, color: THREE.Color) {
    const i = this.next;
    this.next = (this.next + 1) % this.n;
    this.pos.set([p.x, p.y, p.z], i * 3);
    this.vel.set([v.x, v.y, v.z], i * 3);
    this.base.set([color.r, color.g, color.b], i * 3);
    this.life[i] = life;
    this.max[i] = life;
  }

  /** Returns whether any particle is still alive. */
  update(dt: number): boolean {
    let alive = false;
    const k = Math.pow(this.drag, dt * 60);
    for (let i = 0; i < this.n; i++) {
      if (this.life[i] <= 0) {
        this.col[i * 3] = this.col[i * 3 + 1] = this.col[i * 3 + 2] = 0;
        continue;
      }
      alive = true;
      this.life[i] -= dt;
      const t = Math.max(0, this.life[i] / this.max[i]);
      this.vel[i * 3 + 1] -= this.gravity * U * dt;
      for (let a = 0; a < 3; a++) {
        this.vel[i * 3 + a] *= k;
        this.pos[i * 3 + a] += this.vel[i * 3 + a] * dt;
        this.col[i * 3 + a] = this.base[i * 3 + a] * t;
      }
    }
    (this.points.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    (this.points.geometry.attributes.color as THREE.BufferAttribute).needsUpdate = true;
    return alive;
  }

  dispose() {
    // the material is shared and kept (sparkMaterial): disposing it threw its shader away
    this.points.geometry.dispose();
  }
}

const rnd = (a: number) => (Math.random() * 2 - 1) * a;

// The roots' vines share one lit material, made once and kept (a new one each cast was a new
// shader to build when the spell landed).
let _roots: THREE.MeshStandardMaterial | null = null;
const rootsMaterial = () => (_roots ||= new THREE.MeshStandardMaterial({ color: '#3f7a2a', roughness: 0.8, emissive: '#16300c' }));
const tmp = new THREE.Vector3();

// THE LIGHTS ARE POOLED, AND NEVER LEAVE THE SCENE. three.js builds every lit material's shader for
// the number of lights in the scene, so adding a light (a fireball's glow, a burst) and removing it
// again made every material in the village and on every character recompile, twice: the game froze
// for 2-5 s as each spell landed, Recall included (2026-10-26). Since 2026-10-30 the pool is the
// world's, shared with the dragons' fire breath (light-pool.ts).

export class SpellFx {
  private live: Fx[] = [];
  private mine = new Set<THREE.PointLight>();
  private pool: LightPool;

  constructor(private scene: THREE.Scene) {
    this.pool = LightPool.install(scene);
  }

  /** A pooled light, lit (null when all are busy: the effect goes without one). */
  private takeLight(color: THREE.Color, intensity: number, distance: number): THREE.PointLight | null {
    const l = this.pool.take(color, intensity, distance);
    if (l) this.mine.add(l);
    return l;
  }

  private giveLight(l: THREE.PointLight | null) {
    if (!l) return;
    this.pool.give(l);
    this.mine.delete(l);
  }

  update(dt: number) {
    this.live = this.live.filter((f) => {
      const keep = f.update(dt);
      if (!keep) f.dispose();
      return keep;
    });
  }

  clear() {
    this.live.forEach((f) => f.dispose());
    this.live = [];
    for (const l of [...this.mine]) this.giveLight(l);
  }

  /** Sparks circling the caster's hands while a spell is cast. Stop it with the handle. */
  casting(caster: THREE.Object3D, color: string): { stop(): void } {
    const sp = new Sparks(80, 0.12, 0.92);
    this.scene.add(sp.points);
    const c = new THREE.Color(color);
    let on = true;
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        if (on) {
          caster.getWorldPosition(tmp);
          const h = 1.15 * U * (caster.scale.y / U || 1);
          for (let k = 0; k < 3; k++) {
            const a = t * 7 + k * 2.1;
            const p = new THREE.Vector3(tmp.x + Math.cos(a) * 0.32 * U, tmp.y + h + Math.sin(t * 3 + k) * 0.08 * U, tmp.z + Math.sin(a) * 0.32 * U);
            sp.emit(p, new THREE.Vector3(rnd(0.1) * U, 0.35 * U, rnd(0.1) * U), 0.5, c);
          }
        }
        return sp.update(dt) || on;
      },
      dispose: () => {
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
    return { stop: () => (on = false) };
  }

  /** A projectile from `from` to wherever `to` is (it follows a moving target), `ms` long. */
  projectile(from: THREE.Vector3, to: () => THREE.Vector3 | null, ms: number, color = '#ff7a1a', onArrive?: (at: THREE.Vector3) => void) {
    const c = new THREE.Color(color);
    const bright = c.clone().lerp(new THREE.Color('#ffffff'), 0.55);
    const core = new THREE.Mesh(new THREE.SphereGeometry(0.16 * U, 14, 10), new THREE.MeshBasicMaterial({ color: bright }));
    const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: dot(), color: c, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
    halo.scale.setScalar(0.9 * U);
    core.add(halo);
    const light = this.takeLight(c, 6, 8 * U);
    light?.position.copy(from);
    const trail = new Sparks(160, 0.22, 0.86);
    this.scene.add(core, trail.points);
    core.position.copy(from);
    let t = 0;
    let arrived = false;
    const last = from.clone();
    this.live.push({
      update: (dt) => {
        if (!arrived) {
          t += (dt * 1000) / Math.max(ms, 1);
          const dest = to() || last;
          last.copy(dest);
          const k = Math.min(1, t);
          core.position.lerpVectors(from, dest, k);
          core.position.y += Math.sin(k * Math.PI) * 0.5 * U;
          light?.position.copy(core.position);
          for (let i = 0; i < 4; i++) trail.emit(core.position.clone().add(new THREE.Vector3(rnd(0.06 * U), rnd(0.06 * U), rnd(0.06 * U))), new THREE.Vector3(rnd(0.3 * U), rnd(0.3 * U) + 0.2 * U, rnd(0.3 * U)), 0.35 + Math.random() * 0.2, i % 2 ? c : bright);
          if (k >= 1) {
            arrived = true;
            core.visible = false;
            this.giveLight(light);
            this.burst(core.position.clone(), color, 70, 3.2);
            onArrive?.(core.position.clone());
          }
        }
        return trail.update(dt) || !arrived;
      },
      dispose: () => {
        this.giveLight(light);
        this.scene.remove(core, trail.points);
        core.geometry.dispose();
        trail.dispose();
        // (core and halo materials are left to the garbage collector, their shaders kept)
      },
    });
  }

  /** A burst of sparks (an explosion, a hit). */
  burst(at: THREE.Vector3, color: string, n = 50, speed = 2.5) {
    const sp = new Sparks(n, 0.26, 0.9, 1.5);
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.6);
    for (let i = 0; i < n; i++) {
      const v = new THREE.Vector3(rnd(1), rnd(1), rnd(1)).normalize().multiplyScalar(speed * U * (0.4 + Math.random() * 0.6));
      sp.emit(at, v, 0.45 + Math.random() * 0.35, i % 3 ? c : accent);
    }
    const light = this.takeLight(c, 10, 9 * U);
    light?.position.copy(at);
    this.scene.add(sp.points);
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        if (light) light.intensity = Math.max(0, 10 * (1 - t / 0.35));
        return sp.update(dt);
      },
      dispose: () => {
        this.giveLight(light);
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
  }

  /** Healing: sparkles rising around a body, a soft glow. */
  heal(target: THREE.Object3D, height = 1.8, color = '#7dff8f') {
    const sp = new Sparks(120, 0.16, 0.97);
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.6);
    this.scene.add(sp.points);
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        if (t < 0.9) {
          target.getWorldPosition(tmp);
          for (let i = 0; i < 4; i++) {
            const a = Math.random() * Math.PI * 2, r = (0.3 + Math.random() * 0.25) * U;
            sp.emit(new THREE.Vector3(tmp.x + Math.cos(a) * r, tmp.y + Math.random() * height * 0.6 * U, tmp.z + Math.sin(a) * r), new THREE.Vector3(0, (0.8 + Math.random() * 0.8) * U, 0), 0.9, i % 2 ? c : accent);
          }
        }
        return sp.update(dt) || t < 0.9;
      },
      dispose: () => {
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
  }

  /** Roots: thorny vines out of the ground around a creature for `ms`. */
  root(target: THREE.Object3D, ms: number, radius = 0.7) {
    const group = new THREE.Group();
    const mat = rootsMaterial();
    const n = 9;
    const vines: THREE.Mesh[] = [];
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + rnd(0.2);
      const h = (0.6 + Math.random() * 0.5) * U;
      const m = new THREE.Mesh(new THREE.ConeGeometry(0.07 * U, h, 5), mat);
      m.geometry.translate(0, h / 2, 0);
      m.position.set(Math.cos(a) * radius * U, 0, Math.sin(a) * radius * U);
      m.rotation.set(rnd(0.35) - Math.sin(a) * 0.35, 0, rnd(0.35) + Math.cos(a) * 0.35);
      m.scale.y = 0.01;
      group.add(m);
      vines.push(m);
    }
    const ring = new THREE.Mesh(new THREE.RingGeometry(radius * 0.6 * U, radius * 1.15 * U, 32), new THREE.MeshBasicMaterial({ color: '#5fdc5a', transparent: true, opacity: 0.35, depthWrite: false, side: THREE.DoubleSide }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.03 * U;
    group.add(ring);
    this.scene.add(group);
    let t = 0;
    const dur = ms / 1000;
    this.live.push({
      update: (dt) => {
        t += dt;
        target.getWorldPosition(tmp);
        group.position.set(tmp.x, tmp.y, tmp.z);
        const grow = Math.min(1, t / 0.35) * Math.min(1, Math.max(0, (dur - t) / 0.4));
        for (const v of vines) v.scale.y = Math.max(0.01, grow);
        (ring.material as THREE.MeshBasicMaterial).opacity = 0.35 * grow;
        return t < dur;
      },
      dispose: () => {
        this.scene.remove(group);
        for (const v of vines) v.geometry.dispose();
        ring.geometry.dispose();
        // (the shared roots material, and the ring's, are kept: see sparkMaterial)
      },
    });
  }

  /** Recall: a column of blue light swirling up, at the start and at the end. */
  recall(at: THREE.Vector3, color = '#7ab8ff') {
    const sp = new Sparks(220, 0.18, 0.96);
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.65);
    const light = this.takeLight(c, 8, 10 * U);
    light?.position.copy(at).add(new THREE.Vector3(0, 1.2 * U, 0));
    this.scene.add(sp.points);
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        if (t < 1.1) {
          for (let i = 0; i < 6; i++) {
            const a = t * 9 + i * 1.05, r = (0.55 - t * 0.25) * U;
            sp.emit(new THREE.Vector3(at.x + Math.cos(a) * r, at.y + Math.random() * 0.3 * U, at.z + Math.sin(a) * r), new THREE.Vector3(-Math.sin(a) * 0.6 * U, (1.6 + Math.random()) * U, Math.cos(a) * 0.6 * U), 1.0, i % 2 ? c : accent);
          }
        }
        if (light) light.intensity = Math.max(0, 8 * (1 - t / 1.6));
        return sp.update(dt) || t < 1.1;
      },
      dispose: () => {
        this.giveLight(light);
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
  }

  /** A spin attack: a glowing ring and sparks sweeping round the fighter. */
  spin(caster: THREE.Object3D, reach = 1.9, color = '#ffe8b0') {
    const geo = new THREE.RingGeometry(reach * 0.5 * U, reach * U, 48, 1, 0, Math.PI * 1.65);
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.65, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending });
    const ring = new THREE.Mesh(geo, mat);
    ring.rotation.x = -Math.PI / 2;
    const sp = new Sparks(90, 0.2, 0.9);
    const c = new THREE.Color(color);
    this.scene.add(ring, sp.points);
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        caster.getWorldPosition(tmp);
        ring.position.set(tmp.x, tmp.y + 1.0 * U, tmp.z);
        ring.rotation.z = -t * 15;
        mat.opacity = 0.65 * Math.max(0, 1 - t / 0.55);
        if (t < 0.35) {
          for (let i = 0; i < 4; i++) {
            const a = -t * 15 + i * 1.5;
            const p = new THREE.Vector3(tmp.x + Math.cos(a) * reach * 0.85 * U, tmp.y + 1.0 * U, tmp.z + Math.sin(a) * reach * 0.85 * U);
            sp.emit(p, new THREE.Vector3(-Math.sin(a) * 2 * U, rnd(0.5) * U, Math.cos(a) * 2 * U), 0.35, c);
          }
        }
        return sp.update(dt) || t < 0.55;
      },
      dispose: () => {
        this.scene.remove(ring, sp.points);
        geo.dispose();
        sp.dispose();
      },
    });
  }

  /** Area-of-Effect nova / storm / eruption / consecration at `at` with radius `radiusM` metres. */
  aoe(at: THREE.Vector3, radiusM = 5.5, color = '#ff7a1a') {
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.55);
    const rMax = Math.max(2.0, Math.min(12.0, radiusM)) * U;
    const geo = new THREE.RingGeometry(0.72, 1.0, 48);
    const mat = new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: 0.7, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending });
    const ring = new THREE.Mesh(geo, mat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(at.x, at.y + 0.08 * U, at.z);
    const sp = new Sparks(180, 0.24, 0.91, -0.3);
    for (let i = 0; i < 120; i++) {
      const a = Math.random() * Math.PI * 2;
      const dist = Math.sqrt(Math.random()) * rMax;
      const p = new THREE.Vector3(at.x + Math.cos(a) * dist, at.y + (0.1 + Math.random() * 0.6) * U, at.z + Math.sin(a) * dist);
      const v = new THREE.Vector3(Math.cos(a) * 1.8 * U, (1.4 + Math.random() * 2.4) * U, Math.sin(a) * 1.8 * U);
      sp.emit(p, v, 0.55 + Math.random() * 0.45, i % 3 ? c : accent);
    }
    const light = this.takeLight(c, 11, rMax * 1.6);
    light?.position.set(at.x, at.y + 1.2 * U, at.z);
    this.scene.add(ring, sp.points);
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        const k = Math.min(1, t / 0.55);
        const curR = Math.max(0.1, k * rMax);
        ring.scale.set(curR, curR, 1);
        mat.opacity = 0.7 * (1 - k);
        if (light) light.intensity = Math.max(0, 11 * (1 - t / 0.65));
        return sp.update(dt) || t < 0.65;
      },
      dispose: () => {
        this.giveLight(light);
        this.scene.remove(ring, sp.points);
        geo.dispose();
        sp.dispose();
      },
    });
  }

  /** Frontal cone breath / wave / shockwave along `heading`. */
  cone(caster: THREE.Object3D, heading: number, rangeM = 8.0, arcDeg = 100, color = '#ff7a1a') {
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.55);
    const sp = new Sparks(160, 0.25, 0.92);
    caster.getWorldPosition(tmp);
    const origin = new THREE.Vector3(tmp.x, tmp.y + 1.2 * U, tmp.z);
    const halfArc = ((arcDeg || 100) * Math.PI) / 360;
    const speed = Math.max(5.0, Math.min(14.0, rangeM * 1.25)) * U;
    for (let i = 0; i < 150; i++) {
      const ang = heading + rnd(halfArc);
      const spd = speed * (0.45 + Math.random() * 0.65);
      const v = new THREE.Vector3(Math.sin(ang) * spd, rnd(0.7) * U, Math.cos(ang) * spd);
      sp.emit(origin, v, 0.45 + Math.random() * 0.35, i % 3 ? c : accent);
    }
    const light = this.takeLight(c, 9, rangeM * U);
    light?.position.copy(origin);
    this.scene.add(sp.points);
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        if (light) light.intensity = Math.max(0, 9 * (1 - t / 0.5));
        return sp.update(dt);
      },
      dispose: () => {
        this.giveLight(light);
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
  }

  /** Chain lightning / bouncing arc through a list of world positions. */
  chain(points: THREE.Vector3[], color = '#a478ff') {
    if (points.length < 2) return;
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.65);
    const sp = new Sparks(180, 0.22, 0.88);
    for (let s = 0; s < points.length - 1; s++) {
      const a = points[s], b = points[s + 1];
      const steps = 22;
      for (let i = 0; i <= steps; i++) {
        const k = i / steps;
        const p = new THREE.Vector3().lerpVectors(a, b, k);
        p.x += rnd(0.18 * U);
        p.y += rnd(0.18 * U);
        p.z += rnd(0.18 * U);
        sp.emit(p, new THREE.Vector3(rnd(0.6 * U), rnd(0.6 * U), rnd(0.6 * U)), 0.35 + Math.random() * 0.2, i % 2 ? accent : c);
      }
      this.burst(b, color, 32, 2.0);
    }
    this.scene.add(sp.points);
    this.live.push({
      update: (dt) => sp.update(dt),
      dispose: () => {
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
  }

  /** Protective barrier / ward sphere around `caster` for `ms`. */
  shield(caster: THREE.Object3D, ms = 8000, color = '#5cd6ff') {
    const c = new THREE.Color(color);
    const geo = new THREE.SphereGeometry(1.05 * U, 18, 14);
    const mat = new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: 0.24, wireframe: true, depthWrite: false, blending: THREE.AdditiveBlending });
    const mesh = new THREE.Mesh(geo, mat);
    const sp = new Sparks(90, 0.15, 0.94);
    this.scene.add(mesh, sp.points);
    let t = 0;
    const dur = Math.min(ms / 1000, 6.0);
    this.live.push({
      update: (dt) => {
        t += dt;
        caster.getWorldPosition(tmp);
        mesh.position.set(tmp.x, tmp.y + 1.0 * U, tmp.z);
        mesh.rotation.y = t * 1.8;
        const fade = Math.min(1, t / 0.25) * Math.min(1, Math.max(0, (dur - t) / 0.5));
        mat.opacity = 0.24 * fade;
        if (t < dur - 0.3 && Math.random() < 0.6) {
          const a = Math.random() * Math.PI * 2;
          const p = new THREE.Vector3(tmp.x + Math.cos(a) * 0.95 * U, tmp.y + (0.3 + Math.random() * 1.4) * U, tmp.z + Math.sin(a) * 0.95 * U);
          sp.emit(p, new THREE.Vector3(0, 0.4 * U, 0), 0.5, c);
        }
        return sp.update(dt) || t < dur;
      },
      dispose: () => {
        this.scene.remove(mesh, sp.points);
        geo.dispose();
        sp.dispose();
      },
    });
  }

  /** Temporary combat buff / stance / shout aura rising around `caster`. */
  buff(caster: THREE.Object3D, color = '#ffd95e') {
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.6);
    const sp = new Sparks(110, 0.2, 0.95);
    this.scene.add(sp.points);
    let t = 0;
    this.live.push({
      update: (dt) => {
        t += dt;
        if (t < 0.75) {
          caster.getWorldPosition(tmp);
          for (let i = 0; i < 5; i++) {
            const a = t * 12 + i * 1.25;
            const r = 0.55 * U;
            const p = new THREE.Vector3(tmp.x + Math.cos(a) * r, tmp.y + (t * 1.8 + Math.random() * 0.3) * U, tmp.z + Math.sin(a) * r);
            sp.emit(p, new THREE.Vector3(Math.cos(a) * 0.4 * U, 1.4 * U, Math.sin(a) * 0.4 * U), 0.65, i % 2 ? c : accent);
          }
        }
        return sp.update(dt) || t < 0.75;
      },
      dispose: () => {
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
  }

  /** Dash / Leap / Blink / Charge trail from `from` to `to`. */
  dash(from: THREE.Vector3, to: THREE.Vector3, color = '#60b5ff') {
    const c = new THREE.Color(color);
    const accent = c.clone().lerp(new THREE.Color('#ffffff'), 0.6);
    const sp = new Sparks(140, 0.22, 0.9);
    const steps = 28;
    for (let i = 0; i <= steps; i++) {
      const k = i / steps;
      const p = new THREE.Vector3().lerpVectors(from, to, k);
      p.y += (0.8 + Math.sin(k * Math.PI) * 0.6) * U;
      for (let j = 0; j < 3; j++) {
        sp.emit(p.clone().add(new THREE.Vector3(rnd(0.2 * U), rnd(0.2 * U), rnd(0.2 * U))), new THREE.Vector3(rnd(0.8 * U), (0.4 + Math.random() * 0.8) * U, rnd(0.8 * U)), 0.45 + Math.random() * 0.25, j % 2 ? c : accent);
      }
    }
    this.burst(to.clone().add(new THREE.Vector3(0, 0.9 * U, 0)), color, 45, 2.4);
    this.scene.add(sp.points);
    this.live.push({
      update: (dt) => sp.update(dt),
      dispose: () => {
        this.scene.remove(sp.points);
        sp.dispose();
      },
    });
  }
}
