// Device Fingerprinting and Behavioral Analysis
export class DeviceFingerprint {
  private fingerprint: string | null = null;
  private behaviorData: {
    mouseMovements: number;
    keystrokes: number;
    formFocusTime: number;
    timeToSubmit: number;
  };

  constructor() {
    this.behaviorData = {
      mouseMovements: 0,
      keystrokes: 0,
      formFocusTime: 0,
      timeToSubmit: 0
    };
  }

  async generateFingerprint(): Promise<string> {
    if (this.fingerprint) return this.fingerprint;

    const components = {
      userAgent: navigator.userAgent,
      language: navigator.language,
      colorDepth: screen.colorDepth,
      deviceMemory: (navigator as any).deviceMemory || 0,
      hardwareConcurrency: navigator.hardwareConcurrency || 0,
      screenResolution: `${screen.width}x${screen.height}`,
      timezoneOffset: new Date().getTimezoneOffset(),
      platform: navigator.platform,
      plugins: this.getPlugins(),
      canvas: await this.getCanvasFingerprint(),
      webgl: this.getWebGLFingerprint(),
      fonts: await this.getFontFingerprint()
    };

    const fingerprintString = JSON.stringify(components);
    this.fingerprint = await this.hashString(fingerprintString);
    return this.fingerprint;
  }

  private getPlugins(): string {
    if (!navigator.plugins) return '';
    return Array.from(navigator.plugins)
      .map(p => p.name)
      .sort()
      .join(',');
  }

  private async getCanvasFingerprint(): Promise<string> {
    try {
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx) return '';

      canvas.width = 200;
      canvas.height = 50;

      ctx.textBaseline = 'top';
      ctx.font = '14px Arial';
      ctx.fillStyle = '#f60';
      ctx.fillRect(125, 1, 62, 20);
      ctx.fillStyle = '#069';
      ctx.fillText('Browser Fingerprint', 2, 15);

      return canvas.toDataURL();
    } catch {
      return '';
    }
  }

  private getWebGLFingerprint(): string {
    try {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl') as WebGLRenderingContext;
      if (!gl) return '';

      const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
      if (!debugInfo) return '';

      const renderer = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
      const vendor = gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL);

      return `${vendor}~${renderer}`;
    } catch {
      return '';
    }
  }

  private async getFontFingerprint(): Promise<string> {
    const baseFonts = ['monospace', 'sans-serif', 'serif'];
    const testFonts = [
      'Arial', 'Verdana', 'Times New Roman', 'Courier New',
      'Georgia', 'Palatino', 'Garamond', 'Bookman', 'Trebuchet MS'
    ];

    const detected: string[] = [];

    for (const font of testFonts) {
      if (this.isFontAvailable(font, baseFonts)) {
        detected.push(font);
      }
    }

    return detected.join(',');
  }

  private isFontAvailable(font: string, baseFonts: string[]): boolean {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) return false;

    const text = 'mmmmmmmmmmlli';
    const textSize = '72px';

    ctx.font = `${textSize} ${baseFonts[0]}`;
    const baselineSize = ctx.measureText(text).width;

    ctx.font = `${textSize} ${font}, ${baseFonts[0]}`;
    const testSize = ctx.measureText(text).width;

    return baselineSize !== testSize;
  }

  private async hashString(str: string): Promise<string> {
    const encoder = new TextEncoder();
    const data = encoder.encode(str);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  }

  // Behavioral tracking
  trackBehavior(formElement: HTMLFormElement): void {
    const startTime = Date.now();
    let formFocused = false;

    // Track mouse movements
    document.addEventListener('mousemove', () => {
      this.behaviorData.mouseMovements++;
    }, { passive: true });

    // Track keystrokes
    formElement.addEventListener('keydown', () => {
      this.behaviorData.keystrokes++;
    });

    // Track form focus time
    formElement.addEventListener('focusin', () => {
      if (!formFocused) {
        formFocused = true;
        this.behaviorData.formFocusTime = Date.now();
      }
    });

    // Track time to submit
    formElement.addEventListener('submit', () => {
      this.behaviorData.timeToSubmit = Date.now() - startTime;
    });
  }

  getBehaviorData() {
    return {
      ...this.behaviorData,
      seemsHuman: this.analyzeHumanBehavior()
    };
  }

  private analyzeHumanBehavior(): boolean {
    // Heuristics for human behavior
    const hasMouseActivity = this.behaviorData.mouseMovements > 5;
    const hasKeystrokes = this.behaviorData.keystrokes > 3;
    const reasonableTime = this.behaviorData.timeToSubmit > 1000 && this.behaviorData.timeToSubmit < 300000;

    return hasMouseActivity && hasKeystrokes && reasonableTime;
  }
}

// Phoenix LiveView Hook
export const DeviceFingerprintHook = {
  fingerprinter: null as DeviceFingerprint | null,

  async mounted(this: any) {
    this.fingerprinter = new DeviceFingerprint();
    
    // Generate fingerprint
    const fingerprint = await this.fingerprinter.generateFingerprint();
    
    // Track behavior if this is a form
    const form = this.el.closest('form');
    if (form) {
      this.fingerprinter.trackBehavior(form);
    }

    // Store fingerprint in hidden input
    const fingerprintInput = this.el.querySelector('input[name="device_fingerprint"]');
    if (fingerprintInput) {
      (fingerprintInput as HTMLInputElement).value = fingerprint;
    }

    // Send fingerprint to server
    this.pushEvent('device_fingerprint', {
      fingerprint,
      userAgent: navigator.userAgent,
      platform: navigator.platform
    });
  },

  destroyed(this: any) {
    this.fingerprinter = null;
  }
};
