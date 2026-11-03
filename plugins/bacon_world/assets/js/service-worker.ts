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
  readCacheWhileUncontrolled();

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

// Must match the patterns and the stamp in priv/static/sw-game.js.
const CACHE_PATTERNS = [/^\/models\//, /^\/audio\//, /^\/fonts\//];
const STAMP = 'x-bw-cached-at';
let fetchWrapped = false;

/**
 * A hard refresh (Ctrl+Shift+R) loads the page without its service worker: the browser leaves
 * that page uncontrolled for its whole life, so every model came from the network again although
 * the cache held it (2026-11-01). The page can read the same CacheStorage itself: while no worker
 * controls it, a versioned (?vsn=) model, sound or font is answered from the cache, and a miss is
 * fetched and stored the way the worker would. Unversioned URLs go to the network as before.
 */
function readCacheWhileUncontrolled(): void {
  if (fetchWrapped || !('caches' in window) || navigator.serviceWorker.controller) return;
  fetchWrapped = true;
  const network = window.fetch.bind(window);
  window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    let request!: Request;
    let cache!: Cache;
    try {
      request = new Request(input, init);
      const url = new URL(request.url);
      const ours =
        !navigator.serviceWorker.controller &&
        request.method === 'GET' &&
        !request.headers.has('range') &&
        url.origin === location.origin &&
        url.searchParams.has('vsn') &&
        CACHE_PATTERNS.some((p) => p.test(url.pathname));
      if (!ours) return network(input, init);
      cache = await caches.open(CACHE_NAME);
      const hit = await cache.match(request);
      if (hit) return hit;
    } catch {
      return network(input, init);
    }
    const response = await network(request);
    if (response.status === 200 && response.type === 'basic') void storeCopy(cache, request, response.clone());
    return response;
  };
}

// As the worker stores it: stamped, and decoded (a copy that still said gzip would be decoded twice).
async function storeCopy(cache: Cache, request: Request, response: Response): Promise<void> {
  try {
    const headers = new Headers(response.headers);
    headers.set(STAMP, String(Date.now()));
    headers.delete('content-encoding');
    headers.delete('content-length');
    const body = await response.blob();
    await cache.put(request, new Response(body, { status: response.status, statusText: response.statusText, headers }));
  } catch {
    // quota full or the like: the game still works from the network
  }
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
