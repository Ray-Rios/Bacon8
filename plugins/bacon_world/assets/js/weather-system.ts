// WeatherSystem — lightweight procedural clouds, camera-wrapping rain particle streaks,
// sky lightning bolts, and lethal ground lightning strikes with warning telegraphs.
// Built to run at 60+ FPS with 0 GPU lag (1 draw call for clouds, 1 draw call for rain).
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import type { LobbyAudio } from './lobby-audio';

const U = UNITS_PER_METRE;
const RAIN_COUNT = 360; // lightweight, fast, no GPU bus choke
const RAIN_BOX_XZ = 18 * U; // 18m local cylinder around player - drops only where visible
const RAIN_BOX_Y = 22 * U; // 22m vertical span
const RAIN_SPEED = 42 * U; // realistic natural falling speed (m/s)
const DROP_LEN = 0.28 * U; // subtle raindrop streak length
const CLOUD_ALTITUDE = 280 * U; // altitude of the cloud canopy plane
const LETHAL_RADIUS = 3.5 * U; // 3.5 metres blast radius for instant kill

// Procedural lightweight 2-octave cloud shader: 1 draw call, 2 triangles, low fillrate cost.
const CLOUD_VERT = `
  varying vec2 vUv;
  varying vec3 vWorldPos;
  void main() {
    vUv = uv;
    vec4 wp = modelMatrix * vec4(position, 1.0);
    vWorldPos = wp.xyz;
    gl_Position = projectionMatrix * viewMatrix * wp;
  }
`;

const CLOUD_FRAG = `
  uniform float time;
  uniform float rainIntensity;
  uniform float darkness;
  uniform float flash;
  varying vec2 vUv;
  varying vec3 vWorldPos;

  // Fast analytical 2D hash & noise
  float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
  }

  float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
  }

  void main() {
    vec2 uv = vUv * 5.0 + vec2(time * 0.008, time * 0.004);
    float d = 0.70 * noise(uv) + 0.30 * noise(uv * 2.3);

    float threshold = mix(0.50, 0.28, rainIntensity);
    float alpha = smoothstep(threshold, threshold + 0.30, d);

    vec3 dayCol = vec3(0.82, 0.85, 0.90);
    vec3 stormCol = vec3(0.08, 0.10, 0.14);
    vec3 baseCol = mix(dayCol, stormCol, clamp(darkness * 0.85 + rainIntensity * 0.6, 0.0, 0.92));

    vec3 flashCol = vec3(0.85, 0.95, 1.0);
    vec3 finalCol = mix(baseCol, flashCol, flash * 0.95);

    float finalAlpha = clamp(alpha * (0.15 + rainIntensity * 0.60) + flash * 0.45, 0.0, 0.85);

    gl_FragColor = vec4(finalCol, finalAlpha);
  }
`;

/** Generates jagged midpoint-displaced line points between two 3D positions */
function generateJaggedBranch(
  start: THREE.Vector3,
  end: THREE.Vector3,
  displace: number,
  depth: number,
  out: THREE.Vector3[]
) {
  if (depth <= 0) {
    out.push(start.clone(), end.clone());
    return;
  }
  const mid = new THREE.Vector3().addVectors(start, end).multiplyScalar(0.5);
  mid.x += (Math.random() - 0.5) * displace;
  mid.y += (Math.random() - 0.5) * displace * 0.4;
  mid.z += (Math.random() - 0.5) * displace;

  generateJaggedBranch(start, mid, displace * 0.55, depth - 1, out);
  generateJaggedBranch(mid, end, displace * 0.55, depth - 1, out);
}

export class WeatherSystem {
  readonly group = new THREE.Group();

  // Clouds
  private cloudsMesh: THREE.Mesh;
  private cloudsMat: THREE.ShaderMaterial;

  // Rain
  private rainMesh: THREE.LineSegments;
  private rainGeo: THREE.BufferGeometry;
  private rainPositions: Float32Array;
  private rainVelocities: Float32Array;

  // Sky lightning
  private skyBoltMesh: THREE.LineSegments;
  private skyBoltGeo: THREE.BufferGeometry;
  private skyBoltMat: THREE.LineBasicMaterial;
  private skyBoltTime = 0;

  // Lethal Ground Strike
  private telegraphGroup = new THREE.Group();
  private telegraphRing: THREE.LineLoop;
  private telegraphRingMat: THREE.LineBasicMaterial;
  private telegraphSparks: THREE.LineSegments;
  private telegraphSparksPos: Float32Array;
  private telegraphSparksGeo: THREE.BufferGeometry;

  private groundBoltMesh: THREE.LineSegments;
  private groundBoltGeo: THREE.BufferGeometry;
  private groundBoltMat: THREE.LineBasicMaterial;

  private strikeState: 'idle' | 'telegraph' | 'strike' = 'idle';
  private strikeTimer = 0;
  private nextStrikeCooldown = 14 + Math.random() * 10;
  private strikeTarget = new THREE.Vector3();

  // Internal state
  private rainIntensity = 0;
  private shelterType: 'open' | 'tree' | 'tent' | 'cabin' = 'open';
  private flashDecay = 0;

  constructor(
    private scene: THREE.Scene,
    private groundAt: (x: number, z: number) => number,
    private onLightningKill?: (targetPos: THREE.Vector3) => void,
    private audio?: LobbyAudio
  ) {
    this.group.name = 'WeatherSystem';

    // ── 1. Lightweight Overhead Cloud Plane (1 draw call, 2 triangles) ──────
    const cloudGeo = new THREE.PlaneGeometry(2800 * U, 2800 * U, 1, 1);
    this.cloudsMat = new THREE.ShaderMaterial({
      vertexShader: CLOUD_VERT,
      fragmentShader: CLOUD_FRAG,
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      fog: false,
      uniforms: {
        time: { value: 0 },
        rainIntensity: { value: 0 },
        darkness: { value: 0 },
        flash: { value: 0 },
      },
    });
    this.cloudsMesh = new THREE.Mesh(cloudGeo, this.cloudsMat);
    this.cloudsMesh.rotation.x = Math.PI / 2; // face downwards towards terrain
    this.cloudsMesh.position.y = CLOUD_ALTITUDE;
    this.cloudsMesh.renderOrder = -15; // behind normal scene, in front of sky dome
    this.group.add(this.cloudsMesh);

    // ── 2. Raindrop Line Segments (1 draw call, 2000 wrapping drops) ─────────
    this.rainPositions = new Float32Array(RAIN_COUNT * 2 * 3);
    this.rainVelocities = new Float32Array(RAIN_COUNT);

    for (let i = 0; i < RAIN_COUNT; i++) {
      const x = (Math.random() - 0.5) * RAIN_BOX_XZ;
      const y = Math.random() * RAIN_BOX_Y;
      const z = (Math.random() - 0.5) * RAIN_BOX_XZ;
      const i6 = i * 6;

      // Top vertex
      this.rainPositions[i6] = x;
      this.rainPositions[i6 + 1] = y;
      this.rainPositions[i6 + 2] = z;

      // Bottom vertex
      this.rainPositions[i6 + 3] = x;
      this.rainPositions[i6 + 4] = y - DROP_LEN;
      this.rainPositions[i6 + 5] = z;

      this.rainVelocities[i] = RAIN_SPEED * (0.85 + Math.random() * 0.3);
    }

    this.rainGeo = new THREE.BufferGeometry();
    this.rainGeo.setAttribute('position', new THREE.BufferAttribute(this.rainPositions, 3));
    const rainMat = new THREE.LineBasicMaterial({
      color: 0x6e889e, // soft translucent rain tone (not bright white)
      transparent: true,
      opacity: 0.0,
      depthWrite: false,
    });
    this.rainMesh = new THREE.LineSegments(this.rainGeo, rainMat);
    this.rainMesh.frustumCulled = false;
    this.rainMesh.visible = false;
    this.group.add(this.rainMesh);

    // ── 3. Sky Lightning Mesh ────────────────────────────────────────────────
    this.skyBoltGeo = new THREE.BufferGeometry();
    this.skyBoltMat = new THREE.LineBasicMaterial({
      color: 0xcceeFF,
      linewidth: 2,
      transparent: true,
      opacity: 0,
      depthWrite: false,
    });
    this.skyBoltMesh = new THREE.LineSegments(this.skyBoltGeo, this.skyBoltMat);
    this.skyBoltMesh.frustumCulled = false;
    this.skyBoltMesh.visible = false;
    this.group.add(this.skyBoltMesh);

    // ── 4. Lethal Ground Strike Telegraph & Bolt ────────────────────────────
    // Warning Ring (radius 3.5m)
    const ringSegs = 36;
    const ringPts: THREE.Vector3[] = [];
    for (let i = 0; i <= ringSegs; i++) {
      const a = (i / ringSegs) * Math.PI * 2;
      ringPts.push(new THREE.Vector3(Math.cos(a) * LETHAL_RADIUS, 0, Math.sin(a) * LETHAL_RADIUS));
    }
    const ringGeo = new THREE.BufferGeometry().setFromPoints(ringPts);
    this.telegraphRingMat = new THREE.LineBasicMaterial({
      color: 0x00e5ff,
      linewidth: 3,
      transparent: true,
      opacity: 0.85,
      depthWrite: false,
    });
    this.telegraphRing = new THREE.LineLoop(ringGeo, this.telegraphRingMat);
    this.telegraphGroup.add(this.telegraphRing);

    // Crackling ground spark lines inside telegraph
    const sparkCount = 12;
    this.telegraphSparksPos = new Float32Array(sparkCount * 2 * 3);
    this.telegraphSparksGeo = new THREE.BufferGeometry();
    this.telegraphSparksGeo.setAttribute('position', new THREE.BufferAttribute(this.telegraphSparksPos, 3));
    const sparksMat = new THREE.LineBasicMaterial({
      color: 0xffea00,
      linewidth: 2,
      transparent: true,
      opacity: 0.9,
      depthWrite: false,
    });
    this.telegraphSparks = new THREE.LineSegments(this.telegraphSparksGeo, sparksMat);
    this.telegraphGroup.add(this.telegraphSparks);
    this.telegraphGroup.visible = false;
    this.group.add(this.telegraphGroup);

    // Vertical Jagged Ground Lightning Bolt
    this.groundBoltGeo = new THREE.BufferGeometry();
    this.groundBoltMat = new THREE.LineBasicMaterial({
      color: 0xddffff,
      linewidth: 3,
      transparent: true,
      opacity: 1.0,
      depthWrite: false,
    });
    this.groundBoltMesh = new THREE.LineSegments(this.groundBoltGeo, this.groundBoltMat);
    this.groundBoltMesh.frustumCulled = false;
    this.groundBoltMesh.visible = false;
    this.group.add(this.groundBoltMesh);

    scene.add(this.group);
  }

  /**
   * Main per-frame update loop.
   * @param dt delta seconds
   * @param camera active PerspectiveCamera
   * @param playerPos local player's world position
   * @param rainIntensity 0.0 (clear) to 1.0 (violent thunderstorm)
   * @param shelterType player's current shelter
   * @param isDead whether player is currently dead
   */
  update(
    dt: number,
    camera: THREE.PerspectiveCamera,
    playerPos: THREE.Vector3,
    rainIntensity: number,
    shelterType: 'open' | 'tree' | 'tent' | 'cabin' = 'open',
    isDead = false
  ) {
    this.rainIntensity = rainIntensity;
    this.shelterType = shelterType;

    // ── 1. Cloud Layer Update ────────────────────────────────────────────────
    this.cloudsMesh.visible = rainIntensity > 0.02;
    if (this.cloudsMesh.visible) {
      this.cloudsMesh.position.x = camera.position.x;
      this.cloudsMesh.position.z = camera.position.z;
      this.cloudsMat.uniforms.time.value += dt;
      this.cloudsMat.uniforms.rainIntensity.value = rainIntensity;
      this.cloudsMat.uniforms.darkness.value = Math.min(1.0, rainIntensity * 1.2);

      if (this.flashDecay > 0) {
        this.flashDecay = Math.max(0, this.flashDecay - dt * 5.0);
        this.cloudsMat.uniforms.flash.value = this.flashDecay;
      } else {
        this.cloudsMat.uniforms.flash.value = 0;
      }
    }

    // ── 2. Raindrop Particle System ──────────────────────────────────────────
    if (rainIntensity <= 0.02) {
      this.rainMesh.visible = false;
    } else {
      this.rainMesh.visible = true;
      const rainMat = this.rainMesh.material as THREE.LineBasicMaterial;

      // Soft natural opacity (prevents bright white bars, smooth performance)
      let targetOpacity = 0.08 + rainIntensity * 0.22;
      if (shelterType === 'cabin') targetOpacity = 0.0;
      else if (shelterType === 'tent') targetOpacity *= 0.15;
      else if (shelterType === 'tree') targetOpacity *= 0.45;

      rainMat.opacity = targetOpacity;

      if (targetOpacity > 0.01) {
        const camX = camera.position.x;
        const camY = camera.position.y;
        const camZ = camera.position.z;
        const halfXZ = RAIN_BOX_XZ * 0.5;
        const windX = 0.06 * U; // gentle natural slant
        const windZ = 0.03 * U;

        const pos = this.rainPositions;
        for (let i = 0; i < RAIN_COUNT; i++) {
          const i6 = i * 6;
          const fall = this.rainVelocities[i] * dt;

          pos[i6 + 1] -= fall;
          pos[i6 + 4] = pos[i6 + 1] - DROP_LEN;

          // Wrap vertically
          if (pos[i6 + 1] < camY - 3 * U) {
            pos[i6 + 1] = camY + RAIN_BOX_Y * 0.75 + Math.random() * 2 * U;
            pos[i6 + 4] = pos[i6 + 1] - DROP_LEN;
            pos[i6] = camX + (Math.random() - 0.5) * RAIN_BOX_XZ;
            pos[i6 + 2] = camZ + (Math.random() - 0.5) * RAIN_BOX_XZ;
            pos[i6 + 3] = pos[i6] + windX;
            pos[i6 + 5] = pos[i6 + 2] + windZ;
            continue;
          }

          // Wrap horizontally around camera
          let dx = pos[i6] - camX;
          if (dx > halfXZ) pos[i6] -= RAIN_BOX_XZ;
          else if (dx < -halfXZ) pos[i6] += RAIN_BOX_XZ;
          pos[i6 + 3] = pos[i6] + windX;

          let dz = pos[i6 + 2] - camZ;
          if (dz > halfXZ) pos[i6 + 2] -= RAIN_BOX_XZ;
          else if (dz < -halfXZ) pos[i6 + 2] += RAIN_BOX_XZ;
          pos[i6 + 5] = pos[i6 + 2] + windZ;
        }

        this.rainGeo.attributes.position.needsUpdate = true;
      }
    }

    // ── 3. Sky Lightning Flashes ─────────────────────────────────────────────
    if (this.skyBoltTime > 0) {
      this.skyBoltTime -= dt;
      if (this.skyBoltTime <= 0) {
        this.skyBoltMesh.visible = false;
      } else {
        // rapid strobe flicker
        this.skyBoltMat.opacity = Math.random() > 0.3 ? 0.9 : 0.2;
      }
    }

    // ── 4. Lethal Ground Strike Cycle (Thunderstorms only) ───────────────────
    if (rainIntensity >= 0.70 && !isDead) {
      if (this.strikeState === 'idle') {
        this.nextStrikeCooldown -= dt;
        if (this.nextStrikeCooldown <= 0) {
          this.initiateGroundStrike(playerPos, shelterType);
        }
      } else if (this.strikeState === 'telegraph') {
        this.strikeTimer -= dt;
        this.updateTelegraphVisuals(dt);

        if (this.strikeTimer <= 0) {
          this.executeGroundStrike(playerPos, isDead);
        }
      } else if (this.strikeState === 'strike') {
        this.strikeTimer -= dt;
        if (this.strikeTimer <= 0) {
          this.groundBoltMesh.visible = false;
          this.strikeState = 'idle';
          this.nextStrikeCooldown = 15 + Math.random() * 12; // cooldown until next strike
        } else {
          this.groundBoltMat.opacity = Math.random() > 0.25 ? 1.0 : 0.3;
        }
      }
    } else {
      if (this.strikeState !== 'idle') {
        this.telegraphGroup.visible = false;
        this.groundBoltMesh.visible = false;
        this.strikeState = 'idle';
      }
    }
  }

  /** Triggers a horizontal branching lightning bolt across the cloud layer */
  triggerSkyLightning(camPos: THREE.Vector3) {
    const startX = camPos.x + (Math.random() - 0.5) * 400 * U;
    const startZ = camPos.z + (Math.random() - 0.5) * 400 * U;
    const endX = startX + (Math.random() - 0.5) * 300 * U;
    const endZ = startZ + (Math.random() - 0.5) * 300 * U;
    const y = CLOUD_ALTITUDE - 20 * U;

    const pts: THREE.Vector3[] = [];
    generateJaggedBranch(
      new THREE.Vector3(startX, y, startZ),
      new THREE.Vector3(endX, y - (Math.random() * 30 + 10) * U, endZ),
      35 * U,
      4,
      pts
    );

    // Add 2 side forks
    if (pts.length > 4) {
      const fork1 = pts[Math.floor(pts.length * 0.35)];
      generateJaggedBranch(
        fork1,
        fork1.clone().add(new THREE.Vector3((Math.random() - 0.5) * 80 * U, -25 * U, (Math.random() - 0.5) * 80 * U)),
        18 * U,
        2,
        pts
      );
    }

    this.skyBoltGeo.setFromPoints(pts);
    this.skyBoltMesh.visible = true;
    this.skyBoltTime = 0.22;
    this.flashDecay = 1.0;
  }

  /** Begins the 1.8s ground telegraph warning ring */
  private initiateGroundStrike(playerPos: THREE.Vector3, shelterType: string) {
    this.strikeState = 'telegraph';
    this.strikeTimer = 1.8; // 1.8 seconds to react and sprint away!

    let targetX = playerPos.x;
    let targetZ = playerPos.z;

    if (shelterType === 'cabin') {
      // If player is in cabin, strike outdoors nearby
      targetX += (Math.random() < 0.5 ? -1 : 1) * (20 + Math.random() * 15) * U;
      targetZ += (Math.random() < 0.5 ? -1 : 1) * (20 + Math.random() * 15) * U;
    } else {
      // 35% chance to strike directly at/near player's feet (forcing immediate evasion!)
      // 65% chance to strike 6-16 metres away for thrilling close call
      if (Math.random() < 0.35) {
        targetX += (Math.random() - 0.5) * 3.0 * U;
        targetZ += (Math.random() - 0.5) * 3.0 * U;
      } else {
        const angle = Math.random() * Math.PI * 2;
        const dist = (7 + Math.random() * 12) * U;
        targetX += Math.cos(angle) * dist;
        targetZ += Math.sin(angle) * dist;
      }
    }

    const groundY = this.groundAt(targetX, targetZ);
    this.strikeTarget.set(targetX, groundY, targetZ);

    this.telegraphGroup.position.set(targetX, groundY + 0.08 * U, targetZ);
    this.telegraphGroup.visible = true;

    // Ozone crackle audio cue
    this.audio?.play('thunder_distant', 0.5);
  }

  /** Updates the pulsing warning ring and ground crackle sparks */
  private updateTelegraphVisuals(dt: number) {
    const pulse = Math.sin((1.8 - this.strikeTimer) * 16);
    this.telegraphRingMat.color.setHex(pulse > 0 ? 0x00e5ff : 0xffea00);
    this.telegraphRingMat.opacity = 0.7 + pulse * 0.25;

    // Generate random spark lines jumping inside the lethal circle
    const pos = this.telegraphSparksPos;
    for (let i = 0; i < 12; i++) {
      const i6 = i * 6;
      const a = Math.random() * Math.PI * 2;
      const r = Math.random() * (LETHAL_RADIUS * 0.9);
      const sx = Math.cos(a) * r;
      const sz = Math.sin(a) * r;

      pos[i6] = sx;
      pos[i6 + 1] = 0.02 * U;
      pos[i6 + 2] = sz;

      pos[i6 + 3] = sx + (Math.random() - 0.5) * 0.8 * U;
      pos[i6 + 4] = (0.2 + Math.random() * 0.6) * U;
      pos[i6 + 5] = sz + (Math.random() - 0.5) * 0.8 * U;
    }
    this.telegraphSparksGeo.attributes.position.needsUpdate = true;
  }

  /** Executes the lethal lightning strike down from the heavens! */
  private executeGroundStrike(playerPos: THREE.Vector3, isDead: boolean) {
    this.telegraphGroup.visible = false;
    this.strikeState = 'strike';
    this.strikeTimer = 0.24; // bolt visible duration

    // Generate vertical jagged bolt from clouds to ground target
    const skyStart = new THREE.Vector3(
      this.strikeTarget.x + (Math.random() - 0.5) * 20 * U,
      CLOUD_ALTITUDE,
      this.strikeTarget.z + (Math.random() - 0.5) * 20 * U
    );

    const pts: THREE.Vector3[] = [];
    generateJaggedBranch(skyStart, this.strikeTarget, 24 * U, 5, pts);

    // 4 side branching forks
    if (pts.length > 8) {
      for (const frac of [0.3, 0.5, 0.7, 0.85]) {
        const rootPt = pts[Math.floor(pts.length * frac)];
        const branchEnd = rootPt.clone().add(
          new THREE.Vector3(
            (Math.random() - 0.5) * 25 * U,
            -Math.random() * 30 * U,
            (Math.random() - 0.5) * 25 * U
          )
        );
        generateJaggedBranch(rootPt, branchEnd, 12 * U, 3, pts);
      }
    }

    this.groundBoltGeo.setFromPoints(pts);
    this.groundBoltMesh.visible = true;

    // Blinding illumination flash
    this.flashDecay = 1.0;
    this.cloudsMat.uniforms.flash.value = 1.0;

    // Massive thunder clap sound
    this.audio?.play('thunder_strike', 1.0);

    // Proximity check: Is local player inside the lethal blast radius?
    if (!isDead && this.shelterType !== 'cabin') {
      const dist = Math.hypot(playerPos.x - this.strikeTarget.x, playerPos.z - this.strikeTarget.z);
      if (dist <= LETHAL_RADIUS) {
        // INSTANT LETHAL OVERKILL KILL!
        this.onLightningKill?.(this.strikeTarget);
      }
    }
  }

  dispose() {
    this.scene.remove(this.group);
    this.cloudsGeoDispose();
    this.rainGeo.dispose();
    (this.rainMesh.material as THREE.Material).dispose();
    this.skyBoltGeo.dispose();
    this.skyBoltMat.dispose();
    this.telegraphRing.geometry.dispose();
    this.telegraphRingMat.dispose();
    this.telegraphSparksGeo.dispose();
    (this.telegraphSparks.material as THREE.Material).dispose();
    this.groundBoltGeo.dispose();
    this.groundBoltMat.dispose();
  }

  private cloudsGeoDispose() {
    this.cloudsMesh.geometry.dispose();
    this.cloudsMat.dispose();
  }
}
