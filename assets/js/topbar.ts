/**
 * @license MIT
 * topbar 2.0.0, 2021-02-06 (TypeScript version)
 * https://buunguyen.github.io/topbar
 * Copyright (c) 2021 Buu Nguyen
 */

interface TopBarOptions {
  autoRun: boolean;
  barThickness: number;
  barColors: { [key: string]: string };
  shadowBlur: number;
  shadowColor: string;
  className: string | null;
}

interface TopBarAPI {
  config(opts: Partial<TopBarOptions>): void;
  show(delay?: number): void;
  progress(to?: number | string): number;
  hide(): void;
}

(function (window: Window, document: Document): void {
  "use strict";

  // RequestAnimationFrame polyfill
  (function(): void {
    let lastTime = 0;
    const vendors = ['ms', 'moz', 'webkit', 'o'];
    
    for (let x = 0; x < vendors.length && !window.requestAnimationFrame; ++x) {
      window.requestAnimationFrame = (window as any)[vendors[x] + 'RequestAnimationFrame'];
      window.cancelAnimationFrame = (window as any)[vendors[x] + 'CancelAnimationFrame'] 
                                 || (window as any)[vendors[x] + 'CancelRequestAnimationFrame'];
    }
    
    if (!window.requestAnimationFrame) {
      window.requestAnimationFrame = function(callback: FrameRequestCallback): number {
        const currTime = new Date().getTime();
        const timeToCall = Math.max(0, 16 - (currTime - lastTime));
        const id = window.setTimeout(() => callback(currTime + timeToCall), timeToCall);
        lastTime = currTime + timeToCall;
        return id;
      };
    }
    
    if (!window.cancelAnimationFrame) {
      window.cancelAnimationFrame = function(id: number): void {
        clearTimeout(id);
      };
    }
  })();

  let canvas: HTMLCanvasElement;
  let currentProgress: number = 0;
  let showing: boolean = false;
  let progressTimerId: number | null = null;
  let fadeTimerId: number | null = null;
  let delayTimerId: number | null = null;

  const addEvent = function (elem: Element | Window, type: string, handler: EventListener): void {
    if ('addEventListener' in elem) {
      elem.addEventListener(type, handler, false);
    } else if ('attachEvent' in elem) {
      (elem as any).attachEvent('on' + type, handler);
    } else {
      (elem as any)['on' + type] = handler;
    }
  };

  const options: TopBarOptions = {
    autoRun      : true,
    barThickness : 3,
    barColors    : {
      '0'      : 'rgba(26,  188, 156, .9)',
      '.25'    : 'rgba(52,  152, 219, .9)',
      '.50'    : 'rgba(241, 196, 15,  .9)',
      '.75'    : 'rgba(230, 126, 34,  .9)',
      '1.0'    : 'rgba(211, 84,  0,   .9)'
    },
    shadowBlur   : 10,
    shadowColor  : 'rgba(0,   0,   0,   .6)',
    className    : null
  };

  const repaint = function (): void {
    canvas.width = window.innerWidth;
    canvas.height = options.barThickness * 5; // space for shadow

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.shadowBlur = options.shadowBlur;
    ctx.shadowColor = options.shadowColor;

    const lineGradient = ctx.createLinearGradient(0, 0, canvas.width, 0);
    for (const stop in options.barColors) {
      lineGradient.addColorStop(parseFloat(stop), options.barColors[stop]);
    }
    
    ctx.lineWidth = options.barThickness;
    ctx.beginPath();
    ctx.moveTo(0, options.barThickness / 2);
    ctx.lineTo(
      Math.ceil(currentProgress * canvas.width),
      options.barThickness / 2
    );
    ctx.strokeStyle = lineGradient;
    ctx.stroke();
  };

  const createCanvas = function (): void {
    canvas = document.createElement('canvas');
    const style = canvas.style;
    style.position = 'fixed';
    style.top = style.left = style.right = style.margin = style.padding = '0';
    style.zIndex = '100001';
    style.display = 'none';
    if (options.className) canvas.className = options.className;
    document.body.appendChild(canvas);
    addEvent(window, 'resize', repaint);
  };

  const topbar: TopBarAPI = {
    config: function (opts: Partial<TopBarOptions>): void {
      for (const key in opts) {
        if (Object.prototype.hasOwnProperty.call(options, key)) {
          (options as any)[key] = (opts as any)[key];
        }
      }
    },

    show: function (delay?: number): void {
      if (showing) return;
      if (delay) {
        if (delayTimerId) return;
        delayTimerId = window.setTimeout(() => topbar.show(), delay);
      } else {
        showing = true;
        if (fadeTimerId !== null) window.cancelAnimationFrame(fadeTimerId);
        if (!canvas) createCanvas();
        canvas.style.opacity = '1';
        canvas.style.display = 'block';
        topbar.progress(0);
        if (options.autoRun) {
          (function loop(): void {
            progressTimerId = window.requestAnimationFrame(loop);
            topbar.progress(
              '+' + (0.05 * Math.pow(1 - Math.sqrt(currentProgress), 2)).toString()
            );
          })();
        }
      }
    },

    progress: function (to?: number | string): number {
      if (typeof to === 'undefined') return currentProgress;
      
      let newProgress: number;
      if (typeof to === 'string') {
        newProgress =
          (to.indexOf('+') >= 0 || to.indexOf('-') >= 0
            ? currentProgress
            : 0) + parseFloat(to);
      } else {
        newProgress = to;
      }
      
      currentProgress = newProgress > 1 ? 1 : newProgress;
      repaint();
      return currentProgress;
    },

    hide: function (): void {
      if (delayTimerId) {
        clearTimeout(delayTimerId);
        delayTimerId = null;
      }
      if (!showing) return;
      showing = false;
      if (progressTimerId !== null) {
        window.cancelAnimationFrame(progressTimerId);
        progressTimerId = null;
      }
      (function loop(): void {
        if (topbar.progress('+.1') >= 1) {
          const currentOpacity = parseFloat(canvas.style.opacity || '1');
          const newOpacity = currentOpacity - 0.05;
          canvas.style.opacity = newOpacity.toString();
          if (newOpacity <= 0.05) {
            canvas.style.display = 'none';
            fadeTimerId = null;
            return;
          }
        }
        fadeTimerId = window.requestAnimationFrame(loop);
      })();
    }
  };

  // Export for different module systems
  if (typeof (globalThis as any).module === 'object' && typeof (globalThis as any).module.exports === 'object') {
    (globalThis as any).module.exports = topbar;
  } else if (typeof (globalThis as any).define === 'function' && (globalThis as any).define.amd) {
    (globalThis as any).define(() => topbar);
  } else {
    (window as any).topbar = topbar;
  }

})(window, document);

// Export the topbar object that was attached to window
const topbarInstance = (window as any).topbar as TopBarAPI;
export default topbarInstance;