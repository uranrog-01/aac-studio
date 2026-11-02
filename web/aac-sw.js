/* CORE_FILES and BUILD_ID are filled by tools/build_web.py. */
const CORE_FILES = __CORE_FILES__;
const CORE_CACHE = 'aac-core-__BUILD_ID__';
const PICTURES = 'aac-symbols-__BUILD_ID__';
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CORE_CACHE);
    // A failed or partial download must not replace a working offline build.
    await cache.addAll(CORE_FILES);
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if ((key.startsWith('aac-core-') && key !== CORE_CACHE) || (key.startsWith('aac-symbols') && key !== PICTURES)) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  const scope = new URL(self.registration.scope);
  if (request.method !== 'GET' || url.origin !== scope.origin ||
      !url.pathname.startsWith(scope.pathname)) return;
  event.respondWith((async () => {
    const core = await caches.open(CORE_CACHE);
    if (request.mode === 'navigate') {
      try { return await fetch(request); }
      catch (_) { return await core.match('index.html'); }
    }
    const coreHit = await core.match(request, {ignoreSearch: true});
    if (coreHit) return coreHit;
    if ((url.pathname.includes('/assets/assets/flat_symbols/') || url.pathname.includes('/assets/assets/symbols/mulberry/'))) {
      const pictures = await caches.open(PICTURES);
      const hit = await pictures.match(request, {ignoreSearch: true});
      if (hit) return hit;
      const response = await fetch(request);
      if (response.ok) {
        try { await pictures.put(request, response.clone()); }
        catch (_) { /* A full picture cache must not interrupt communication. */ }
      }
      return response;
    }
    return fetch(request);
  })());
});
