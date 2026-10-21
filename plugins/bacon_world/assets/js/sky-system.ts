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

  private readonly ORBIT_RADIUS = 55;

  constructor(scene: THREE.Scene, ambient: THREE.AmbientLight) {
    this.scene  = scene;
    this.ambient = ambient;

    // Sun
    const sunGeo = new THREE.SphereGeometry(1.8, 12, 12);
    const sunMat = new THREE.MeshBasicMaterial({ color: 0xfffde7 });
    this.sunMesh = new THREE.Mesh(sunGeo, sunMat);
    scene.add(this.sunMesh);

    this.sunLight = new THREE.DirectionalLight(0xfff4cc, 1.0);
    this.sunLight.castShadow = false;
    scene.add(this.sunLight);

    // Moon
    const moonGeo = new THREE.SphereGeometry(1.2, 12, 12);
    const moonMat = new THREE.MeshBasicMaterial({ color: 0xd0d8e8 });
    this.moonMesh = new THREE.Mesh(moonGeo, moonMat);
    scene.add(this.moonMesh);

    this.moonLight = new THREE.DirectionalLight(0x8899cc, 0.12);
    scene.add(this.moonLight);
  }

  /** Call every frame from the animate loop. */
  tick() {
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
    const R = this.ORBIT_RADIUS;
    const sx = Math.cos(sunAngle) * R;
    const sy = Math.sin(sunAngle) * R;
    this.sunMesh.position.set(sx, sy, -10);
    this.sunLight.position.copy(this.sunMesh.position);

    // Sun visible above horizon
    const sunAbove = sy > 0;
    this.sunMesh.visible = sunAbove;
    this.sunLight.intensity = sunAbove ? Math.max(0, Math.sin(sunAngle)) * 1.1 : 0;

    // ── Moon position (opposite arc) ──────────────────────────────────────────
    const moonAngle = sunAngle + Math.PI;
    const mx = Math.cos(moonAngle) * R;
    const my = Math.sin(moonAngle) * R;
    this.moonMesh.position.set(mx, my, -10);
    this.moonLight.position.copy(this.moonMesh.position);

    const moonAbove = my > 0;
    this.moonMesh.visible = moonAbove;
    this.moonLight.intensity = moonAbove ? 0.14 : 0;
  }

  dispose() {
    this.scene.remove(this.sunMesh, this.moonMesh, this.sunLight, this.moonLight);
    this.sunMesh.geometry.dispose();
    (this.sunMesh.material as THREE.Material).dispose();
    this.moonMesh.geometry.dispose();
    (this.moonMesh.material as THREE.Material).dispose();
  }
}
