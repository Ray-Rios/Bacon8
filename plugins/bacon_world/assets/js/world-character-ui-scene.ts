import * as THREE from '../../../../assets/js/vendor/three';
import { CharacterModelManager } from './model-manager';
import CharacterController from './character-controller';
import { PACE, SENSITIVITY, UNITS_PER_METRE } from './controls-math';

// Mouse settings from the game menu, remembered in this browser.
const MOUSE_SENS_KEY = 'bacon_world:mouse_sensitivity';
const INVERT_Y_KEY = 'bacon_world:invert_mouse_y';
const QUALITY_KEY = 'bacon_world:quality'; // auto | full | low

function readSetting(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeSetting(key: string, value: string): void {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // private mode or blocked storage: the setting lasts for this visit
  }
}
import { SkySystem } from './sky-system';
import { LobbyAudio } from './lobby-audio';
import { HumanFactory, HumanAssets } from './human-factory';
import { CharacterStage } from './character-stage';
import { FrontUI } from './front-ui';
import { WorldDressing, Collider } from './world-dressing';
import { BODY_MODEL, isHumanModel, randomAppearance } from './appearance';
import { Nameplates, PLAYER_COLOR, plateHeight } from './nameplates';
import { setAssetVersions } from './asset-url';
import { GameWorld } from './game-world';
import type { GameUI } from './game-ui';
import type { MobsView } from './mobs-view';

type CharacterCard = {
  id: string;
  name: string;
  character_type: string;
  model_path?: string;
  appearance?: unknown;
};

type SceneState = {
  uiState: string;
  selectedCharacterId: string | null;
  canLogin: boolean;
  characters: CharacterCard[];
  modelPaths: string[];
  availableModels: Array<{ label: string; model_path: string }>;
  onlineCharacters: Array<{ character_id: string; character_name: string; user_id: string; character_type?: string; model_path?: string; x?: number; y?: number; z?: number; heading?: number }>;
  currentPlayer: any;
};

type PanelData = {
  panelId: string;
  label: string;
  characterId?: string;
};

export const WorldCharacterUIScene = {
  scene: null as THREE.Scene | null,
  camera: null as THREE.PerspectiveCamera | null,
  renderer: null as THREE.WebGLRenderer | null,
  raycaster: null as THREE.Raycaster | null,
  pointer: null as THREE.Vector2 | null,
  animationFrame: 0,
  panelMeshes: [] as THREE.Mesh[],
  panelTargets: [] as { mesh: THREE.Mesh; targetX: number; targetY: number; targetZ: number }[],
  ambientStars: null as THREE.Points | null,
  state: null as SceneState | null,
  characterManager: null as CharacterModelManager | null,
  controller: null as CharacterController | null,
  worldGroup: null as THREE.Group | null,
  movementAccumulator: 0,
  lastPositionPushMs: 0,
  lastSentLocalPosition: null as { x: number; y: number; z: number; heading: number } | null,
  remoteNetTargets: new Map<string, { x: number; y: number; z: number; heading: number; updatedAt: number }>(),
  remoteLastSeenMs: new Map<string, number>(),
  // Remote players' horizontal speed (m/s) and direction relative to their facing,
  // smoothed, for their animations.
  remoteSpeeds: new Map<string, number>(),
  remoteDirs: new Map<string, { x: number; z: number }>(),
  airborneSince: 0,
  remoteStaleTimeoutMs: 30000,
  worldInitialized: false,
  remoteSyncInProgress: false,
  remoteSyncQueued: false,
  frameClock: new THREE.Clock(),
  nameplateLayer: null as HTMLDivElement | null,
  chatPanel: null as HTMLDivElement | null,
  chatInput: null as HTMLInputElement | null,
  chatOutsideClickHandler: null as ((event: MouseEvent) => void) | null,
  // Mouse look (character-controller.ts): the centre dot, and a message shown
  // briefly when the browser refuses pointer lock.
  lookHintEl: null as HTMLDivElement | null,
  lookDotEl: null as HTMLDivElement | null,
  // The game menu (Esc): its element, and when it last opened (a browser may
  // report Esc twice: as the key and as the lost pointer lock).
  gameMenuEl: null as HTMLDivElement | null,
  gameMenuOpenedAtMs: 0,
  lookHintTimer: null as ReturnType<typeof setTimeout> | null,
  // Names over heads (nameplates.ts): sprites placed every frame before drawing.
  nameplates: null as Nameplates | null,
  // The game (game-world.ts): windows, creatures, what we carry and hold, our level.
  gameUI: null as GameUI | null,
  mobsView: null as MobsView | null,
  inventory: null as any,
  localGear: null as { main: string | null; off: string | null } | null,
  progress: null as any,
  nextSwing: { left: 0, right: 0, both: 0 } as Record<string, number>,
  lootingId: null as string | null,
  camps: [] as any[],
  refreshTargetSoon: 0,
  rmbDown: null as { x: number; y: number; t: number } | null,
  creatorOverlay: null as HTMLDivElement | null,
  // sky & combat state
  skySystem: null as SkySystem | null,
  ambientLight: null as THREE.AmbientLight | null,
  targetId: null as string | null,
  targetRingMesh: null as THREE.Mesh | null,
  // sound: effects, footsteps and the lobby music (see lobby-audio.ts)
  audio: null as LobbyAudio | null,
  wasGrounded: true,
  lastStepMs: 0,
  // death state
  isDead: false,
  deathOverlayEl: null as HTMLDivElement | null,
  deathCountdownInterval: null as ReturnType<typeof setInterval> | null,
  deathSpawnCoords: null as { x: number; y: number; z: number; heading: number } | null,
  activeProjectiles: [] as Array<{
    mesh: THREE.Mesh;
    startPos: THREE.Vector3;
    endPos: THREE.Vector3;
    progress: number; // 0→1
    duration: number; // ms
    startMs: number;
    arcOffset: number; // random lateral offset for arc
  }>,
  floatingTexts: [] as Array<{
    el: HTMLDivElement;
    x: number; y: number; z: number;
    vy: number;
    alpha: number;
    startMs: number;
    duration: number;
  }>,
  spellCooldowns: {} as Record<string, number>,
  // character select / creator (front-ui.ts) on the 3D stage (character-stage.ts)
  humanFactory: null as HumanFactory | null,
  stage: null as CharacterStage | null,
  front: null as FrontUI | null,
  keyLight: null as THREE.DirectionalLight | null,
  rimLight: null as THREE.DirectionalLight | null,
  enteringTimer: null as ReturnType<typeof setTimeout> | null,
  // the lobby village (world-dressing.ts) and what players can't walk through
  dressing: null as WorldDressing | null,
  worldColliders: [] as Collider[],
  // other players' looks, fetched once per session (fetch_appearances)
  appearanceCache: new Map<string, unknown>(),
  appearanceWaiters: new Map<string, Array<(a: unknown) => void>>(),
  appearanceQueue: new Set<string>(),
  appearanceTimer: null as ReturnType<typeof setTimeout> | null,

  mounted(this: any) {
    if (!this.el) return;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x000000);

    const width = this.el.clientWidth || window.innerWidth;
    const height = this.el.clientHeight || 480;

    this.camera = new THREE.PerspectiveCamera(60, width / height, 0.1, 1000);
    this.camera.position.set(0, 0.25, 11.5);
    this.camera.lookAt(0, 0, 0);

    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    const isFirefox = typeof navigator !== 'undefined' && /firefox/i.test(navigator.userAgent || '');
    const maxPixelRatio = isFirefox ? 1.5 : 2;
    this.basePixelRatio = Math.min(window.devicePixelRatio || 1, maxPixelRatio);
    this.renderer.setPixelRatio(this.basePixelRatio * this.qualityScale());
    this.renderer.setSize(width, height);
    this.renderer.domElement.className = 'w-full h-full rounded-xl border border-cyan-900/60 shadow-[0_0_40px_rgba(34,211,238,0.08)]';

    this.el.innerHTML = '';
    this.el.style.position = 'relative';
    this.el.appendChild(this.renderer.domElement);

    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    this.humanFactory = new HumanFactory(this.readHumanAssets());
    this.characterManager = new CharacterModelManager();
    this.characterManager.setActiveScene(this.scene);
    this.characterManager.setHumanFactory(this.humanFactory);
    this.audio = new LobbyAudio();
    this.worldGroup = new THREE.Group();
    this.scene.add(this.worldGroup);

    this.setupLights();
    this.createAmbientStars();
    this.stage = new CharacterStage(this.scene, this.camera, this.renderer, this.humanFactory);
    this.front = this.createFrontUI();
    this.stage.onLoading = (on: boolean) => this.front?.setLoading(on);
    this.readState();
    this.syncSceneMode();

    this.handleResize = this.handleResize.bind(this);
    this.handleClick = this.handleClick.bind(this);
    this.handleRightButton = this.handleRightButton.bind(this);
    this.handleWorldKeyDown = this.handleWorldKeyDown.bind(this);

    window.addEventListener('resize', this.handleResize);
    window.addEventListener('keydown', this.handleWorldKeyDown);
    this.renderer.domElement.addEventListener('click', this.handleClick);
    this.renderer.domElement.addEventListener('mousedown', this.handleRightButton);
    this.renderer.domElement.addEventListener('mouseup', this.handleRightButton);

    this.handleEvent('zone_presence_state', (payload: any) => {
      if (payload?.online_characters && this.state) {
        this.state.onlineCharacters = payload.online_characters;
      } else {
        this.readState();
      }

      if (this.state?.uiState === 'world' && this.state.currentPlayer) {
        void this.syncOtherPlayers();
      } else {
        this.syncSceneMode();
      }
    });

    this.handleEvent('zone_position_update', (payload: any) => {
      if (!payload?.character_id || !this.state?.currentPlayer) return;
      if (payload.character_id === this.state.currentPlayer.character_id) return;

      const now = performance.now();
      this.remoteLastSeenMs.set(payload.character_id, now);
      this.remoteNetTargets.set(payload.character_id, {
        x: payload.x || 0,
        y: payload.y || 0,
        z: payload.z || 0,
        heading: payload.heading || 0,
        updatedAt: now
      });

      if (this.state) {
        const idx = this.state.onlineCharacters.findIndex((c: any) => c.character_id === payload.character_id);
        const next = {
          character_id: payload.character_id,
          character_name: payload.character_name || 'Player',
          user_id: payload.user_id || '',
          character_type: payload.character_type,
          model_path: payload.model_path,
          x: payload.x || 0,
          y: payload.y || 0,
          z: payload.z || 0,
          heading: payload.heading || 0
        };

        if (idx >= 0) {
          this.state.onlineCharacters[idx] = { ...this.state.onlineCharacters[idx], ...next };
        } else {
          this.state.onlineCharacters.push(next);
        }
      }

      if (!this.characterManager?.getAllCharacters().has(payload.character_id) && this.state?.uiState === 'world' && this.characterManager) {
        const modelPath = payload.model_path || (this.state.currentPlayer?.model_path as string);
        void (isHumanModel(modelPath) ? this.getAppearance(payload.character_id) : Promise.resolve(undefined))
          .then((appearance: unknown) => {
            if (!this.characterManager || this.state?.uiState !== 'world') return;
            return this.characterManager.createPlayerCharacterFromModelPath(
              payload.character_id,
              payload.character_name || 'Player',
              payload.character_type || 'AA',
              modelPath,
              { x: payload.x || 0, y: payload.y || 0, z: payload.z || 0 },
              false,
              appearance
            );
          })
          .catch(() => {
            // If creation races with presence sync, ignore and let the next sync resolve.
          });
      }
    });

    this.handleEvent('world_logged_out', () => {
      this.teardownWorldMode();
      this.resetSelectionCamera();
      this.worldInitialized = false;
      this.readState();

      if (this.state) {
        this.state.currentPlayer = null;
        this.state.onlineCharacters = [];
        this.state.uiState = 'selection';
      }

      this.syncSceneMode();
    });

    this.handleEvent('character_login_ready', (payload: any) => {
      this.readState();
      if (payload && this.state) {
        this.state.currentPlayer = payload;
        this.state.uiState = 'world';
      }
      this.syncSceneMode();
      this.flashLoginPanel();
      this.updateHUD();
    });

    this.handleEvent('world_position_corrected', (payload: any) => {
      if (!this.characterManager || !this.state?.currentPlayer?.character_id || !payload) return;

      this.characterManager.updateCharacterPosition(
        this.state.currentPlayer.character_id,
        { x: payload.x || 0, y: payload.y || 0, z: payload.z || 0 },
        { x: 0, y: payload.heading || 0, z: 0 }
      );

      if (this.state.currentPlayer?.position) {
        this.state.currentPlayer.position = {
          x: payload.x || 0,
          y: payload.y || 0,
          z: payload.z || 0,
          heading: payload.heading || 0
        };
      }
    });

    this.handleEvent('zone_chat_message', (payload: any) => {
      if (!payload || !payload.message) return;
      if (payload.character_id && payload.character_id === this.state?.currentPlayer?.character_id) return;
      this.appendChatMessage(payload.character_name || 'Player', payload.message);
    });

    this.handleEvent('zone_spell_result', (result: any) => {
      if (!result) return;
      const myId = this.state?.currentPlayer?.character_id;

      // Everyone sees the caster throw; the stone's sounds come from where they happen.
      if (result.caster_id) {
        this.characterManager?.playOneShot(result.caster_id, 'attack');
        this.audio?.play('throw', 0.9, this.distanceToCharacter(result.caster_id));
      }
      if (result.hit && result.target_id) {
        const d = this.distanceToCharacter(result.target_id);
        const flight = this.stoneFlightMs(result.caster_id, result.target_id);
        setTimeout(() => this.audio?.play('hit', 1, d), flight);
        if (result.target_id === myId && !result.target_died) setTimeout(() => this.audio?.say('hurt', 0.8), flight + 30);
      }
      if (result.target_died && result.target_id && result.target_id !== myId) {
        const body = (this.appearanceCache.get(result.target_id) as any)?.body;
        this.audio?.say('death', 0.7, this.distanceToCharacter(result.target_id), body === 'female' ? 'f' : 'm');
      }

      // Update our own MP if we were the caster
      if (result.caster_id === myId && this.state?.currentPlayer) {
        this.state.currentPlayer.mp = result.caster_mp;
        this.state.currentPlayer.max_mp = result.caster_max_mp;
        this.updateHUD();
      }

      // Update target HP in local state (for our own char AND in onlineCharacters for observers)
      if (result.target_id === myId && this.state?.currentPlayer) {
        // Don't update HUD while dead — we show 0 HP until respawn
        if (!this.isDead) {
          this.state.currentPlayer.hp = result.target_hp;
          this.state.currentPlayer.max_hp = result.target_max_hp;
          this.updateHUD();
        }
        // character_died event handles the death screen
      }

      // Always update the target's HP in onlineCharacters so the target frame reflects it
      if (this.state?.onlineCharacters) {
        const idx = this.state.onlineCharacters.findIndex((c: any) => c.character_id === result.target_id);
        if (idx >= 0) {
          this.state.onlineCharacters[idx] = {
            ...this.state.onlineCharacters[idx],
            hp: result.target_hp,
            max_hp: result.target_max_hp
          };
        }
      }
      // Refresh the target frame if the damaged character is our current target
      if (result.target_id === this.targetId) {
        this.setTarget(this.targetId);
      }

      // Play death animation on a remote character that just died
      if (result.target_died && result.target_id !== myId) {
        this.characterManager?.playCharacterAnimation(result.target_id, 'death', false);
      }

      // Launch projectile if WE were the caster
      if (result.caster_id === myId) {
        const casterChar = myId ? this.characterManager?.getAllCharacters().get(myId) : null;
        const targetChar = result.target_id ? this.characterManager?.getAllCharacters().get(result.target_id) : null;
        if (casterChar && targetChar) {
          this.launchProjectile(
            casterChar.mesh.position.clone(),
            targetChar.mesh.position.clone(),
            result.hit,
            result.damage,
            result.target_id
          );
        }
      }

      // Also show floating text for everyone who sees the target
      if (result.hit && result.damage > 0) {
        const targetChar = result.target_id ? this.characterManager?.getAllCharacters().get(result.target_id) : null;
        if (targetChar) {
          this.showFloatingDamage(targetChar.mesh.position.clone(), `-${result.damage}`);
        }
      }
    });

    this.handleEvent('character_died', (payload: any) => {
      if (!payload) return;
      this.deathSpawnCoords = payload.spawn_coords || { x: 0, y: 0, z: 0, heading: 0 };
      console.log('[Death] spawn_coords received:', this.deathSpawnCoords);
      // Update state HP to 0 for HUD display
      if (this.state?.currentPlayer) {
        this.state.currentPlayer.hp = 0;
        this.updateHUD();
      }
      this.audio?.say('death', 1);
      if (this.lootingId) this.closeLoot();
      this.combatLog('You have been slain!', '#FF5A4A');
      this.enterDeathState(payload.respawn_in_ms ?? 30000);
    });

    this.handleEvent('character_respawned', (payload: any) => {
      if (!payload) return;
      // Spawn coords come from the server payload directly (most reliable source)
      const coords = payload.spawn_coords || this.deathSpawnCoords || { x: 0, y: 0, z: 0, heading: 0 };
      console.log('[Respawn] teleporting to', coords);

      this.exitDeathState();

      if (this.controller) {
        this.controller.teleportTo(
          coords.x ?? 0,
          coords.y ?? 0,
          coords.z ?? 0,
          coords.heading ?? 0
        );
      }
      // Keep characterManager's internal position in sync too
      const myId = this.state?.currentPlayer?.character_id;
      if (myId && this.characterManager) {
        this.characterManager.updateCharacterPosition(
          myId,
          { x: coords.x ?? 0, y: coords.y ?? 0, z: coords.z ?? 0 },
          { x: 0, y: coords.heading ?? 0, z: 0 }
        );
      }
      // Restore HP/MP
      if (this.state?.currentPlayer) {
        this.state.currentPlayer.hp = payload.hp;
        this.state.currentPlayer.max_hp = payload.max_hp;
        this.state.currentPlayer.mp = payload.mp;
        this.state.currentPlayer.max_mp = payload.max_mp;
        this.updateHUD();
      }
      this.deathSpawnCoords = null;
      if (myId) this.characterManager?.playCharacterAnimation(myId, 'idle', true);
      this.audio?.play('respawn', 0.9);
    });

    this.handleEvent('spell_error', (payload: any) => {
      const reason = payload?.reason || 'unknown';
      const msgs: Record<string, string> = {
        insufficient_mp: 'Not enough MP!',
        out_of_range: 'Target is out of range!',
        pvp_not_flagged: 'Both you and your target must have PvP enabled.',
        character_not_found: 'Invalid target.'
      };
      this.appendChatMessage('System', msgs[reason] || `Spell failed: ${reason}`);
    });

    this.handleEvent('pvp_flag_changed', (payload: any) => {
      if (this.state?.currentPlayer) {
        this.state.currentPlayer.pvp_flagged = payload.pvp_flagged;
      }
      this.updateHUD();
    });

    this.handleEvent('world_login_error', (payload: any) => {
      const msg = payload?.message || 'Login failed. Please try again.';
      // Show error in chat log if available, otherwise alert
      if (this.chatPanel) {
        this.appendChatMessage('System', `⛔ ${msg}`);
      } else {
        alert(msg);
      }
    });

    // Creatures (game-world.ts, mobs-view.ts) and other players' weapons.
    this.handleEvent('mob_events', (payload: any) => {
      for (const e of payload?.events || []) this.mobsView?.event(e);
    });
    this.handleEvent('mob_motion', (payload: any) => {
      this.mobsView?.motion(payload?.m || []);
    });
    this.handleEvent('zone_gear', (payload: any) => {
      if (!payload?.character_id) return;
      const c = this.state?.onlineCharacters?.find((o: any) => o.character_id === payload.character_id);
      if (c) c.gear = payload.gear;
      this.applyRemoteGear(payload.character_id, payload.gear);
    });

    this.handleEvent('character_stats_update', (payload: any) => {
      if (!payload || !this.state?.currentPlayer) return;
      // Don't update HUD stats while dead — keep showing 0 HP until respawn
      if (this.isDead) return;
      this.state.currentPlayer.hp = payload.hp;
      this.state.currentPlayer.max_hp = payload.max_hp;
      this.state.currentPlayer.mp = payload.mp;
      this.state.currentPlayer.max_mp = payload.max_mp;
      this.updateHUD();
    });

    this.animate();
  },

  updated(this: any) {
    // In world mode the DOM data-attributes are static; all live updates come via
    // push_event (zone_presence_state, character_login_ready, etc.).  Calling
    // readState + syncSceneMode here at 20 Hz causes the stutter.
    if (this.worldInitialized) return;
    this.readState();
    this.syncSceneMode();
  },

  destroyed(this: any) {
    if (this.positionHeartbeatInterval) {
      clearInterval(this.positionHeartbeatInterval);
      this.positionHeartbeatInterval = null;
    }
    cancelAnimationFrame(this.animationFrame);
    window.removeEventListener('resize', this.handleResize);
    window.removeEventListener('keydown', this.handleWorldKeyDown);
    if (this.renderer) {
      this.renderer.domElement.removeEventListener('click', this.handleClick);
      this.renderer.domElement.removeEventListener('mousedown', this.handleRightButton);
      this.renderer.domElement.removeEventListener('mouseup', this.handleRightButton);
      this.renderer.dispose();
    }
    this.controller?.dispose();
    this.characterManager?.dispose();
    this.audio?.dispose();
    this.audio = null;
    this.stage?.dispose();
    this.stage = null;
    this.front?.dispose();
    this.front = null;
    if (this.enteringTimer) clearTimeout(this.enteringTimer);
    if (this.appearanceTimer) clearTimeout(this.appearanceTimer);
    this.clearPanels();
    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.raycaster = null;
    this.pointer = null;
    this.characterManager = null;
    this.controller = null;
    this.worldGroup = null;
    this.removeWorldOverlayUI();
    this.nameplates?.clear();
    this.nameplates = null;
  },

  reconnected(this: any) {
    // Reset any stuck push lock — the same hook instance is reused across reconnects,
    // so a _pushPending=true left over from before the disconnect would block all sends.
    this._pushPending = false;
    if (this._pushPendingTimer) {
      clearTimeout(this._pushPendingTimer);
      this._pushPendingTimer = null;
    }
    // Re-sync other players in case presence state changed while offline.
    if (this.worldInitialized && this.state?.uiState === 'world') {
      void this.syncOtherPlayers();
    }
  },

  setupLights(this: any) {
    if (!this.scene) return;

    const ambient = new THREE.AmbientLight(0xffffff, 0.8);
    this.ambientLight = ambient;
    // Key and rim lights stay fixed for the character selection screen;
    // in world mode the SkySystem overrides the ambient and adds sun/moon.
    const key = new THREE.DirectionalLight(0x67e8f9, 0.8);
    key.position.set(6, 8, 10);

    const rim = new THREE.DirectionalLight(0xa855f7, 0.45);
    rim.position.set(-7, -3, 6);

    this.keyLight = key;
    this.rimLight = rim;
    this.scene.add(ambient, key, rim);
  },

  createAmbientStars(this: any) {
    if (!this.scene) return;

    const starCount = 320;
    const geometry = new THREE.BufferGeometry();
    const positions = new Float32Array(starCount * 3);

    for (let index = 0; index < starCount; index += 1) {
      positions[index * 3] = (Math.random() - 0.5) * 54;
      positions[index * 3 + 1] = (Math.random() - 0.5) * 34;
      positions[index * 3 + 2] = (Math.random() - 0.5) * 38;
    }

    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const material = new THREE.PointsMaterial({ color: 0x7dd3fc, size: 0.1, transparent: true, opacity: 0.78 });
    this.ambientStars = new THREE.Points(geometry, material);
    this.scene.add(this.ambientStars);
  },

  readState(this: any) {
    const uiState = this.el.dataset.uiState || 'intro';
    const selectedCharacterId = this.el.dataset.selectedCharacterId || null;
    const canLogin = this.el.dataset.canLogin === 'true';

    let characters: CharacterCard[] = [];
    let modelPaths: string[] = [];
    let onlineCharacters: Array<{ character_id: string; character_name: string; user_id: string; character_type?: string; model_path?: string; x?: number; y?: number; z?: number; heading?: number }> = [];
    let currentPlayer: any = null;
    try {
      characters = JSON.parse(this.el.dataset.characters || '[]');
    } catch (_err) {
      characters = [];
    }

    try {
      modelPaths = JSON.parse(this.el.dataset.modelPaths || '[]');
    } catch (_err) {
      modelPaths = [];
    }

    let availableModels: Array<{ label: string; model_path: string }> = [];
    try {
      availableModels = JSON.parse(this.el.dataset.availableModels || '[]');
    } catch (_err) {
      availableModels = [];
    }

    try {
      onlineCharacters = JSON.parse(this.el.dataset.onlineCharacters || '[]');
    } catch (_err) {
      onlineCharacters = [];
    }

    try {
      currentPlayer = JSON.parse(this.el.dataset.currentPlayer || 'null');
    } catch (_err) {
      currentPlayer = null;
    }

    const resolvedUiState = currentPlayer ? 'world' : uiState;
    this.state = { uiState: resolvedUiState, selectedCharacterId, canLogin, characters, modelPaths, availableModels, onlineCharacters, currentPlayer };
  },

  syncSceneMode(this: any) {
    if (this.state?.uiState === 'world' && this.state.currentPlayer) {
      this.clearPanels();
      this.hideFront();

      if (!this.worldInitialized) {
        void this.initializeWorldMode();
      } else {
        void this.syncOtherPlayers();
      }

      return;
    }

    this.teardownWorldMode();
    this.showFront();
  },

  // ── Character select and creator ────────────────────────────────────────────

  readHumanAssets(this: any): HumanAssets {
    try {
      const assets = JSON.parse(this.el.dataset.humanAssets || '{}');
      // Model URLs carry each file's version (asset-url.ts), so updates aren't cached.
      setAssetVersions(assets?.versions);
      return assets;
    } catch (_err) {
      return {};
    }
  },

  createFrontUI(this: any): FrontUI {
    const reply = (event: string, payload: any, fallback: any): Promise<any> =>
      new Promise((resolve) => {
        const timer = setTimeout(() => resolve(fallback), 12000);
        try {
          this.pushEvent(event, payload, (res: any) => {
            clearTimeout(timer);
            resolve(res || fallback);
          });
        } catch (_e) {
          clearTimeout(timer);
          resolve(fallback);
        }
      });
    return new FrontUI(this.el, {
      select: (id: string) => {
        (this.pushEvent('select_character', { character_id: id }) as any)?.catch?.(() => {});
      },
      play: (id: string) => {
        this.front?.setEntering(true);
        if (this.enteringTimer) clearTimeout(this.enteringTimer);
        // the server answers with character_login_ready, or a flash if it refuses
        this.enteringTimer = setTimeout(() => this.front?.setEntering(false), 15000);
        this.pushEvent('select_character', { character_id: id }, () => {
          (this.pushEvent('login_character', {}) as any)?.catch?.(() => {});
        });
      },
      remove: (id: string) => {
        (this.pushEvent('delete_character', { character_id: id }) as any)?.catch?.(() => {});
      },
      // No classes: every character starts the same (one skill tree, one start).
      create: (name: string, a: any) =>
        reply('three_ui_create_character', { name, character_type: 'Adventurer', model_path: BODY_MODEL[a.body as 'male' | 'female'], appearance: a },
          { ok: false, error: 'No answer from the server. Try again.' }),
      updateLook: (id: string, a: any) =>
        reply('three_ui_update_appearance', { character_id: id, appearance: a }, { ok: false, error: 'No answer from the server. Try again.' }),
      preview: (a: any) => {
        if (!this.stage) return;
        if (a) void this.stage.setAppearance(a);
        else {
          const st = this.humanFactory?.styles('male') || { hair: [], facial: [] };
          void this.stage.setAppearance(randomAppearance('male', st.hair.map((x: any) => x.id), [], 20261021));
        }
      },
      framing: (f: any) => this.stage?.setFraming(f),
      insets: (l: number, r: number, t?: number, b?: number) => this.stage?.setInsets(l, r, t || 0, b || 0),
      styles: (b: any) => this.humanFactory?.styles(b) || { hair: [], facial: [] },
      iconUrl: (e: any) => this.humanFactory?.iconUrl(e) || null,
      back: () => {},
    });
  },

  showFront(this: any) {
    if (!this.stage || !this.front || !this.state) return;
    this.clearPanels();
    this.stage.show();
    if (this.keyLight) this.keyLight.visible = false;
    if (this.rimLight) this.rimLight.visible = false;
    if (this.ambientStars) this.ambientStars.visible = false;
    if (this.ambientLight) this.ambientLight.intensity = 0.15;
    this.front.setCharacters(this.state.characters, this.state.selectedCharacterId);
    if (this.front.current === 'hidden') this.front.showSelect();
  },

  hideFront(this: any) {
    this.front?.hide();
    this.stage?.hide();
    if (this.keyLight) this.keyLight.visible = true;
    if (this.rimLight) this.rimLight.visible = true;
    // The old lobby's floating blue specks don't belong in the village.
    if (this.ambientStars) this.ambientStars.visible = false;
    if (this.ambientLight) this.ambientLight.intensity = 0.8;
  },

  // Other players' looks: batched requests, answered by the LiveView (fetch_appearances).
  getAppearance(this: any, characterId: string): Promise<unknown> {
    if (this.appearanceCache.has(characterId)) return Promise.resolve(this.appearanceCache.get(characterId));
    return new Promise((resolve) => {
      const list = this.appearanceWaiters.get(characterId) || [];
      list.push(resolve);
      this.appearanceWaiters.set(characterId, list);
      this.appearanceQueue.add(characterId);
      if (this.appearanceTimer) return;
      this.appearanceTimer = setTimeout(() => {
        this.appearanceTimer = null;
        const ids = [...this.appearanceQueue].slice(0, 64);
        ids.forEach((id) => this.appearanceQueue.delete(id));
        const settle = (map: Record<string, unknown>) => {
          for (const id of ids) {
            const a = map?.[id] ?? null;
            if (a) this.appearanceCache.set(id, a);
            (this.appearanceWaiters.get(id) || []).forEach((fn: any) => fn(a));
            this.appearanceWaiters.delete(id);
          }
        };
        const timer = setTimeout(() => settle({}), 4000);
        try {
          this.pushEvent('fetch_appearances', { ids }, (res: any) => {
            clearTimeout(timer);
            settle(res?.appearances || {});
          });
        } catch (_e) {
          clearTimeout(timer);
          settle({});
        }
      }, 60);
    });
  },

  async initializeWorldMode(this: any) {
    if (!this.scene || !this.camera || !this.state?.currentPlayer || !this.characterManager || !this.worldGroup) return;

    if (this.worldGroup.children.length === 0) {
      const ground = new THREE.Mesh(
        new THREE.PlaneGeometry(180, 180),
        new THREE.MeshStandardMaterial({ color: 0x101820, roughness: 0.9, metalness: 0.08 })
      );
      ground.rotation.x = -Math.PI / 2;
      ground.receiveShadow = true;
      this.worldGroup.add(ground);

      const grid = new THREE.GridHelper(180, 40, 0x2dd4bf, 0x1f2937);
      this.worldGroup.add(grid);
    }

    this.createWorldOverlayUI();
    if (!this.nameplates) {
      this.nameplates = new Nameplates();
      this.scene.add(this.nameplates.group);
    }

    // The village replaces the plain ground and grid once its models have loaded.
    if (!this.dressing && this.scene && this.renderer) {
      this.dressing = new WorldDressing(this.scene, this.renderer);
      const plain = [...this.worldGroup.children];
      void this.dressing.build(this.worldGroup).then(() => {
        if (!this.dressing) return;
        this.worldColliders = this.dressing.colliders();
        if (this.worldColliders.length) plain.forEach((o: THREE.Object3D) => (o.visible = false));
      });
    }

    const currentPlayer = this.state.currentPlayer;
    const localExists = this.characterManager.getAllCharacters().has(currentPlayer.character_id);
    if (!localExists) {
      await this.characterManager.createPlayerCharacterFromModelPath(
        currentPlayer.character_id,
        currentPlayer.name,
        currentPlayer.character_type,
        currentPlayer.model_path,
        {
          x: currentPlayer.position.x,
          y: currentPlayer.position.y,
          z: currentPlayer.position.z
        },
        true,
        currentPlayer.appearance
      );
    }

    const localCharacter = this.characterManager.getAllCharacters().get(currentPlayer.character_id);
    if (localCharacter && !this.controller) {
      this.controller = new CharacterController(localCharacter.mesh, this.camera, {
        canvas: this.renderer.domElement,
        // No pointer lock while dead or in the menu (they need the cursor). A click
        // that closes chat locks too: the chat's pointerdown handler blurs it first.
        canLock: () => !this.isDead && !this.isGameMenuOpen(),
        onPointerLockChange: (locked: boolean) => this.updateLookHint(locked),
        onPointerLockError: () => this.flashLookHint('Click again to look around'),
        onEscape: (reason: 'key' | 'lock-lost') => this.handleGameEscape(reason),
        // Mouse-look on: the left button swings the left hand, the right button the right.
        onAttack: (hand: 'left' | 'right') => this.meleeAttack(hand),
        // The village's colliders (world-dressing.ts); empty until it has loaded.
        collide: (x: number, z: number) =>
          this.worldColliders.length ? WorldDressing.pushOut(this.worldColliders, x, z, 0.32 * UNITS_PER_METRE) : { x, z },
      });
      this.controller.setMouseSettings(
        Number(readSetting(MOUSE_SENS_KEY)) || SENSITIVITY.default,
        readSetting(INVERT_Y_KEY) === 'on'
      );
      this.updateLookHint(false);
      this.controller.setPositionCallback((x: number, y: number, z: number, rotation: number) => {
        this.sendLocalPosition(x, y, z, rotation);
      });
    }

    this.worldInitialized = true;
    if (this.enteringTimer) clearTimeout(this.enteringTimer);
    this.front?.setEntering(false);
    this.audio?.setMusic(true);
    this.audio?.preload();
    this.initGame();

    // Start day/night sky system
    if (!this.skySystem && this.ambientLight) {
      this.skySystem = new SkySystem(this.scene, this.ambientLight);
    }

    // Fallback heartbeat so position keeps sending even when tab is backgrounded
    // (requestAnimationFrame throttles to ~1fps in background tabs)
    this.positionHeartbeatInterval = setInterval(() => {
      if (!this.worldInitialized || !this.el?.isConnected) {
        clearInterval(this.positionHeartbeatInterval);
        this.positionHeartbeatInterval = null;
        return;
      }
      const currentId = this.state?.currentPlayer?.character_id;
      const localCharacter = currentId ? this.characterManager?.getAllCharacters().get(currentId) : null;
      if (localCharacter) {
        this.sendLocalPosition(
          localCharacter.mesh.position.x,
          localCharacter.mesh.position.y,
          localCharacter.mesh.position.z,
          localCharacter.mesh.rotation.y,
          true
        );
      }
    }, 500);

    await this.syncOtherPlayers();
  },

  async syncOtherPlayers(this: any) {
    if (!this.state?.currentPlayer || !this.characterManager) return;

    if (this.remoteSyncInProgress) {
      this.remoteSyncQueued = true;
      return;
    }

    this.remoteSyncInProgress = true;

    try {
      const now = performance.now();
      const currentId = this.state.currentPlayer.character_id;
      const onlineIds = new Set<string>();

      for (const online of this.state.onlineCharacters) {
        if (!online.character_id || online.character_id === currentId) continue;
        onlineIds.add(online.character_id);
        this.remoteLastSeenMs.set(online.character_id, now);

        if (!this.characterManager.getAllCharacters().has(online.character_id)) {
          const modelPath = online.model_path || (this.state.currentPlayer.model_path as string);
          const appearance = isHumanModel(modelPath) ? await this.getAppearance(online.character_id) : undefined;
          if (!this.characterManager || !this.state?.currentPlayer) return;
          await this.characterManager.createPlayerCharacterFromModelPath(
            online.character_id,
            online.character_name || 'Player',
            online.character_type || 'AA',
            modelPath,
            { x: online.x || 0, y: online.y || 0, z: online.z || 0 },
            false,
            appearance
          );
          this.remoteNetTargets.set(online.character_id, {
            x: online.x || 0,
            y: online.y || 0,
            z: online.z || 0,
            heading: online.heading || 0,
            updatedAt: performance.now()
          });
          this.applyRemoteGear(online.character_id, online.gear);
        } else {
          this.applyRemoteGear(online.character_id, online.gear);
          const existingTarget = this.remoteNetTargets.get(online.character_id);
          const onlineX = online.x || 0;
          const onlineY = online.y || 0;
          const onlineZ = online.z || 0;
          const onlineHeading = online.heading || 0;

          if (!existingTarget) {
            this.remoteNetTargets.set(online.character_id, {
              x: onlineX,
              y: onlineY,
              z: onlineZ,
              heading: onlineHeading,
              updatedAt: performance.now()
            });
          } else {
            const dx = onlineX - existingTarget.x;
            const dy = onlineY - existingTarget.y;
            const dz = onlineZ - existingTarget.z;
            const distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
            const staleTarget = now - existingTarget.updatedAt > 500;

            // Fallback path: keep remote movement alive from presence snapshots if
            // realtime zone_position_update packets are delayed or missing.
            if (distance > 0.05 || staleTarget) {
              this.remoteNetTargets.set(online.character_id, {
                x: onlineX,
                y: onlineY,
                z: onlineZ,
                heading: onlineHeading,
                updatedAt: performance.now()
              });
            }
          }
        }
      }

      this.characterManager.getAllCharacters().forEach((_character, id) => {
        if (id !== currentId && !onlineIds.has(id)) {
          const lastSeen = this.remoteLastSeenMs.get(id) || 0;
          const lastTargetUpdate = this.remoteNetTargets.get(id)?.updatedAt || 0;
          if (now - lastSeen >= this.remoteStaleTimeoutMs && now - lastTargetUpdate >= this.remoteStaleTimeoutMs) {
            this.characterManager?.removeCharacter(id);
            this.remoteNetTargets.delete(id);
            this.remoteLastSeenMs.delete(id);
            this.remoteSpeeds.delete(id);
          }
        }
      });
    } finally {
      this.remoteSyncInProgress = false;
      if (this.remoteSyncQueued) {
        this.remoteSyncQueued = false;
        void this.syncOtherPlayers();
      }
    }
  },

  applyRemoteSmoothing(this: any, deltaSeconds: number) {
    if (!this.characterManager || !this.state?.currentPlayer) return;

    const currentId = this.state.currentPlayer.character_id;
    const snapDistance = 15.0;
    const baseAlpha = Math.min(1, deltaSeconds * 12);

    this.remoteNetTargets.forEach((target: any, id: string) => {
      if (id === currentId) return;
      const character = this.characterManager.getAllCharacters().get(id);
      if (!character) {
        return;
      }

      const currentPos = character.mesh.position;
      const prevX = currentPos.x;
      const prevZ = currentPos.z;
      const dx = target.x - currentPos.x;
      const dy = target.y - currentPos.y;
      const dz = target.z - currentPos.z;
      const distance = Math.sqrt(dx * dx + dy * dy + dz * dz);

      if (distance > snapDistance) {
        currentPos.set(target.x, target.y, target.z);
      } else {
        currentPos.x += dx * baseAlpha;
        currentPos.y += dy * baseAlpha;
        currentPos.z += dz * baseAlpha;
      }

      const currentHeading = character.mesh.rotation.y;
      const headingDiff = this.shortestAngleDiff(currentHeading, target.heading || 0);
      character.mesh.rotation.y = currentHeading + headingDiff * Math.min(1, deltaSeconds * 14);

      character.position.set(currentPos.x, currentPos.y, currentPos.z);
      character.rotation.set(0, character.mesh.rotation.y, 0);

      // Speed from how far the smoothed position moved this frame (m/s), eased so a
      // late network update doesn't flicker the clip. Same paces as the local player.
      let speed = 0;
      if (distance <= snapDistance && deltaSeconds > 0) {
        const frameSpeed = Math.hypot(currentPos.x - prevX, currentPos.z - prevZ) / deltaSeconds / UNITS_PER_METRE;
        const previous = this.remoteSpeeds.get(id) ?? frameSpeed;
        speed = previous + (frameSpeed - previous) * Math.min(1, deltaSeconds * 8);
      }
      this.remoteSpeeds.set(id, speed);
      // Which way it moves relative to where it faces: strafing and backpedalling
      // players show the right clips here too.
      const mx = currentPos.x - prevX;
      const mz = currentPos.z - prevZ;
      const ml = Math.hypot(mx, mz);
      const hh = character.mesh.rotation.y;
      const dirZ = ml > 1e-5 ? (mx * Math.sin(hh) + mz * Math.cos(hh)) / ml : 1;
      const dirX = ml > 1e-5 ? (-mx * Math.cos(hh) + mz * Math.sin(hh)) / ml : 0;
      const prevDir = this.remoteDirs.get(id) || { x: 0, z: 1 };
      const k = Math.min(1, deltaSeconds * 6);
      const dir = { x: prevDir.x + (dirX - prevDir.x) * k, z: prevDir.z + (dirZ - prevDir.z) * k };
      this.remoteDirs.set(id, dir);
      this.characterManager.updateCharacterMotionState(id, {
        isMoving: speed >= PACE.idleBelow,
        isRunning: true,
        isSprinting: speed > PACE.jogUpTo,
        isJumping: false,
        speed,
        dirX: dir.x,
        dirZ: dir.z
      });
    });
  },

  syncCharacterAnimations(this: any) {
    if (!this.characterManager || !this.state?.currentPlayer) return;

    const currentId = this.state.currentPlayer.character_id;
    const movementState = this.controller?.getMovementState?.();

    this.characterManager.updateCharacterMotionState(currentId, {
      isMoving: !!movementState?.isMoving,
      isRunning: !!movementState?.isRunning,
      isSprinting: !!movementState?.isSprinting,
      isCrouching: !!movementState?.isCrouching,
      isJumping: movementState ? !movementState.isGrounded : false,
      speed: movementState?.speed ?? 0,
      dirX: movementState?.dirX ?? 0,
      dirZ: movementState?.dirZ ?? 1
    });

    if (movementState && this.audio && !this.isDead) {
      const grounded = !!movementState.isGrounded;
      const now = performance.now();
      // A grunt when jumping, a thud when landing (a short hop lands quietly).
      if (this.wasGrounded && !grounded) {
        this.airborneSince = now;
        this.audio.say('jump', 0.55);
      }
      if (!this.wasGrounded && grounded) {
        const air = now - (this.airborneSince || now);
        this.audio.play('land', air > 450 ? 0.9 : 0.55);
      }
      this.wasGrounded = grounded;
      // Steps by pace: sprint 260 ms, jog 330 ms, crouch-walk 500 ms; the sound by what's underfoot.
      const interval = movementState.isCrouching ? 500 : movementState.isSprinting ? 260 : 330;
      if (grounded && movementState.isMoving && now - this.lastStepMs > interval) {
        this.lastStepMs = now;
        const me = this.localCharacter();
        const surface = me ? this.surfaceAt(me.mesh.position.x, me.mesh.position.z) : 'grass';
        this.audio.footstep(!movementState.isCrouching, surface);
      }
    }
  },

  // How long a thrown stone is in the air (same rule as launchProjectile), so the
  // hit sound lands with it.
  stoneFlightMs(this: any, casterId: string | null | undefined, targetId: string | null | undefined): number {
    const chars = this.characterManager?.getAllCharacters();
    const a = casterId ? chars?.get(casterId) : null;
    const b = targetId ? chars?.get(targetId) : null;
    if (!a || !b) return 350;
    return Math.max(250, Math.min(600, a.mesh.position.distanceTo(b.mesh.position) * 25));
  },

  // Distance from the local player to another character, for quieter far-away sounds.
  distanceToCharacter(this: any, characterId: string | null | undefined): number {
    const myId = this.state?.currentPlayer?.character_id;
    if (!characterId || !myId || characterId === myId) return 0;
    const chars = this.characterManager?.getAllCharacters();
    const me = chars?.get(myId);
    const other = chars?.get(characterId);
    if (!me || !other) return 0;
    return me.mesh.position.distanceTo(other.mesh.position);
  },

  shortestAngleDiff(this: any, from: number, to: number): number {
    let diff = to - from;
    while (diff > Math.PI) diff -= Math.PI * 2;
    while (diff < -Math.PI) diff += Math.PI * 2;
    return diff;
  },

  teardownWorldMode(this: any) {
    this.audio?.setMusic(false);
    this.teardownGame();
    if (this.positionHeartbeatInterval) {
      clearInterval(this.positionHeartbeatInterval);
      this.positionHeartbeatInterval = null;
    }
    if (this._pushPendingTimer) {
      clearTimeout(this._pushPendingTimer);
      this._pushPendingTimer = null;
    }
    this.controller?.dispose();
    this.controller = null;
    this.movementAccumulator = 0;
    this.lastPositionPushMs = 0;
    this.lastSentLocalPosition = null;
    this._pushPending = false;
    this.remoteNetTargets.clear();
    this.remoteLastSeenMs.clear();
    this.remoteSpeeds.clear();
    this.worldInitialized = false;
    this.remoteSyncInProgress = false;
    this.remoteSyncQueued = false;
    this.targetId = null;

    if (this.skySystem) {
      this.skySystem.dispose();
      this.skySystem = null;
    }

    if (this.dressing) {
      this.dressing.dispose();
      this.dressing = null;
      this.worldColliders = [];
    }

    if (this.targetRingMesh) {
      this.scene?.remove(this.targetRingMesh);
      this.targetRingMesh.geometry.dispose();
      (this.targetRingMesh.material as THREE.Material).dispose();
      this.targetRingMesh = null;
    }

    // Clear any in-flight projectiles
    for (const proj of this.activeProjectiles) {
      this.scene?.remove(proj.mesh);
      proj.mesh.geometry.dispose();
      (proj.mesh.material as THREE.Material).dispose();
    }
    this.activeProjectiles = [];

    // Clear floating damage texts
    for (const ft of this.floatingTexts) {
      ft.el.parentElement?.removeChild(ft.el);
    }
    this.floatingTexts = [];
    this.spellCooldowns = {};

    // Clean up death state
    this.isDead = false;
    this.deathSpawnCoords = null;
    if (this.deathCountdownInterval) {
      clearInterval(this.deathCountdownInterval);
      this.deathCountdownInterval = null;
    }
    if (this.deathOverlayEl) {
      this.deathOverlayEl.parentElement?.removeChild(this.deathOverlayEl);
      this.deathOverlayEl = null;
    }

    if (this.characterManager) {
      this.characterManager.dispose();
      this.characterManager = new CharacterModelManager();
      this.characterManager.setActiveScene(this.scene);
      this.characterManager.setHumanFactory(this.humanFactory);
    }

    if (this.worldGroup) {
      this.worldGroup.clear();
    }

    this.removeWorldOverlayUI();
    this.nameplates?.clear();
  },

  createWorldOverlayUI(this: any) {
    if (!this.el || this.nameplateLayer) return;

    const layer = document.createElement('div');
    layer.className = 'absolute inset-0 pointer-events-none';
    // Also inline: the windows inside must not depend on the site's Tailwind build.
    Object.assign(layer.style, { position: 'absolute', inset: '0', pointerEvents: 'none' });

    // The player, target and inventory windows and the hotbar (game-ui.ts).
    this.initGameUI(layer);

    // ── Chat panel (bottom-left) ─────────────────────────────────────────────
    const chatPanel = document.createElement('div');
    chatPanel.className = 'absolute left-3 bottom-3 w-[360px] max-w-[92%] rounded border border-[#6d5b3c] bg-[rgba(17,15,13,0.82)] text-[#e8dcc0] p-2 pointer-events-auto';

    const log = document.createElement('div');
    log.className = 'text-xs h-36 overflow-y-auto space-y-0.5 pr-1';
    log.setAttribute('data-chat-log', 'true');

    const form = document.createElement('form');
    form.className = 'mt-2 flex gap-2';

    const worldControls = document.createElement('div');
    worldControls.className = 'mb-2 flex items-center justify-between gap-2';

    const worldTitle = document.createElement('div');
    worldTitle.className = 'text-[11px] uppercase tracking-wide text-cyan-200/90';
    worldTitle.textContent = 'World Chat';

    const logoutButton = document.createElement('button');
    logoutButton.type = 'button';
    logoutButton.className = 'rounded bg-rose-700 hover:bg-rose-600 px-2 py-1 text-[11px] text-white';
    logoutButton.textContent = 'Logout';
    logoutButton.addEventListener('click', () => {
      (this.pushEvent('logout_character', {}) as any)?.catch?.(() => {});
    });

    const input = document.createElement('input');
    input.type = 'text';
    input.maxLength = 220;
    input.placeholder = 'Proximity chat (nearby players only)';
    input.className = 'flex-1 rounded bg-slate-900/80 border border-cyan-900/60 px-2 py-1 text-xs text-cyan-50 outline-none';

    const chatBtn = document.createElement('button');
    chatBtn.type = 'submit';
    chatBtn.className = 'rounded bg-cyan-700 hover:bg-cyan-600 px-2 py-1 text-xs text-white';
    chatBtn.textContent = 'Send';

    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const message = input.value.trim();
      if (!message) return;
      (this.pushEvent('world_chat_message', { message }) as any)?.catch?.(() => {});
      this.appendChatMessage('You', message);
      input.value = '';
    });

    form.appendChild(input);
    form.appendChild(chatBtn);
    worldControls.appendChild(worldTitle);
    worldControls.appendChild(logoutButton);
    chatPanel.appendChild(worldControls);
    chatPanel.appendChild(log);
    chatPanel.appendChild(form);
    layer.appendChild(chatPanel);

    // Mouse look (character-controller.ts): a centre dot while the pointer is
    // locked, and a short message when the browser refuses the lock. No
    // standing hint: the controls are in the game menu (Esc).
    const lookHint = document.createElement('div');
    lookHint.className = 'absolute bottom-24 left-1/2 -translate-x-1/2 text-[11px] text-cyan-200/80 bg-black/50 rounded px-2 py-0.5 select-none hidden';
    layer.appendChild(lookHint);

    const lookDot = document.createElement('div');
    lookDot.className = 'absolute top-1/2 left-1/2 w-1 h-1 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white/80 hidden';
    layer.appendChild(lookDot);

    layer.appendChild(this.buildGameMenu());

    this.el.appendChild(layer);

    this.nameplateLayer = layer;
    this.lookHintEl = lookHint;
    this.lookDotEl = lookDot;
    this.chatPanel = chatPanel;
    this.chatInput = input;

    this.chatOutsideClickHandler = (event: MouseEvent) => {
      const target = event.target as Node | null;
      if (!target) return;
      if (this.chatPanel && this.chatPanel.contains(target)) return;
      if (document.activeElement === this.chatInput) {
        this.chatInput?.blur();
      }
    };

    this.renderer?.domElement.addEventListener('pointerdown', this.chatOutsideClickHandler, true);

    // Sync initial stats from currentPlayer payload
    this.updateHUD();
  },

  updateLookHint(this: any, locked: boolean) {
    this.lookDotEl?.classList.toggle('hidden', !locked);
  },

  // A short message for a few seconds (e.g. the browser refused the lock).
  flashLookHint(this: any, text: string) {
    if (!this.lookHintEl) return;
    this.lookHintEl.textContent = text;
    this.lookHintEl.classList.remove('hidden');
    if (this.lookHintTimer) clearTimeout(this.lookHintTimer);
    this.lookHintTimer = setTimeout(() => {
      this.lookHintTimer = null;
      this.lookHintEl?.classList.add('hidden');
    }, 2500);
  },

  // ── Game menu (Esc) ────────────────────────────────────────────────────────

  isGameMenuOpen(this: any): boolean {
    return !!this.gameMenuEl && !this.gameMenuEl.classList.contains('hidden');
  },

  handleGameEscape(this: any, reason: 'key' | 'lock-lost') {
    if (this.isDead) return;
    // Esc closes the inventory or loot window (or drops what the cursor holds) first.
    if (reason === 'key' && this.gameUI?.closeTop()) return;
    if (reason === 'lock-lost') {
      this.openGameMenu();
      return;
    }
    // The same Esc can arrive as a lost lock and then as the key: don't close
    // a menu that has only just opened.
    if (this.isGameMenuOpen()) {
      if (performance.now() - this.gameMenuOpenedAtMs > 250) this.closeGameMenu();
    } else {
      this.openGameMenu();
    }
  },

  openGameMenu(this: any) {
    if (!this.gameMenuEl || this.isGameMenuOpen()) return;
    this.gameMenuEl.classList.remove('hidden');
    this.gameMenuOpenedAtMs = performance.now();
    this.controller?.setInputEnabled(false);
    this.syncGameMenu();
    this.updateLookHint(false);
  },

  closeGameMenu(this: any) {
    if (!this.gameMenuEl) return;
    this.gameMenuEl.classList.add('hidden');
    this.controller?.setInputEnabled(true);
    this.updateLookHint(!!this.controller?.isPointerLocked());
  },

  // Refresh the menu's controls from the current settings.
  syncGameMenu(this: any) {
    const menu = this.gameMenuEl;
    if (!menu) return;
    const sens = menu.querySelector('[data-menu-sensitivity]') as HTMLInputElement | null;
    const sensValue = menu.querySelector('[data-menu-sensitivity-value]') as HTMLElement | null;
    const invert = menu.querySelector('[data-menu-invert]') as HTMLInputElement | null;
    const sound = menu.querySelector('[data-menu-sound]') as HTMLButtonElement | null;
    const value = Number(readSetting(MOUSE_SENS_KEY)) || SENSITIVITY.default;
    if (sens) sens.value = String(value);
    if (sensValue) sensValue.textContent = `${value.toFixed(2)}×`;
    if (invert) invert.checked = readSetting(INVERT_Y_KEY) === 'on';
    if (sound) sound.textContent = this.audio?.enabled ? 'Sound: ON' : 'Sound: OFF';
    for (const kind of ['effects', 'ambience', 'music'] as const) {
      const v = this.audio?.getVolume(kind) ?? 0;
      const slider = menu.querySelector(`[data-menu-volume="${kind}"]`) as HTMLInputElement | null;
      const readout = menu.querySelector(`[data-menu-volume-value="${kind}"]`) as HTMLElement | null;
      if (slider) slider.value = String(Math.round(v * 100));
      if (readout) readout.textContent = `${Math.round(v * 100)}%`;
    }
    const quality = menu.querySelector('[data-menu-quality]') as HTMLButtonElement | null;
    const q = readSetting(QUALITY_KEY) || 'auto';
    if (quality) quality.textContent = `Resolution: ${q === 'auto' ? 'Auto' : q === 'full' ? 'Full' : 'Low'}`;
  },

  buildGameMenu(this: any): HTMLDivElement {
    const backdrop = document.createElement('div');
    backdrop.className = 'absolute inset-0 hidden bg-black/60 flex items-center justify-center pointer-events-auto z-50';
    backdrop.setAttribute('data-game-menu', 'true');

    const panel = document.createElement('div');
    panel.className = 'w-[320px] max-w-[92%] max-h-[94vh] overflow-y-auto rounded-lg border border-cyan-900/70 bg-slate-950/95 p-4 text-cyan-50 shadow-[0_0_40px_rgba(34,211,238,0.15)]';
    backdrop.appendChild(panel);

    const title = document.createElement('div');
    title.className = 'text-sm font-bold uppercase tracking-wide text-cyan-200 mb-3';
    title.textContent = 'Game Menu';
    panel.appendChild(title);

    const button = (label: string, cls: string, onClick: () => void) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = `w-full rounded px-3 py-2 text-sm mb-2 ${cls}`;
      b.textContent = label;
      b.addEventListener('click', onClick);
      return b;
    };

    // Resume locks the pointer straight away (this click is the gesture browsers need).
    panel.appendChild(button('Resume', 'bg-cyan-700 hover:bg-cyan-600 text-white', () => {
      this.closeGameMenu();
      this.controller?.requestPointerLock();
    }));

    // Mouse sensitivity
    const sensRow = document.createElement('label');
    sensRow.className = 'block text-xs text-slate-300 mt-2 mb-1';
    const sensText = document.createElement('div');
    sensText.className = 'flex justify-between';
    const sensLabel = document.createElement('span');
    sensLabel.textContent = 'Mouse sensitivity';
    const sensValue = document.createElement('span');
    sensValue.setAttribute('data-menu-sensitivity-value', 'true');
    sensText.appendChild(sensLabel);
    sensText.appendChild(sensValue);
    const sens = document.createElement('input');
    sens.type = 'range';
    sens.min = String(SENSITIVITY.min);
    sens.max = String(SENSITIVITY.max);
    sens.step = '0.05';
    sens.className = 'w-full accent-cyan-500';
    sens.setAttribute('data-menu-sensitivity', 'true');
    sens.addEventListener('input', () => {
      const value = Number(sens.value);
      writeSetting(MOUSE_SENS_KEY, String(value));
      sensValue.textContent = `${value.toFixed(2)}×`;
      this.controller?.setMouseSettings(value, readSetting(INVERT_Y_KEY) === 'on');
    });
    sensRow.appendChild(sensText);
    sensRow.appendChild(sens);
    panel.appendChild(sensRow);

    // Invert mouse Y
    const invertRow = document.createElement('label');
    invertRow.className = 'flex items-center gap-2 text-xs text-slate-300 mb-3 cursor-pointer';
    const invert = document.createElement('input');
    invert.type = 'checkbox';
    invert.className = 'accent-cyan-500';
    invert.setAttribute('data-menu-invert', 'true');
    invert.addEventListener('change', () => {
      writeSetting(INVERT_Y_KEY, invert.checked ? 'on' : 'off');
      this.controller?.setMouseSettings(Number(readSetting(MOUSE_SENS_KEY)) || SENSITIVITY.default, invert.checked);
    });
    const invertText = document.createElement('span');
    invertText.textContent = 'Invert mouse Y';
    invertRow.appendChild(invert);
    invertRow.appendChild(invertText);
    panel.appendChild(invertRow);

    // Sound: all of it on or off (the same switch as the player window's button), and a
    // volume for each part.
    const sound = button('Sound', 'bg-slate-700 hover:bg-slate-600 text-slate-100', () => {
      this.audio?.toggle();
      this.syncGameMenu();
      this.updateHUD();
    });
    sound.setAttribute('data-menu-sound', 'true');
    panel.appendChild(sound);
    const volumes: Array<['effects' | 'ambience' | 'music', string]> = [
      ['effects', 'Effects volume'],
      ['ambience', 'Nature volume'],
      ['music', 'Music volume'],
    ];
    for (const [kind, label] of volumes) {
      const row = document.createElement('label');
      row.className = 'block text-xs text-slate-300 mb-1';
      const text = document.createElement('div');
      text.className = 'flex justify-between';
      const name = document.createElement('span');
      name.textContent = label;
      const readout = document.createElement('span');
      readout.setAttribute('data-menu-volume-value', kind);
      text.appendChild(name);
      text.appendChild(readout);
      const slider = document.createElement('input');
      slider.type = 'range';
      slider.min = '0';
      slider.max = '100';
      slider.step = '1';
      slider.className = 'w-full accent-cyan-500';
      slider.setAttribute('data-menu-volume', kind);
      slider.addEventListener('input', () => {
        this.audio?.setVolume(kind, Number(slider.value) / 100);
        readout.textContent = `${slider.value}%`;
      });
      row.appendChild(text);
      row.appendChild(slider);
      panel.appendChild(row);
    }

    // Graphics: resolution (auto lowers it when frames are slow).
    const quality = button('Resolution', 'bg-slate-700 hover:bg-slate-600 text-slate-100', () => {
      const order = ['auto', 'full', 'low'];
      const cur = readSetting(QUALITY_KEY) || 'auto';
      const next = order[(order.indexOf(cur) + 1) % order.length];
      writeSetting(QUALITY_KEY, next);
      if (this.perf && next === 'auto') this.perf.scale = 1;
      this.renderer?.setPixelRatio((this.basePixelRatio || 1) * this.qualityScale());
      this.handleResize();
      this.syncGameMenu();
    });
    quality.setAttribute('data-menu-quality', 'true');
    panel.appendChild(quality);
    const fps = document.createElement('div');
    fps.className = 'text-[11px] text-slate-500 mb-2';
    fps.setAttribute('data-menu-fps', 'true');
    panel.appendChild(fps);

    // Controls
    const help = document.createElement('div');
    help.className = 'text-[11px] leading-5 text-slate-400 border-t border-slate-800 pt-2 mt-1 mb-3';
    help.innerHTML = [
      '<b class="text-slate-300">Click</b> mouse-look on · <b class="text-slate-300">Ctrl</b> cursor back',
      'Mouse-look on: <b class="text-slate-300">left / right button</b> swing your left / right hand (hold to keep swinging)',
      'Cursor free: <b class="text-slate-300">hold right button</b> to steer · <b class="text-slate-300">right-click</b> a corpse to loot it',
      '<b class="text-slate-300">WASD</b> move · <b class="text-slate-300">Shift</b> sprint · <b class="text-slate-300">C</b> crouch · <b class="text-slate-300">Space</b> jump · <b class="text-slate-300">Wheel</b> zoom',
      '<b class="text-slate-300">I</b> inventory · <b class="text-slate-300">G</b> loot nearest corpse · <b class="text-slate-300">Tab</b> next target · <b class="text-slate-300">1</b> throw stone',
      '<b class="text-slate-300">Q E F Z X</b> special attacks (earned in the skill tree) · <b class="text-slate-300">Enter</b> chat · <b class="text-slate-300">Esc</b> this menu',
    ].join('<br>');
    panel.appendChild(help);

    panel.appendChild(button('Log out', 'bg-rose-700 hover:bg-rose-600 text-white', () => {
      this.closeGameMenu();
      (this.pushEvent('logout_character', {}) as any)?.catch?.(() => {});
    }));

    // Clicking outside the panel closes the menu.
    backdrop.addEventListener('click', (event) => {
      if (event.target === backdrop) this.closeGameMenu();
    });

    this.gameMenuEl = backdrop;
    return backdrop;
  },

  removeWorldOverlayUI(this: any) {
    if (this.nameplateLayer && this.nameplateLayer.parentElement) {
      this.nameplateLayer.parentElement.removeChild(this.nameplateLayer);
    }
    this.nameplateLayer = null;
    this.lookHintEl = null;
    this.lookDotEl = null;
    this.gameMenuEl = null;
    if (this.lookHintTimer) {
      clearTimeout(this.lookHintTimer);
      this.lookHintTimer = null;
    }
    this.chatPanel = null;
    this.chatInput = null;
    this.gameUI?.dispose();
    this.gameUI = null;

    if (this.chatOutsideClickHandler) {
      this.renderer?.domElement.removeEventListener('pointerdown', this.chatOutsideClickHandler, true);
      this.chatOutsideClickHandler = null;
    }
  },

  // ── Death / Respawn ────────────────────────────────────────────────────────

  enterDeathState(this: any, respawnInMs: number) {
    this.isDead = true;
    this.closeGameMenu();
    this.controller?.releasePointerLock();

    // Play death animation on local character
    const myId = this.state?.currentPlayer?.character_id;
    if (myId) this.characterManager?.playCharacterAnimation(myId, 'death', false);

    // Build overlay
    const overlay = document.createElement('div');
    overlay.setAttribute('data-death-overlay', 'true');
    overlay.style.cssText = [
      'position:absolute', 'inset:0', 'display:flex', 'flex-direction:column',
      'align-items:center', 'justify-content:center',
      'background:rgba(0,0,0,0)', 'transition:background 1.5s ease',
      'pointer-events:auto', 'z-index:100'
    ].join(';');

    const title = document.createElement('div');
    title.textContent = 'You Died';
    title.style.cssText = [
      'color:#c00', 'font-size:4rem', 'font-weight:900',
      'text-shadow:0 0 24px #f00,0 0 8px #800',
      'letter-spacing:0.15em', 'opacity:0', 'transition:opacity 1.5s ease',
      'margin-bottom:1.5rem', 'font-family:serif'
    ].join(';');

    const countdownEl = document.createElement('div');
    countdownEl.setAttribute('data-death-countdown', 'true');
    countdownEl.style.cssText = [
      'color:#ddd', 'font-size:1rem', 'margin-bottom:1.5rem',
      'text-shadow:0 0 6px #000'
    ].join(';');

    const respawnBtn = document.createElement('button');
    respawnBtn.textContent = 'Respawn Now';
    respawnBtn.style.cssText = [
      'background:#7f1d1d', 'color:#fff', 'border:1px solid #ef4444',
      'padding:0.5rem 1.5rem', 'border-radius:0.375rem',
      'font-size:0.875rem', 'cursor:pointer',
      'transition:background 0.2s'
    ].join(';');
    respawnBtn.onmouseenter = () => { respawnBtn.style.background = '#991b1b'; };
    respawnBtn.onmouseleave = () => { respawnBtn.style.background = '#7f1d1d'; };
    respawnBtn.onclick = () => { this.pushEvent('respawn_now', {}); };

    overlay.appendChild(title);
    overlay.appendChild(countdownEl);
    overlay.appendChild(respawnBtn);
    this.el.appendChild(overlay);
    this.deathOverlayEl = overlay;

    // Fade in the darkening
    requestAnimationFrame(() => {
      overlay.style.background = 'rgba(0,0,0,0.72)';
      title.style.opacity = '1';
    });

    // Countdown ticker
    let remaining = Math.ceil(respawnInMs / 1000);
    const updateCountdown = () => {
      countdownEl.textContent = `Respawning at zone entrance in: ${remaining}s`;
    };
    updateCountdown();
    this.deathCountdownInterval = setInterval(() => {
      remaining -= 1;
      if (remaining <= 0) {
        clearInterval(this.deathCountdownInterval);
        this.deathCountdownInterval = null;
        countdownEl.textContent = 'Respawning…';
      } else {
        updateCountdown();
      }
    }, 1000);
  },

  exitDeathState(this: any) {
    this.isDead = false;

    if (this.deathCountdownInterval) {
      clearInterval(this.deathCountdownInterval);
      this.deathCountdownInterval = null;
    }

    if (this.deathOverlayEl) {
      // Fade out then remove
      this.deathOverlayEl.style.transition = 'opacity 0.8s ease';
      this.deathOverlayEl.style.opacity = '0';
      const el = this.deathOverlayEl;
      setTimeout(() => el.parentElement?.removeChild(el), 850);
      this.deathOverlayEl = null;
    }
  },

  appendChatMessage(this: any, sender: string, message: string) {
    if (!this.chatPanel) return;
    const log = this.chatPanel.querySelector('[data-chat-log="true"]') as HTMLDivElement | null;
    if (!log) return;

    const entry = document.createElement('div');
    entry.className = 'leading-tight';
    entry.textContent = `${sender}: ${message}`;
    log.appendChild(entry);
    log.scrollTop = log.scrollHeight;

    while (log.childElementCount > 16) {
      log.removeChild(log.firstElementChild as Node);
    }
  },

  handleWorldKeyDown(this: any, event: KeyboardEvent) {
    if (this.state?.uiState !== 'world') return;

    const target = event.target as HTMLElement | null;
    const isTyping = target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName);

    // Prevent movement keys from reaching the CharacterController while typing
    if (isTyping) {
      if (event.key === 'Escape') {
        (target as HTMLElement).blur();
        event.preventDefault();
        event.stopImmediatePropagation();
        return;
      }

      const movementKeys = [
        'KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
        'Space', 'ShiftLeft', 'ShiftRight', 'KeyC'
      ];
      if (movementKeys.includes(event.code)) {
        event.stopImmediatePropagation();
      }
      return;
    }

    // Tab: cycle targets
    if (event.key === 'Tab') {
      event.preventDefault();
      this.tabCycleTarget();
      return;
    }

    // 1: cast Throw Stone
    if (event.key === '1' && !this.isGameMenuOpen()) {
      this.castSpell('throw_stone');
      return;
    }

    // I: inventory; G: loot the nearest corpse
    if ((event.key === 'i' || event.key === 'I') && !this.isGameMenuOpen()) {
      this.gameUI?.toggleInventory();
      return;
    }
    if ((event.key === 'g' || event.key === 'G') && !this.isGameMenuOpen() && !this.isDead) {
      this.lootNearest();
      return;
    }

    // "/" starts a slash command: chat opens with the slash already typed.
    if (event.key === '/' && this.chatInput && !this.isGameMenuOpen()) {
      event.preventDefault();
      this.controller?.releasePointerLock();
      this.chatInput.value = '/';
      this.chatInput.focus();
      this.chatInput.setSelectionRange(1, 1);
      return;
    }

    if (event.key !== 'Enter') return;
    if (!this.chatInput || this.isGameMenuOpen()) return;
    event.preventDefault();
    this.controller?.releasePointerLock();
    this.chatInput.focus();
  },

  // Every character's name over its head (nameplates.ts). Runs after everything
  // has moved this frame, so the names are drawn exactly where the heads are.
  updateNameplates(this: any) {
    if (!this.camera || !this.characterManager || !this.nameplates) return;
    const keep = new Set<string>();
    this.characterManager.getAllCharacters().forEach((character: any, id: string) => {
      keep.add(id);
      const human = !!this.characterManager.getHuman(id);
      const known = this.nameplates.has(id);
      this.nameplates.set(
        id,
        character.mesh,
        { name: character.name, color: PLAYER_COLOR },
        {
          // Measured once (bounds are costly); humans follow their height.
          height: human || !known ? plateHeight(character.mesh, human) : undefined,
          target: id === this.targetId,
        }
      );
    });
    this.mobsView?.nameplateIds?.forEach((id: string) => keep.add(id));
    this.nameplates.prune(keep);
    this.nameplates.update(this.camera);
  },

  clearPanels(this: any) {
    if (!this.scene) return;

    this.panelMeshes.forEach((mesh: THREE.Mesh) => {
      this.scene?.remove(mesh);
      mesh.geometry.dispose();
      const material = mesh.material as THREE.MeshStandardMaterial;
      if (material.map) material.map.dispose();
      material.dispose();
    });

    this.panelMeshes = [];
    this.panelTargets = [];
  },

  buildPanelsFromState(this: any) {
    if (!this.scene || !this.state) return;

    if (this.state.uiState === 'world') return;

    this.clearPanels();

    const panels: PanelData[] = [];

    if (this.state.uiState === 'intro') {
      panels.push({ panelId: 'intro', label: 'Welcome. Create your first character.' });
      panels.push({ panelId: 'creator', label: 'Click to create from 3D panel' });
    } else {
      panels.push({ panelId: 'creator', label: 'Click to create another (max 16)' });

      this.state.characters.slice(0, 5).forEach((character) => {
        panels.push({
          panelId: `char-${character.id}`,
          label: `${character.name} [${character.character_type}]`,
          characterId: character.id
        });
      });

      panels.push({ panelId: 'login', label: this.state.canLogin ? 'Login is ready' : 'Select character to login' });

      if (this.state.selectedCharacterId) {
        panels.push({ panelId: 'delete', label: 'Delete selected character' });
      }

      if (this.state.onlineCharacters.length > 0) {
        panels.push({ panelId: 'presence', label: `${this.state.onlineCharacters.length} online in zone` });
      }
    }

    panels.forEach((panel, index) => {
      const mesh = this.createPanelMesh(panel);

      const columns = Math.min(3, panels.length);
      const row = Math.floor(index / columns);
      const column = index % columns;

      const spacingX = 4.9;
      const spacingY = 2.8;
      const targetX = (column - (columns - 1) / 2) * spacingX;
      const targetY = 2.6 - row * spacingY;
      const targetZ = 0;

      mesh.position.set(targetX + 10 + index * 0.3, targetY + 1.4, -8);
      mesh.userData = {
        panelId: panel.panelId,
        characterId: panel.characterId || null
      };

      this.panelMeshes.push(mesh);
      this.panelTargets.push({ mesh, targetX, targetY, targetZ });
      this.scene?.add(mesh);
    });
  },

  createPanelMesh(this: any, panel: PanelData): THREE.Mesh {
    const isSelectedCharacter = panel.characterId && panel.characterId === this.state?.selectedCharacterId;
    const isLoginPanel = panel.panelId === 'login';
    const isPresencePanel = panel.panelId === 'presence';
    const isDeletePanel = panel.panelId === 'delete';

    const geometry = new THREE.PlaneGeometry(4.2, 1.7, 1, 1);
    const texture = this.createLabelTexture(panel.label);
    const material = new THREE.MeshStandardMaterial({
      color: isSelectedCharacter ? 0x2563eb : isLoginPanel ? 0x10b981 : isDeletePanel ? 0xdc2626 : isPresencePanel ? 0x9333ea : 0x23364d,
      emissive: isSelectedCharacter ? 0x1d4ed8 : isLoginPanel ? 0x064e3b : isDeletePanel ? 0x7f1d1d : isPresencePanel ? 0x4c1d95 : 0x102033,
      emissiveIntensity: isSelectedCharacter ? 0.78 : 0.55,
      metalness: 0.12,
      roughness: 0.48,
      map: texture,
      transparent: true,
      opacity: 1
    });

    const mesh = new THREE.Mesh(geometry, material);
    mesh.scale.setScalar(isSelectedCharacter ? 1.06 : 1);
    return mesh;
  },

  createLabelTexture(this: any, text: string): THREE.CanvasTexture {
    const canvas = document.createElement('canvas');
    canvas.width = 1024;
    canvas.height = 384;

    const ctx = canvas.getContext('2d');
    if (!ctx) return new THREE.CanvasTexture(canvas);

    const gradient = ctx.createLinearGradient(0, 0, canvas.width, canvas.height);
    gradient.addColorStop(0, '#13263f');
    gradient.addColorStop(1, '#223a57');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.strokeStyle = 'rgba(125, 211, 252, 0.95)';
    ctx.lineWidth = 12;
    ctx.strokeRect(8, 8, canvas.width - 16, canvas.height - 16);

    ctx.fillStyle = '#f8fafc';
    ctx.font = 'bold 72px "Trebuchet MS", "Verdana", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    const lines = this.wrapText(ctx, text, 900);
    const startY = canvas.height / 2 - ((lines.length - 1) * 74) / 2;

    lines.forEach((line: string, index: number) => {
      ctx.fillText(line, canvas.width / 2, startY + index * 74);
    });

    const texture = new THREE.CanvasTexture(canvas);
    texture.needsUpdate = true;
    return texture;
  },

  wrapText(this: any, ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string[] {
    const words = text.split(' ');
    const lines: string[] = [];
    let current = '';

    words.forEach((word) => {
      const test = current ? `${current} ${word}` : word;
      if (ctx.measureText(test).width > maxWidth && current) {
        lines.push(current);
        current = word;
      } else {
        current = test;
      }
    });

    if (current) lines.push(current);
    return lines.slice(0, 3);
  },

  // ── Frame rate and resolution ─────────────────────────────────────────────
  // "Auto" lowers the rendering resolution while the game runs below ~38 fps and
  // raises it again above ~57 (remote desktop often renders without the GPU);
  // "Full" and "Low" fix it. The menu shows the frame rate.

  qualityScale(this: any): number {
    const mode = readSetting(QUALITY_KEY) || 'auto';
    if (mode === 'low') return 0.55;
    if (mode === 'full') return 1;
    return this.perf?.scale ?? 1;
  },

  adaptQuality(this: any, dt: number) {
    if (!this.renderer || !(dt > 0)) return;
    const perf = (this.perf ||= { ema: 1 / 60, t: 0, scale: 1, fps: 60 });
    perf.ema += (Math.min(dt, 0.5) - perf.ema) * 0.05;
    perf.t += dt;
    if (perf.t < 2) return;
    perf.t = 0;
    perf.fps = 1 / perf.ema;
    const fpsEl = this.gameMenuEl?.querySelector('[data-menu-fps]') as HTMLElement | null;
    if (fpsEl) {
      // Over remote desktop, say so: the mouse filter is mending the jumps it sends.
      const mouse = this.controller?.mouseStats();
      const remote = mouse?.remoteDesktop ? ` · remote-desktop mouse (${mouse.repaired} fixed)` : '';
      fpsEl.textContent = `${Math.round(perf.fps)} fps · ${Math.round(this.qualityScale() * 100)}% resolution${remote}`;
    }
    if ((readSetting(QUALITY_KEY) || 'auto') !== 'auto' || this.state?.uiState !== 'world') return;
    let next = perf.scale;
    if (perf.fps < 38 && perf.scale > 0.5) next = Math.max(0.5, perf.scale - 0.15);
    else if (perf.fps > 57 && perf.scale < 1) next = Math.min(1, perf.scale + 0.1);
    if (next !== perf.scale) {
      perf.scale = next;
      this.renderer.setPixelRatio((this.basePixelRatio || 1) * next);
      this.handleResize();
    }
  },

  handleResize(this: any) {
    if (!this.renderer || !this.camera) return;
    const width = this.el.clientWidth || window.innerWidth;
    const height = this.el.clientHeight || 480;

    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height);
    this.stage?.applyViewOffset();
  },

  sendLocalPosition(this: any, x: number, y: number, z: number, heading: number, force = false) {
    // Don't send if a previous push is still in-flight — prevents flooding long-poll
    if (this._pushPending) return;

    const now = performance.now();
    const prev = this.lastSentLocalPosition;

    const moved =
      !prev ||
      Math.abs(x - prev.x) > 0.01 ||
      Math.abs(y - prev.y) > 0.01 ||
      Math.abs(z - prev.z) > 0.01 ||
      Math.abs(this.shortestAngleDiff(prev.heading, heading)) > 0.015;

    const heartbeatDue = !prev || now - this.lastPositionPushMs >= 300;

    if (!force && now - this.lastPositionPushMs < 50) return;
    if (!force && !moved && !heartbeatDue) return;

    this.lastPositionPushMs = now;
    this.lastSentLocalPosition = { x, y, z, heading };
    this._pushPending = true;

    // Watchdog: auto-reset after 5 s in case the promise never resolves
    if (this._pushPendingTimer) clearTimeout(this._pushPendingTimer);
    this._pushPendingTimer = setTimeout(() => {
      this._pushPending = false;
      this._pushPendingTimer = null;
    }, 5000);

    const clearPending = () => {
      this._pushPending = false;
      if (this._pushPendingTimer) {
        clearTimeout(this._pushPendingTimer);
        this._pushPendingTimer = null;
      }
    };

    try {
      const p = this.pushEvent('world_position_update', { x, y, z, heading });
      if (p && typeof p.then === 'function') {
        p.then(clearPending, clearPending);
      } else {
        clearPending();
      }
    } catch (_e) {
      clearPending();
    }
  },

  resetSelectionCamera(this: any) {
    if (!this.camera) return;
    this.camera.position.set(0, 0.25, 11.5);
    this.camera.lookAt(0, 0, 0);
  },

  // handleClick is now defined later and handles both world targeting + selection mode.

  showCharacterCreator(this: any) {
    if (this.creatorOverlay) return;

    const overlay = document.createElement('div');
    overlay.className = 'absolute inset-0 bg-black/75 flex items-center justify-center pointer-events-auto';
    overlay.style.zIndex = '20';

    const panel = document.createElement('div');
    panel.className = 'bg-slate-900 border border-cyan-700/60 rounded-2xl p-6 w-80 shadow-2xl text-cyan-50';

    // Block all keyboard events from leaving the panel (prevents model movement while typing)
    const stopProp = (e: Event) => e.stopImmediatePropagation();
    panel.addEventListener('keydown', stopProp, true);
    panel.addEventListener('keyup', stopProp, true);

    const titleEl = document.createElement('h2');
    titleEl.textContent = 'Create Character';
    titleEl.className = 'text-lg font-bold mb-4 text-cyan-200';

    const mkInput = (placeholder: string) => {
      const inp = document.createElement('input');
      inp.type = 'text';
      inp.placeholder = placeholder;
      inp.className = 'w-full rounded bg-slate-800 border border-cyan-900/60 px-3 py-2 text-sm text-cyan-50 outline-none focus:border-cyan-500 mb-3';
      return inp;
    };

    const nameInput = mkInput('Name (min 2 chars)');
    const typeInput = mkInput('Type / Class (min 2 chars)');

    const modelSelect = document.createElement('select');
    modelSelect.className = 'w-full rounded bg-slate-800 border border-cyan-900/60 px-3 py-2 text-sm text-cyan-50 outline-none focus:border-cyan-500 mb-4';

    const defaultOpt = document.createElement('option');
    defaultOpt.value = '';
    defaultOpt.textContent = '— Choose model —';
    modelSelect.appendChild(defaultOpt);

    const models: Array<{ label: string; model_path: string }> = this.state?.availableModels || [];
    models.forEach((model) => {
      const opt = document.createElement('option');
      opt.value = model.model_path;
      opt.textContent = model.label;
      modelSelect.appendChild(opt);
    });

    const btnRow = document.createElement('div');
    btnRow.className = 'flex gap-2 mt-1';

    const createBtn = document.createElement('button');
    createBtn.textContent = 'Create';
    createBtn.className = 'flex-1 rounded bg-cyan-700 hover:bg-cyan-600 py-2 text-sm font-semibold';

    const cancelBtn = document.createElement('button');
    cancelBtn.textContent = 'Cancel';
    cancelBtn.className = 'flex-1 rounded bg-slate-700 hover:bg-slate-600 py-2 text-sm';

    createBtn.addEventListener('click', () => {
      const name = nameInput.value.trim();
      const characterType = typeInput.value.trim();
      const modelPath = modelSelect.value;
      this.removeCharacterCreator();
      (this.pushEvent('three_ui_create_character', { name, character_type: characterType, model_path: modelPath }) as any)?.catch?.(() => {});
    });

    cancelBtn.addEventListener('click', () => this.removeCharacterCreator());

    btnRow.appendChild(createBtn);
    btnRow.appendChild(cancelBtn);
    panel.appendChild(titleEl);
    panel.appendChild(nameInput);
    panel.appendChild(typeInput);
    panel.appendChild(modelSelect);
    panel.appendChild(btnRow);
    overlay.appendChild(panel);
    this.el.appendChild(overlay);

    this.creatorOverlay = overlay;
    nameInput.focus();
  },

  removeCharacterCreator(this: any) {
    if (this.creatorOverlay?.parentElement) {
      this.creatorOverlay.parentElement.removeChild(this.creatorOverlay);
    }
    this.creatorOverlay = null;
  },

  flashLoginPanel(this: any) {
    if (this.state?.uiState === 'world') {
      return;
    }
    this.panelMeshes.forEach((mesh: THREE.Mesh) => {
      if (mesh.userData.panelId === 'login') {
        const material = mesh.material as THREE.MeshStandardMaterial;
        material.emissiveIntensity = 1.0;
        setTimeout(() => {
          material.emissiveIntensity = 0.35;
        }, 500);
      }
    });
  },

  animate(this: any) {
    if (!this.renderer || !this.scene || !this.camera) return;

    // Real elapsed time (up to 0.25 s): clamping it shorter made slow machines and
    // remote desktop run in slow motion and then catch up in spurts.
    const rawDelta = this.frameClock.getDelta();
    const deltaSeconds = Math.min(rawDelta, 0.25);
    this.adaptQuality(rawDelta);

    this.panelTargets.forEach(({ mesh, targetX, targetY, targetZ }) => {
      mesh.position.x += (targetX - mesh.position.x) * 0.08;
      mesh.position.y += (targetY - mesh.position.y) * 0.08;
      mesh.position.z += (targetZ - mesh.position.z) * 0.08;
      mesh.rotation.y += (0 - mesh.rotation.y) * 0.08;
      mesh.rotation.x += (0 - mesh.rotation.x) * 0.08;
    });

    if (this.ambientStars) {
      this.ambientStars.rotation.y += 0.0008;
    }

    if (this.stage?.isVisible) {
      this.stage.update(deltaSeconds);
    }

    // Day/night sky tick (only in world mode, SkySystem controls ambient+sky)
    if (this.worldInitialized && this.skySystem) {
      this.skySystem.tick();
      if (this.dressing && this.ambientLight) this.dressing.tick((this.ambientLight.intensity - 0.04) / 0.81);
    }

    if (this.state?.uiState === 'world') {
      // Freeze controller while dead — character cannot move
      if (!this.isDead) {
        // Walls, stalls and trees are kept out inside the controller (its `collide`
        // option), before it places the camera and reports the position.
        this.controller?.update(deltaSeconds);
      }

      const currentId = this.state?.currentPlayer?.character_id;
      const localCharacter = currentId ? this.characterManager?.getAllCharacters().get(currentId) : null;
      if (!localCharacter) {
        this._noCharFrames = (this._noCharFrames || 0) + 1;
      } else {
        this._noCharFrames = 0;
        this.sendLocalPosition(
          localCharacter.mesh.position.x,
          localCharacter.mesh.position.y,
          localCharacter.mesh.position.z,
          localCharacter.mesh.rotation.y
        );
      }

      this.applyRemoteSmoothing(deltaSeconds);
      this.syncCharacterAnimations();
      this.characterManager?.updateAnimations(deltaSeconds);
      this.tickGame(deltaSeconds);
      this.updateNameplates();
      this.tickTargetRing();
      this.tickProjectiles();
      this.tickFloatingTexts();
    }

    this.renderer.render(this.scene, this.camera);
    this.animationFrame = requestAnimationFrame(() => this.animate());
  },

  // ── Targeting ───────────────────────────────────────────────────────────────

  handleClick(this: any, event: MouseEvent) {
    if (!this.state?.uiState || this.state.uiState !== 'world') {
      this._handleSelectionClick(event);
      return;
    }

    // In world mode: ray-cast for characters (targeting). With the pointer locked
    // the cursor is hidden, so aim at the centre of the screen (the dot).
    if (!this.camera || !this.renderer) return;
    if (!this.pointer) return;
    // A click with the cursor free also grabs the mouse: it can pick a target,
    // but missing shouldn't drop the one you have.
    const grabbing = !this.controller?.isPointerLocked();
    if (this.controller?.isPointerLocked()) {
      this.pointer.set(0, 0);
    } else {
      const rect = this.renderer.domElement.getBoundingClientRect();
      this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    }
    this.raycaster!.setFromCamera(this.pointer, this.camera);

    // Creatures first: a click targets one; with the cursor free, clicking a corpse loots it.
    const mobId = this.pickMob(this.raycaster);
    if (mobId) {
      const mob = this.mobsView?.get(mobId);
      if (mob?.view.state === 'dead' && grabbing) {
        void this.openLoot(mobId);
      }
      this.setTarget(mobId);
      return;
    }

    const allMeshes: THREE.Object3D[] = [];
    this.characterManager?.getAllCharacters().forEach((ch: any, id: string) => {
      if (id !== this.state?.currentPlayer?.character_id) {
        allMeshes.push(ch.mesh);
      }
    });

    const hits = this.raycaster!.intersectObjects(allMeshes, true);
    if (hits.length > 0) {
      let obj: THREE.Object3D | null = hits[0].object;
      while (obj) {
        const foundId = this.findCharacterIdForMesh(obj);
        if (foundId) {
          this.setTarget(foundId);
          return;
        }
        obj = obj.parent;
      }
    }

    // A click on nothing keeps the target: with mouse-look on, clicks are swings.
  },

  // EverQuest's right-click: a quick right click (not a steering drag) on a corpse
  // loots it, on a creature targets it. Only with the cursor free.
  handleRightButton(this: any, event: MouseEvent) {
    if (event.button !== 2 || this.state?.uiState !== 'world' || this.controller?.isPointerLocked()) return;
    if (event.type === 'mousedown') {
      this.rmbDown = { x: event.clientX, y: event.clientY, t: performance.now() };
      return;
    }
    const down = this.rmbDown;
    this.rmbDown = null;
    if (!down || performance.now() - down.t > 350 || Math.hypot(event.clientX - down.x, event.clientY - down.y) > 6) return;
    if (!this.camera || !this.renderer || !this.pointer || !this.raycaster) return;
    const rect = this.renderer.domElement.getBoundingClientRect();
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const mobId = this.pickMob(this.raycaster);
    if (!mobId) return;
    if (this.mobsView?.get(mobId)?.view.state === 'dead') void this.openLoot(mobId);
    this.setTarget(mobId);
  },

  _handleSelectionClick(this: any, event: MouseEvent) {
    // The select screen and creator are HTML (front-ui.ts); the stage handles dragging.
    if (this.stage?.isVisible) return;
    if (!this.camera || !this.renderer) return;
    const rect = this.renderer.domElement.getBoundingClientRect();
    if (!this.pointer) return;
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    this.raycaster!.setFromCamera(this.pointer, this.camera);

    const intersects = this.raycaster!.intersectObjects(this.panelMeshes, false);
    if (intersects.length === 0) return;

    const first = intersects[0].object as THREE.Mesh;
    const { panelId, characterId } = first.userData || {};

    if (characterId) {
      (this.pushEvent('select_character', { character_id: characterId }) as any)?.catch?.(() => {});
      return;
    }

    if (panelId === 'login' && this.state?.canLogin) {
      (this.pushEvent('login_character', {}) as any)?.catch?.(() => {});
      return;
    }

    if (panelId === 'delete' && this.state?.selectedCharacterId) {
      const character = this.state.characters.find((c: CharacterCard) => c.id === this.state?.selectedCharacterId);
      const name = character?.name || 'this character';
      const confirmed = window.confirm(`Delete ${name}? This cannot be undone.`);
      if (confirmed) {
        (this.pushEvent('delete_character', { character_id: this.state.selectedCharacterId }) as any)?.catch?.(() => {});
      }
      return;
    }

    if (panelId === 'creator') {
      this.showCharacterCreator();
    }
  },

  findCharacterIdForMesh(this: any, mesh: THREE.Object3D): string | null {
    let found: string | null = null;
    this.characterManager?.getAllCharacters().forEach((ch: any, id: string) => {
      if (!found && (ch.mesh === mesh || ch.mesh.children.includes(mesh as THREE.Mesh))) {
        found = id;
      }
    });
    return found;
  },

  tickTargetRing(this: any) {
    if (!this.targetId) {
      if (this.targetRingMesh) this.targetRingMesh.visible = false;
      return;
    }

    const targetChar = this.characterManager?.getAllCharacters().get(this.targetId) || (this.mobsView?.get(this.targetId) ? { mesh: this.mobsView.get(this.targetId).root } : null);
    if (!targetChar) {
      if (this.targetRingMesh) this.targetRingMesh.visible = false;
      return;
    }

    // Create ring on first use
    if (!this.targetRingMesh) {
      const geo = new THREE.TorusGeometry(0.55, 0.06, 8, 32);
      const mat = new THREE.MeshBasicMaterial({ color: 0xffdd00, transparent: true, opacity: 0.85 });
      this.targetRingMesh = new THREE.Mesh(geo, mat);
      this.targetRingMesh.rotation.x = Math.PI / 2;
      this.scene?.add(this.targetRingMesh);
    }

    const pos = targetChar.mesh.position;
    this.targetRingMesh.position.set(pos.x, 0.02, pos.z);
    this.targetRingMesh.visible = true;
    // Pulse alpha
    const pulse = 0.6 + 0.4 * Math.sin(Date.now() / 300);
    (this.targetRingMesh.material as THREE.MeshBasicMaterial).opacity = pulse;
  },

  // ── Spell casting ──────────────────────────────────────────────────────────

  castSpell(this: any, spellSlug: string) {
    if (this.isDead) return;
    const now = Date.now();
    const lastCast = this.spellCooldowns[spellSlug] || 0;

    const spellDef = this.state?.currentPlayer?.spells?.find((s: any) => s.slug === spellSlug);
    const recastMs = spellDef?.recast_ms ?? 500;

    if (now - lastCast < recastMs) {
      // Still on cooldown — update overlay briefly
      this.updateCooldownOverlay(spellSlug, recastMs - (now - lastCast));
      return;
    }

    if (!this.targetId) {
      this.appendChatMessage('System', 'No target selected. Click a character or press Tab.');
      return;
    }

    const local = this.state?.currentPlayer;
    if (!local) return;

    const localChar = this.characterManager?.getAllCharacters().get(local.character_id);
    const targetChar = this.characterManager?.getAllCharacters().get(this.targetId);
    if (!localChar || !targetChar) return;

    const lp = localChar.mesh.position;
    const tp = targetChar.mesh.position;

    (this.pushEvent('cast_spell', {
      spell: spellSlug,
      target_id: this.targetId,
      caster_x: lp.x,
      caster_z: lp.z,
      target_x: tp.x,
      target_z: tp.z
    }) as any)?.catch?.(() => {});

    this.spellCooldowns[spellSlug] = now;
    this.updateCooldownOverlay(spellSlug, recastMs);
  },

  updateCooldownOverlay(this: any, spellSlug: string, remainingMs: number) {
    this.gameUI?.cooldown(spellSlug, remainingMs);
  },

  // ── Projectile animation ───────────────────────────────────────────────────

  launchProjectile(
    this: any,
    from: THREE.Vector3,
    to: THREE.Vector3,
    hit: boolean,
    damage: number,
    targetId: string
  ) {
    if (!this.scene) return;
    const geo = new THREE.SphereGeometry(0.12, 6, 6);
    const mat = new THREE.MeshBasicMaterial({ color: hit ? 0xaaaaaa : 0x666666 });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.copy(from).add(new THREE.Vector3(0, 1.2, 0));
    this.scene.add(mesh);

    const dist = from.distanceTo(to);
    const duration = Math.max(250, Math.min(600, dist * 25));
    const arcOffset = (Math.random() - 0.5) * 1.8; // random left-right arc

    this.activeProjectiles.push({
      mesh,
      startPos: mesh.position.clone(),
      endPos: to.clone().add(new THREE.Vector3(0, 1.0, 0)),
      progress: 0,
      duration,
      startMs: Date.now(),
      arcOffset
    });
  },

  tickProjectiles(this: any) {
    const now = Date.now();
    const remaining: typeof this.activeProjectiles = [];

    for (const proj of this.activeProjectiles) {
      const elapsed = now - proj.startMs;
      const t = Math.min(1, elapsed / proj.duration);

      // Parabolic arc: lerp x/z straight, add random lateral offset, arc y
      const straight = new THREE.Vector3().lerpVectors(proj.startPos, proj.endPos, t);
      const arcY = Math.sin(t * Math.PI) * 1.5;

      // Lateral arc: perpendicular to travel direction
      const dir = new THREE.Vector3().subVectors(proj.endPos, proj.startPos).normalize();
      const perp = new THREE.Vector3(-dir.z, 0, dir.x);
      const lateralOffset = perp.multiplyScalar(proj.arcOffset * Math.sin(t * Math.PI));

      proj.mesh.position.set(
        straight.x + lateralOffset.x,
        straight.y + arcY,
        straight.z + lateralOffset.z
      );

      if (t >= 1) {
        this.scene?.remove(proj.mesh);
        proj.mesh.geometry.dispose();
        (proj.mesh.material as THREE.Material).dispose();
      } else {
        remaining.push(proj);
      }
    }

    this.activeProjectiles = remaining;
  },

  // ── Floating damage text ───────────────────────────────────────────────────

  showFloatingDamage(this: any, worldPos: THREE.Vector3, text: string, color = '#F87171', scale = 1) {
    if (!this.el || !this.camera || !this.renderer) return;

    const el = document.createElement('div');
    el.className = 'absolute pointer-events-none font-bold select-none';
    el.style.transform = 'translate(-50%, -50%)';
    el.style.position = 'absolute';
    el.style.pointerEvents = 'none';
    el.style.zIndex = '4';
    el.style.color = color;
    el.style.fontSize = `${Math.round(15 * scale)}px`;
    el.style.textShadow = '0 1px 2px #000, 0 0 3px #000';
    el.style.fontFamily = '"Trebuchet MS", "Segoe UI", Arial, sans-serif';
    el.textContent = text;
    // Spread repeated numbers a little so they don't stack.
    worldPos.x += (Math.random() - 0.5) * 0.5;
    worldPos.z += (Math.random() - 0.5) * 0.5;
    this.el.appendChild(el);

    this.floatingTexts.push({
      el,
      x: worldPos.x,
      y: worldPos.y + 2.4,
      z: worldPos.z,
      vy: 1.5,
      alpha: 1.0,
      startMs: Date.now(),
      duration: 1200
    });
  },

  tickFloatingTexts(this: any) {
    if (!this.camera || !this.renderer) return;
    // Project with this frame's camera (its matrices otherwise update only when rendering).
    this.camera.updateMatrixWorld();
    const dt = 0.016;
    const remaining: typeof this.floatingTexts = [];
    const rect = this.renderer.domElement.getBoundingClientRect();

    for (const ft of this.floatingTexts) {
      const elapsed = Date.now() - ft.startMs;
      const progress = elapsed / ft.duration;

      ft.y += ft.vy * dt;
      ft.alpha = Math.max(0, 1 - progress);
      ft.el.style.opacity = ft.alpha.toString();

      // Project 3D → 2D screen
      const v = new THREE.Vector3(ft.x, ft.y, ft.z).project(this.camera);
      const sx = (v.x * 0.5 + 0.5) * rect.width;
      const sy = (-v.y * 0.5 + 0.5) * rect.height;
      ft.el.style.left = `${sx}px`;
      ft.el.style.top = `${sy}px`;

      if (progress >= 1) {
        ft.el.parentElement?.removeChild(ft.el);
      } else {
        remaining.push(ft);
      }
    }

    this.floatingTexts = remaining;
  },

  // Fighting, creatures, looting, the inventory and the windows (game-world.ts).
  ...GameWorld,
};
