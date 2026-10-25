// What the personal glass colour also drives: the menus' body (--glass-menu-*) and, when the
// player has chosen a colour, Bacon World's windows (--bwg-*; absent means the game's own
// look). The inline script in layouts/root.html.heex does the same sums on page load:
// keep the two in step.
export function setGlassExtras(root: HTMLElement, rgb: number[], opacity: number, personalised: boolean) {
  const mix = (c: number[], base: number[], t: number) => c.map((v, i) => Math.round(v * t + base[i] * (1 - t)));
  const css = (c: number[], a = 1) => `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${a})`;

  // Menus are always mostly opaque: the tint darkened, at 62-85%. The brighter the tint, the
  // more it is darkened, or the menus' light text could not be read on it (worst case about
  // 4:1 at the sheen's brightest corner, 5:1 and up on most themes).
  const menuAlpha = Math.min(0.85, Math.max(0.62, 0.35 + opacity * 0.6));
  const luma = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2];
  const keep = luma <= 90 ? 0.45 : luma <= 180 ? 0.3 : 0.18;
  root.style.setProperty('--glass-menu-bg', css(mix(rgb, [11, 15, 25], keep), menuAlpha));
  root.style.setProperty('--glass-menu-border', css(mix(rgb, [255, 255, 255], 0.35), 0.45));

  const game = ['--bwg-bg', '--bwg-title-a', '--bwg-title-b', '--bwg-border', '--bwg-border-soft', '--bwg-accent'];
  if (personalised) {
    root.style.setProperty('--bwg-bg', css(mix(rgb, [10, 9, 8], 0.2), 0.94));
    root.style.setProperty('--bwg-title-a', css(mix(rgb, [20, 18, 16], 0.34)));
    root.style.setProperty('--bwg-title-b', css(mix(rgb, [12, 11, 10], 0.16)));
    root.style.setProperty('--bwg-border', css(mix(rgb, [255, 255, 255], 0.55)));
    root.style.setProperty('--bwg-border-soft', css(mix(rgb, [255, 255, 255], 0.3)));
    root.style.setProperty('--bwg-accent', css(mix(rgb, [255, 255, 255], 0.45)));
  } else {
    game.forEach((v) => root.style.removeProperty(v));
  }
}

export const GlassTheme = {
  mounted(this: any) {
    console.log('✅ GlassTheme hook mounted');
    
    // Listen for glass theme updates from LiveView
    const handleGlassUpdate = (data: any) => {
      console.log('🎨 GlassTheme: Received update_glass_theme from LiveView:', data);
      this.applyGlassTheme(data);
      
      // If this is a global update, dispatch a window event for all components
      if (data.global) {
        window.dispatchEvent(new CustomEvent('glass-theme-update', { detail: data }));
        console.log('📢 GlassTheme: Dispatched glass-theme-update window event');
      }
    };

    this.handleEvent("update_glass_theme", handleGlassUpdate);
    this.handleEvent("glass_theme_update", handleGlassUpdate);
    
    // Listen for global glass theme updates from other components
    window.addEventListener('glass-theme-update', (event: any) => {
      console.log('👂 GlassTheme: Received glass-theme-update window event:', event.detail);
      this.applyGlassTheme(event.detail);
    });
    
    console.log('👂 GlassTheme: Now listening for update_glass_theme and glass-theme-update events');
  },

  applyGlassTheme(data: any) {
    console.log('🎨 Applying glass theme:', data);
    const root = document.documentElement;
    
    // Convert theme to CSS values - base colors with placeholder for opacity
    const themeColors = {
      'dark': { rgb: '17, 24, 39', border: 'rgba(255, 255, 255, 0.15)' },
      'blue': { rgb: '59, 130, 246', border: 'rgba(59, 130, 246, 0.3)' },
      'purple': { rgb: '147, 51, 234', border: 'rgba(147, 51, 234, 0.3)' },
      'green': { rgb: '34, 197, 94', border: 'rgba(34, 197, 94, 0.3)' },
      'red': { rgb: '239, 68, 68', border: 'rgba(239, 68, 68, 0.3)' },
      'amber': { rgb: '245, 158, 11', border: 'rgba(245, 158, 11, 0.3)' },
      'teal': { rgb: '20, 184, 166', border: 'rgba(20, 184, 166, 0.3)' },
      'light': { rgb: '249, 250, 251', border: 'rgba(0, 0, 0, 0.15)' },
    };

    let bgColor, borderColor, rgbValues;
    const opacity = parseFloat(data.opacity?.toString() || '0.15');
    const blur = parseInt(data.blur?.toString() || '15', 10);

    // Check if custom color is provided - prioritize it over theme selection
    if (data.custom_color && data.custom_color !== '' && data.custom_color !== '#000000') {
      // Convert hex to rgba with custom opacity
      const hex = data.custom_color.replace('#', '');
      const r = parseInt(hex.substr(0, 2), 16);
      const g = parseInt(hex.substr(2, 2), 16);
      const b = parseInt(hex.substr(4, 2), 16);
      
      rgbValues = `${r}, ${g}, ${b}`;
      bgColor = `rgba(${r}, ${g}, ${b}, ${opacity})`;
      borderColor = `rgba(${r}, ${g}, ${b}, ${Math.min(1, opacity + 0.2)})`;
    } else {
      // Use predefined theme colors with dynamic opacity
      const theme = themeColors[data.theme as keyof typeof themeColors] || themeColors.dark;
      rgbValues = theme.rgb;
      bgColor = `rgba(${theme.rgb}, ${opacity})`;
      borderColor = theme.border;
    }

    // Update CSS custom properties globally - FORCE update
    root.style.setProperty('--glass-rgb', rgbValues);
    root.style.setProperty('--glass-bg', bgColor);
    root.style.setProperty('--glass-border', borderColor);
    root.style.setProperty('--glass-blur', `${blur}px`);
    root.style.setProperty('--glass-saturation', '120%');

    // Menus and Bacon World follow the same colour (a plain dark theme leaves the game as it is)
    const personalised = !!(data.custom_color && data.custom_color !== '' && data.custom_color !== '#000000') ||
      (data.theme && data.theme !== 'dark');
    setGlassExtras(root, rgbValues.split(',').map((n: string) => parseInt(n.trim(), 10)), opacity, personalised);

    // Force reflow to apply changes immediately
    void root.offsetHeight;

    console.log('✅ Glass theme applied globally:', {
      bg: bgColor,
      border: borderColor,
      blur: `${blur}px`,
      theme: data.theme,
      custom_color: data.custom_color
    });
  }
};