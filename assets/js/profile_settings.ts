// Profile Settings Hook - handles real-time updates for glass theme and background settings
export const ProfileSettings = {
  mounted(this: any) {
    console.log('✅ ProfileSettings hook mounted');

    // Listen for glass theme updates from this LiveView
    this.handleEvent("glass_theme_update", (data: any) => {
      console.log('🎨 Profile: Glass theme update received from LiveView:', data);
      
      // Dispatch as window event so GlobalHooks can pick it up
      window.dispatchEvent(new CustomEvent('glass-theme-update', { detail: data }));
      console.log('📢 Profile: Dispatched glass-theme-update window event');
    });

    // Listen for background updates from this LiveView
    this.handleEvent("background_update", (data: any) => {
      console.log('🖼️ Profile: Background update received from LiveView:', data);
      
      // Dispatch as window event so GlobalHooks can pick it up
      window.dispatchEvent(new CustomEvent('background-update', { detail: data }));
      console.log('📢 Profile: Dispatched background-update window event');
    });
    
    console.log('👂 ProfileSettings: Now listening for glass_theme_update and background_update events');
  },

  updated() {},
  destroyed() {
    console.log('🗑️ ProfileSettings hook destroyed');
  }
};
