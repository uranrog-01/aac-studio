/* Local-only board storage and device speech. No account or analytics. */
(() => {
  'use strict';
  const BUILD_ID = '__BUILD_ID__';
  const PICTURES_CACHE = self.aacPictures.name;
  let database;
  function openDatabase() {
    if (!database) database = new Promise((resolve, reject) => {
      const request = indexedDB.open('aac-studio', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('files');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(new Error('Close other AAC Studio tabs and retry.'));
    }).catch(error => { database = null; throw error; });
    return database;
  }
  async function transaction(mode, operation) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('files', mode);
      const request = operation(tx.objectStore('files'));
      tx.oncomplete = () => resolve(request.result ?? null);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error('Save interrupted'));
    });
  }
  window.aacStorage = {
    read: key => transaction('readonly', store => store.get(key)),
    write: (key, value) => transaction('readwrite', store => store.put(value, key)).catch(error => {
      const banner = document.getElementById('save-error');
      if (banner) { banner.hidden = false; banner.textContent = 'A change could not be saved. Keep this app open and save a backup in Settings.'; }
      throw error;
    }),
    async restore(json) {
      const files = JSON.parse(json);
      const db = await openDatabase();
      return new Promise((resolve, reject) => {
        const tx = db.transaction('files', 'readwrite');
        const store = tx.objectStore('files');
        for (const key of ['packs/sample_pack.json', 'settings.json', 'learned_words.json']) {
          if (files[key]) store.put(JSON.stringify(files[key]), key);
        }
        tx.oncomplete = () => resolve(null);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error || new Error('Restore interrupted'));
      });
    },
  };

  let utterance;
  const speech = window.speechSynthesis;
  window.aacSpeech = {
    available: !!speech,
    onError: () => {},
    voices: () => speech ? speech.getVoices() : [],
    stop: () => { if (speech) speech.cancel(); utterance = null; },
    speak(text, rate, pitch, volume, name, locale) {
      if (!speech) throw new Error('Browser speech unavailable');
      speech.cancel();
      utterance = new SpeechSynthesisUtterance(text);
      const voices = speech.getVoices();
      const voice = voices.find(v => v.name === name && (!locale || v.lang === locale));
      if (voice) utterance.voice = voice;
      utterance.lang = voice?.lang || locale || 'en-US';
      utterance.rate = Math.max(.25, Math.min(2, rate / .45));
      utterance.pitch = pitch;
      utterance.volume = volume;
      utterance.onerror = event => {
        if (!['canceled', 'interrupted'].includes(event.error)) {
          window.aacSpeech.onError(event.error || 'Speech failed');
        }
      };
      // Keep a reference for Safari, and start within the original tap activation.
      speech.speak(utterance);
    },
  };

  window.aacWeb = {
    async offlineStatus() {
      if (!window.isSecureContext) return 'Use an HTTPS address to enable offline use.';
      if (!('serviceWorker' in navigator)) return 'Offline storage is unavailable in this browser.';
      if (window.aacOfflineError) return 'Offline download failed. Reopen online and try again.';
      const registration = await navigator.serviceWorker.getRegistration();
      if (!registration?.active) return 'Preparing starter boards for offline use...';
      const active = await activeBuild(registration.active);
      if (!active?.ready || active.buildId !== BUILD_ID) return 'An update is preparing. Keep the app online, then reload.';
      const cache = await caches.open(PICTURES_CACHE);
      const count = (await cache.keys()).length;
      return `Starter boards ready offline. ${count.toLocaleString()} extra pictures saved. Voice availability depends on your device.`;
    },
    async downloadSymbols(onProgress) {
      if (!('serviceWorker' in navigator) || !window.isSecureContext) {
        throw new Error('Open the HTTPS version to save pictures offline.');
      }
      const registration = await navigator.serviceWorker.ready;
      const active = await activeBuild(registration.active);
      if (!active?.ready || active.buildId !== BUILD_ID) throw Error('Reload to finish the app update.');
      await navigator.storage?.persist?.();
      const response = await fetch('offline-symbols.json');
      if (!response.ok) throw new Error('Picture list unavailable');
      const paths = await response.json();
      const cache = await caches.open(PICTURES_CACHE);
      let next = 0, done = 0;
      await Promise.all(Array.from({length: 4}, async () => {
        while (next < paths.length) {
          const path = paths[next++];
          const key = self.aacPictures.key(path);
          if (!await cache.match(key)) {
            const image = await fetch(path);
            if (!image.ok) throw new Error('A picture could not be saved. Retry to resume.');
            if (!await cache.match(key)) await self.aacPictures.put(path, image);
          }
          onProgress(++done, paths.length);
        }
      }));
      return paths.length;
    },
    async exportBackup() {
      const files = {};
      for (const key of ['packs/sample_pack.json', 'settings.json', 'learned_words.json']) {
        const value = await window.aacStorage.read(key);
        if (value !== null) files[key] = JSON.parse(value);
      }
      const blob = new Blob([JSON.stringify({format: 'aac-studio-web', version: 1, files}, null, 2)], {type: 'application/json'});
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = `AAC-Studio-backup-${new Date().toISOString().slice(0, 10)}.json`;
      document.body.append(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    },
    pickBackup() {
      return new Promise((resolve, reject) => {
        const input = document.createElement('input');
        input.type = 'file'; input.accept = '.json,application/json';
        input.oncancel = () => resolve('');
        input.onchange = async () => {
          try { resolve(input.files[0] ? await input.files[0].text() : ''); }
          catch (error) { reject(error); }
        };
        input.click();
      });
    },
  };
  function activeBuild(worker) {
    return new Promise(resolve => {
      if (!worker) return resolve(null);
      const channel = new MessageChannel();
      const timer = setTimeout(() => { channel.port1.close(); resolve(null); }, 5000);
      channel.port1.onmessage = event => { clearTimeout(timer); channel.port1.close(); resolve(event.data); };
      worker.postMessage({type: 'AAC_STATUS'}, [channel.port2]);
    });
  }
  if ('serviceWorker' in navigator && window.isSecureContext) {
    const hadController = !!navigator.serviceWorker.controller;
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (hadController) document.getElementById('update-ready').hidden = false;
    });
    document.getElementById('reload-app').onclick = () => location.reload();
    navigator.serviceWorker.register('aac-sw.js', {updateViaCache: 'none'})
        .catch(() => { window.aacOfflineError = true; });
  }
})();
