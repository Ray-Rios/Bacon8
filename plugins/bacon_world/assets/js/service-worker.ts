/**
 * Bacon World Service Worker client manager.
 * Registers /sw-game.js to enable persistent local caching of 3D models, textures,
 * animations, terrain heightmaps, and audio in browser CacheStorage.
 */

// Must match CACHE_NAME in priv/static/sw-game.js.
const CACHE_NAME = 'bacon-world-assets-v2';

export function initGameServiceWorker(): void {
  if (typeof window === 'undefined' || !('serviceWorker' in navigator)) {
    return;
  }

  // Register the service worker at root scope to intercept /models/**, /audio/world/**, etc.
  navigator.serviceWorker
    .register('/sw-game.js', { scope: '/' })
    .then((registration) => {
      console.log('[bacon-world] Game Service Worker active (disk asset cache enabled):', registration.scope);

      // Handle worker updates in the background
      registration.onupdatefound = () => {
        const installingWorker = registration.installing;
        if (installingWorker) {
          installingWorker.onstatechange = () => {
            if (installingWorker.state === 'installed' && navigator.serviceWorker.controller) {
              console.log('[bacon-world] Updated Game Service Worker available; will activate on next visit.');
            }
          };
        }
      };
    })
    .catch((err) => {
      console.warn('[bacon-world] Service Worker registration failed (assets will load via standard network):', err);
    });
}

/** Utility to inspect the current cache contents from the browser console. */
export async function getGameCacheInfo(): Promise<any> {
  if (typeof window === 'undefined' || !('caches' in window)) return null;
  const cache = await window.caches.open(CACHE_NAME);
  const requests = await cache.keys();
  return {
    cacheName: CACHE_NAME,
    count: requests.length,
    urls: requests.map((r) => r.url)
  };
}

/** Utility to clear the game asset cache from the browser console if needed. */
export async function clearGameCache(): Promise<boolean> {
  if (typeof window === 'undefined' || !('caches' in window)) return false;
  return window.caches.delete(CACHE_NAME);
}

// Expose debug utilities on window for convenience
if (typeof window !== 'undefined') {
  (window as any).bwCache = {
    info: getGameCacheInfo,
    clear: clearGameCache
  };
}
