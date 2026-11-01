// Bacon World Game Asset Service Worker
// Automatically caches 3D models, textures, animations, terrain heightmaps, and audio
// in browser CacheStorage so reloads load instantly from local disk, while auto-updating in the background.

const CACHE_NAME = 'bacon-world-assets-v1';

// Asset paths targeted for persistent offline/disk caching
const CACHE_PATTERNS = [
  /^\/models\//,
  /^\/audio\/world\//,
  /^\/assets\/audio\//,
  /^\/fonts\//
];

self.addEventListener('install', (event) => {
  // Activate worker immediately without waiting for existing tabs to close
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Remove older asset cache versions if cache name changes in the future
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.map((key) => {
          if (key.startsWith('bacon-world-assets-') && key !== CACHE_NAME) {
            console.log('[bacon-world-sw] Deleting obsolete cache:', key);
            return caches.delete(key);
          }
        })
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Only intercept GET requests
  if (request.method !== 'GET') return;

  // Never intercept HTML page navigation or LiveView / Phoenix websockets
  if (request.mode === 'navigate') return;
  const url = new URL(request.url);
  if (url.pathname.startsWith('/live') || url.pathname.startsWith('/phoenix')) return;

  // Skip range requests (e.g. streaming media chunks) to prevent CacheStorage 206 errors
  if (request.headers.get('range')) return;

  // Check if this request is a target game asset
  const isGameAsset = CACHE_PATTERNS.some((pattern) => pattern.test(url.pathname));
  if (!isGameAsset) return;

  // Stale-While-Revalidate with Auto-Update:
  // 1. If cached, respond immediately from local disk (0ms network delay).
  // 2. Concurrently fetch the file in the background from network.
  // 3. If the server response is 200 OK, update the cache with the new version.
  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cachedResponse = await cache.match(request);

      const fetchPromise = fetch(request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            // Save updated file in cache for subsequent loads
            cache.put(request, networkResponse.clone());
          }
          return networkResponse;
        })
        .catch((err) => {
          // If offline or network drop, return cached version if available
          if (cachedResponse) {
            return cachedResponse;
          }
          throw err;
        });

      return cachedResponse || fetchPromise;
    })
  );
});

// Message interface for checking cache status or clearing cache
self.addEventListener('message', (event) => {
  if (event.data && event.data.action === 'clearCache') {
    caches.delete(CACHE_NAME).then(() => {
      event.ports[0]?.postMessage({ ok: true, message: 'Game asset cache cleared.' });
    });
  } else if (event.data && event.data.action === 'getCacheInfo') {
    caches.open(CACHE_NAME).then(async (cache) => {
      const keys = await cache.keys();
      event.ports[0]?.postMessage({
        ok: true,
        cacheName: CACHE_NAME,
        itemCount: keys.length,
        urls: keys.map((k) => k.url)
      });
    });
  }
});
