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