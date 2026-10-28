// Bacon Store's LiveView hooks and elements (assets/scripts/gen-plugin-hooks.js merges `hooks`
// into the LiveSocket's). <b8-spin>, the store items in 3D, defines itself on import.
import "./store_spin";
import { StoreCard, StoreSheet } from "./store_card";

export const hooks = { StoreCard, StoreSheet };
