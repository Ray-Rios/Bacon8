// Phone and desktop notifications (Bacon8.Push, 2026-11-03): the browser's half of
// Bacon8Web.PushOptIn. The server renders the buttons; this hook does what only the browser
// can (ask permission, which must come straight from a tap; subscribe; unsubscribe) and tells
// the component what this device can do and whether it's on.
//
// The worker lives at /push/sw.js with the scope /push/, so it never replaces Bacon World's
// game worker (/sw-game.js, scope /). Pages aren't controlled by it, so this file never waits
// on navigator.serviceWorker.ready (that would be the game's worker, or never resolve).

const SW_URL = '/push/sw.js';
const SW_SCOPE = '/push/';

/** base64url (no padding) to bytes, for applicationServerKey. */
export function urlB64ToBytes(s: string): ArrayBuffer {
  const b64 = (s + '='.repeat((4 - (s.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(b64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer as ArrayBuffer;
}

/** Whether a subscription was made with this key. Unknown (no options) counts as yes. */
export function sameKey(k: ArrayBuffer | null | undefined, key: ArrayBuffer): boolean {
  if (!k) return true;
  const a = new Uint8Array(k);
  const b = new Uint8Array(key);
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export interface DeviceInfo {
  supported: boolean;
  ios: boolean;
  standalone: boolean;
}

/** What this browser can do. iPadOS reports itself as a Mac with a touch screen. */
export function deviceInfo(nav: any, win: any): DeviceInfo {
  const ua: string = (nav && nav.userAgent) || '';
  const ios = /iPhone|iPad|iPod/.test(ua) || (nav && nav.platform === 'MacIntel' && nav.maxTouchPoints > 1);
  const standalone = !!(nav && nav.standalone === true) || !!(win && win.matchMedia && win.matchMedia('(display-mode: standalone)').matches);
  const supported = !!nav && 'serviceWorker' in nav && !!win && 'PushManager' in win && 'Notification' in win;
  return { supported, ios: !!ios, standalone };
}

async function findRegistration(): Promise<ServiceWorkerRegistration | undefined> {
  const regs = await navigator.serviceWorker.getRegistrations();
  return regs.find((r) => new URL(r.scope).pathname === SW_SCOPE);
}

async function activeRegistration(): Promise<ServiceWorkerRegistration> {
  const reg = await navigator.serviceWorker.register(SW_URL, { scope: SW_SCOPE });
  if (reg.active) return reg;
  const worker = reg.installing || reg.waiting;
  if (worker) {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('the notification worker did not start')), 15000);
      const check = () => {
        if (worker.state === 'activated') {
          clearTimeout(timer);
          resolve();
        }
      };
      worker.addEventListener('statechange', check);
      check();
    });
  }
  return reg;
}

export const PushOptIn = {
  mounted(this: any) {
    this.key = this.el.dataset.key || '';
    this.el.addEventListener('click', (e: Event) => {
      const btn = (e.target as HTMLElement).closest('[data-push]') as HTMLElement | null;
      if (!btn || !this.el.contains(btn)) return;
      e.preventDefault();
      if (btn.dataset.push === 'on') this.enable();
      else if (btn.dataset.push === 'off') this.disable();
    });
    this.report();
  },

  updated(this: any) {
    this.key = this.el.dataset.key || '';
  },

  reconnected(this: any) {
    this.report();
  },

  send(this: any, event: string, payload: object) {
    this.pushEventTo(this.el, event, payload);
  },

  async status(this: any) {
    const info = deviceInfo(navigator, window);
    const s: any = { ...info, permission: info.supported ? Notification.permission : 'unsupported', endpoint: null };
    if (!info.supported || !this.key) return s;
    try {
      const reg = await findRegistration();
      const sub = reg ? await reg.pushManager.getSubscription() : null;
      if (sub && sameKey(sub.options && sub.options.applicationServerKey, urlB64ToBytes(this.key))) s.endpoint = sub.endpoint;
    } catch (_e) {
      // a browser that won't say counts as off
    }
    return s;
  },

  report(this: any) {
    this.status().then((s: any) => this.send('push_device', s));
  },

  // Must run straight from the tap: Safari (and Chrome, quietly) only ask then.
  async enable(this: any) {
    try {
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        this.report();
        return;
      }
      const key = urlB64ToBytes(this.key);
      const reg = await activeRegistration();
      let sub = await reg.pushManager.getSubscription();
      if (sub && !sameKey(sub.options && sub.options.applicationServerKey, key)) {
        // made with an older key: the server can't use it
        await sub.unsubscribe();
        sub = null;
      }
      if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
      this.send('push_subscribed', { subscription: sub.toJSON(), ua: navigator.userAgent.slice(0, 250) });
    } catch (e) {
      this.send('push_failed', { reason: String(e).slice(0, 200) });
    }
  },

  async disable(this: any) {
    try {
      const reg = await findRegistration();
      const sub = reg ? await reg.pushManager.getSubscription() : null;
      if (sub) {
        const endpoint = sub.endpoint;
        await sub.unsubscribe();
        this.send('push_unsubscribed', { endpoint });
      } else {
        this.report();
      }
    } catch (e) {
      this.send('push_failed', { reason: String(e).slice(0, 200) });
    }
  },
};
