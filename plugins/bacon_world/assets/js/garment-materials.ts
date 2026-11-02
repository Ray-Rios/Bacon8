// The three.js side of garment parts (garment-parts.ts): fabric materials tinted for an item.
import * as THREE from '../../../../assets/js/vendor/three';
import { FabricMeta, roleColor } from './garment-parts';

export type FabricTextures = (fabric: string, kind: 'c' | 'n' | 'r') => Promise<THREE.Texture | null>;

/** A material for a garment surface, tinted for an item. Textures arrive asynchronously. */
export function fabricMaterial(meta: FabricMeta, colors: Record<string, string>, tex: FabricTextures, name = ''): THREE.MeshStandardMaterial {
  const physical = (meta.sheen || 0) > 0;
  const m: THREE.MeshStandardMaterial = physical ? new THREE.MeshPhysicalMaterial() : new THREE.MeshStandardMaterial();
  m.name = name || `${meta.role || 'main'}:${meta.fabric || ''}`;
  m.userData.b8 = meta;
  tintFabric(m, meta, colors);
  m.roughness = meta.rough ?? 1;
  m.metalness = Math.min(meta.metal ?? 0, 0.85);
  // polished plate and jewellery (2026-11-01): the world's environment light is dim (0.12-0.47), and a pure
  // metal shows only what it reflects, so metals take more of it and keep a little of their own colour
  if ((meta.metal ?? 0) > 0.5) m.envMapIntensity = 2.2;
  m.side = THREE.DoubleSide;
  if (physical) {
    const p = m as THREE.MeshPhysicalMaterial;
    p.sheen = meta.sheen || 0;
    p.sheenRoughness = meta.sheenRough ?? 0.5;
  }
  if (meta.alpha) {
    // lace and tulle: the net is a veil over the skin, so blend rather than cut it out
    m.transparent = true;
    m.alphaTest = 0.03;
    m.depthWrite = false;
  }
  if (meta.opacity != null && meta.opacity < 1) {
    m.transparent = true;
    m.opacity = meta.opacity;
    m.depthWrite = false;
  }
  const f = meta.fabric;
  if (f) {
    void tex(f, 'c').then((t) => {
      if (!t) return;
      m.map = t;
      m.needsUpdate = true;
    });
    if (meta.normal !== false) {
      void tex(f, 'n').then((t) => {
        if (!t) return;
        m.normalMap = t;
        const s = meta.normalScale ?? 1;
        m.normalScale.set(s, -s); // OpenGL-convention maps on glTF UVs
        m.needsUpdate = true;
      });
    }
    if (meta.roughMap) {
      void tex(f, 'r').then((t) => {
        if (!t) return;
        m.roughnessMap = t;
        m.needsUpdate = true;
      });
    }
  }
  return m;
}

/** Sets a garment material's colour for an item (the texture's mean is brought to the colour). */
export function tintFabric(m: THREE.MeshStandardMaterial, meta: FabricMeta, colors: Record<string, string>) {
  m.color.set(roleColor(meta, colors));
  const gain = meta.natural || meta.metal ? 1 : meta.gain ?? 1;
  if (gain !== 1) m.color.multiplyScalar(gain);
  const p = m as THREE.MeshPhysicalMaterial;
  if ((p as any).isMeshPhysicalMaterial && p.sheen) p.sheenColor.set(roleColor(meta, colors)).lerp(new THREE.Color(1, 1, 1), 0.35);
}
