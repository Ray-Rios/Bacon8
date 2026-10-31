import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { GLYPHS, SCHOOL_COLORS, abilityColors, abilityLines, iconHTML, type Ability } from '../skill-tree-canvas';

describe('skill-tree-canvas icons and school colors', () => {
  it('has radial gradients for all 10 spell schools, 10 skill archetypes, and passive buffs', () => {
    const schools = [
      'arcane', 'fire', 'frost', 'storm', 'holy', 'nature', 'shadow', 'blood', 'earth', 'water',
      'blade', 'berserk', 'blunt', 'polearm', 'rogue', 'archery', 'shield', 'monk', 'warlord', 'survival',
      'passive', 'buff',
    ];
    for (const s of schools) {
      assert.ok(SCHOOL_COLORS[s], `Missing SCHOOL_COLORS for ${s}`);
      assert.equal(SCHOOL_COLORS[s].length, 2);
    }
  });

  it('has crisp white SVG glyphs for every icon used in BaconWorld.Abilities', () => {
    const requiredIcons = [
      'portal', 'flame', 'lance', 'burst', 'meteor', 'volcano', 'shield_star', 'diamond', 'snowflake',
      'wind', 'spikes', 'shield', 'cube', 'orb', 'droplet', 'bolt', 'chain', 'sparks', 'cloud_bolt',
      'boot', 'star', 'zzz', 'hourglass', 'beam', 'spiral', 'cross', 'sun', 'sprout', 'crown', 'hand',
      'pillar', 'leaf', 'paw', 'skull', 'heart', 'gem', 'clock', 'fangs', 'waves', 'vampire', 'mountain',
      'quake', 'totem', 'lotus', 'spin', 'cleave', 'sword', 'slash', 'swords', 'eye', 'cracks', 'flail',
      'spear', 'whirl', 'wing', 'dagger', 'daggers', 'smoke', 'mask', 'crosshair', 'arrow', 'arrows',
      'speaker', 'fist', 'flag', 'trap', 'net', 'bandage', 'flask',
    ];
    for (const icon of requiredIcons) {
      assert.ok(GLYPHS[icon], `Missing GLYPHS entry for ${icon}`);
    }
  });

  it('renders HTML badge and tooltip lines for spells, skills, and buffs', () => {
    const spell: Ability = {
      id: 'fireball',
      name: 'Fireball',
      kind: 'spell',
      school: 'fire',
      icon: 'flame',
      summary: 'Hurls a ball of fire.',
      mp: 6,
      cast_ms: 1500,
      cooldown_ms: 3000,
      range_m: 28,
    };
    const html = iconHTML(spell, 40);
    assert.ok(html.includes('border-radius:50%'));
    assert.ok(html.includes('#ff8833'));
    assert.ok(html.includes('<svg'));
    const lines = abilityLines(spell);
    assert.equal(lines[0], 'Hurls a ball of fire.');
    assert.ok(lines[1].includes('fire · 6 mana · 1.5 s cast'));
    assert.deepEqual(abilityColors(spell), SCHOOL_COLORS.fire);
  });
});
