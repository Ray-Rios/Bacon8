// Terminal Typewriter Effect Hook
// Handles typing animation for terminal-style text

import { LiveViewHook } from './types/liveview';

interface TerminalTypewriterData {
  typewriterSpeed: number;
  blinkSpeed: number;
  fallbackStartDelay: number;
  _typingStarted: boolean;
  _blinkInterval: number | null;
  container: HTMLElement | null;
  cursorContainer: HTMLElement | null;
  targetText: string;
  _loadListeners: [string, EventListener][] | null;
  _fallbackTimer: number | null;
}

interface TerminalTypewriterHook extends LiveViewHook, TerminalTypewriterData {
  startCursorBlink(): void;
  startTyping(): void;
  detachLoadListeners(): void;
}

const TerminalTypewriter: TerminalTypewriterHook = {
  mounted() {
    // Defensive check for element existence
    if (!this.el) {
      console.error('❌ TerminalTypewriter hook mounted but element is null');
      return;
    }
    
    console.log('⌨️ TerminalTypewriter mounted', this.el.id);
    
    this.typewriterSpeed = 80; // ms per character
    this.blinkSpeed = 530; // cursor blink speed
    this.fallbackStartDelay = 1500; // safety fallback if events fail
    this._typingStarted = false;
    this._blinkInterval = null;
    
    // Get the text container and cursor
    this.container = this.el.querySelector('.typewriter-text');
    this.cursorContainer = this.el.querySelector('.typewriter-cursor');
    
    if (!this.container) {
      console.error('Typewriter container not found');
      return;
    }
    
    // Get the target text from data attribute or use default, then clear the container
    this.targetText = this.container.dataset.text || "IT'S A SECRET TO EVERYBODY.";
    this.container.textContent = '';
    
    // Start cursor blinking immediately (even before typing)
    this.startCursorBlink();

    // Prefer full window load; LiveView partial patches can arrive before images/fonts
    const startIfReady = (): void => {
      if (this._typingStarted) return; // idempotent
      this._typingStarted = true;
      this.startTyping();
      this.detachLoadListeners();
    };

    // Track listeners so we can detach on destroy
    this._loadListeners = [];

    // 1. If document already fully loaded, start immediately next tick
    if (document.readyState === 'complete') {
      setTimeout(startIfReady, 10);
    } else {
      // 2. Listen for full window load
      const onWindowLoad = (): void => startIfReady();
      window.addEventListener('load', onWindowLoad, { once: true });
      this._loadListeners.push(['load', onWindowLoad]);

      // 3. Also listen for LiveView page-loading-stop which signals DOM settled
      const onLVStop = (): void => startIfReady();
      window.addEventListener('phx:page-loading-stop', onLVStop, { once: true });
      this._loadListeners.push(['phx:page-loading-stop', onLVStop]);

      // 4. Fallback timeout to guarantee it eventually starts
      this._fallbackTimer = setTimeout(() => startIfReady(), this.fallbackStartDelay);
    }
  },
  
  startCursorBlink(): void {
    if (this.cursorContainer) {
      this.cursorContainer.style.opacity = '1';
      this._blinkInterval = window.setInterval(() => {
        if (this.cursorContainer) {
          this.cursorContainer.style.opacity =
            this.cursorContainer.style.opacity === '0' ? '1' : '0';
        }
      }, this.blinkSpeed);
    }
  },
  
  startTyping(): void {
    let currentIndex = 0;
    
    const typeNextCharacter = (): void => {
      if (currentIndex < this.targetText.length && this.container) {
        this.container.textContent += this.targetText[currentIndex];
        currentIndex++;
        setTimeout(typeNextCharacter, this.typewriterSpeed);
      }
    };
    
    typeNextCharacter();
  },

  detachLoadListeners(): void {
    if (this._fallbackTimer) {
      clearTimeout(this._fallbackTimer);
      this._fallbackTimer = null;
    }
    if (this._loadListeners) {
      this._loadListeners.forEach(([evt, handler]) => {
        window.removeEventListener(evt, handler);
      });
      this._loadListeners = null;
    }
  },
  
  destroyed(): void {
    this.detachLoadListeners();
    if (this._blinkInterval) {
      clearInterval(this._blinkInterval);
      this._blinkInterval = null;
    }
  }
} as TerminalTypewriterHook;

export { TerminalTypewriter };