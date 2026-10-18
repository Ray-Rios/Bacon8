import { GlassTheme } from "./glass_theme";
import { BackgroundUpdater } from "./background_updater";

export const GlobalHooks = {
  mounted(this: any) {
    console.log('🌍 GlobalHooks mounted on element:', this.el.id);
    
    // Mount GlassTheme and BackgroundUpdater with the same hook context
    try {
      if (GlassTheme && typeof GlassTheme.mounted === 'function') {
        GlassTheme.mounted.call(this);
        console.log('✅ GlassTheme mounted via GlobalHooks');
      }
    } catch (e) {
      console.error('❌ Failed to mount GlassTheme inside GlobalHooks', e);
    }

    try {
      if (BackgroundUpdater && typeof BackgroundUpdater.mounted === 'function') {
        BackgroundUpdater.mounted.call(this);
        console.log('✅ BackgroundUpdater mounted via GlobalHooks');
      }
    } catch (e) {
      console.error('❌ Failed to mount BackgroundUpdater inside GlobalHooks', e);
    }
  },

  updated(this: any) {
    console.log('🔄 GlobalHooks updated');
  },
  
  destroyed(this: any) {
    console.log('💀 GlobalHooks destroyed');
  }
};
