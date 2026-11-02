// Bacon World's asset cache (a service worker at /sw-game.js, registered by the game page).
//
// What it keeps: the game's models (/models/...), its sounds (/audio/...) and fonts, in the
// browser's CacheStorage, so a reload or a second visit reads them from disk.
//
// How (rewritten 2026-11-01; the first version never reached production, see BACON_WORLD.md):
//   * A URL with ?vsn= (the game versions every model URL from its size and date) never changes:
//     answered from the cache, with no network request at all.
//   * Any other matching URL: from the cache at once, and refreshed in the background at most
//     once an hour (the first version re-downloaded every model on every load, competing with the
//     page for bandwidth).
//   * Only complete 200 answers are kept. Range requests go to the network untouched.
//
// Bump CACHE_NAME to throw the whole cache away on the next visit.

const CACHE_NAME = 'bacon-world-assets-v2';
const REVALIDATE_MS = 60 * 60 * 1000;
const STAMP = 'x-bw-cached-at';

const CACHE_PATTERNS = [/^\/models\//, /^\/audio\//, /^\/fonts\//];

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key.startsWith('bacon-world-assets-') && key !== CACHE_NAME)
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

// A copy of the response with the time it was stored, so the hourly refresh can be decided.
async function stamped(response) {
  const headers = new Headers(response.headers);
  headers.set(STAMP, String(Date.now()));
  // the body below is already decoded: models arrive gzip-encoded (.glb.gz), and a stored copy that
  // still said so would be decoded twice
  headers.delete('content-encoding');
  headers.delete('content-length');
  const body = await response.blob();
  return new Response(body, { status: response.status, statusText: response.statusText, headers });
}

async function store(cache, request, response) {
  if (!response || response.status !== 200 || response.type === 'opaque') return;
  try {
    await cache.put(request, await stamped(response));
  } catch (_) {
    // quota full or the like: the game still works from the network
  }
}

async function fromNetwork(cache, request) {
  const response = await fetch(request);
  // stored after it has been handed back, so the page never waits on the copy
  store(cache, request, response.clone());
  return response;
}

async function handle(request, url) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  const versioned = url.searchParams.has('vsn');

  if (cached) {
    if (!versioned) {
      const at = Number(cached.headers.get(STAMP) || 0);
      if (Date.now() - at > REVALIDATE_MS) fromNetwork(cache, request).catch(() => {});
    }
    return cached;
  }
  return fromNetwork(cache, request);
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || request.mode === 'navigate') return;
  if (request.headers.has('range')) return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (!CACHE_PATTERNS.some((p) => p.test(url.pathname))) return;
  event.respondWith(handle(request, url));
});

self.addEventListener('message', (event) => {
  const reply = (msg) => event.ports && event.ports[0] && event.ports[0].postMessage(msg);
  const action = event.data && event.data.action;
  if (action === 'clearCache') {
    caches.delete(CACHE_NAME).then(() => reply({ ok: true }));
  } else if (action === 'getCacheInfo') {
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.keys())
      .then((keys) => reply({ ok: true, cacheName: CACHE_NAME, itemCount: keys.length }));
  }
});
