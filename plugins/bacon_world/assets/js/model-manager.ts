// Character Model Manager - Replaces Babylon.js character system
import * as THREE from "../../../../assets/js/vendor/three";
import { SkeletonUtils } from "../../../../assets/js/vendor/three-loaders";
import { PACE } from './controls-math';
import UniversalModelLoader from './universal-model-loader';
import { HumanFactory, HumanInstance } from './human-factory';
import { appearanceKey, bodyFromModelPath, isHumanModel, normalizeAppearance } from './appearance';
import type { 
  PlayerCharacter, 
  CreatureNPC, 
  LoadedModel, 
  ModelLoadOptions 
} from './types';
import { CharacterAnimator } from './anim-driver';
import { WeaponModels, gearOf, holdItem } from './items';
import type { Gear } from './wardrobe';

// Clip names (lower case) each lobby action prefers, best first. The Bacon8 humans
// carry Quaternius Universal Animation Library clips (CC0) baked onto the B8
// skeleton, so their names are listed alongside the generic ones; anything not
// listed falls back to pattern matching in canonicalAnimationName().
// A remote character reported as moving without a speed: assume a jog (m/s).
const MOVE_FALLBACK_SPEED = 4;

const PREFERRED_CLIPS: Record<string, string[]> = {
  idle: ['idle', 'idle_loop'],
  walk: ['walk', 'walk_loop'],
  run: ['jog_fwd_loop', 'run', 'jog'],
  sprint: ['sprint_loop', 'sprint'],
  jump: ['jump', 'jump_loop'],
  attack: ['attack', 'overhandthrow', 'attack_throw', 'throw'],
  cast: ['cast', 'spell_simple_shoot'],
  death: ['death', 'death01'],
  crouch: ['crouch_idle_loop', 'crouch'],
  crouch_walk: ['crouch_fwd_loop', 'crouch_walk'],
  hit: ['hit', 'hit_chest', 'hit_react'],
};

export class CharacterModelManager {
  private loadedModels: Map<string, LoadedModel> = new Map();
  private characters: Map<string, PlayerCharacter> = new Map();
  private creatures: Map<string, CreatureNPC> = new Map();
  private creatingCharacters: Map<string, Promise<PlayerCharacter>> = new Map();
  // The clip each character is playing. "oneshot:<clip>" (a throw) and "hold:<clip>"
  // (death) are not interrupted by movement updates; see playOneShot / playCharacterAnimation.
  private activeCharacterAnimations: Map<string, string> = new Map();
  // Bacon8 humans (and creatures on the same skeleton) are animated by an
  // anim-driver.ts animator: strafes, stances, swings with either hand.
  private animators: Map<string, CharacterAnimator> = new Map();
  private gear: Map<string, Gear> = new Map();
  readonly weapons = new WeaponModels();
  // A one-shot that just finished, so the next locomotion clip can fade out of it.
  private fadingFrom: Map<string, THREE.AnimationAction> = new Map();
  private universalLoader: UniversalModelLoader;
  private activeScene: THREE.Scene | null = null;
  // Bacon8 humans (Humans/Male.glb, Female.glb) are built from an appearance by the
  // HumanFactory (human-factory.ts) instead of being cloned as they are.
  private humans: HumanFactory | null = null;
  private humanInstances: Map<string, HumanInstance> = new Map();
  private humanKeys: Map<string, string> = new Map();

  constructor() {
    this.universalLoader = new UniversalModelLoader();
    console.log('🎭 CharacterModelManager initialized');
  }

  setActiveScene(scene: THREE.Scene | null): void {
    this.activeScene = scene;
  }

  setHumanFactory(factory: HumanFactory | null): void {
    this.humans = factory;
  }

  /** The animator of a Bacon8 human (swings, reactions), if it has one. */
  getAnimator(characterId: string): CharacterAnimator | undefined {
    return this.animators.get(characterId);
  }

  /**
   * What a character holds and wears (catalogue item ids by slot): the models go in its
   * hands, the animator takes the stance, and a Bacon8 human is dressed in what it wears.
   */
  async setGear(characterId: string, gear: Gear): Promise<void> {
    const g: Gear = { ...gear };
    this.gear.set(characterId, g);
    const character = this.characters.get(characterId);
    if (!character) return;
    const main = g.main ?? null;
    const off = g.off ?? null;
    const twoHanded = gearOf(main)?.hands === 2;
    this.animators.get(characterId)?.setGear(gearOf(main), twoHanded ? null : gearOf(off));
    this.humanInstances.get(characterId)?.setWorn(g);
    await Promise.all([
      holdItem(this.weapons, character.mesh, 'main', main),
      holdItem(this.weapons, character.mesh, 'off', twoHanded ? null : off),
    ]);
  }

  getGear(characterId: string): Gear {
    return this.gear.get(characterId) || {};
  }

  /** The built human for a character (bones for weapons, current appearance), if any. */
  getHuman(characterId: string): HumanInstance | undefined {
    return this.humanInstances.get(characterId);
  }

  /**
   * Re-dresses a character that is a Bacon8 human. Same body: updated in place;
   * a different body (rare: a look edited elsewhere) rebuilds the character where it stands.
   */
  async applyAppearance(characterId: string, appearance: unknown): Promise<void> {
    const inst = this.humanInstances.get(characterId);
    const character = this.characters.get(characterId);
    if (!inst || !character) return;
    const a = normalizeAppearance(appearance, inst.body);
    const key = appearanceKey(a);
    if (this.humanKeys.get(characterId) === key) return;
    this.humanKeys.set(characterId, key);
    if (a.body === inst.body) {
      await inst.apply(a);
      return;
    }
    const pos = character.mesh.position.clone();
    const rotY = character.mesh.rotation.y;
    const { name, isLocalPlayer } = character;
    this.removeCharacter(characterId);
    const rebuilt = await this.createPlayerCharacterFromModelPath(characterId, name, '', a.body === 'female' ? '/models/Humans/Female.glb' : '/models/Humans/Male.glb', { x: pos.x, y: pos.y, z: pos.z }, isLocalPlayer, a);
    rebuilt.mesh.rotation.y = rotY;
  }

  // Load FBX character models
  async loadCharacterModel(
    modelPath: string, 
    characterType: string,
    options: Partial<ModelLoadOptions> = {}
  ): Promise<LoadedModel> {
    const cacheKey = `${characterType}_${modelPath}`;
    
    if (this.loadedModels.has(cacheKey)) {
      return this.loadedModels.get(cacheKey)!;
    }

    console.log(`🔄 Loading character model: ${characterType} from ${modelPath}`);

    try {
      // This would normally use FBXLoader
      const model = await this.loadFBXModel(modelPath, options);
      this.loadedModels.set(cacheKey, model);
      
      console.log(`✅ Character model loaded: ${characterType}`);
      return model;
    } catch (error) {
      console.error(`❌ Failed to load character model ${characterType}:`, error);
      throw error;
    }
  }

  // Create player character instance
  async createPlayerCharacter(
    id: string,
    name: string,
    characterType: string,
    position: { x: number; y: number; z: number } = { x: 0, y: 0, z: 0 },
    isLocalPlayer: boolean = false
  ): Promise<PlayerCharacter> {
    // Get the model path based on character type
    const modelPath = this.getCharacterModelPath(characterType);
    
    // Load the model if not already loaded
    const loadedModel = await this.loadCharacterModel(modelPath, characterType);
    
    // Clone the model for this character instance
    const characterMesh = this.cloneModel(loadedModel);
    this.normalizeCharacterMesh(characterMesh);
    characterMesh.position.set(position.x, position.y, position.z);

    // Create animation mixer
    const mixer = loadedModel.animations.length > 0 
      ? new THREE.AnimationMixer(characterMesh) 
      : null;

    // Setup animations
    const animations = this.buildAnimationActionMap(mixer, loadedModel.animations as unknown as THREE.AnimationClip[]);

    const character: PlayerCharacter = {
      id,
      name,
      mesh: characterMesh,
      mixer,
      animations,
      position: new THREE.Vector3(position.x, position.y, position.z),
      rotation: new THREE.Euler(0, 0, 0),
      stats: {
        level: 1,
        health: 100,
        maxHealth: 100,
        mana: 50,
        maxMana: 50,
        experience: 0,
        strength: 10,
        dexterity: 10,
        intelligence: 10,
        constitution: 10
      },
      equipment: {
        helmet: null,
        armor: null,
        weapon: null,
        shield: null,
        boots: null,
        gloves: null
      },
      isMoving: false,
      isLocalPlayer
    };

    this.characters.set(id, character);
    
    // Add to scene
    const sceneRef = this.activeScene || window.ThreeJSMMO?.scene?.scene || null;
    if (sceneRef) {
      sceneRef.add(characterMesh);
    }

    console.log(`✅ Player character created: ${name} (${characterType})`);
    return character;
  }

  async createPlayerCharacterFromModelPath(
    id: string,
    name: string,
    characterType: string,
    modelPath: string,
    position: { x: number; y: number; z: number } = { x: 0, y: 0, z: 0 },
    isLocalPlayer: boolean = false,
    appearance?: unknown
  ): Promise<PlayerCharacter> {
    const existingCharacter = this.characters.get(id);
    if (existingCharacter) {
      return existingCharacter;
    }

    const inFlight = this.creatingCharacters.get(id);
    if (inFlight) {
      return inFlight;
    }

    const createPromise = this.createPlayerCharacterFromModelPathInternal(
      id,
      name,
      characterType,
      modelPath,
      position,
      isLocalPlayer,
      appearance
    );

    this.creatingCharacters.set(id, createPromise);

    try {
      return await createPromise;
    } finally {
      this.creatingCharacters.delete(id);
    }
  }

  private async createPlayerCharacterFromModelPathInternal(
    id: string,
    name: string,
    characterType: string,
    modelPath: string,
    position: { x: number; y: number; z: number } = { x: 0, y: 0, z: 0 },
    isLocalPlayer: boolean = false,
    appearance?: unknown
  ): Promise<PlayerCharacter> {
    let characterMesh: any;
    let mixer: THREE.AnimationMixer | null = null;
    let animations: any = new Map();
    let human: HumanInstance | null = null;

    if (this.humans && isHumanModel(modelPath)) {
      // Feet at the origin and scaled by height (UNITS_PER_METRE), so no normalising.
      const a = normalizeAppearance(appearance, bodyFromModelPath(modelPath));
      human = await this.humans.create(a, 'male', this.gear.get(id) || null);
      characterMesh = human.root;
      characterMesh.position.set(position.x, position.y, position.z);
      mixer = new THREE.AnimationMixer(characterMesh);
      animations = this.buildAnimationActionMap(mixer, human.clips);
      this.humanKeys.set(id, appearanceKey(a));
    } else if (modelPath.startsWith('builtin://')) {
      characterMesh = this.buildBuiltinCharacterMesh(modelPath);
      characterMesh.position.set(position.x, position.y, position.z);
    } else {
      const loadedModel = await this.loadCharacterModel(modelPath, characterType, {
        scale: 1,
        castShadow: true,
        receiveShadow: true,
        enableAnimations: true,
        position,
        rotation: { x: 0, y: 0, z: 0 }
      });

      characterMesh = this.cloneModel(loadedModel);
      this.normalizeCharacterMesh(characterMesh);
      characterMesh.position.set(position.x, position.y, position.z);

      mixer = loadedModel.animations.length > 0
        ? new THREE.AnimationMixer(characterMesh)
        : null;

      animations = this.buildAnimationActionMap(mixer, loadedModel.animations as unknown as THREE.AnimationClip[]);
    }

    const character: PlayerCharacter = {
      id,
      name,
      mesh: characterMesh,
      mixer,
      animations,
      position: new THREE.Vector3(position.x, position.y, position.z),
      rotation: new THREE.Euler(0, 0, 0),
      stats: {
        level: 1,
        health: 100,
        maxHealth: 100,
        mana: 50,
        maxMana: 50,
        experience: 0,
        strength: 10,
        dexterity: 10,
        intelligence: 10,
        constitution: 10
      },
      equipment: {
        helmet: null,
        armor: null,
        weapon: null,
        shield: null,
        boots: null,
        gloves: null
      },
      isMoving: false,
      isLocalPlayer
    };

    const duplicate = this.characters.get(id);
    if (duplicate) {
      this.removeCharacter(id);
    }

    this.characters.set(id, character);
    if (human && mixer) {
      this.humanInstances.set(id, human);
      const animator = new CharacterAnimator(characterMesh, mixer, human.clips);
      this.animators.set(id, animator);
      const factory = this.humans;
      void factory?.loadAnimPacks(human.body).then((clips) => {
        if (this.animators.get(id) === animator) animator.addClips(clips);
      });
      // A rebuilt character (new body) keeps what it held and wore.
      const held = this.gear.get(id);
      if (held) void this.setGear(id, held);
    }

    const sceneRef = this.activeScene || window.ThreeJSMMO?.scene?.scene || null;
    if (sceneRef) {
      sceneRef.add(characterMesh);
    }

    return character;
  }

  private buildBuiltinCharacterMesh(modelPath: string): THREE.Group {
    const group = new THREE.Group();
    const variant = modelPath.replace('builtin://', '');

    const bodyColor =
      variant === 'sentinel' ? 0x22d3ee :
      variant === 'runner' ? 0xf59e0b :
      0x34d399;

    const body = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.42, 1.1, 8, 12),
      new THREE.MeshStandardMaterial({ color: bodyColor, roughness: 0.42, metalness: 0.18 })
    );
    body.castShadow = true;
    body.receiveShadow = true;
    body.position.y = 1.2;

    const head = new THREE.Mesh(
      new THREE.SphereGeometry(0.28, 16, 16),
      new THREE.MeshStandardMaterial({ color: 0xe2e8f0, roughness: 0.35, metalness: 0.05 })
    );
    head.position.y = 2.05;
    head.castShadow = true;

    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.52, 0.06, 14, 32),
      new THREE.MeshStandardMaterial({ color: 0x0ea5e9, emissive: 0x0369a1, emissiveIntensity: 0.6 })
    );
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.08;

    group.add(body, head, ring);
    return group;
  }

  // Create creature/NPC instance  
  async createCreature(
    id: string,
    creatureType: string,
    name: string,
    position: { x: number; y: number; z: number } = { x: 0, y: 0, z: 0 }
  ): Promise<CreatureNPC> {
    const modelPath = this.getCreatureModelPath(creatureType);
    const loadedModel = await this.loadCharacterModel(modelPath, creatureType);
    
    const creatureMesh = this.cloneModel(loadedModel);
    this.normalizeCharacterMesh(creatureMesh);
    creatureMesh.position.set(position.x, position.y, position.z);

    const mixer = loadedModel.animations.length > 0 
      ? new THREE.AnimationMixer(creatureMesh) 
      : null;

    const animations = this.buildAnimationActionMap(mixer, loadedModel.animations as unknown as THREE.AnimationClip[]);

    const creature: CreatureNPC = {
      id,
      type: creatureType,
      name,
      mesh: creatureMesh,
      mixer,
      animations,
      position: new THREE.Vector3(position.x, position.y, position.z),
      rotation: new THREE.Euler(0, 0, 0),
      stats: this.getCreatureStats(creatureType),
      aiState: 'idle',
      isHostile: this.isCreatureHostile(creatureType)
    };

    this.creatures.set(id, creature);
    
    // Add to scene
    const sceneRef = this.activeScene || window.ThreeJSMMO?.scene?.scene || null;
    if (sceneRef) {
      sceneRef.add(creatureMesh);
    }

    console.log(`✅ Creature created: ${name} (${creatureType})`);
    return creature;
  }

  private normalizeCharacterMesh(mesh: THREE.Object3D): void {
    const box = new THREE.Box3().setFromObject(mesh);
    const size = new THREE.Vector3();
    const center = new THREE.Vector3();
    box.getSize(size);
    box.getCenter(center);

    const maxAxis = Math.max(size.x, size.y, size.z);
    if (maxAxis > 0) {
      const targetHeight = 2.2;
      const scale = targetHeight / Math.max(size.y, 0.001);
      mesh.scale.multiplyScalar(scale);
    }

    const normalizedBox = new THREE.Box3().setFromObject(mesh);
    const normalizedCenter = new THREE.Vector3();
    normalizedBox.getCenter(normalizedCenter);

    // Center model over X/Z and place feet at y=0 to avoid underground spawns.
    mesh.position.x -= normalizedCenter.x;
    mesh.position.z -= normalizedCenter.z;
    mesh.position.y -= normalizedBox.min.y;
  }
  // Play character animation
  playCharacterAnimation(characterId: string, animationName: string, loop: boolean = true): void {
    const animator = this.animators.get(characterId);
    if (animator) {
      if (animationName === 'death') animator.die();
      else if (animationName === 'idle') animator.revive();
      else animator.oneShot(animationName);
      return;
    }
    const character = this.characters.get(characterId);
    if (!character || !character.animations.has(animationName)) {
      console.warn(`Animation ${animationName} not found for character ${characterId}`);
      return;
    }

    // Stop current animations
    character.animations.forEach(action => action.stop());

    // Play new animation. A non-looping clip (death) plays once and holds its last
    // frame until the character moves again.
    const action = character.animations.get(animationName)!;
    action.reset();
    if (loop) {
      action.setLoop(THREE.LoopRepeat, Infinity);
      action.clampWhenFinished = false;
    } else {
      action.setLoop(THREE.LoopOnce, 1);
      action.clampWhenFinished = true;
    }
    action.play();
    this.fadingFrom.delete(characterId);
    this.activeCharacterAnimations.set(characterId, loop ? animationName : `hold:${animationName}`);
  }

  // Play a clip once over whatever the character is doing (the throw when casting),
  // then fade back to walking/idling. Does nothing if the model has no such clip.
  playOneShot(characterId: string, animationName: string): void {
    const animator = this.animators.get(characterId);
    if (animator) {
      // 'attack' is an overhand throw on the upper body (for a thrown spell; none yet).
      animator.oneShot(animationName === 'attack' ? 'OverhandThrow' : animationName, { upperOnly: true });
      return;
    }
    const character = this.characters.get(characterId);
    if (!character || !character.mixer) return;
    const current = this.activeCharacterAnimations.get(characterId);
    if (current && current.startsWith('hold:')) return; // dead characters don't throw

    const action = character.animations.get(animationName);
    if (!action) return;
    const previous = current && !current.startsWith('oneshot:') ? character.animations.get(current) : undefined;

    action.reset();
    action.setLoop(THREE.LoopOnce, 1);
    action.clampWhenFinished = true;
    action.enabled = true;
    if (previous && previous !== action) {
      action.crossFadeFrom(previous, 0.12, false);
    }
    action.play();
    this.activeCharacterAnimations.set(characterId, `oneshot:${animationName}`);

    const mixer = character.mixer;
    const onFinished = (event: any) => {
      if (event.action !== action) return;
      mixer.removeEventListener('finished', onFinished);
      if (this.activeCharacterAnimations.get(characterId) === `oneshot:${animationName}`) {
        this.activeCharacterAnimations.delete(characterId);
        this.fadingFrom.set(characterId, action);
      }
    };
    mixer.addEventListener('finished', onFinished);
  }

  // Picks the clip for a character's motion (RaysSpaceSim's paces, controls-math.ts):
  // airborne -> jump; crouching -> crouch idle / crouch walk; under 0.3 m/s -> idle;
  // sprinting (Shift, or over 5.5 m/s) -> sprint; otherwise the jog.
  updateCharacterMotionState(
    characterId: string,
    state: {
      isMoving: boolean;
      isRunning?: boolean;
      isJumping?: boolean;
      isSprinting?: boolean;
      isCrouching?: boolean;
      speed?: number;
      /** Movement relative to facing (+x right, +z forward), for strafes and backpedals. */
      dirX?: number;
      dirZ?: number;
    }
  ): void {
    const animator = this.animators.get(characterId);
    if (animator) {
      animator.setMotion({
        speed: state.speed ?? (state.isMoving ? MOVE_FALLBACK_SPEED : 0),
        dirX: state.dirX ?? 0,
        dirZ: state.dirZ ?? 1,
        grounded: !state.isJumping,
        crouch: !!state.isCrouching,
        sprint: !!state.isSprinting,
      });
      return;
    }
    const character = this.characters.get(characterId);
    if (!character || !character.mixer || character.animations.size === 0) return;

    const moving = state.speed !== undefined ? state.speed >= PACE.idleBelow : state.isMoving;
    const sprinting = !!state.isSprinting || (state.speed !== undefined && state.speed > PACE.jogUpTo);

    const requested = state.isJumping
      ? 'jump'
      : state.isCrouching
        ? moving
          ? 'crouch_walk'
          : 'crouch'
        : !moving
          ? 'idle'
          : sprinting
            ? 'sprint'
            : state.isRunning === false
              ? 'walk'
              : 'run';

    const resolved = this.resolveAvailableAnimation(character.animations, requested);
    const previous = this.activeCharacterAnimations.get(characterId);

    // Let a throw finish; keep a death pose until the character moves (respawned).
    if (previous && previous.startsWith('oneshot:')) return;
    if (previous && previous.startsWith('hold:') && !state.isMoving) return;
    if (previous === resolved) return;

    const nextAction = character.animations.get(resolved);
    if (!nextAction) return;

    const prevKey = previous ? previous.replace(/^hold:/, '') : undefined;
    const prevAction = (prevKey ? character.animations.get(prevKey) : undefined) || this.fadingFrom.get(characterId);
    this.fadingFrom.delete(characterId);

    nextAction.enabled = true;
    nextAction.reset();
    nextAction.setLoop(THREE.LoopRepeat, Infinity);
    nextAction.clampWhenFinished = false;

    if (prevAction) {
      nextAction.crossFadeFrom(prevAction, 0.2, true);
    }

    nextAction.play();
    this.activeCharacterAnimations.set(characterId, resolved);
  }

  updateAnimations(deltaSeconds: number): void {
    this.characters.forEach((character, id) => {
      const animator = this.animators.get(id);
      animator?.update(deltaSeconds);
      character.mixer?.update(deltaSeconds);
      // after the clips: bones the morphs move, posture, relaxed empty hands
      this.humanInstances.get(id)?.postAnimate(deltaSeconds, animator ? animator.freeHands() : undefined, animator ? animator.armSets() : undefined);
    });

    this.creatures.forEach((creature) => {
      creature.mixer?.update(deltaSeconds);
    });
  }

  // Update character position
  updateCharacterPosition(
    characterId: string, 
    position: { x: number; y: number; z: number },
    rotation?: { x: number; y: number; z: number }
  ): void {
    const character = this.characters.get(characterId);
    if (!character) return;

    character.mesh.position.set(position.x, position.y, position.z);
    character.position.set(position.x, position.y, position.z);

    if (rotation) {
      character.mesh.rotation.set(rotation.x, rotation.y, rotation.z);
      character.rotation.set(rotation.x, rotation.y, rotation.z);
    }
  }

  // Remove character
  removeCharacter(characterId: string): void {
    const character = this.characters.get(characterId);
    if (character) {
      // Remove from scene
      const sceneRef = this.activeScene || window.ThreeJSMMO?.scene?.scene || null;
      if (sceneRef) {
        sceneRef.remove(character.mesh);
      }
      
      // Dispose resources. A human shares its geometry with every other copy of that
      // body, so only its own materials go.
      const human = this.humanInstances.get(characterId);
      this.animators.get(characterId)?.dispose();
      this.animators.delete(characterId);
      character.mixer?.stopAllAction();
      if (human) {
        human.dispose();
        this.humanInstances.delete(characterId);
        this.humanKeys.delete(characterId);
      } else {
        this.disposeCharacterMesh(character.mesh);
      }

      this.characters.delete(characterId);
      this.activeCharacterAnimations.delete(characterId);
      console.log(`🗑️ Character removed: ${characterId}`);
    }
  }

  // Remove creature
  removeCreature(creatureId: string): void {
    const creature = this.creatures.get(creatureId);
    if (creature) {
      // Remove from scene
      const sceneRef = this.activeScene || window.ThreeJSMMO?.scene?.scene || null;
      if (sceneRef) {
        sceneRef.remove(creature.mesh);
      }
      
      // Dispose resources
      this.disposeCharacterMesh(creature.mesh);
      
      this.creatures.delete(creatureId);
      console.log(`🗑️ Creature removed: ${creatureId}`);
    }
  }

  // Get all characters
  getAllCharacters(): Map<string, PlayerCharacter> {
    return this.characters;
  }

  // Get all creatures
  getAllCreatures(): Map<string, CreatureNPC> {
    return this.creatures;
  }

  // Private helper methods
  private async loadFBXModel(modelPath: string, options: Partial<ModelLoadOptions>): Promise<LoadedModel> {
    const asset = await this.universalLoader.loadModel(modelPath);
    const cloned = this.universalLoader.cloneModel(asset) as THREE.Group;

    if (options.scale) {
      cloned.scale.setScalar(options.scale);
    }
    if (options.position) {
      cloned.position.set(options.position.x, options.position.y, options.position.z);
    }
    if (options.rotation) {
      cloned.rotation.set(options.rotation.x, options.rotation.y, options.rotation.z);
    }

    cloned.traverse((child: any) => {
      if (child.isMesh) {
        if (options.castShadow) child.castShadow = true;
        if (options.receiveShadow) child.receiveShadow = true;
      }
    });

    return {
      name: modelPath.split('/').pop() || 'unknown',
      mesh: cloned,
      animations: asset.animations as unknown as THREE.AnimationAction[],
      mixer: null,
      boundingBox: {
        min: new THREE.Vector3(-1, 0, -1),
        max: new THREE.Vector3(1, 4, 1)
      },
      triangleCount: 100
    };
  }

  private cloneModel(loadedModel: LoadedModel): any {
    // SkeletonUtils.clone rebinds each copy's skinned meshes to the copy's own bones;
    // a plain clone() would leave every player's mesh following the template's skeleton.
    return SkeletonUtils.clone(loadedModel.mesh);
  }

  private getCharacterModelPath(characterType: string): string {
    const modelPaths: Record<string, string> = {
      'human_male': '/models/characters/human/male/human_male_base.fbx',
      'human_female': '/models/characters/human/female/human_female_base.fbx',
      'elf_male': '/models/characters/elf/male/elf_male_base.fbx',
      'elf_female': '/models/characters/elf/female/elf_female_base.fbx',
      'dwarf_male': '/models/characters/dwarf/male/dwarf_male_base.fbx',
      'dwarf_female': '/models/characters/dwarf/female/dwarf_female_base.fbx'
    };

    return modelPaths[characterType] || modelPaths['human_male'];
  }

  private getCreatureModelPath(creatureType: string): string {
    const modelPaths: Record<string, string> = {
      'skeleton': '/models/creatures/skeleton/skeleton_warrior.fbx',
      'orc': '/models/creatures/orc/orc_warrior.fbx',
      'spider': '/models/creatures/spider/giant_spider.fbx',
      'wolf': '/models/creatures/wolf/dire_wolf.fbx',
      'goblin': '/models/creatures/goblin/goblin_warrior.fbx'
    };

    return modelPaths[creatureType] || modelPaths['skeleton'];
  }

  private buildAnimationActionMap(
    mixer: THREE.AnimationMixer | null,
    clips: THREE.AnimationClip[]
  ): Map<string, THREE.AnimationAction> {
    const animationMap = new Map<string, THREE.AnimationAction>();
    if (!mixer || clips.length === 0) return animationMap;

    // 1) Exact clip names first, so a model that ships several matching clips
    //    (Idle_Loop, Idle_Talking_Loop, ...) gets the intended one.
    const byName = new Map(clips.map((clip) => [(clip.name || '').toLowerCase(), clip]));
    for (const [key, names] of Object.entries(PREFERRED_CLIPS)) {
      const clip = names.map((n) => byName.get(n)).find(Boolean);
      if (clip) animationMap.set(key, mixer.clipAction(clip));
    }

    // 2) Then pattern matching for anything still missing.
    clips.forEach((clip, index) => {
      const key = this.canonicalAnimationName(clip.name, index);
      const action = mixer.clipAction(clip);

      if (!animationMap.has(key)) {
        animationMap.set(key, action);
      }

      // Keep original clip names available for debugging/custom triggers.
      if (clip.name && !animationMap.has(clip.name)) {
        animationMap.set(clip.name, action);
      }
    });

    if (!animationMap.has('idle') && clips.length > 0) {
      animationMap.set('idle', mixer.clipAction(clips[0]));
    }

    return animationMap;
  }

  private canonicalAnimationName(name: string, index: number): string {
    const lower = (name || '').toLowerCase();

    if (/(^|_|\b)(idle|stand|breath|wait)(_|\b)/.test(lower)) return 'idle';
    if (/(^|_|\b)(walk|locomotion|move)(_|\b)/.test(lower)) return 'walk';
    if (/(^|_|\b)(run|sprint|jog)(_|\b)/.test(lower)) return 'run';
    if (/(^|_|\b)(jump|hop|leap|fall)(_|\b)/.test(lower)) return 'jump';
    if (/(^|_|\b)(attack|hit|slash|bite|claw|punch|kick)(_|\b)/.test(lower)) return 'attack';
    if (/(^|_|\b)(cast|spell|magic)(_|\b)/.test(lower)) return 'cast';
    if (/(^|_|\b)(death|die|dead|knockout)(_|\b)/.test(lower)) return 'death';
    if (/(^|_|\b)(crouch|duck)(_|\b)/.test(lower)) return 'crouch';

    return index === 0 ? 'idle' : `animation_${index}`;
  }

  private resolveAvailableAnimation(animations: Map<string, THREE.AnimationAction>, requested: string): string {
    if (animations.has(requested)) return requested;

    const fallbackChain: Record<string, string[]> = {
      sprint: ['run', 'walk', 'idle'],
      run: ['walk', 'idle'],
      walk: ['run', 'idle'],
      crouch_walk: ['crouch', 'walk', 'idle'],
      jump: ['run', 'walk', 'idle'],
      attack: ['idle'],
      cast: ['idle'],
      death: ['idle'],
      crouch: ['idle'],
      idle: []
    };

    const fallbacks = fallbackChain[requested] || ['idle'];
    for (const fallback of fallbacks) {
      if (animations.has(fallback)) return fallback;
    }

    const first = animations.keys().next();
    return first.done ? requested : first.value;
  }

  private getCreatureStats(creatureType: string): any {
    const creatureStats: Record<string, any> = {
      'skeleton': { level: 5, health: 50, maxHealth: 50, damage: 15, defense: 5, speed: 1.0 },
      'orc': { level: 8, health: 80, maxHealth: 80, damage: 20, defense: 10, speed: 0.8 },
      'spider': { level: 3, health: 30, maxHealth: 30, damage: 10, defense: 2, speed: 1.5 },
      'wolf': { level: 6, health: 60, maxHealth: 60, damage: 18, defense: 8, speed: 1.2 },
      'goblin': { level: 4, health: 40, maxHealth: 40, damage: 12, defense: 6, speed: 1.1 }
    };

    return creatureStats[creatureType] || creatureStats['skeleton'];
  }

  private isCreatureHostile(creatureType: string): boolean {
    const hostileCreatures = ['skeleton', 'orc', 'spider', 'wolf', 'goblin'];
    return hostileCreatures.includes(creatureType);
  }

  private disposeCharacterMesh(mesh: any): void {
    // Recursively dispose of geometries and materials
    mesh.traverse((child: any) => {
      if (child.geometry) {
        child.geometry.dispose();
      }
      if (child.material) {
        if (Array.isArray(child.material)) {
          child.material.forEach((material: any) => material.dispose());
        } else {
          child.material.dispose();
        }
      }
    });
  }

  // Cleanup all resources
  dispose(): void {
    // Remove all characters
    this.characters.forEach((_, id) => this.removeCharacter(id));
    
    // Remove all creatures
    this.creatures.forEach((_, id) => this.removeCreature(id));
    
    // Clear caches
    this.loadedModels.clear();
    this.creatingCharacters.clear();
    this.activeCharacterAnimations.clear();
    this.universalLoader.dispose();
    
    console.log('✅ CharacterModelManager disposed');
  }
}

export default CharacterModelManager;
