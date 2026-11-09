/* Verify a real 1.8.0 -> current service-worker upgrade on one browser origin.
 * Run before replacing sites/aac-studio-iphone/dist with the new export. */
const {chromium} = require(process.env.AAC_PLAYWRIGHT_MODULE || 'playwright');
const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const previous = path.join(root, 'sites/aac-studio-iphone/dist');
const current = path.join(root, 'build/web-pwa');
let activeRoot = previous;
const network = [];
const mime = {'.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.png': 'image/png'};
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://localhost');
    const relative = decodeURIComponent(url.pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(activeRoot, relative);
    if (!file.startsWith(activeRoot + path.sep)) throw Error('Invalid path');
    if (activeRoot === current) network.push(relative);
    const bytes = await fs.readFile(file);
    response.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream',
      'Content-Length': bytes.length, 'Cache-Control': 'no-store'});
    response.end(bytes);
  } catch (_) { response.writeHead(404); response.end(); }
});

(async () => {
  await new Promise(resolve => server.listen(8890, '127.0.0.1', resolve));
  const browser = await chromium.launch({headless: true});
  try {
    const context = await browser.newContext({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true});
    const page = await context.newPage();
    await page.goto('http://127.0.0.1:8890/');
    await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, {timeout: 120000});
    const paths = JSON.parse(await fs.readFile(path.join(previous, 'offline-symbols.json'), 'utf8'));
    const oldWorker = await fs.readFile(path.join(previous, 'aac-sw.js'), 'utf8');
    const core = new Set(JSON.parse(oldWorker.match(/^const CORE_FILES = (.*);$/m)[1]));
    const pictures = paths.filter(file => !core.has(file)).slice(0, 3);
    await page.evaluate(async pictures => {
      for (const picture of pictures) {
        const response = await fetch(picture);
        if (!response.ok) throw Error('Old picture did not load');
        await response.arrayBuffer();
      }
      const board = JSON.parse(await aacStorage.read('packs/sample_pack.json'));
      const id = board.views[board.rootFolder][0].cells[0].btn;
      board.buttons.find(button => button.id === id).label = 'Upgrade saved word';
      await aacStorage.write('packs/sample_pack.json', JSON.stringify(board));
    }, pictures);
    const expected = JSON.parse(await fs.readFile(path.join(current, 'web-build.json'), 'utf8'));
    activeRoot = current;
    await page.evaluate(async () => (await navigator.serviceWorker.getRegistration()).update());
    const deadline = Date.now() + 120000;
    let activated = false;
    while (Date.now() < deadline) {
      const status = await page.evaluate(() => new Promise(resolve => {
        const worker = navigator.serviceWorker.controller;
        if (!worker) return resolve(null);
        const channel = new MessageChannel();
        const timer = setTimeout(() => { channel.port1.close(); resolve(null); }, 300);
        channel.port1.onmessage = event => {
          clearTimeout(timer); channel.port1.close(); resolve(event.data);
        };
        worker.postMessage({type: 'AAC_STATUS'}, [channel.port2]);
      }));
      if (status?.ready && status.buildId === expected.buildId) { activated = true; break; }
      await new Promise(resolve => setTimeout(resolve, 200));
    }
    assert.equal(activated, true, 'Updated worker must finish activation and cache migration');
    assert.equal(pictures.some(file => network.includes(file)), false, 'Cached pictures must migrate locally');
    await page.reload();
    await page.waitForSelector('flt-semantics-placeholder', {state: 'attached'});
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    await page.getByRole('button', {name: 'Upgrade saved word', exact: true}).waitFor();
    assert.equal(await page.getByRole('button', {name: 'My words', exact: true}).count(), 0);
    const migrated = await page.evaluate(async pictures => {
      const cache = await caches.open(aacPictures.name);
      return Promise.all(pictures.map(async file => !!await cache.match(aacPictures.key(file))));
    }, pictures);
    assert.deepEqual(migrated, [true, true, true]);
    await context.setOffline(true);
    for (const picture of pictures) assert.equal(await page.evaluate(async file => (await fetch(file)).ok, picture), true);
    await page.getByRole('button', {name: 'Type', exact: true}).tap();
    await page.getByRole('button', {name: 'a', exact: true}).waitFor();
    await page.screenshot({path: path.join(root, 'docs/web-upgraded-keyboard.png')});
    const report = {passed: true, previousVersion: '1.8.0', newBuildId: expected.buildId,
      savedBoardRetained: true, cachedPicturesRetainedWithoutNetwork: pictures.length,
      newKeyboardOffline: true, removedMyWords: true};
    await fs.writeFile(path.join(root, 'docs/web-upgrade-verification.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report));
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
