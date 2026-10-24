import * as THREE from '../../../../assets/js/vendor/three';

/**
 * SkySystem — server-synced day/night cycle.
 *
 * One full cycle = 1 real hour, anchored to wall-clock time so all players
 * always see the same sky regardless of when they joined.
 *
 * t=0.00 → midnight  (dark)
 * t=0.25 → sunrise   (orange glow)
 * t=0.50 → noon      (bright blue)
 * t=0.75 → sunset    (orange/red)
 * t=1.00 → midnight  (wraps)
 */

const CYCLE_MS = 60 * 60 * 1000; // 1 real hour

// Sky-colour key-frames  [t,  r, g, b] (0-255)
const SKY_KEYS: [number, number, number, number][] = [
  [0.00, 0,   3,  16],  // midnight
  [0.20, 0,   3,  16],  // late night
  [0.24, 20,  10,  30],  // pre-dawn
  [0.27, 110, 40,  20],  // dawn
  [0.33, 120, 140, 200], // morning
  [0.45, 74, 144, 217], // day
  [0.55, 74, 144, 217], // day
  [0.67, 120, 140, 200], // afternoon
  [0.73, 110, 60,  20],  // dusk
  [0.76, 100, 30,  10],  // late dusk
  [0.80, 0,   3,  16],  // night falls
  [1.00, 0,   3,  16],  // midnight
];

// Ambient-light intensity key-frames  [t, intensity]
const AMBIENT_KEYS: [number, number][] = [
  [0.00, 0.04],
  [0.20, 0.04],
  [0.27, 0.25],
  [0.33, 0.55],
  [0.45, 0.85],
  [0.55, 0.85],
  [0.67, 0.55],
  [0.73, 0.25],
  [0.80, 0.04],
  [1.00, 0.04],
];

function sampleKeys1D(keys: [number, number][], t: number): number {
  for (let i = 0; i < keys.length - 1; i++) {
    const [t0, v0] = keys[i];
    const [t1, v1] = keys[i + 1];
    if (t >= t0 && t <= t1) {
      const alpha = (t - t0) / (t1 - t0);
      return v0 + (v1 - v0) * alpha;
    }
  }
  return keys[keys.length - 1][1];
}

function sampleSkyColor(keys: [number, number, number, number][], t: number): THREE.Color {
  for (let i = 0; i < keys.length - 1; i++) {
    const [t0, r0, g0, b0] = keys[i];
    const [t1, r1, g1, b1] = keys[i + 1];
    if (t >= t0 && t <= t1) {
      const a = (t - t0) / (t1 - t0);
      return new THREE.Color(
        (r0 + (r1 - r0) * a) / 255,
        (g0 + (g1 - g0) * a) / 255,
        (b0 + (b1 - b0) * a) / 255
      );
    }
  }
  const last = keys[keys.length - 1];
  return new THREE.Color(last[1] / 255, last[2] / 255, last[3] / 255);
}

export class SkySystem {
  scene: THREE.Scene;
  sunMesh: THREE.Mesh;
  moonMesh: THREE.Mesh;
  sunLight: THREE.DirectionalLight;
  moonLight: THREE.DirectionalLight;
  ambient: THREE.AmbientLight;

  // The sun and moon sit far out along their direction from the camera, just inside its far
  // plane, so they look like they are in the sky rather than over the next field (2026-10-23:
  // they circled 55 units from the plaza, inside the village). Angular sizes in degrees.
  private readonly SUN_DEG = 3.2;
  private readonly MOON_DEG = 2.4;
  private readonly TILT = -0.25; // the arc leans a little to the south (-z)

  constructor(scene: THREE.Scene, ambient: THREE.AmbientLight) {
    this.scene  = scene;
    this.ambient = ambient;

    // Sun
    const sunGeo = new THREE.SphereGeometry(1, 16, 12);
    // fog: false - the village's scene fog (world-dressing.ts) would tint a far-off
    // sun toward the sky colour, which made it look green against the blue.
    const sunMat = new THREE.MeshBasicMaterial({ color: 0xfffde7, fog: false, depthWrite: false });
    this.sunMesh = new THREE.Mesh(sunGeo, sunMat);
    scene.add(this.sunMesh);

    this.sunLight = new THREE.DirectionalLight(0xfff4cc, 1.0);
    this.sunLight.castShadow = false;
    scene.add(this.sunLight);

    // Moon
    const moonGeo = new THREE.SphereGeometry(1, 16, 12);
    const moonMat = new THREE.MeshBasicMaterial({ color: 0xd0d8e8, fog: false, depthWrite: false });
    this.moonMesh = new THREE.Mesh(moonGeo, moonMat);
    scene.add(this.moonMesh);

    this.moonLight = new THREE.DirectionalLight(0x8899cc, 0.12);
    scene.add(this.moonLight);
  }

  /** Call every frame from the animate loop (with the camera, so the sun stays in the sky). */
  tick(camera?: THREE.PerspectiveCamera) {
    const t = (Date.now() % CYCLE_MS) / CYCLE_MS; // 0→1 over the cycle

    // ── Sky colour ────────────────────────────────────────────────────────────
    (this.scene.background as THREE.Color)?.copy?.(sampleSkyColor(SKY_KEYS, t));
    if (!(this.scene.background instanceof THREE.Color)) {
      this.scene.background = sampleSkyColor(SKY_KEYS, t);
    } else {
      this.scene.background.copy(sampleSkyColor(SKY_KEYS, t));
    }

    // ── Ambient ───────────────────────────────────────────────────────────────
    this.ambient.intensity = sampleKeys1D(AMBIENT_KEYS, t);

    // ── Sun position ──────────────────────────────────────────────────────────
    // sunAngle: 0→sunrise at +x horizon, PI/2→zenith, PI→sunset at -x horizon
    const sunAngle = (t - 0.25) * 2 * Math.PI;
    const sunDir = new THREE.Vector3(Math.cos(sunAngle), Math.sin(sunAngle), this.TILT).normalize();
    this.place(this.sunMesh, sunDir, this.SUN_DEG, camera);
    this.sunLight.position.copy(sunDir).multiplyScalar(100);
    const sy = sunDir.y;

    // Sun visible above horizon
    const sunAbove = sy > 0;
    this.sunMesh.visible = sunAbove;
    this.sunLight.intensity = sunAbove ? Math.max(0, Math.sin(sunAngle)) * 1.1 : 0;

    // ── Moon position (opposite arc) ──────────────────────────────────────────
    const moonAngle = sunAngle + Math.PI;
    const moonDir = new THREE.Vector3(Math.cos(moonAngle), Math.sin(moonAngle), this.TILT).normalize();
    this.place(this.moonMesh, moonDir, this.MOON_DEG, camera);
    this.moonLight.position.copy(moonDir).multiplyScalar(100);
    const my = moonDir.y;

    const moonAbove = my > 0;
    this.moonMesh.visible = moonAbove;
    this.moonLight.intensity = moonAbove ? 0.14 : 0;
  }

  // Far along `dir` from the camera (90% of its far plane), scaled to `deg` across.
  private place(mesh: THREE.Mesh, dir: THREE.Vector3, deg: number, camera?: THREE.PerspectiveCamera) {
    const dist = camera ? camera.far * 0.9 : 500;
    const origin = camera ? camera.position : new THREE.Vector3();
    mesh.position.copy(origin).addScaledVector(dir, dist);
    mesh.scale.setScalar(dist * Math.tan(THREE.MathUtils.degToRad(deg / 2)));
  }

  dispose() {
    this.scene.remove(this.sunMesh, this.moonMesh, this.sunLight, this.moonLight);
    this.sunMesh.geometry.dispose();
    (this.sunMesh.material as THREE.Material).dispose();
    this.moonMesh.geometry.dispose();
    (this.moonMesh.material as THREE.Material).dispose();
  }
}
