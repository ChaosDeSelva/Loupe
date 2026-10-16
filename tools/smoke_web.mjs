#!/usr/bin/env node
// Browser smoke test for the Afterimage love.js build's analytics.
//
//   node tools/smoke_web.mjs site/play --expect key       # page built with a public key
//   node tools/smoke_web.mjs site/play --expect keyless   # a fork or local build
//
// Serves the folder on localhost, answers the Ravensight API with a local mock
// (nothing leaves the machine), launches the game in Chromium and checks:
//   key:     analytics is always on: nothing before the player presses Play,
//            then exactly one settings check and one session before the first
//            event batch, then the game's session_started; the page keeps
//            nothing in localStorage.
//   keyless: the bridge is a sink and the page sends nothing at all.
// Both: the game keeps its exit mailbox in the love.js file system.
// Any request to another origin fails the test.
//
// Needs the playwright package and Chromium (npx playwright install chromium).
// Resolves playwright from this folder, the working directory or --modules DIR.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};
const root = path.resolve(args.find((a, i) => !a.startsWith('--') && !args[i - 1]?.startsWith('--')) || 'site/play');
const expect = option('--expect', 'key');
const apiOrigin = option('--api', 'https://api.ravensight.io');
const timeoutMs = Number(option('--timeout', '90000'));
if (!['key', 'keyless'].includes(expect)) throw new Error('--expect is key or keyless');

async function loadPlaywright() {
  const places = [option('--modules'), process.cwd(), path.dirname(new URL(import.meta.url).pathname)];
  for (const place of places.filter(Boolean)) {
    try {
      return createRequire(path.join(path.resolve(place), 'noop.js'))('playwright');
    } catch {
      // try the next place
    }
  }
  return import('playwright');
}

const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.wasm': 'application/wasm', '.png': 'image/png', '.txt': 'text/plain', '.data': 'application/octet-stream',
};
function serve(dir) {
  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const file = path.join(dir, decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
      if (!file.startsWith(dir)) throw new Error('outside');
      if (!(await stat(file)).isFile()) throw new Error('not a file');
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      res.end(await readFile(file));
    } catch {
      res.writeHead(404).end();
    }
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(check, what, ms = timeoutMs) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await check()) return;
    await sleep(250);
  }
  throw new Error('timed out waiting for ' + what);
}

const failures = [];
const check = (ok, message) => {
  console.log((ok ? 'ok   ' : 'FAIL ') + message);
  if (!ok) failures.push(message);
};

const { chromium } = await loadPlaywright();
const server = await serve(root);
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
const context = await browser.newContext({ viewport: { width: Number(option('--width', '1440')), height: Number(option('--height', '900')) }, deviceScaleFactor: Number(option('--dpr', '1')) });
const api = [];
const foreign = [];
await context.route(apiOrigin + '/**', async (route) => {
  const request = route.request();
  const endpoint = new URL(request.url()).pathname.replace(/^\/api\/v1/, '');
  api.push({ method: request.method(), endpoint, body: request.postData() });
  if (endpoint === '/settings') return route.fulfill({ json: { trackingEnabled: true } });
  if (endpoint === '/session') return route.fulfill({ status: 201, json: { token: 'smoke', expiresIn: 3600 } });
  if (endpoint.startsWith('/track')) return route.fulfill({ status: 202, json: { accepted: 1 } });
  return route.fulfill({ status: 404, json: {} });
});
context.on('request', (request) => {
  const url = request.url();
  if (!url.startsWith(base) && !url.startsWith(apiOrigin) && !url.startsWith('data:') && !url.startsWith('blob:')) foreign.push(url);
});

const page = await context.newPage();
const consoleLines = [];
page.on('console', (message) => consoleLines.push(message.text()));
page.on('pageerror', (error) => failures.push('page error: ' + error.message));

// The game is drawing once its first frame wrote the input-size mailbox.
async function launch() {
  await page.goto(base);
  await page.waitForSelector('#launch:not([disabled])', { timeout: timeoutMs });
  await sleep(1500);
  check(api.length === 0, `no API request before the player presses Play (${api.length})`);
  check(await page.locator('#launch').evaluate(el=>document.activeElement===el), 'Play receives initial focus');
  check(await page.locator('#status').isHidden(), 'launch status is hidden');
  await page.click('#launch');
  await until(() => page.evaluate(() => {
    try { return Boolean(window.Module && Module.FS && Module.FS.readFile('/tmp/afterimage-input.txt')); } catch { return false; }
  }), 'the game to draw');
  await sleep(1500);
}
const readMailbox = () => page.evaluate(() => { try { return Module.FS.readFile('/tmp/ravensight-exit.json', { encoding: 'utf8' }); } catch { return null; } });

try {
  await launch();
  if (option('--screenshot')) {
    console.log('Canvas: ' + await page.getAttribute('#canvas', 'data-render-size'));
    await page.screenshot({ path: option('--screenshot') });
  }
  const mode = await page.evaluate(() => document.documentElement.dataset.analytics);
  check(mode === (expect === 'key' ? 'live' : 'sink'), `page analytics mode is ${mode}`);
  if (expect === 'keyless') {
    await sleep(5000);
    check(api.length === 0, `a keyless page sends nothing (${api.length})`);
    check(!consoleLines.some((l) => l.startsWith('__RAVENSIGHT__')), 'tagged lines are swallowed by the sink');
  } else {
    await until(() => api.some((r) => r.endpoint === '/session'), 'a session after Play', 20000);
    await until(() => api.some((r) => r.endpoint.startsWith('/track')), 'the first event batch', 20000);
    const beforeEvents = [];
    for (const r of api) {
      if (r.endpoint.startsWith('/track')) break;
      beforeEvents.push(`${r.method} ${r.endpoint}`);
    }
    check(beforeEvents.join(', ') === 'GET /settings, POST /session', `before the first batch: ${beforeEvents.join(', ')}`);
    await sleep(3000);
    const tally = (endpoint) => api.filter((r) => r.endpoint === endpoint).length;
    check(tally('/settings') === 1 && tally('/session') === 1,
      `one settings check and one session (${tally('/settings')}, ${tally('/session')})`);
    // The SDK's own game_started may go first; the game's events follow.
    const sent = () => api.filter((r) => r.endpoint.startsWith('/track'))
      .flatMap((r) => JSON.parse(r.body || '{}').events || []);
    await until(() => sent().some((e) => e.event === 'session_started'), 'session_started', 20000).catch(() => {});
    const names = sent().map((e) => e.event);
    check(names.includes('session_started'), `the game's session_started was sent (${names.join(', ')})`);
    const game = sent().find((e) => e.event === 'session_started');
    check(game && game.data.distribution && game.data.distribution.startsWith('web-') && game.data.platform === 'web',
      'events name the web distribution and platform');
    check(await page.evaluate(() => localStorage.getItem('ravensight.love.enabled')) === null,
      'the page keeps no choice in localStorage');
    check(await page.getAttribute('#canvas', 'data-analytics-ready') === 'true', 'SDK startup follows the game ready signal');
    // Emulate a returning player's existing SDK opt-out, then reload normally.
    await page.evaluate(() => new Promise((resolve, reject) => {
      const dir='/home/web_user/love/afterimage-first-flight';
      Module.FS.mkdirTree(dir);
      Module.FS.writeFile(dir+'/ravensight_optout', '1');
      Module.FS.syncfs(false, error => error ? reject(error) : resolve());
    }));
    const beforeOptOut=api.length;
    await page.reload();
    await page.waitForSelector('#launch:not([disabled])');
    await page.click('#launch');
    await until(() => page.getAttribute('#canvas','data-analytics-ready').then(x=>x==='false'), 'saved opt-out ready signal');
    await sleep(5000);
    check(api.length===beforeOptOut, 'saved opt-out makes ZERO settings/session/event requests on return');
    check(await readMailbox()===null, 'saved opt-out has no exit-event mailbox');

  }
  const mailbox = await readMailbox();
  if(expect==='keyless')check(Boolean(mailbox && mailbox.includes('session_ended')), 'the exit mailbox is kept in the love.js file system');
  check(foreign.length === 0, `no request to any other origin (${foreign.join(' ') || 'none'})`);
} catch (error) {
  failures.push(error.message);
  console.log('FAIL ' + error.message);
} finally {
  await browser.close();
  server.close();
}
if (failures.length) {
  console.log(`smoke_web: ${failures.length} failure(s)`);
  process.exit(1);
}
console.log(`smoke_web: PASS (${expect})`);
