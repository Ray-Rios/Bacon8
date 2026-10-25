// Bacon World's LiveView hooks. assets/scripts/gen-plugin-hooks.js finds this file
// and merges `hooks` into the LiveSocket's hooks, so the names are global:
// pick names unlikely to clash with another plugin's.
import { WorldCharacterUIScene } from "./world-character-ui-scene";
import { BaconWorldSkillTreeEditor } from "./skill-tree-editor";

export const hooks = { WorldCharacterUIScene, BaconWorldSkillTreeEditor };
