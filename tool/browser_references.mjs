#!/usr/bin/env node

import { execFileSync, spawn } from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const MANIFEST_PATH = join(ROOT, 'conformance', 'manifest.json');
const DEFAULT_OUTPUT = join(ROOT, 'build', 'conformance', 'browser');
const BROWSER_CANDIDATES = [
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
];

const FONT_FACES = [
  ['WeftRoboto', 'Roboto-Regular.ttf', 400, 'normal'],
  ['WeftRoboto', 'Roboto-Bold.ttf', 700, 'normal'],
  ['WeftRoboto', 'Roboto-Italic.ttf', 400, 'italic'],
  ['WeftRoboto', 'Roboto-BoldItalic.ttf', 700, 'italic'],
  ['WeftRobotoMono', 'RobotoMono-Regular.ttf', 400, 'normal'],
  ['WeftRobotoMono', 'RobotoMono-Bold.ttf', 700, 'normal'],
];

const { values } = parseArgs({
  options: {
    browser: { type: 'string' },
    output: { type: 'string' },
    case: { type: 'string', multiple: true },
  },
  strict: true,
});

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : String(error));
  process.exitCode = 1;
});

async function main() {
  const browser = findBrowser(values.browser);
  const output = resolve(values.output ?? DEFAULT_OUTPUT);
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'));
  const allCases = manifest.cases;
  const fontFaceCss = buildFontFaceCss();
  const compatCss = readFileSync(
    join(ROOT, 'conformance', 'browser_compat.css'),
    'utf8',
  );
  const selected = new Set(values.case ?? []);
  const known = new Set(allCases.map((item) => item.id));
  const unknown = [...selected].filter((id) => !known.has(id));
  if (unknown.length > 0) {
    throw new Error(`Unknown case ids: ${unknown.join(', ')}`);
  }
  const cases = allCases.filter(
    (item) => selected.size === 0 || selected.has(item.id),
  );

  const htmlDir = join(output, 'html');
  const imageDir = join(output, 'images');
  const geometryDir = join(output, 'geometry');
  mkdirSync(htmlDir, { recursive: true });
  mkdirSync(imageDir, { recursive: true });
  mkdirSync(geometryDir, { recursive: true });

  const assetsSource = join(ROOT, 'conformance', 'assets');
  if (existsSync(assetsSource)) {
    // Cases reference fixtures as `assets/<name>` relative to the wrapped
    // HTML files, so the copy must live beside them under html/.
    cpSync(assetsSource, join(htmlDir, 'assets'), { recursive: true });
  }

  const profile = mkdtempSync(join(tmpdir(), 'weft-chrome-'));
  let chrome;
  let cdp;
  try {
    chrome = await launchBrowser(browser, profile);
    const port = await waitForDevtoolsPort(profile);
    cdp = await openPage(port);
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');

    const rendered = [];
    for (const item of cases) {
      const result = await renderCase(
        cdp,
        item,
        output,
        htmlDir,
        imageDir,
        geometryDir,
        fontFaceCss,
        compatCss,
      );
      rendered.push(result);
      console.log(`rendered ${item.id} -> ${result.screenshot}`);
    }

    const metadata = {
      manifestVersion: manifest.version,
      browser: browserInfo(browser),
      viewport: manifest.viewport,
      cases: rendered,
    };
    writeFileSync(
      join(output, 'metadata.json'),
      `${JSON.stringify(metadata, null, 2)}\n`,
      'utf8',
    );
    console.log(`wrote ${join(output, 'metadata.json')}`);
  } finally {
    await cdp?.close();
    if (chrome && chrome.exitCode === null) {
      chrome.kill();
    }
    try {
      rmSync(profile, { recursive: true, force: true });
    } catch {
      // Chrome may still hold profile files briefly on Windows.
    }
  }
}

function findBrowser(explicit) {
  if (explicit) {
    const path = resolve(explicit);
    if (!existsSync(path)) {
      throw new Error(`Browser executable not found: ${path}`);
    }
    return path;
  }
  if (process.env.WEFT_BROWSER) {
    const path = resolve(process.env.WEFT_BROWSER);
    if (!existsSync(path)) {
      throw new Error(
        `WEFT_BROWSER does not point to a file: ${process.env.WEFT_BROWSER}`,
      );
    }
    return path;
  }
  const found = BROWSER_CANDIDATES.find((candidate) => existsSync(candidate));
  if (found) return found;
  throw new Error(
    'No Chromium browser found. Set WEFT_BROWSER or pass --browser.',
  );
}

function browserInfo(browser) {
  const executable = browser.toLowerCase();
  const name = executable.includes('msedge')
    ? 'Microsoft Edge'
    : executable.includes('chrome')
      ? 'Google Chrome'
      : executable.includes('chromium')
        ? 'Chromium'
        : browser;
  let version = 'unknown';

  if (process.platform === 'win32') {
    const powershell = join(
      process.env.SystemRoot ?? 'C:\\Windows',
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
    if (existsSync(powershell)) {
      const escaped = browser.replaceAll("'", "''");
      try {
        version =
          execFileSync(
            powershell,
            [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              `(Get-Item -LiteralPath '${escaped}').VersionInfo.ProductVersion`,
            ],
            { encoding: 'utf8', timeout: 15000 },
          ).trim() || 'unknown';
      } catch {
        version = 'unknown';
      }
    }
  } else {
    try {
      const output = execFileSync(browser, ['--version'], {
        encoding: 'utf8',
        timeout: 15000,
      }).trim();
      const match = output.match(/(\d+\.\d+\.\d+(?:\.\d+)?)/);
      version = match ? match[1] : output || 'unknown';
    } catch {
      version = 'unknown';
    }
  }
  return { name, version };
}

function buildFontFaceCss() {
  return FONT_FACES.map(([family, file, weight, style]) => {
    const bytes = readFileSync(join(ROOT, 'conformance', 'fonts', file));
    return `@font-face{font-family:"${family}";` +
      `src:url(data:font/ttf;base64,${bytes.toString('base64')}) ` +
      `format("truetype");font-weight:${weight};font-style:${style};}`;
  }).join('\n');
}

function wrapDocument(fragment, fontFaceCss, compatCss) {
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>${fontFaceCss}</style>
<style>${compatCss}</style>
</head>
<body>
${fragment}
</body>
</html>
`;
}

async function launchBrowser(browser, profile) {
  const child = spawn(
    browser,
    [
      '--headless=new',
      '--disable-gpu',
      '--disable-background-networking',
      '--disable-extensions',
      '--disable-sync',
      '--hide-scrollbars',
      '--no-first-run',
      '--no-default-browser-check',
      '--force-device-scale-factor=1',
      '--force-color-profile=srgb',
      '--font-render-hinting=none',
      '--disable-lcd-text',
      '--remote-debugging-port=0',
      `--user-data-dir=${profile}`,
      'about:blank',
    ],
    { stdio: 'ignore' },
  );
  child.on('error', () => {});
  return child;
}

async function waitForDevtoolsPort(profile) {
  const activePort = join(profile, 'DevToolsActivePort');
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    if (existsSync(activePort)) {
      const [port] = readFileSync(activePort, 'utf8').trim().split(/\r?\n/);
      if (port) return Number(port);
    }
    await delay(100);
  }
  throw new Error('Timed out waiting for the browser DevTools port.');
}

async function openPage(port) {
  const endpoint = `http://127.0.0.1:${port}/json/list`;
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(endpoint);
      if (response.ok) {
        const targets = await response.json();
        const page = targets.find((item) => item.type === 'page');
        if (page?.webSocketDebuggerUrl) {
          return CdpClient.connect(page.webSocketDebuggerUrl);
        }
      }
    } catch {
      // Browser is still starting.
    }
    await delay(100);
  }
  throw new Error('Timed out waiting for a debuggable browser page.');
}

async function renderCase(
  cdp,
  item,
  output,
  htmlDir,
  imageDir,
  geometryDir,
  fontFaceCss,
  compatCss,
) {
  const width = Number(item.width);
  const height = Number(item.height);
  const fragment = readFileSync(
    join(ROOT, 'conformance', item.file),
    'utf8',
  );
  const htmlPath = join(htmlDir, `${item.id}.html`);
  const imagePath = join(imageDir, `${item.id}.png`);
  writeFileSync(
    htmlPath,
    wrapDocument(fragment, fontFaceCss, compatCss),
    'utf8',
  );

  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: false,
    screenWidth: width,
    screenHeight: height,
  });
  await cdp.send('Emulation.setScrollbarsHidden', { hidden: true });

  const loaded = cdp.waitFor('Page.loadEventFired');
  await cdp.send('Page.navigate', { url: pathToFileURL(htmlPath).href });
  await loaded;
  await cdp.send('Runtime.evaluate', {
    expression: `new Promise((resolve) => {
      const finish = () => requestAnimationFrame(() =>
        requestAnimationFrame(() => resolve(true)));
      if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(finish);
      } else {
        finish();
      }
    })`,
    awaitPromise: true,
    returnByValue: true,
  });

  const viewportResult = await cdp.send('Runtime.evaluate', {
    expression:
      '({ width: window.innerWidth, height: window.innerHeight, dpr: window.devicePixelRatio })',
    returnByValue: true,
  });
  const viewport = viewportResult.result.value;
  if (viewport.width !== width || viewport.height !== height) {
    throw new Error(
      `Viewport mismatch for ${item.id}: expected ${width}x${height}, ` +
        `got ${viewport.width}x${viewport.height}.`,
    );
  }

  const screenshot = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  const image = Buffer.from(screenshot.data, 'base64');
  const actual = pngSize(image);
  if (actual.width !== width || actual.height !== height) {
    throw new Error(
      `Screenshot mismatch for ${item.id}: expected ${width}x${height}, ` +
        `got ${actual.width}x${actual.height}.`,
    );
  }
  writeFileSync(imagePath, image);

  const geometry = await collectGeometry(cdp);
  const geometryPath = join(geometryDir, `${item.id}.json`);
  writeFileSync(
    geometryPath,
    `${JSON.stringify(geometry, null, 2)}\n`,
    'utf8',
  );

  return {
    id: item.id,
    width,
    height,
    viewport,
    html: relative(output, htmlPath),
    screenshot: relative(output, imagePath),
    geometry: relative(output, geometryPath),
  };
}

async function collectGeometry(cdp) {
  const result = await cdp.send('Runtime.evaluate', {
    expression: GEOMETRY_EXPRESSION,
    returnByValue: true,
  });
  return result.result.value;
}

const GEOMETRY_EXPRESSION = `(() => {
  const elements = {};
  for (const el of document.body.querySelectorAll('[data-geo]')) {
    const key = el.getAttribute('data-geo');
    const r = el.getBoundingClientRect();
    elements[key] = {
      tag: el.tagName.toLowerCase(),
      left: round(r.left),
      top: round(r.top + window.scrollY),
      width: round(r.width),
      height: round(r.height),
    };
  }
  const words = {};
  for (const el of document.body.querySelectorAll('[data-words]')) {
    const key = el.getAttribute('data-words');
    const tokens = [];
    for (const node of el.childNodes) {
      if (node.nodeType !== Node.TEXT_NODE) continue;
      const pattern = /\\S+/g;
      let match;
      while ((match = pattern.exec(node.data)) !== null) {
        const range = document.createRange();
        range.setStart(node, match.index);
        range.setEnd(node, pattern.lastIndex);
        const rects = [...range.getClientRects()].filter((r) => r.width > 0);
        if (rects.length === 0) continue;
        tokens.push({
          text: match[0],
          rects: rects.map((r) => ({
            left: round(r.left),
            top: round(r.top + window.scrollY),
            right: round(r.right),
            bottom: round(r.bottom + window.scrollY),
          })),
        });
      }
    }
    words[key] = tokens;
  }
  return {
    documentHeight: round(
      Math.max(
        document.documentElement.scrollHeight,
        document.body.scrollHeight,
      ),
    ),
    elements,
    words,
  };
  function round(value) {
    return Math.round(value * 100) / 100;
  }
})()`;

function pngSize(buffer) {
  if (
    buffer.length < 24 ||
    buffer.toString('ascii', 1, 4) !== 'PNG'
  ) {
    throw new Error('Browser returned an invalid PNG.');
  }
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  };
}

function relative(root, path) {
  return path
    .slice(root.length + 1)
    .split('\\')
    .join('/');
}

function delay(milliseconds) {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}

class CdpClient {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.eventWaiters = new Map();
  }

  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolveOpen, rejectOpen) => {
      ws.addEventListener('open', resolveOpen, { once: true });
      ws.addEventListener('error', rejectOpen, { once: true });
    });
    const client = new CdpClient(ws);
    ws.addEventListener('message', (event) => client.handleMessage(event));
    return client;
  }

  handleMessage(event) {
    const message = JSON.parse(String(event.data));
    if (message.id) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(
          new Error(`${pending.method}: ${message.error.message}`),
        );
      } else {
        pending.resolve(message.result ?? {});
      }
      return;
    }
    const waiters = this.eventWaiters.get(message.method);
    if (!waiters || waiters.length === 0) return;
    this.eventWaiters.set(message.method, []);
    for (const waiter of waiters) waiter.resolve(message.params ?? {});
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolveSend, rejectSend) => {
      this.pending.set(id, { resolve: resolveSend, reject: rejectSend, method });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  waitFor(method, timeout = 15000) {
    return new Promise((resolveWait, rejectWait) => {
      const waiters = this.eventWaiters.get(method) ?? [];
      const timer = setTimeout(() => {
        const current = (this.eventWaiters.get(method) ?? []).filter(
          (waiter) => waiter.resolve !== resolveWait,
        );
        this.eventWaiters.set(method, current);
        rejectWait(new Error(`Timed out waiting for ${method}.`));
      }, timeout);
      waiters.push({
        resolve: (params) => {
          clearTimeout(timer);
          resolveWait(params);
        },
        reject: rejectWait,
      });
      this.eventWaiters.set(method, waiters);
    });
  }

  async close() {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.close();
    }
  }
}
