/* Usage: AAC_PLAYWRIGHT_MODULE=<installed playwright module> node tools/test_web.cjs
 * Start a static server for build/web-pwa on localhost:8878 first.
 * Browser speech is intercepted: these tests do not prove audible iPhone speech.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium, webkit} = require(process.env.AAC_PLAYWRIGHT_MODULE || 'playwright');
const base = process.env.AAC_TEST_URL || 'http://127.0.0.1:8878/';
const output = path.resolve(__dirname, '../docs');

async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', {state: 'attached', timeout: 60000});
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
}

(async () => {
  const report = {physicalIphoneTested: false, audibleSpeechTested: false, browsers: []};
  for (const [name, engine] of Object.entries({chromium, webkit})) {
    if (process.env.AAC_TEST_ENGINES && !process.env.AAC_TEST_ENGINES.split(',').includes(name)) continue;
    const browser = await engine.launch({headless: true});
    try {
      const context = await browser.newContext({
        viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true,
        deviceScaleFactor: 1,
      });
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(base);
      await enableSemantics(page);
      await page.getByRole('button', {name: 'I', exact: true}).waitFor();
      await page.evaluate(() => {
        window.testSpeechRequests = [];
        window.aacSpeech.speak = (...args) => window.testSpeechRequests.push(args);
      });
      await page.getByRole('button', {name: 'I', exact: true}).tap();
      await page.getByRole('button', {name: 'want', exact: true}).tap();
      const speechAvailable = await page.evaluate(() => window.aacSpeech.available);
      if (speechAvailable) assert.deepEqual(await page.evaluate(() => window.testSpeechRequests.map(x => x[0])), ['I', 'want']);
      await page.getByRole('button', {name: 'Speak message', exact: true}).tap();
      if (speechAvailable) assert.equal(await page.evaluate(() => window.testSpeechRequests.at(-1)[0]), 'I want');
      await page.getByRole('button', {name: 'Clear', exact: true}).tap();
      await page.screenshot({path: path.join(output, `web-${name}-phone.png`)});
      await page.getByRole('button', {name: 'More', exact: true}).tap();
      await page.getByRole('button', {name: 'Settings', exact: true}).tap();
      await page.getByRole('button', {name: /Device voice Safari voices/}).waitFor();
      assert.equal(await page.getByRole('button', {name: /^Offline voice/}).count(), 0);

      // Let the real service worker finish its full starter-board installation.
      await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, {timeout: 120000});
      assert.match(await page.evaluate(() => window.aacWeb.offlineStatus()), /ready offline/);
      const saved = await page.evaluate(async () => {
        const pack = JSON.parse(await window.aacStorage.read('packs/sample_pack.json'));
        const id = pack.views[pack.rootFolder][0].cells[0].btn;
        pack.buttons.find(button => button.id === id).label = 'Saved web word';
        await window.aacStorage.write('packs/sample_pack.json', JSON.stringify(pack));
        return pack;
      });
      const downloadEvent = page.waitForEvent('download');
      await page.evaluate(() => window.aacWeb.exportBackup());
      const download = await downloadEvent;
      const backup = JSON.parse(await fs.readFile(await download.path(), 'utf8'));
      assert.equal(backup.format, 'aac-studio-web');
      assert.deepEqual(backup.files['packs/sample_pack.json'], saved);
      // Exercise a real atomic restore, including settings and learned words.
      await page.evaluate(async files => {
        await window.aacStorage.restore(JSON.stringify(files));
      }, {...backup.files, 'learned_words.json': {hello: 2}});

      const symbols = await page.evaluate(async () => (await fetch('offline-symbols.json')).json());
      if (name === 'chromium') {
        const count = await page.evaluate(() => window.aacWeb.downloadSymbols(() => {}));
        assert.equal(count, symbols.length);
      } else {
        // Verify on-demand caching in Safari's engine as well.
        await page.evaluate(async picture => {
          const response = await fetch(picture);
          if (!response.ok) throw Error('Picture unavailable');
        }, symbols.at(-1));
      }
      await context.setOffline(true);
      await page.reload();
      await enableSemantics(page);
      await page.getByRole('button', {name: 'Saved web word', exact: true}).waitFor();
      const offlinePicture = await page.evaluate(async picture => {
        const response = await fetch(picture);
        return response.ok && (await response.arrayBuffer()).byteLength > 0;
      }, symbols.at(-1));
      assert.equal(offlinePicture, true);
      assert.equal(await page.evaluate(async () => JSON.parse(await window.aacStorage.read('learned_words.json')).hello), 2);
      await page.screenshot({path: path.join(output, `web-${name}-offline.png`)});
      await page.setViewportSize({width: 844, height: 390});
      await page.getByRole('button', {name: 'Type', exact: true}).tap();
      await page.getByRole('textbox').waitFor();
      await page.screenshot({path: path.join(output, `web-${name}-landscape-keyboard.png`)});
      assert.deepEqual(errors, []);
      report.browsers.push({name, engine: browser.version(), persistedBoard: true,
        backupExportRestore: true, offlineRelaunch: true, offlinePicture: true,
        synchronousSpeechRequests: speechAvailable, landscapeKeyboard: true,
        fullLibraryDownload: name === 'chromium', pictureFiles: symbols.length});
      console.log(`${name}: passed`);
    } finally { await browser.close(); }
  }
  await fs.writeFile(path.join(output, 'web-verification.json'), JSON.stringify(report, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
