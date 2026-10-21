// three.js model loaders for plugins; see ./three.ts.
export { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
export { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";
// Cloning a rigged (skinned) model needs SkeletonUtils.clone: Object3D.clone()
// leaves the copy's meshes bound to the original's bones, so it never animates.
export * as SkeletonUtils from "three/examples/jsm/utils/SkeletonUtils.js";
