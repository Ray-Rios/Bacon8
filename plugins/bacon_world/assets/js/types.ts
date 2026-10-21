// TypeScript type definitions for Three.js MMO Client
import type { 
  Scene, 
  PerspectiveCamera, 
  WebGLRenderer, 
  Object3D, 
  Group,
  AnimationMixer,
  AnimationAction,
  Vector3,
  Euler,
  Material,
  Mesh,
  Clock
} from '../../../../assets/js/vendor/three';

// Phoenix LiveView Hook interface
export interface PhoenixLiveViewHook {
  el: HTMLElement;
  mounted(): void;
  updated(): void;
  destroyed(): void;
  pushEvent?(event: string, payload: any): void;
  pushEventTo?(selector: string, event: string, payload: any): void;
  handleEvent?(event: string, callback: (payload: any) => void): void;
}

// Core Three.js scene state
export interface ThreeSceneState {
  scene: Scene;
  camera: PerspectiveCamera;
  renderer: WebGLRenderer;
  controls: OrbitControls | FirstPersonControls;
  clock: Clock;
  isInitialized: boolean;
  isDisposed: boolean;
}

// Game world state
export interface GameWorldState {
  player: PlayerCharacter | null;
  otherPlayers: Map<string, PlayerCharacter>;
  creatures: Map<string, CreatureNPC>;
  environment: EnvironmentObjects;
  terrain: TerrainSystem | null;
}

// Character system
export interface PlayerCharacter {
  id: string;
  name: string;
  mesh: Group;
  mixer: AnimationMixer | null;
  animations: Map<string, AnimationAction>;
  position: Vector3;
  rotation: Euler;
  stats: PlayerStats;
  equipment: EquipmentSlots;
  isMoving: boolean;
  isLocalPlayer: boolean;
}

export interface CreatureNPC {
  id: string;
  type: string;
  name: string;
  mesh: Group;
  mixer: AnimationMixer | null;
  animations: Map<string, AnimationAction>;
  position: Vector3;
  rotation: Euler;
  stats: CreatureStats;
  aiState: AIState;
  isHostile: boolean;
}

export interface PlayerStats {
  level: number;
  health: number;
  maxHealth: number;
  mana: number;
  maxMana: number;
  experience: number;
  strength: number;
  dexterity: number;
  intelligence: number;
  constitution: number;
}

export interface CreatureStats {
  level: number;
  health: number;
  maxHealth: number;
  damage: number;
  defense: number;
  speed: number;
}

export interface EquipmentSlots {
  helmet: Equipment | null;
  armor: Equipment | null;
  weapon: Equipment | null;
  shield: Equipment | null;
  boots: Equipment | null;
  gloves: Equipment | null;
}

export interface Equipment {
  id: string;
  name: string;
  type: EquipmentType;
  stats: EquipmentStats;
  mesh: Object3D | null;
}

export type EquipmentType = 'helmet' | 'armor' | 'weapon' | 'shield' | 'boots' | 'gloves';

export interface EquipmentStats {
  damage?: number;
  defense?: number;
  strength?: number;
  dexterity?: number;
  intelligence?: number;
  constitution?: number;
}

export type AIState = 'idle' | 'patrolling' | 'chasing' | 'attacking' | 'fleeing' | 'dead';

// Environment and terrain
export interface EnvironmentObjects {
  buildings: Map<string, Object3D>;
  trees: Map<string, Object3D>;
  rocks: Map<string, Object3D>;
  water: Object3D | null;
  skybox: Object3D | null;
}

export interface TerrainSystem {
  mesh: Mesh;
  heightMap: Float32Array;
  size: number;
  maxHeight: number;
  material: Material;
}

// Input and controls
export interface InputState {
  keys: KeyState;
  mouse: MouseState;
  touch: TouchState;
}

export interface KeyState {
  forward: boolean;
  backward: boolean;
  left: boolean;
  right: boolean;
  jump: boolean;
  run: boolean;
  crouch: boolean;
  interact: boolean;
  inventory: boolean;
  chat: boolean;
}

export interface MouseState {
  x: number;
  y: number;
  deltaX: number;
  deltaY: number;
  leftButton: boolean;
  rightButton: boolean;
  middleButton: boolean;
  wheel: number;
}

export interface TouchState {
  touches: Touch[];
  isActive: boolean;
}

// Camera control types
export interface OrbitControls {
  enabled: boolean;
  target: Vector3;
  minDistance: number;
  maxDistance: number;
  minPolarAngle: number;
  maxPolarAngle: number;
  enableDamping: boolean;
  dampingFactor: number;
  update(): void;
  dispose(): void;
}

export interface FirstPersonControls {
  enabled: boolean;
  movementSpeed: number;
  lookSpeed: number;
  lookVertical: boolean;
  autoForward: boolean;
  activeLook: boolean;
  heightSpeed: boolean;
  heightCoef: number;
  heightMin: number;
  heightMax: number;
  constrainVertical: boolean;
  verticalMin: number;
  verticalMax: number;
  update(delta: number): void;
  dispose(): void;
}

// Asset loading
export interface AssetLoadingState {
  isLoading: boolean;
  loadedAssets: number;
  totalAssets: number;
  currentAsset: string;
  errors: AssetError[];
}

export interface AssetError {
  asset: string;
  error: Error;
  timestamp: Date;
}

// Network and server communication
export interface ServerMessage {
  type: MessageType;
  data: any;
  timestamp: number;
}

export type MessageType = 
  | 'player_joined'
  | 'player_left'
  | 'player_moved'
  | 'player_animation'
  | 'creature_spawned'
  | 'creature_moved'
  | 'creature_died'
  | 'chat_message'
  | 'world_update'
  | 'player_stats_update'
  | 'equipment_changed';

export interface PlayerJoinedData {
  playerId: string;
  playerName: string;
  position: { x: number; y: number; z: number };
  rotation: { x: number; y: number; z: number };
  characterType: string;
}

export interface PlayerLeftData {
  playerId: string;
}

export interface PlayerMovedData {
  playerId: string;
  position: { x: number; y: number; z: number };
  rotation: { x: number; y: number; z: number };
  isMoving: boolean;
  animation: string;
}

export interface ChatMessageData {
  playerId: string;
  playerName: string;
  message: string;
  channel: ChatChannel;
  timestamp: number;
}

export type ChatChannel = 'say' | 'yell' | 'tell' | 'guild' | 'group' | 'ooc' | 'auction';

// Configuration interfaces
export interface ThreeSceneConfig {
  canvas: HTMLCanvasElement;
  enableShadows: boolean;
  enableFog: boolean;
  antialias: boolean;
  devicePixelRatio: number;
  backgroundColor: number;
  fogColor: number;
  fogNear: number;
  fogFar: number;
}

export interface CameraConfig {
  fov: number;
  near: number;
  far: number;
  position: { x: number; y: number; z: number };
  target: { x: number; y: number; z: number };
}

export interface LightingConfig {
  ambientIntensity: number;
  directionalIntensity: number;
  directionalPosition: { x: number; y: number; z: number };
  enableShadows: boolean;
  shadowMapSize: number;
}

// Performance monitoring
export interface PerformanceMetrics {
  fps: number;
  frameTime: number;
  triangles: number;
  drawCalls: number;
  textureMemory: number;
  geometryMemory: number;
  programs: number;
}

// Error handling
export interface ThreeJSError extends Error {
  component: string;
  context: any;
  timestamp: Date;
}

// Model loading specific types
export interface ModelLoadOptions {
  scale: number;
  position: { x: number; y: number; z: number };
  rotation: { x: number; y: number; z: number };
  castShadow: boolean;
  receiveShadow: boolean;
  enableAnimations: boolean;
}

export interface LoadedModel {
  name: string;
  mesh: Group;
  animations: AnimationAction[];
  mixer: AnimationMixer | null;
  boundingBox: { min: Vector3; max: Vector3 };
  triangleCount: number;
}

// Global type extensions
declare global {
  interface Window {
    ThreeJSMMO: {
      scene: ThreeSceneState | null;
      world: GameWorldState | null;
      input: InputState | null;
      performance: PerformanceMetrics | null;
      debug: boolean;
    };
  }
}

export {};