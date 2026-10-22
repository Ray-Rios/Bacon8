// three.js model loaders for plugins; see ./three.ts.
export { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
export { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";
// Cloning a rigged (skinned) model needs SkeletonUtils.clone: Object3D.clone()
// leaves the copy's meshes bound to the original's bones, so it never animates.
export * as SkeletonUtils from "three/examples/jsm/utils/SkeletonUtils.js";
// GLBs packed with gltf-transform's meshopt step (the Bacon8 humans, hair, items)
// need the decoder: loader.setMeshoptDecoder(MeshoptDecoder).
export { MeshoptDecoder } from "three/examples/jsm/libs/meshopt_decoder.module.js";
// A neutral studio light for PBR materials (metal looks black without an environment).
export { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
