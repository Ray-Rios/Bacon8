// The skill tree drawn as SVG (BaconWorld.SkillTree's shape: nodes in rings around the
// start, edges between them), shared by the in-game skill window (skills-ui.ts, K) and
// the admin editor (skill-tree-editor.ts, /admin/bacon_world/skills). It pans (drag the
// background) and zooms (wheel); the caller decides how each node looks (its state)
// and what clicks and drags do.

export interface TreeNode { id: string; x: number; y: number; ability: string | null }
export interface Tree { start: string; nodes: TreeNode[]; edges: Array<[string, string]> }
export interface Ability {
  id: string;
  name: string;
  kind: 'spell' | 'skill' | 'buff';
  school?: string;
  icon: string;
  summary: string;
  order?: number;
  mp?: number;
  cast_ms?: number;
  cooldown_ms?: number;
  target?: string;
  range_m?: number;
  effect?: { type: string; stat?: string; amount?: number; ms?: number; duration_ms?: number };
}
export type Catalog = Record<string, Ability>;
export type NodeState = 'learned' | 'available' | 'locked' | 'edit' | 'selected';

/** School and archetype radial gradients matching the spell & skill icon sheets. */
export const SCHOOL_COLORS: Record<string, [string, string]> = {
  // Spell schools (glossy circles)
  arcane: ['#c46bff', '#5b1ea8'],
  fire: ['#ff8833', '#9e2608'],
  frost: ['#63d2ff', '#1458a6'],
  storm: ['#9f78ff', '#3a228a'],
  holy: ['#ffd45e', '#94620a'],
  nature: ['#5fe069', '#196923'],
  shadow: ['#9e54eb', '#371163'],
  blood: ['#ff4747', '#820b12'],
  earth: ['#c99359', '#593716'],
  water: ['#45bdff', '#0f528a'],
  // Combat skill archetypes (glossy rounded squares)
  blade: ['#9ea9b8', '#3c444f'],
  berserk: ['#f55838', '#7d1909'],
  blunt: ['#cca068', '#593c18'],
  polearm: ['#59a9e6', '#1b4973'],
  rogue: ['#8868bd', '#2f1c54'],
  archery: ['#7ac952', '#2b5e14'],
  shield: ['#dbb346', '#694e0c'],
  monk: ['#e0a14f', '#6b3e0d'],
  warlord: ['#e3493b', '#6e1109'],
  survival: ['#6ca854', '#264a18'],
  // Passive buffs
  passive: ['#dec068', '#664f14'],
  buff: ['#dec068', '#664f14'],
};

export const KIND_COLORS: Record<string, [string, string]> = {
  spell: ['#3b6fd8', '#14285a'],
  skill: ['#c2492f', '#4a160c'],
  buff: ['#c9a442', '#4a3a10'],
  none: ['#55504a', '#1c1a17'],
};

/** Crisp white inner SVG glyphs (24x24 viewBox) for every spell, skill and buff icon. */
export const GLYPHS: Record<string, string> = {
  portal: '<ellipse cx="12" cy="12" rx="5.5" ry="8" fill="none" stroke="#fff" stroke-width="2.6"/><ellipse cx="12" cy="12" rx="2" ry="4" fill="#fff" opacity=".45"/>',
  flame: '<path fill="#fff" d="M12.5 3C12.5 3 18 8.2 18 13.5a6 6 0 0 1-12 0C6 9.8 8.5 7 9.5 5.8c0 2.2 1.5 3.2 1.8 3.2.5-2.5 1.2-6 1.2-6zm-.5 11a2.5 2.5 0 0 0-2.5 2.5c0 1.4 1.1 2.5 2.5 2.5s2.5-1.1 2.5-2.5S13.4 14 12 14z"/>',
  beam: '<path fill="#fff" d="M19 4L5 18l1.5 1.5L20.5 5.5 19 4zM16 3l-9 9 1.2 1.2 9-9L16 3zm4.8 4.2l-9 9 1.2 1.2 9-9-1.2-1.2z"/><circle cx="6.5" cy="17.5" r="2.3" fill="#fff"/>',
  burst: '<polygon fill="#fff" points="12,2 14.3,8.2 20.8,6.2 16.5,11.5 21.5,16 15,15.3 14.5,21.8 11.2,16.2 5.5,19.8 8.2,13.6 2.5,11 8.8,9.2 6.8,3.5 11.5,7.8"/>',
  meteor: '<circle cx="8.5" cy="15.5" r="4.2" fill="#fff"/><path fill="#fff" d="M11.5 11L20 3.5 16.5 11l4.5-2.5-6.5 7z"/>',
  pillar: '<path fill="#fff" d="M7 20h10l-2-13H9L7 20zm-2 0h14v2H5v-2zm7-17l3 3H9l3-3z"/>',
  shield: '<path fill="#fff" d="M12 3L5 6v5.5C5 16.5 8 20.3 12 22c4-1.7 7-5.5 7-10.5V6l-7-3z"/>',
  shield_star: '<path fill="#fff" d="M12 3L5 6v5.5C5 16.5 8 20.3 12 22c4-1.7 7-5.5 7-10.5V6l-7-3zm0 4.5l1.3 2.7 3 .4-2.2 2.1.5 3-2.6-1.4-2.6 1.4.5-3-2.2-2.1 3-.4L12 7.5z"/>',
  snowflake: '<g stroke="#fff" stroke-width="2" stroke-linecap="round"><line x1="12" y1="3" x2="12" y2="21"/><line x1="4.2" y1="7.5" x2="19.8" y2="16.5"/><line x1="4.2" y1="16.5" x2="19.8" y2="7.5"/><circle cx="12" cy="12" r="2.2" fill="#fff"/></g>',
  wind: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" d="M4 9h11.5a2.5 2.5 0 1 0-2.5-2.5M3 13h14.5a2.5 2.5 0 1 1-2.5 2.5M5 17h7.5a2 2 0 1 1-2 2"/>',
  spikes: '<polygon fill="#fff" points="4,20 7.5,9 10.5,20"/><polygon fill="#fff" points="8.5,20 12,4 15.5,20"/><polygon fill="#fff" points="13.5,20 16.8,10 20,20"/>',
  cube: '<path fill="none" stroke="#fff" stroke-width="2" stroke-linejoin="round" d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3zm0 9l8-4.5M12 12v9M12 12L4 7.5"/>',
  orb: '<circle cx="12" cy="12" r="7.5" fill="#fff"/><circle cx="9.5" cy="9.5" r="2.3" fill="rgba(0,0,0,.35)"/>',
  drop: '<path fill="#fff" d="M12 3.5c0 0-6.5 7.2-6.5 11.5a6.5 6.5 0 0 0 13 0C18.5 10.7 12 3.5 12 3.5z"/>',
  bolt: '<polygon fill="#fff" points="13.5,2.5 5.5,13.5 11.5,13.5 9.5,21.5 18.5,10.5 12.5,10.5"/>',
  chain: '<g fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round"><rect x="4.5" y="11" width="8" height="5" rx="2.5" transform="rotate(-35 8.5 13.5)"/><rect x="11.5" y="7" width="8" height="5" rx="2.5" transform="rotate(-35 15.5 9.5)"/></g>',
  cloud: '<path fill="#fff" d="M7.5 15.5h9.2a3.5 3.5 0 0 0 .5-7A5 5 0 0 0 7.5 7a4 4 0 0 0 0 8.5z"/><polygon fill="#fff" points="12.5,16 9.5,20.5 12.2,20.5 11.2,23 15,18.2 12.3,18.2"/>',
  boot: '<path fill="#fff" d="M8 4h5v8.5l5 2.5v4H6v-3l2-1V4zm-2 16h12v1.5H6V20z"/>',
  star: '<polygon fill="#fff" points="12,2.5 14.8,8.5 21.2,9.3 16.5,13.8 17.7,20.2 12,17 6.3,20.2 7.5,13.8 2.8,9.3 9.2,8.5"/>',
  zzz: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M13 5h6l-6 6h6M6 12h5l-5 5h5"/>',
  hourglass: '<path fill="#fff" d="M6 3h12v2l-4.5 5 4.5 5v2H6v-2l4.5-5L6 5V3zm2 16h8v2H8v-2z"/>',
  spiral: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" d="M12 12a1.5 1.5 0 1 1 1.5 1.5 3 3 0 1 1-3-3 4.8 4.8 0 1 1 4.8 4.8 6.8 6.8 0 1 1-6.8-6.8"/>',
  cross: '<path fill="#fff" d="M9.5 4h5v5.5H20v5h-5.5V20h-5v-5.5H4v-5h5.5V4z"/>',
  sun: '<circle cx="12" cy="12" r="4.5" fill="#fff"/><g stroke="#fff" stroke-width="2.2" stroke-linecap="round"><line x1="12" y1="2.5" x2="12" y2="5"/><line x1="12" y1="19" x2="12" y2="21.5"/><line x1="2.5" y1="12" x2="5" y2="12"/><line x1="19" y1="12" x2="21.5" y2="12"/><line x1="5.3" y1="5.3" x2="7.1" y2="7.1"/><line x1="16.9" y1="16.9" x2="18.7" y2="18.7"/><line x1="18.7" y1="5.3" x2="16.9" y2="7.1"/><line x1="7.1" y1="16.9" x2="5.3" y2="18.7"/></g>',
  roots: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" d="M12 20V9M12 13c-3-1-5-3.5-5-6.5 2.5 0 4.5 1.5 5 4.5M12 11c3-1 5-3.5 5-6.5-2.5 0-4.5 1.5-5 4.5"/>',
  crown: '<polygon fill="#fff" points="4,18 5.5,8 10,13 12,6 14,13 18.5,8 20,18"/><rect x="4" y="19" width="16" height="2" fill="#fff"/>',
  hand: '<path fill="#fff" d="M8 11V5.5a1 1 0 0 1 2 0V10h1V4.5a1 1 0 0 1 2 0V10h1V5.5a1 1 0 0 1 2 0V11h1V7.5a1 1 0 0 1 2 0V15a6 6 0 0 1-6 6h-1a6 6 0 0 1-6-6v-3.5a1 1 0 0 1 2 0V11z"/>',
  leaf: '<path fill="#fff" d="M19 4C11 4 6 9 6 16c0 1.2.3 2.3.8 3.2L5 21l1.4 1.4 2-2C9.5 20.8 10.7 21 12 21c7 0 7-17 7-17zm-8.5 11.5L16 10l-4.2 6.8-1.3-1.3z"/>',
  paw: '<ellipse cx="12" cy="15.5" rx="4.2" ry="3.5" fill="#fff"/><circle cx="7" cy="10.5" r="1.8" fill="#fff"/><circle cx="10.2" cy="8" r="1.8" fill="#fff"/><circle cx="13.8" cy="8" r="1.8" fill="#fff"/><circle cx="17" cy="10.5" r="1.8" fill="#fff"/>',
  skull: '<path fill="#fff" d="M12 3.5a7.5 7.5 0 0 0-7.5 7.5c0 2.8 1.5 5.2 3.8 6.5V21h7.4v-3.5c2.3-1.3 3.8-3.7 3.8-6.5A7.5 7.5 0 0 0 12 3.5zm-3 8.5a1.8 1.8 0 1 1 0-3.6 1.8 1.8 0 0 1 0 3.6zm6 0a1.8 1.8 0 1 1 0-3.6 1.8 1.8 0 0 1 0 3.6z"/>',
  skull_bolt: '<path fill="#fff" d="M12 3.5a7.5 7.5 0 0 0-7.5 7.5c0 2.8 1.5 5.2 3.8 6.5V21h7.4v-3.5c2.3-1.3 3.8-3.7 3.8-6.5A7.5 7.5 0 0 0 12 3.5zm-3 8.5a1.8 1.8 0 1 1 0-3.6 1.8 1.8 0 0 1 0 3.6zm6 0a1.8 1.8 0 1 1 0-3.6 1.8 1.8 0 0 1 0 3.6z"/>',
  heart: '<path fill="#fff" d="M12 20.5s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 3.1c0 5.6-7.5 10.2-7.5 10.2z"/>',
  gem: '<polygon fill="#fff" points="7,4 17,4 21,9.5 12,21 3,9.5"/>',
  clock: '<circle cx="12" cy="12" r="8" fill="none" stroke="#fff" stroke-width="2.2"/><polyline fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" points="12,7 12,12 15.5,14"/>',
  fang: '<polygon fill="#fff" points="7,5 11.5,5 9.2,18"/><polygon fill="#fff" points="12.5,5 17,5 14.8,18"/>',
  waves: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" d="M3.5 8.5c2-2 4-2 6 0s4 2 6 0 3-2 5 0M3.5 13c2-2 4-2 6 0s4 2 6 0 3-2 5 0M3.5 17.5c2-2 4-2 6 0s4 2 6 0 3-2 5 0"/>',
  vamp: '<path fill="#fff" d="M4 8c3-2 5.5-1 8 1.5C14.5 7 17 6 20 8c-1 5-4.5 8-8 8S5 13 4 8zm4.5 6.5L10 19l1.2-3.5M15.5 14.5L14 19l-1.2-3.5"/>',
  boulder: '<polygon fill="#fff" points="3,19 9,7 14,15 17,10 21,19"/>',
  totem: '<rect x="9.5" y="3.5" width="5" height="17" rx="1" fill="#fff"/><rect x="5" y="7.5" width="14" height="3.2" rx="1" fill="#fff"/>',
  lotus: '<path fill="#fff" d="M12 5c2 3.5 2.5 6.8 0 10-2.5-3.2-2-6.5 0-10zm-1 10c-3.5-.5-6-2.8-7-6.5 3.5.5 6 2.5 7 6.5zm2 0c3.5-.5 6-2.8 7-6.5-3.5.5-6 2.5-7 6.5zM5 17.5h14v2H5v-2z"/>',
  spin: '<path fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round" d="M18.5 10A7 7 0 1 0 17 16.5"/><polygon fill="#fff" points="19.5,6 20.5,12 15,10.5"/>',
  cleave: '<path fill="#fff" d="M19 4L9 14l2.5 2.5L21.5 6.5 19 4zM7.5 15.5L4 19l1.5 1.5 3.5-3.5-1.5-1.5z"/>',
  sword: '<path fill="#fff" d="M19.5 4.5l-10 10-2-2 10-10h2v2zM6.5 13.5l4 4-1.2 1.2-1-1-2.8 2.8-1.5-1.5 2.8-2.8-1-1 1.2-1.2z"/>',
  swords: '<g stroke="#fff" stroke-width="2.2" stroke-linecap="round"><line x1="5" y1="19" x2="19" y2="5"/><line x1="5" y1="5" x2="19" y2="19"/><line x1="5" y1="14" x2="10" y2="19"/><line x1="19" y1="14" x2="14" y2="19"/></g>',
  slash: '<path fill="#fff" d="M19.5 4.5C14 7 9 12 5 19.5 11.5 15 16.5 10 19.5 4.5z"/>',
  eye: '<path fill="none" stroke="#fff" stroke-width="2.2" d="M3 12s3.5-5.5 9-5.5S21 12 21 12s-3.5 5.5-9 5.5S3 12 3 12z"/><circle cx="12" cy="12" r="2.8" fill="#fff"/>',
  cracks: '<polyline fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" points="12,3 9.5,9.5 13.5,13 10,21"/><polyline fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" points="9.5,9.5 5,12"/><polyline fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" points="13.5,13 18,15.5"/>',
  flail: '<circle cx="16.5" cy="7.5" r="4" fill="#fff"/><line x1="5" y1="19" x2="13" y2="11" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>',
  spear: '<line x1="5" y1="19" x2="17" y2="7" stroke="#fff" stroke-width="2.3" stroke-linecap="round"/><polygon fill="#fff" points="20,4 13.5,6.5 17.5,10.5"/>',
  whirl: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" d="M12 12a2 2 0 1 1 2 2 4 4 0 1 1-4-4 6.5 6.5 0 1 1 6.5 6.5"/>',
  dagger: '<path fill="#fff" d="M18.5 5.5C15 7.5 12 10.5 9.5 14l-3-1.5-1.2 1.2 2.5 2.5L5 19l1.5 1.5 2.8-2.8 2.5 2.5 1.2-1.2-1.5-3c3.5-2.5 6.5-5.5 8.5-9z"/>',
  smoke: '<path fill="#fff" d="M8 16h8a3.2 3.2 0 0 0 .4-6.4A4.5 4.5 0 0 0 7.8 8.5 3.5 3.5 0 0 0 8 16z"/><circle cx="9" cy="19.5" r="1.4" fill="#fff"/><circle cx="13.5" cy="20" r="1.1" fill="#fff"/>',
  crosshair: '<circle cx="12" cy="12" r="6.5" fill="none" stroke="#fff" stroke-width="2"/><circle cx="12" cy="12" r="2" fill="#fff"/><g stroke="#fff" stroke-width="2" stroke-linecap="round"><line x1="12" y1="2.5" x2="12" y2="6"/><line x1="12" y1="18" x2="12" y2="21.5"/><line x1="2.5" y1="12" x2="6" y2="12"/><line x1="18" y1="12" x2="21.5" y2="12"/></g>',
  arrow: '<line x1="5" y1="19" x2="18" y2="6" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/><polyline fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" points="12,5.5 18.5,5.5 18.5,12"/>',
  arrows: '<g stroke="#fff" stroke-width="2" stroke-linecap="round" fill="none"><line x1="4" y1="17" x2="15" y2="6"/><polyline points="10,6 15,6 15,11"/><line x1="8" y1="20" x2="19" y2="9"/><polyline points="14,9 19,9 19,14"/></g>',
  horn: '<path fill="#fff" d="M5 10v4h3.5l5 4V6L8.5 10H5zm11.5-2.5a4.5 4.5 0 0 1 0 9m2-11.5a7.5 7.5 0 0 1 0 14" stroke="#fff" stroke-width="1.8" stroke-linecap="round" fill="none"/><polygon fill="#fff" points="5,10 8.5,10 13.5,6 13.5,18 8.5,14 5,14"/>',
  flag: '<line x1="6.5" y1="4" x2="6.5" y2="20" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/><polygon fill="#fff" points="7.5,4.5 18.5,6.5 15.5,10 18.5,13.5 7.5,13.5"/>',
  trap: '<path fill="#fff" d="M4 16h16v2.5H4V16zm1.5 0l2-4.5 2 4.5 2.5-4.5 2.5 4.5 2-4.5 2 4.5"/>',
  net: '<g stroke="#fff" stroke-width="2" stroke-linecap="round"><line x1="4" y1="12" x2="20" y2="12"/><line x1="12" y1="4" x2="12" y2="20"/><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></g>',
  bandage: '<rect x="4" y="8.5" width="16" height="7" rx="3.5" transform="rotate(-35 12 12)" fill="#fff"/><circle cx="10.5" cy="12" r="1" fill="rgba(0,0,0,.4)"/><circle cx="13.5" cy="12" r="1" fill="rgba(0,0,0,.4)"/>',
  flask: '<path fill="#fff" d="M9.5 4h5v2h-1v3.2l4.8 7.8a2 2 0 0 1-1.7 3H7.4a2 2 0 0 1-1.7-3l4.8-7.8V6h-1V4z"/>',
  fist: '<path fill="#fff" d="M7 9a1.5 1.5 0 0 1 3 0v1h.5V8.5a1.5 1.5 0 0 1 3 0V10h.5V9a1.5 1.5 0 0 1 3 0v5.5a5.5 5.5 0 0 1-5.5 5.5h-1A5.5 5.5 0 0 1 5.5 14.5V11A1.5 1.5 0 0 1 7 9.5V9z"/>',
  // Legacy & catalogue icon aliases
  lance: '<path fill="#fff" d="M19 4L5 18l1.5 1.5L20.5 5.5 19 4zM16 3l-9 9 1.2 1.2 9-9L16 3zm4.8 4.2l-9 9 1.2 1.2 9-9-1.2-1.2z"/><circle cx="6.5" cy="17.5" r="2.3" fill="#fff"/>',
  volcano: '<path fill="#fff" d="M7 20h10l-2-13H9L7 20zm-2 0h14v2H5v-2zm7-17l3 3H9l3-3z"/>',
  diamond: '<polygon fill="#fff" points="12,3 19,12 12,21 5,12"/>',
  droplet: '<path fill="#fff" d="M12 3.5c0 0-6.5 7.2-6.5 11.5a6.5 6.5 0 0 0 13 0C18.5 10.7 12 3.5 12 3.5z"/>',
  sparks: '<circle cx="8" cy="9" r="1.6" fill="#fff"/><circle cx="15" cy="7" r="1.4" fill="#fff"/><circle cx="12" cy="13" r="1.8" fill="#fff"/><circle cx="7" cy="16" r="1.3" fill="#fff"/><circle cx="16.5" cy="15" r="1.5" fill="#fff"/>',
  cloud_bolt: '<path fill="#fff" d="M7.5 15.5h9.2a3.5 3.5 0 0 0 .5-7A5 5 0 0 0 7.5 7a4 4 0 0 0 0 8.5z"/><polygon fill="#fff" points="12.5,16 9.5,20.5 12.2,20.5 11.2,23 15,18.2 12.3,18.2"/>',
  sprout: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" d="M12 20V9M12 13c-3-1-5-3.5-5-6.5 2.5 0 4.5 1.5 5 4.5M12 11c3-1 5-3.5 5-6.5-2.5 0-4.5 1.5-5 4.5"/>',
  fangs: '<polygon fill="#fff" points="7,5 11.5,5 9.2,18"/><polygon fill="#fff" points="12.5,5 17,5 14.8,18"/>',
  vampire: '<path fill="#fff" d="M4 8c3-2 5.5-1 8 1.5C14.5 7 17 6 20 8c-1 5-4.5 8-8 8S5 13 4 8zm4.5 6.5L10 19l1.2-3.5M15.5 14.5L14 19l-1.2-3.5"/>',
  mountain: '<polygon fill="#fff" points="3,19 9,7 14,15 17,10 21,19"/>',
  quake: '<polygon fill="#fff" points="4,18 7.5,11 10.5,16 13.5,9 16.5,15 20,18"/>',
  daggers: '<g stroke="#fff" stroke-width="2.2" stroke-linecap="round"><line x1="5" y1="19" x2="19" y2="5"/><line x1="5" y1="5" x2="19" y2="19"/><line x1="5" y1="14" x2="10" y2="19"/><line x1="19" y1="14" x2="14" y2="19"/></g>',
  fracture: '<polyline fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" points="12,3 9.5,9.5 13.5,13 10,21"/><polyline fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" points="9.5,9.5 5,12"/><polyline fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" points="13.5,13 18,15.5"/>',
  hammer: '<path fill="#fff" d="M19 4L9 14l2.5 2.5L21.5 6.5 19 4zM7.5 15.5L4 19l1.5 1.5 3.5-3.5-1.5-1.5z"/>',
  wing: '<path fill="#fff" d="M19 4C11 4 6 9 6 16c0 1.2.3 2.3.8 3.2L5 21l1.4 1.4 2-2C9.5 20.8 10.7 21 12 21c7 0 7-17 7-17zm-8.5 11.5L16 10l-4.2 6.8-1.3-1.3z"/>',
  mask: '<path fill="#fff" d="M4 9c0-2.2 3.6-4 8-4s8 1.8 8 4c0 3.8-3.2 6.5-8 6.5S4 12.8 4 9zm4.5 1.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zm7 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z"/>',
  speaker: '<path fill="#fff" d="M5 10v4h3.5l5 4V6L8.5 10H5zm11.5-2.5a4.5 4.5 0 0 1 0 9m2-11.5a7.5 7.5 0 0 1 0 14" stroke="#fff" stroke-width="1.8" stroke-linecap="round" fill="none"/><polygon fill="#fff" points="5,10 8.5,10 13.5,6 13.5,18 8.5,14 5,14"/>',
  recall: '<ellipse cx="12" cy="12" rx="5.5" ry="8" fill="none" stroke="#fff" stroke-width="2.6"/>',
  heal: '<path fill="#fff" d="M9.5 4h5v5.5H20v5h-5.5V20h-5v-5.5H4v-5h5.5V4z"/>',
  fireball: '<path fill="#fff" d="M12.5 3C12.5 3 18 8.2 18 13.5a6 6 0 0 1-12 0C6 9.8 8.5 7 9.5 5.8c0 2.2 1.5 3.2 1.8 3.2.5-2.5 1.2-6 1.2-6z"/>',
  root: '<path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" d="M12 20V9M12 13c-3-1-5-3.5-5-6.5 2.5 0 4.5 1.5 5 4.5M12 11c3-1 5-3.5 5-6.5-2.5 0-4.5 1.5-5 4.5"/>',
  hp: '<path fill="#fff" d="M12 20.5s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 3.1c0 5.6-7.5 10.2-7.5 10.2z"/>',
  mp: '<path fill="#fff" d="M12 3.5c0 0-6.5 7.2-6.5 11.5a6.5 6.5 0 0 0 13 0C18.5 10.7 12 3.5 12 3.5z"/>',
  might: '<path fill="#fff" d="M7 9a1.5 1.5 0 0 1 3 0v1h.5V8.5a1.5 1.5 0 0 1 3 0V10h.5V9a1.5 1.5 0 0 1 3 0v5.5a5.5 5.5 0 0 1-5.5 5.5h-1A5.5 5.5 0 0 1 5.5 14.5V11A1.5 1.5 0 0 1 7 9.5V9z"/>',
  arcana: '<polygon fill="#fff" points="12,2.5 14.8,8.5 21.2,9.3 16.5,13.8 17.7,20.2 12,17 6.3,20.2 7.5,13.8 2.8,9.3 9.2,8.5"/>',
};

/** Legacy text fallback map kept for callers importing ICONS. */
export const ICONS: Record<string, string> = {
  recall: '🏠',
  heal: '✚',
  fireball: '🔥',
  root: '🌿',
  spin: '🌀',
  hp: '❤',
  mp: '💧',
  might: '💪',
  arcana: '✨',
};

export function abilityColors(a: Ability | null | undefined): [string, string] {
  if (!a) return KIND_COLORS.none;
  if (a.school && SCHOOL_COLORS[a.school]) return SCHOOL_COLORS[a.school];
  return KIND_COLORS[a.kind || 'none'] || KIND_COLORS.none;
}

export function abilityGlyphSVG(a: Ability | null | undefined, size: number): string {
  if (!a) return '';
  const body = GLYPHS[a.icon] || GLYPHS.star;
  const s = Math.round(size * 0.62);
  return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" style="display:block;filter:drop-shadow(0 1px 2px rgba(0,0,0,.65));pointer-events:none">${body}</svg>`;
}

/**
 * An ability's icon as HTML (a glossy circle for spells/buffs, a rounded square for
 * combat skills, coloured by its school/archetype with its crisp white SVG glyph).
 */
export function iconHTML(a: Ability | null | undefined, size = 38): string {
  const [c1, c2] = abilityColors(a);
  const radius = a?.kind === 'skill' ? `${Math.round(size * 0.24)}px` : '50%';
  const inner = a ? abilityGlyphSVG(a, size) : '';
  return `<div style="width:${size}px;height:${size}px;border-radius:${radius};display:flex;align-items:center;justify-content:center;background:radial-gradient(circle at 32% 26%,rgba(255,255,255,.35) 0%,${c1} 28%,${c2} 95%);box-shadow:inset 0 1px 2px rgba(255,255,255,.35),inset 0 0 0 1.5px rgba(0,0,0,.45),0 2px 4px rgba(0,0,0,.65);color:#fff">${inner}</div>`;
}

const SVGNS = 'http://www.w3.org/2000/svg';
function s(tag: string, attrs: Record<string, string | number> = {}): SVGElement {
  const el = document.createElementNS(SVGNS, tag) as SVGElement;
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, String(v));
  return el;
}

export interface CanvasOptions {
  /** Pixels per ring. */
  ring?: number;
  state(node: TreeNode): NodeState;
  onNodeDown?(node: TreeNode, e: PointerEvent): void;
  onNodeClick?(node: TreeNode, e: MouseEvent): void;
  /** Right-click on a node (the game: unlearn it). The browser's menu is suppressed only when set. */
  onNodeContext?(node: TreeNode, e: MouseEvent): void;
  onNodeHover?(node: TreeNode | null, e: MouseEvent | null): void;
  onBackgroundDblClick?(x: number, y: number, e: MouseEvent): void;
  onBackgroundClick?(e: MouseEvent): void;
}

export class TreeCanvas {
  readonly svg: SVGSVGElement;
  private layer: SVGGElement;
  private tree: Tree = { start: 'n0', nodes: [], edges: [] };
  private catalog: Catalog = {};
  private zoom = 1;
  private pan = { x: 0, y: 0 };
  private ring: number;
  private dragging: { x: number; y: number; px: number; py: number; moved: boolean } | null = null;

  constructor(private host: HTMLElement, private opts: CanvasOptions) {
    this.ring = opts.ring ?? 92;
    this.svg = s('svg', { width: '100%', height: '100%' }) as SVGSVGElement;
    this.svg.style.display = 'block';
    this.svg.style.touchAction = 'none';
    this.svg.style.cursor = 'grab';
    const defs = s('defs');
    defs.innerHTML =
      '<radialGradient id="bwtgl"><stop offset="0" stop-color="#ffe9a6" stop-opacity=".55"/><stop offset="1" stop-color="#ffe9a6" stop-opacity="0"/></radialGradient>' +
      '<radialGradient id="bwtga"><stop offset="0" stop-color="#8dff9a" stop-opacity=".45"/><stop offset="1" stop-color="#8dff9a" stop-opacity="0"/></radialGradient>';
    this.svg.appendChild(defs);
    this.layer = s('g') as SVGGElement;
    this.svg.appendChild(this.layer);
    host.appendChild(this.svg);
    this.svg.addEventListener('wheel', (e) => {
      e.preventDefault();
      const r = this.svg.getBoundingClientRect();
      const mx = e.clientX - r.left - r.width / 2 - this.pan.x;
      const my = e.clientY - r.top - r.height / 2 - this.pan.y;
      const z0 = this.zoom;
      this.zoom = Math.min(3, Math.max(0.3, this.zoom * Math.exp(-e.deltaY * 0.0015)));
      this.pan.x -= mx * (this.zoom / z0 - 1);
      this.pan.y -= my * (this.zoom / z0 - 1);
      this.applyView();
    }, { passive: false });
    this.svg.addEventListener('pointerdown', (e) => {
      if ((e.target as Element).closest('[data-node]')) return;
      this.dragging = { x: e.clientX, y: e.clientY, px: this.pan.x, py: this.pan.y, moved: false };
      this.svg.setPointerCapture(e.pointerId);
      this.svg.style.cursor = 'grabbing';
    });
    this.svg.addEventListener('pointermove', (e) => {
      if (!this.dragging) return;
      const dx = e.clientX - this.dragging.x, dy = e.clientY - this.dragging.y;
      if (Math.abs(dx) + Math.abs(dy) > 3) this.dragging.moved = true;
      this.pan.x = this.dragging.px + dx;
      this.pan.y = this.dragging.py + dy;
      this.applyView();
    });
    const end = (e: PointerEvent) => {
      if (!this.dragging) return;
      const moved = this.dragging.moved;
      this.dragging = null;
      this.svg.style.cursor = 'grab';
      if (!moved && !(e.target as Element).closest?.('[data-node]')) this.opts.onBackgroundClick?.(e);
    };
    this.svg.addEventListener('pointerup', end);
    this.svg.addEventListener('pointercancel', end);
    this.svg.addEventListener('dblclick', (e) => {
      if ((e.target as Element).closest('[data-node]')) return;
      const p = this.toTree(e.clientX, e.clientY);
      this.opts.onBackgroundDblClick?.(p.x, p.y, e);
    });
    new ResizeObserver(() => this.applyView()).observe(host);
  }

  set(tree: Tree, catalog: Catalog) {
    this.tree = tree;
    this.catalog = catalog;
    this.render();
  }

  /** Screen point -> tree coordinates (rings; +y up). */
  toTree(clientX: number, clientY: number): { x: number; y: number } {
    const r = this.svg.getBoundingClientRect();
    return {
      x: (clientX - r.left - r.width / 2 - this.pan.x) / (this.ring * this.zoom),
      y: -(clientY - r.top - r.height / 2 - this.pan.y) / (this.ring * this.zoom),
    };
  }

  /** The node under a screen point, if any. */
  nodeAt(clientX: number, clientY: number): TreeNode | null {
    const el = document.elementFromPoint(clientX, clientY)?.closest?.('[data-node]');
    const id = el?.getAttribute('data-node');
    return (id && this.tree.nodes.find((n) => n.id === id)) || null;
  }

  centre() {
    this.pan = { x: 0, y: 0 };
    this.zoom = 1;
    this.applyView();
  }

  private applyView() {
    const r = this.host.getBoundingClientRect();
    this.layer.setAttribute('transform', `translate(${r.width / 2 + this.pan.x},${r.height / 2 + this.pan.y}) scale(${this.zoom})`);
  }

  render() {
    const R = this.ring;
    const byId = new Map(this.tree.nodes.map((n) => [n.id, n]));
    const states = new Map(this.tree.nodes.map((n) => [n.id, this.opts.state(n)]));
    this.layer.replaceChildren();
    // faint rings
    const maxR = Math.max(1, ...this.tree.nodes.map((n) => Math.ceil(Math.hypot(n.x, n.y))));
    for (let i = 1; i <= maxR; i++) this.layer.appendChild(s('circle', { cx: 0, cy: 0, r: i * R, fill: 'none', stroke: 'rgba(201,166,94,.07)', 'stroke-width': 1 }));
    for (const [a, b] of this.tree.edges) {
      const na = byId.get(a), nb = byId.get(b);
      if (!na || !nb) continue;
      const sa = states.get(a), sb = states.get(b);
      const lit = sa === 'learned' && sb === 'learned';
      const open = (sa === 'learned' && sb === 'available') || (sb === 'learned' && sa === 'available');
      this.layer.appendChild(s('line', {
        x1: na.x * R, y1: -na.y * R, x2: nb.x * R, y2: -nb.y * R,
        stroke: lit ? '#e2c071' : open ? '#5fae6a' : 'rgba(150,130,100,.35)',
        'stroke-width': lit ? 5 : open ? 3.5 : 3,
        'stroke-linecap': 'round',
      }));
    }
    for (const n of this.tree.nodes) {
      const st = states.get(n.id)!;
      const a = n.ability ? this.catalog[n.ability] : null;
      const g = s('g', { transform: `translate(${n.x * R},${-n.y * R})`, 'data-node': n.id }) as SVGGElement;
      g.style.cursor = 'pointer';
      const big = n.id === this.tree.start ? 30 : a ? 24 : 12;
      if (st === 'learned') g.appendChild(s('circle', { r: big + 16, fill: 'url(#bwtgl)' }));
      if (st === 'available') g.appendChild(s('circle', { r: big + 14, fill: 'url(#bwtga)', class: 'bwt-pulse' }));
      const [c1, c2] = abilityColors(a);
      const gradKey = a?.school || a?.kind || 'none';
      const gradId = `bwtk_${gradKey}`;
      if (!this.svg.querySelector(`#${gradId}`)) {
        const gr = s('radialGradient', { id: gradId, cx: '35%', cy: '30%' });
        gr.appendChild(s('stop', { offset: 0, 'stop-color': c1 }));
        gr.appendChild(s('stop', { offset: 1, 'stop-color': c2 }));
        this.svg.querySelector('defs')!.appendChild(gr);
      }
      const ringColour = st === 'learned' ? '#f0d27a' : st === 'available' ? '#7be08a' : st === 'selected' ? '#ffffff' : st === 'edit' ? '#9a8a6a' : '#4a4234';
      if (a?.kind === 'skill') {
        const side = big * 1.85;
        g.appendChild(s('rect', {
          x: -side / 2,
          y: -side / 2,
          width: side,
          height: side,
          rx: Math.round(side * 0.24),
          fill: `url(#${gradId})`,
          stroke: ringColour,
          'stroke-width': st === 'locked' ? 2 : 3.5,
          opacity: st === 'locked' ? 0.55 : 1,
        }));
      } else {
        g.appendChild(s('circle', { r: big, fill: `url(#${gradId})`, stroke: ringColour, 'stroke-width': st === 'locked' ? 2 : 3.5, opacity: st === 'locked' ? 0.55 : 1 }));
      }
      if (a) {
        const glyphSize = big * 1.25;
        const iconSvg = s('svg', {
          x: -glyphSize / 2,
          y: -glyphSize / 2,
          width: glyphSize,
          height: glyphSize,
          viewBox: '0 0 24 24',
          opacity: st === 'locked' ? 0.5 : 1,
        });
        iconSvg.innerHTML = GLYPHS[a.icon] || GLYPHS.star;
        (iconSvg as any).style.pointerEvents = 'none';
        g.appendChild(iconSvg);
      }
      g.addEventListener('pointerdown', (e) => this.opts.onNodeDown?.(n, e as PointerEvent));
      g.addEventListener('click', (e) => this.opts.onNodeClick?.(n, e as MouseEvent));
      if (this.opts.onNodeContext) {
        g.addEventListener('contextmenu', (e) => {
          e.preventDefault();
          e.stopPropagation();
          this.opts.onNodeContext?.(n, e as MouseEvent);
        });
      }
      g.addEventListener('mouseenter', (e) => this.opts.onNodeHover?.(n, e as MouseEvent));
      g.addEventListener('mousemove', (e) => this.opts.onNodeHover?.(n, e as MouseEvent));
      g.addEventListener('mouseleave', () => this.opts.onNodeHover?.(null, null));
      this.layer.appendChild(g);
    }
    this.applyView();
  }
}

/** The CSS the canvas's pulse uses (added once by whoever shows a canvas). */
export const TREE_CSS = `@keyframes bwtpulse{0%,100%{opacity:.35}50%{opacity:1}}.bwt-pulse{animation:bwtpulse 1.6s ease-in-out infinite}`;

/**
 * Drags an ability with the pointer (a ghost of its icon follows the cursor) and
 * reports the element it was dropped on (`[data-drop]`, or null). Used to put
 * abilities on the hotbars and, in the editor, onto nodes.
 */
export function dragAbility(a: Ability, e: PointerEvent, onDrop: (target: Element | null, x: number, y: number) => void) {
  const ghost = document.createElement('div');
  ghost.innerHTML = iconHTML(a, 40);
  Object.assign(ghost.style, { position: 'fixed', left: '0', top: '0', pointerEvents: 'none', zIndex: '100', opacity: '0.9', transform: `translate(${e.clientX - 20}px,${e.clientY - 20}px)` });
  document.body.appendChild(ghost);
  const move = (ev: PointerEvent) => {
    ghost.style.transform = `translate(${ev.clientX - 20}px,${ev.clientY - 20}px)`;
  };
  const up = (ev: PointerEvent) => {
    window.removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', up);
    ghost.remove();
    const under = document.elementFromPoint(ev.clientX, ev.clientY);
    onDrop(under?.closest?.('[data-drop]') || under || null, ev.clientX, ev.clientY);
  };
  window.addEventListener('pointermove', move);
  window.addEventListener('pointerup', up);
}

/** An ability's tooltip lines. */
export function abilityLines(a: Ability): string[] {
  const lines = [a.summary];
  if (a.kind === 'buff') return lines;
  const bits: string[] = [];
  if (a.school) bits.push(a.school);
  if (a.mp) bits.push(`${a.mp} mana`);
  bits.push(a.cast_ms ? `${(a.cast_ms / 1000).toFixed(1)} s cast` : 'instant');
  if (a.cooldown_ms) bits.push(`${Math.round(a.cooldown_ms / 1000)} s recast`);
  if (a.range_m) bits.push(`${a.range_m} m`);
  lines.push(bits.join(' · '));
  lines.push(a.kind === 'spell' ? 'Spell: drag it onto the spell bar.' : 'Skill: drag it onto Q, E, F, Z or X.');
  return lines;
}
