// Color Picker Hook - sends color input changes to LiveView
export const ColorPicker = {
  mounted(this: any) {
    const input = this.el as HTMLInputElement;
    const eventName = input.dataset.event || 'update_color';
    
    console.log('✅ ColorPicker hook mounted for event:', eventName);
    
    // Debounce to avoid too many events
    let timeout: ReturnType<typeof setTimeout> | null = null;

    // Listen for color changes
    input.addEventListener('input', (e) => {
      const color = (e.target as HTMLInputElement).value;
      
      if (timeout) clearTimeout(timeout);
      timeout = setTimeout(() => {
        console.log('🎨 ColorPicker: Color changed to', color, 'sending event:', eventName);
        this.pushEvent(eventName, { color: color });
      }, 200);
    });
  },
  
  destroyed() {
    console.log('🗑️ ColorPicker hook destroyed');
  }
};

// Opacity Slider Hook - sends opacity changes to LiveView
export const OpacitySlider = {
  mounted(this: any) {
    const input = this.el as HTMLInputElement;
    const eventName = input.dataset.event || 'update_avatar_opacity';
    const valueDisplay = document.getElementById('opacity-value');
    
    console.log('✅ OpacitySlider hook mounted for event:', eventName);
    
    // Debounce to avoid too many events
    let timeout: ReturnType<typeof setTimeout> | null = null;
    
    // Listen for opacity changes
    input.addEventListener('input', (e) => {
      const opacity = (e.target as HTMLInputElement).value;
      
      // Update display immediately
      if (valueDisplay) {
        valueDisplay.textContent = opacity;
      }
      
      // Debounce the server update
      if (timeout) clearTimeout(timeout);
      timeout = setTimeout(() => {
        console.log('🎚️ OpacitySlider: Opacity changed to', opacity, 'sending event:', eventName);
        this.pushEvent(eventName, { opacity: opacity });
      }, 300);
    });
  },
  
  destroyed() {
    console.log('🗑️ OpacitySlider hook destroyed');
  }
};
