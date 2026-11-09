/* CORE_FILES and BUILD_ID are filled by tools/build_web.py. */
const CORE_FILES = __CORE_FILES__;
const CORE_CACHE = 'aac-core-__BUILD_ID__';
importScripts('picture_cache.js');
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CORE_CACHE);
    // A failed or partial download must not replace a working offline build.
    // 'reload' skips the browser's HTTP cache: hosts such as GitHub Pages let
    // it keep files for minutes, and an update must not store the previous
    // version's board or code under the new build.
    await cache.addAll(CORE_FILES.map(file => new Request(file, {cache: 'reload'})));
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('aac-core-') && key !== CORE_CACHE) await caches.delete(key);
    }
    await self.aacPictures.migrateLegacy();
    await self.clients.claim();
    const core = await caches.open(CORE_CACHE);
    await core.put(new URL('aac-ready', self.registration.scope).href, new Response('__BUILD_ID__'));
  })());
});
self.addEventListener('message', event => {
  if (event.data?.type === 'AAC_STATUS' && event.ports[0]) {
    event.waitUntil((async () => {
      const core = await caches.open(CORE_CACHE);
      const ready = !!await core.match(new URL('aac-ready', self.registration.scope).href);
      event.ports[0].postMessage({buildId: '__BUILD_ID__', ready});
    })());
  }
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  const scope = new URL(self.registration.scope);
  // Fonts for other scripts (Arabic, Hindi, Chinese, Japanese, Korean...)
  // come from Google Fonts the first time a language is used; keep them so
  // that language also works offline afterwards.
  if (request.method === 'GET' && url.hostname === 'fonts.gstatic.com') {
    event.respondWith((async () => {
      const fonts = await caches.open('aac-fonts-v1');
      const hit = await fonts.match(request);
      if (hit) return hit;
      const response = await fetch(request);
      if (response.ok || response.type === 'opaque') {
        try { await fonts.put(request, response.clone()); } catch (_) {}
      }
      return response;
    })());
    return;
  }
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
    const pictureKey = self.aacPictures.key(url.href);
    if (pictureKey) {
      const pictures = await caches.open(self.aacPictures.name);
      const hit = await pictures.match(pictureKey);
      if (hit) return hit;
      const response = await fetch(pictureKey);
      if (response.ok) {
        try { await self.aacPictures.put(url.href, response.clone()); }
        catch (_) { /* A full picture cache must not interrupt communication. */ }
      }
      return response;
    }
    return fetch(request);
  })());
});
