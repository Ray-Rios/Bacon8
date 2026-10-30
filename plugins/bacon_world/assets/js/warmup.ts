// Shaders built before they are needed (2026-10-30).
//
// The first time an effect is drawn, three.js compiles its shader: tens to hundreds of
// milliseconds, and on a slow GPU or software WebGL whole seconds, all on the frame the effect
// appears (a drake's first breath, the first fireball, the Kraken's first ink). warmUp() compiles a
// stand-in for every effect material kind while the world loads, against the world's own lights, so
// those frames find the programs ready. A stand-in only has to match the material's *kind* (its type,
// and whether it has a map, vertex colours, size attenuation...): values like colour and size are
// uniforms and share the program.
//
// watchShaders() then reports any program built later during play: in the console as
// "[bacon world] shader compiled during play", with the material type, so a new effect that missed the
// warm-up shows up in testing rather than as a player's freeze.
import * as THREE from '../../../../assets/js/vendor/three';

function dotTexture(): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = c.height = 4;
  return new THREE.CanvasTexture(c);
}

/** One small object per effect material kind (spell-fx.ts, dragon-view.ts, kraken-view.ts, arrows, nameplates). */
function standIns(): THREE.Object3D[] {
  const tex = dotTexture();
  const pts = (m: THREE.PointsMaterial, colours: boolean) => {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(3), 3));
    if (colours) g.setAttribute('color', new THREE.BufferAttribute(new Float32Array(3), 3));
    return new THREE.Points(g, m);
  };
  const quad = () => new THREE.PlaneGeometry(1, 1);
  return [
    // sparks, fireballs, heals (spell-fx.ts) and the dragons' fire breath (dragon-view.ts)
    pts(new THREE.PointsMaterial({ size: 1, map: tex, vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true }), true),
    // the Kraken's ink (map, no vertex colours) and its bubbles (no map)
    pts(new THREE.PointsMaterial({ size: 1, map: tex, transparent: true, depthWrite: false, sizeAttenuation: true }), false),
    pts(new THREE.PointsMaterial({ size: 1, transparent: true, depthWrite: false, sizeAttenuation: true }), false),
    // the maelstrom's swirl, the fireball's core, rings and shockwaves
    new THREE.Mesh(quad(), new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false })),
    new THREE.Mesh(quad(), new THREE.MeshBasicMaterial({ color: '#ffffff', transparent: true, side: THREE.DoubleSide, depthWrite: false })),
    // the roots' vines (lit, emissive)
    new THREE.Mesh(quad(), new THREE.MeshStandardMaterial({ color: '#3f7a2a', roughness: 0.8, emissive: '#16300c' })),
    // halos and names (sprites: additive with a map, and plain)
    new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending })),
    new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, depthTest: false })),
  ];
}

/**
 * Compiles every effect's shader against `scene`'s lights (call once the world's lights, the
 * LightPool included, are in place). Returns how many programs it built.
 */
export function warmUp(renderer: THREE.WebGLRenderer, scene: THREE.Scene, camera: THREE.Camera): number {
  const before = renderer.info.programs?.length ?? 0;
  const group = new THREE.Scene();
  const objs = standIns();
  objs.forEach((o) => group.add(o));
  try {
    // compile the stand-ins with the world scene's lights (three r160+: the third argument)
    renderer.compile(group, camera, scene);
  } catch (err) {
    console.warn('[bacon world] warm-up skipped', err);
  }
  // the programs stay cached; the stand-ins' own buffers go
  objs.forEach((o: any) => {
    o.geometry?.dispose?.();
  });
  return (renderer.info.programs?.length ?? 0) - before;
}

/**
 * Reports shaders compiled after `armAfterMs` (by then the world has loaded). Returns a stop function.
 * Cheap: it compares one array length every two seconds.
 */
export function watchShaders(renderer: THREE.WebGLRenderer, armAfterMs = 20000): () => void {
  let known = new Set<unknown>();
  let armed = false;
  const arm = setTimeout(() => {
    known = new Set(renderer.info.programs || []);
    armed = true;
  }, armAfterMs);
  const timer = setInterval(() => {
    if (!armed) return;
    const progs: any[] = (renderer.info.programs as any[]) || [];
    if (progs.length === known.size) return;
    for (const p of progs) {
      if (known.has(p)) continue;
      known.add(p);
      console.info('[bacon world] shader compiled during play:', p.name || p.type || 'unknown', '- add a stand-in for it to warmup.ts');
    }
  }, 2000);
  return () => {
    clearTimeout(arm);
    clearInterval(timer);
  };
}
