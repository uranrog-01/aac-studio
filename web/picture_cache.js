/* Shared by the page and service worker. Pictures survive app-code updates;
   content hashes prevent outdated artwork being reused under a new label. */
(() => {
  const hashes = __PICTURE_HASHES__;
  const base = typeof document === 'undefined' ? self.registration.scope : document.baseURI;
  const expected = new Map(Object.entries(hashes).map(([path, hash]) => [new URL(path, base).href, hash]));
  const CACHE = 'aac-pictures-v1';
  function key(path) {
    const url = new URL(path, base);
    url.search = ''; url.hash = '';
    const hash = expected.get(url.href);
    if (!hash) return null;
    url.searchParams.set('aac-image', hash);
    return url.href;
  }
  async function put(path, response) {
    const address = key(path);
    if (!address || !response.ok) throw Error('Picture unavailable');
    const digest = await crypto.subtle.digest('SHA-256', await response.clone().arrayBuffer());
    const actual = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
    if (actual !== new URL(address).searchParams.get('aac-image')) throw Error('Picture version changed. Reload and retry.');
    await (await caches.open(CACHE)).put(address, response);
  }
  async function migrateLegacy() {
    const pictures = await caches.open(CACHE);
    for (const name of await caches.keys()) {
      if (!name.startsWith('aac-symbols-') && name !== 'aac-symbols') continue;
      const old = await caches.open(name);
      let complete = true;
      for (const request of await old.keys()) {
        const address = key(request.url);
        if (address && !await pictures.match(address)) {
          try { await put(request.url, await old.match(request)); }
          catch (error) {
            if (error.name === 'QuotaExceededError') { complete = false; break; }
            // Changed artwork is downloaded again when needed.
          }
        }
        await old.delete(request);
      }
      if (complete) await caches.delete(name);
    }
    const valid = new Set([...expected.keys()].map(key));
    for (const request of await pictures.keys()) {
      if (!valid.has(request.url)) await pictures.delete(request);
    }
  }
  self.aacPictures = {name: CACHE, key, put, migrateLegacy, files: Object.keys(hashes)};
})();
