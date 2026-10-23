// The pre-world stage: a lit platform where the selected (or new) character stands for the
// character select screen and the creator. Drag turns the character, the wheel zooms, and
// the camera eases between framings (whole body, upper body, face) per creator tab.
// It lives in the hook's scene and is hidden while the player is in the world.
import * as THREE from '../../../../assets/js/vendor/three';
import { RoomEnvironment } from '../../../../assets/js/vendor/three-loaders';
import { Appearance, appearanceKey, normalizeAppearance } from './appearance';
import type { Gear } from './wardrobe';
import { HumanFactory, HumanInstance } from './human-factory';
import { UNITS_PER_METRE } from './controls-math';

export type Framing = 'full' | 'upper' | 'face';

// Target height (in metres of a 1.8 m body) and distance (units) per framing.
const FRAMES: Record<Framing, { y: number; dist: number }> = {
  full: { y: 0.88, dist: 5.7 },
  upper: { y: 1.3, dist: 2.9 },
  face: { y: 1.6, dist: 1.6 },
};

const BACKDROP_VERT = /* glsl */ `
varying vec3 vPos;
void main() { vPos = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;
const BACKDROP_FRAG = /* glsl */ `
varying vec3 vPos;
uniform vec3 top; uniform vec3 mid; uniform vec3 bottom;
void main() {
  float h = normalize(vPos).y;
  vec3 c = h > 0.0 ? mix(mid, top, smoothstep(0.0, 0.65, h)) : mix(mid, bottom, smoothstep(0.0, 0.35, -h));
  // soft vignette toward the sides
  float side = abs(normalize(vPos).x);
  c *= 1.0 - 0.25 * smoothstep(0.4, 1.0, side);
  gl_FragColor = vec4(c, 1.0);
}`;

export class CharacterStage {
  readonly group = new THREE.Group();
  private instance: HumanInstance | null = null;
  private instanceKey = '';
  private mixer: THREE.AnimationMixer | null = null;
  private gear: Gear | null = null;
  private idle: THREE.AnimationAction | null = null;
  private pending = 0;
  private visible = false;
  private yaw = 0.35;
  private yawVel = 0;
  private dragging = false;
  private lastX = 0;
  private framing: Framing = 'full';
  private zoom = 1;
  private camTarget = new THREE.Vector3();
  private camPos = new THREE.Vector3();
  private camReady = false;
  private envTex: THREE.Texture | null = null;
  private prevEnv: THREE.Texture | null = null;
  private prevFov = 60;
  private prevFog: THREE.Fog | THREE.FogExp2 | null = null;
  private prevBg: THREE.Color | THREE.Texture | null = null;
  private offsetPx = { left: 0, right: 0, top: 0, bottom: 0 };
  private ring: THREE.Mesh;
  private dust: THREE.Points;
  private t = 0;
  onLoading: ((loading: boolean) => void) | null = null;

  constructor(private scene: THREE.Scene, private camera: THREE.PerspectiveCamera, private renderer: THREE.WebGLRenderer, private factory: HumanFactory) {
    this.group.name = 'CharacterStage';
    this.group.visible = false;

    const backdrop = new THREE.Mesh(
      new THREE.SphereGeometry(60, 32, 16),
      new THREE.ShaderMaterial({
        vertexShader: BACKDROP_VERT,
        fragmentShader: BACKDROP_FRAG,
        side: THREE.BackSide,
        depthWrite: false,
        uniforms: {
          top: { value: new THREE.Color('#0E1A30') },
          mid: { value: new THREE.Color('#1E3D6E') },
          bottom: { value: new THREE.Color('#07090E') },
        },
      })
    );
    backdrop.renderOrder = -10;
    this.group.add(backdrop);

    // floor: a wide dark disc fading out, and the platform with a glowing rim
    const floorTex = radialTexture([[0, 'rgba(36,125,241,0.22)'], [0.35, 'rgba(20,41,74,0.55)'], [1, 'rgba(7,9,14,0)']]);
    const floor = new THREE.Mesh(new THREE.CircleGeometry(14, 64), new THREE.MeshBasicMaterial({ map: floorTex, transparent: true, depthWrite: false }));
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -0.002;
    this.group.add(floor);

    const plat = new THREE.Mesh(
      new THREE.CylinderGeometry(1.05, 1.14, 0.14, 64),
      new THREE.MeshStandardMaterial({ color: '#1A2233', roughness: 0.55, metalness: 0.2 })
    );
    plat.position.y = -0.07;
    plat.receiveShadow = true;
    this.group.add(plat);
    this.ring = new THREE.Mesh(
      new THREE.TorusGeometry(1.1, 0.016, 8, 96),
      new THREE.MeshBasicMaterial({ color: '#247DF1', transparent: true, opacity: 0.85 })
    );
    this.ring.rotation.x = -Math.PI / 2;
    this.ring.position.y = 0.005;
    this.group.add(this.ring);
    const shadow = new THREE.Mesh(
      new THREE.CircleGeometry(0.75, 48),
      new THREE.MeshBasicMaterial({ map: radialTexture([[0, 'rgba(0,0,0,0.55)'], [0.6, 'rgba(0,0,0,0.2)'], [1, 'rgba(0,0,0,0)']]), transparent: true, depthWrite: false })
    );
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = 0.006;
    this.group.add(shadow);

    // lights: warm key, cool fill, brand-blue rim
    const hemi = new THREE.HemisphereLight('#E7F1FD', '#14100F', 0.55);
    const key = new THREE.DirectionalLight('#FFF1E0', 2.1);
    key.position.set(2.5, 5, 4);
    const fill = new THREE.DirectionalLight('#BFD8FF', 0.55);
    fill.position.set(-4, 2.5, 3);
    const rim = new THREE.DirectionalLight('#5FA2FF', 1.6);
    rim.position.set(-2.5, 3.5, -4.5);
    const rim2 = new THREE.DirectionalLight('#E7F1FD', 0.7);
    rim2.position.set(3, 2, -4);
    this.group.add(hemi, key, fill, rim, rim2);

    // slow dust motes
    const n = 220;
    const pos = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) {
      const r = 2 + Math.random() * 9;
      const a = Math.random() * Math.PI * 2;
      pos[i * 3] = Math.cos(a) * r;
      pos[i * 3 + 1] = Math.random() * 6;
      pos[i * 3 + 2] = Math.sin(a) * r - 2;
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    this.dust = new THREE.Points(g, new THREE.PointsMaterial({ color: '#9CC4FF', size: 0.035, transparent: true, opacity: 0.55, depthWrite: false }));
    this.group.add(this.dust);

    scene.add(this.group);
    this.onPointerDown = this.onPointerDown.bind(this);
    this.onPointerMove = this.onPointerMove.bind(this);
    this.onPointerUp = this.onPointerUp.bind(this);
    this.onWheel = this.onWheel.bind(this);
  }

  get isVisible() {
    return this.visible;
  }

  show() {
    if (this.visible) return;
    this.visible = true;
    this.group.visible = true;
    this.prevFov = this.camera.fov;
    this.camera.fov = 30;
    this.camera.updateProjectionMatrix();
    this.prevEnv = this.scene.environment;
    this.prevFog = this.scene.fog;
    this.prevBg = this.scene.background as any;
    if (!this.envTex) {
      const pm = new THREE.PMREMGenerator(this.renderer);
      this.envTex = pm.fromScene(new RoomEnvironment(), 0.04).texture;
      pm.dispose();
    }
    this.scene.environment = this.envTex;
    (this.scene as any).environmentIntensity = 0.45;
    this.scene.fog = null;
    this.camReady = false;
    const el = this.renderer.domElement;
    el.addEventListener('pointerdown', this.onPointerDown);
    window.addEventListener('pointermove', this.onPointerMove);
    window.addEventListener('pointerup', this.onPointerUp);
    el.addEventListener('wheel', this.onWheel, { passive: false });
    this.applyViewOffset();
  }

  hide() {
    if (!this.visible) return;
    this.visible = false;
    this.group.visible = false;
    this.camera.fov = this.prevFov || 60;
    this.camera.clearViewOffset();
    this.camera.updateProjectionMatrix();
    this.scene.environment = this.prevEnv;
    (this.scene as any).environmentIntensity = 1;
    this.scene.fog = this.prevFog;
    if (this.prevBg) this.scene.background = this.prevBg;
    const el = this.renderer.domElement;
    el.removeEventListener('pointerdown', this.onPointerDown);
    window.removeEventListener('pointermove', this.onPointerMove);
    window.removeEventListener('pointerup', this.onPointerUp);
    el.removeEventListener('wheel', this.onWheel);
    this.clear();
  }

  /** Shows a character with this look. Same body: updated in place; else rebuilt. */
  async setAppearance(raw: Appearance | unknown, fallbackBody: 'male' | 'female' = 'male', gear: Gear | null = null) {
    const a = normalizeAppearance(raw, fallbackBody);
    this.gear = gear;
    const key = appearanceKey(a);
    if (key === this.instanceKey && this.instance) {
      this.instance.setWorn(gear);
      return;
    }
    this.instanceKey = key;
    if (this.instance && this.instance.body === a.body) {
      this.instance.setWorn(gear);
      await this.instance.apply(a);
      return;
    }
    const ticket = ++this.pending;
    this.onLoading?.(true);
    try {
      const inst = await this.factory.create(a, 'male', this.gear);
      if (ticket !== this.pending || !this.visible) {
        inst.dispose();
        return;
      }
      this.clear(false);
      this.instance = inst;
      inst.root.rotation.y = this.yaw;
      this.group.add(inst.root);
      this.mixer = new THREE.AnimationMixer(inst.root);
      const idle = inst.clips.find((c) => c.name === 'Idle_Loop') || inst.clips[0];
      if (idle) {
        this.idle = this.mixer.clipAction(idle);
        this.idle.play();
      }
      // a later edit may have arrived while this body was loading
      inst.setWorn(this.gear);
      if (this.instanceKey !== key) await inst.apply(JSON.parse(this.instanceKey));
    } catch (err) {
      console.warn('[stage] could not build the character', err);
    } finally {
      if (ticket === this.pending) this.onLoading?.(false);
    }
  }

  /** Plays a clip once (e.g. "Yes" after creating), then back to idle. */
  gesture(name: string) {
    if (!this.instance || !this.mixer || !this.idle) return;
    const clip = this.instance.clips.find((c) => c.name === name);
    if (!clip) return;
    const act = this.mixer.clipAction(clip);
    act.reset();
    act.setLoop(THREE.LoopOnce, 1);
    act.clampWhenFinished = false;
    act.crossFadeFrom(this.idle, 0.2, false);
    act.play();
    const done = (e: any) => {
      if (e.action !== act) return;
      this.mixer?.removeEventListener('finished', done);
      this.idle?.reset().play();
      this.idle?.crossFadeFrom(act, 0.3, false);
    };
    this.mixer.addEventListener('finished', done);
  }

  setFraming(f: Framing) {
    this.framing = f;
    this.zoom = 1;
  }

  /** Pixels covered by UI panels on each side, so the character stays centred in the rest. */
  setInsets(left: number, right: number, top = 0, bottom = 0) {
    this.offsetPx = { left, right, top, bottom };
    this.applyViewOffset();
  }

  applyViewOffset() {
    if (!this.visible) return;
    const el = this.renderer.domElement;
    const w = el.clientWidth || 1;
    const h = el.clientHeight || 1;
    const sx = (this.offsetPx.right - this.offsetPx.left) / 2;
    const sy = (this.offsetPx.bottom - this.offsetPx.top) / 2;
    if (Math.abs(sx) < 1 && Math.abs(sy) < 1) this.camera.clearViewOffset();
    else this.camera.setViewOffset(w, h, sx, sy, w, h);
    this.camera.updateProjectionMatrix();
  }

  // How much of the canvas height the UI leaves for the character (0..1), and the aspect.
  private freeFraction() {
    const el = this.renderer.domElement;
    const h = el.clientHeight || 1;
    const w = el.clientWidth || 1;
    const freeH = Math.max(0.25, 1 - (this.offsetPx.top + this.offsetPx.bottom) / h);
    const freeW = Math.max(0.25, 1 - (this.offsetPx.left + this.offsetPx.right) / w);
    return { freeH, aspect: (w * freeW) / (h * freeH) };
  }

  private clear(resetKey = true) {
    if (this.instance) {
      this.mixer?.stopAllAction();
      this.instance.dispose();
    }
    this.instance = null;
    this.mixer = null;
    this.idle = null;
    if (resetKey) this.instanceKey = '';
  }

  update(dt: number) {
    if (!this.visible) return;
    this.t += dt;
    this.mixer?.update(dt);
    // the bones the morphs move, the posture correction and relaxed hands
    this.instance?.postAnimate(dt);
    if (!this.dragging) {
      this.yawVel *= Math.pow(0.04, dt);
      this.yaw += this.yawVel * dt;
    }
    if (this.instance) this.instance.root.rotation.y = this.yaw;
    (this.ring.material as THREE.MeshBasicMaterial).opacity = 0.65 + 0.2 * Math.sin(this.t * 1.6);
    this.dust.rotation.y += dt * 0.02;

    const h = (this.instance?.appearance.height || 1) * (this.instance?.body === 'female' ? 1.7 / 1.8 : 1);
    const f = FRAMES[this.framing];
    const ty = f.y * h * UNITS_PER_METRE * 1.0;
    // Narrow or partly covered views pull the camera back so the whole framing fits.
    const { freeH, aspect } = this.freeFraction();
    const fit = Math.max(1 / freeH, aspect < 0.75 ? 0.75 / Math.max(aspect, 0.3) : 1);
    const dist = f.dist * this.zoom * Math.min(fit, 2.6);
    const goalT = new THREE.Vector3(0, ty, 0);
    const goalP = new THREE.Vector3(0, ty + dist * 0.06, dist);
    const k = this.camReady ? 1 - Math.pow(0.002, dt) : 1;
    this.camTarget.lerp(goalT, k);
    this.camPos.lerp(goalP, k);
    this.camReady = true;
    this.camera.position.copy(this.camPos);
    this.camera.lookAt(this.camTarget);
  }

  private onPointerDown(e: PointerEvent) {
    if (e.button !== 0) return;
    this.dragging = true;
    this.lastX = e.clientX;
    this.yawVel = 0;
  }

  private onPointerMove(e: PointerEvent) {
    if (!this.dragging) return;
    const dx = e.clientX - this.lastX;
    this.lastX = e.clientX;
    const d = dx * 0.012;
    this.yaw += d;
    this.yawVel = d * 60;
  }

  private onPointerUp() {
    this.dragging = false;
  }

  private onWheel(e: WheelEvent) {
    e.preventDefault();
    this.zoom = Math.min(1.6, Math.max(0.45, this.zoom * Math.exp(e.deltaY * 0.0012)));
  }

  dispose() {
    this.hide();
    this.scene.remove(this.group);
    this.envTex?.dispose();
    this.group.traverse((o: any) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m: any) => { m.map?.dispose(); m.dispose(); });
    });
  }
}

function radialTexture(stops: Array<[number, string]>): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const ctx = c.getContext('2d')!;
  const g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
  for (const [o, col] of stops) g.addColorStop(o, col);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 256, 256);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
