// three.js for plugins (BACON8.md §9). Files under plugins/ sit outside
// assets/, where esbuild can't find node_modules, so they import three from
// here instead: import * as THREE from "../../../../assets/js/vendor/three";
export * from "three";
