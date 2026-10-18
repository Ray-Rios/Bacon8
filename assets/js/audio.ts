/**
 * Audio Hook for LiveView
 * Handles notification sounds and volume control
 */

let globalVolume = 0.5; // Default volume

// Function to apply volume to all media elements
const applyGlobalVolume = (volume: number) => {
  globalVolume = Math.max(0, Math.min(1, volume));
  const mediaElements = document.querySelectorAll('audio, video');
  mediaElements.forEach((el) => {
    if (el instanceof HTMLMediaElement) {
      el.volume = globalVolume;
    }
  });
};

// Observer to apply volume to new media elements
const observer = new MutationObserver((mutations) => {
  mutations.forEach((mutation) => {
    mutation.addedNodes.forEach((node) => {
      if (node instanceof HTMLMediaElement) {
        node.volume = globalVolume;
      } else if (node instanceof HTMLElement) {
        const media = node.querySelectorAll('audio, video');
        media.forEach((el) => {
          if (el instanceof HTMLMediaElement) {
            el.volume = globalVolume;
          }
        });
      }
    });
  });
});

export const AudioHook = {
  mounted() {
    // Initialize volume from data attribute
    const initialVolume = parseFloat(this.el.dataset.volume);
    if (!isNaN(initialVolume)) {
      applyGlobalVolume(initialVolume);
    }

    // Start observing the document body for new media elements
    observer.observe(document.body, { childList: true, subtree: true });

    // Handle play_sound event from server
    this.handleEvent("play_sound", ({ path, volume }) => {
      this.playSound(path, volume);
    });

    // Handle volume_changed event
    this.handleEvent("volume_changed", ({ volume }) => {
      console.log(`Volume updated to ${(volume * 100).toFixed(0)}%`);
      applyGlobalVolume(volume);
    });
  },

  destroyed() {
    observer.disconnect();
  },

  playSound(path: string, volume: number) {
    try {
      const audio = new Audio(path);
      audio.volume = Math.max(0, Math.min(1, volume)); // Clamp between 0 and 1
      
      audio.play().catch((error) => {
        console.error("Failed to play notification sound:", error);
      });
    } catch (error) {
      console.error("Error creating audio element:", error);
    }
  }
};
