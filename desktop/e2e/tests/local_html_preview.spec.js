import { test, expect } from './support/test.js';
import { writeFile, symlink } from 'node:fs/promises';
import { createConnection } from 'node:net';
import { join } from 'node:path';
import { StaticPreviewHarness } from './support/static_preview_harness.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

function probePreviewPort(url) {
  return new Promise(resolve => {
    const socket = createConnection({ host: '127.0.0.1', port: Number(new URL(url).port) });
    socket.setTimeout(1000, () => { socket.destroy(); resolve('timeout'); });
    socket.once('connect', () => { socket.destroy(); resolve('listening'); });
    socket.once('error', error => resolve(error.code));
  });
}

test('real HTTP preview resolves relative resources, dynamic imports, fetch and refreshed files', async ({ page }, testInfo) => {
  test.setTimeout(120_000);
  const server = await new StaticPreviewHarness().start();
  try {
    const { url } = await server.open();
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    await page.goto(url);
    const title = page.getByRole('heading', { name: 'Local static preview' });
    await expect(title).toHaveCSS('color', 'rgb(30, 64, 175)');
    await expect(page.getByRole('img', { name: 'Preview image' })).toHaveJSProperty('naturalWidth', 96);
    const fontResponse = page.waitForResponse(response => response.url().endsWith('/assets/font.ttf'));
    expect(await page.evaluate(async () => (await document.fonts.load('16px PreviewFont')).length)).toBe(1);
    expect((await fontResponse).headers()['content-type']).toBe('font/ttf');
    await expect.poll(() => page.evaluate(() => typeof window.__MoonBit__)).toBe('undefined');
    const moduleResponse = page.waitForResponse(response => response.url().endsWith('/assets/dynamic.mjs'));
    const dataResponse = page.waitForResponse(response => response.url().endsWith('/assets/data.json'));
    await page.getByRole('button', { name: 'Run JavaScript' }).click();
    expect((await moduleResponse).headers()['content-type']).toContain('javascript');
    expect((await dataResponse).headers()['content-type']).toBe('application/json');
    await expect(page.locator('#result')).toHaveText('Dynamic import + fetch: loaded');
    const screenshot = testInfo.outputPath('local-static-preview.png');
    await page.screenshot({ path: screenshot });
    await testInfo.attach('Real loopback HTTP preview after JavaScript, dynamic import and JSON fetch', { path: screenshot, contentType: 'image/png' });
    await writeFile(join(server.root, 'assets/data.json'), '{"value":"updated"}');
    await writeFile(join(server.root, 'assets/style.css'), 'h1 { color: rgb(21, 128, 61) }');
    await page.reload();
    await expect(title).toHaveCSS('color', 'rgb(21, 128, 61)');
    await page.getByRole('button', { name: 'Run JavaScript' }).click();
    await expect(page.locator('#result')).toHaveText('Dynamic import + fetch: updated');
    await server.request({ close: 1 });
    await expect.poll(() => probePreviewPort(url)).toBe('ECONNREFUSED');
    expect(errors).toEqual([]);
  } finally { await server.close(); }
});

test('real HTTP preview refuses symlink escapes, encoded traversal and writes', async ({ page }) => {
  test.setTimeout(120_000);
  const server = await new StaticPreviewHarness().start();
  try {
    const { url } = await server.open();
    const base = url.slice(0, -'pages/index.html'.length);
    for (const path of ['%2e%2e/%2e%2e/etc/passwd', '%2fetc/passwd', '..%5csecret.txt', 'missing.json']) {
      expect([400, 404]).toContain((await page.request.get(base + path)).status());
    }
    if (process.platform !== 'win32') {
      await symlink('/etc/passwd', join(server.root, 'assets/escape.txt'));
      expect((await page.request.get(base + 'assets/escape.txt')).status()).toBe(404);
    }
    expect((await page.request.post(url, { data: 'write' })).status()).toBe(405);
  } finally { await server.close(); }
});

test('preview tabs have independent origins and close with their tab or app', async ({ page }) => {
  const server = await new StaticPreviewHarness().start();
  try {
    const [{ url: first }, { url: second }] = await Promise.all([server.open(1), server.open(2)]);
    expect(new URL(first).origin).not.toBe(new URL(second).origin);
    await page.goto(first);
    await page.evaluate(() => localStorage.setItem('preview', 'first'));
    await page.goto(second);
    expect(await page.evaluate(() => localStorage.getItem('preview'))).toBeNull();
    await server.request({ close: 1 });
    await expect.poll(() => probePreviewPort(first)).toBe('ECONNREFUSED');
    expect((await page.request.get(second)).status()).toBe(200);
    await server.close();
    await expect.poll(() => probePreviewPort(second)).toBe('ECONNREFUSED');
  } finally { await server.close(); }
});

async function installLocalWindow(page, app, server) {
  await app.install();
  await page.exposeFunction('previewHostRequest', async request => {
    app.requests.push(request);
    if (request.method === 'app.system_appearance') return { dark: false };
    if (request.method === 'browser.preview') {
      const { id } = request.params;
      const { url } = await server.open(id);
      const redirected = `${url}?redirected=1`;
      await page.evaluate(payload => window.desktopEvent('openseek.browser.event', payload), {
        kind: 'navigated', id, url: redirected,
      });
      // Deliver the native navigation before the open command completes.
      await expect(page.locator('#browser-address-input')).toHaveValue(redirected);
      return {};
    }
    if (request.method === 'browser.close') return server.request({ close: request.params.id }).then(() => ({}));
    return app.replyFor(request);
  });
  await page.addInitScript(() => {
    const listeners = new Map();
    const events = { on(name, callback) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name).add(callback);
      return () => listeners.get(name).delete(callback);
    } };
    window.desktopEvent = (name, payload) => {
      for (const callback of listeners.get(name) || []) callback({ payload });
    };
    window.__MoonBit__ = { getTitlebarArea: async () => null, app: events, events,
      openseek: new Proxy({}, { get: (_, method) => async params => {
        if (method === 'host.connect') window.desktopEvent('openseek.agent.connected', { protocol: 5 });
        return window.previewHostRequest({ method, params });
      } }),
    };
  });
  await page.goto('/index.html');
  await app.openSession();
}

test('a failed HTTP preview preserves its startup error without reloading the file placeholder', async ({ page }) => {
  await page.clock.install();
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'index.html', is_dir: false }];
  app.workingFiles['index.html'] = '<h1>Preview fixture</h1>';
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'fs.stat_files') return { stats: request.params.paths.map(path => ({
      path, signature: { kind: 'present', sig: 'unchanged' },
    })) };
    if (request.method === 'browser.reload') throw new Error('op ext:openseek/browser.reload failed');
    return replyFor(request);
  };
  await installLocalWindow(page, app, {
    open: async () => { throw new Error('Local HTML preview runtime is unavailable'); },
  });
  await app.openReview();
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await page.getByRole('treeitem', { name: 'index.html', exact: true }).click({ button: 'right' });
  await page.getByRole('menuitem', { name: 'Preview', exact: true }).click();
  await expect(page.locator('.browser-failure')).toContainText('Local HTML preview runtime is unavailable');
  await page.clock.runFor(5000);
  expect(app.requests.filter(request => request.method === 'browser.reload')).toHaveLength(0);
  await expect(page.locator('.browser-failure')).toContainText('Local HTML preview runtime is unavailable');
});

for (const local of [true, false]) {
  test(`${local ? 'Local' : 'remote'} HTML file menu and editor expose the correct preview capability`, async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    const server = await new StaticPreviewHarness().start();
    const app = new DesktopBrowserHarness(page);
    app.directoryEntries['/workspace'] = [
      { name: 'index.HTML', is_dir: false }, { name: 'notes.txt', is_dir: false },
    ];
    app.workingFiles['index.HTML'] = '<h1>Preview fixture</h1>';
    app.workingFiles['notes.txt'] = 'Not HTML';
    try {
      if (local) await installLocalWindow(page, app, server);
      else { await app.install(); await app.goto(); await app.openSession(); }
      await app.openReview();
      await page.getByRole('tab', { name: 'Files', exact: true }).click();
      const file = page.getByRole('treeitem', { name: 'index.HTML', exact: true });
      await file.click({ button: 'right' });
      const preview = page.getByRole('menuitem', { name: 'Preview', exact: true });
      if (local) {
        await expect(preview).toBeVisible();
        const path = testInfo.outputPath('local-html-preview-menu.png');
        await page.screenshot({ path });
        await testInfo.attach('Local HTML file context menu', { path, contentType: 'image/png' });
        await preview.click();
        // The event's theme update queues behind the open command, so this
        // assertion observes the address after its reply has been processed.
        await expect.poll(() => app.requests.some(request => request.method === 'browser.set_theme')).toBe(true);
        await expect(page.locator('#browser-address-input')).toHaveValue(/^http:\/\/127\.0\.0\.1:\d+\/pages\/index\.html\?redirected=1$/);
        const request = app.requests.find(request => request.method === 'browser.preview');
        expect(request.params).toMatchObject({ root: '/workspace', path: '/workspace/index.HTML', session: 'session-1' });
        const url = await page.locator('#browser-address-input').inputValue();
        await page.locator('.editor-tab.active .tab-close').click();
        await expect.poll(() => probePreviewPort(url)).toBe('ECONNREFUSED');
        await app.openReview();
        await page.getByRole('tab', { name: 'Files', exact: true }).click();
      } else {
        await expect(preview).toHaveCount(0);
        await page.keyboard.press('Escape');
      }
      await file.click();
      const toolbar = page.locator('.viewer-breadcrumb');
      await expect(toolbar.getByRole('button', { name: 'Preview', exact: true })).toHaveCount(local ? 1 : 0);
      if (local) {
        const path = testInfo.outputPath('local-html-preview-toolbar.png');
        await page.screenshot({ path });
        await testInfo.attach('Local HTML editor Preview action', { path, contentType: 'image/png' });
        await toolbar.getByRole('button', { name: 'Preview', exact: true }).click();
        await expect.poll(() => app.requests.filter(request => request.method === 'browser.preview').length).toBe(2);
        await expect(page.locator('#browser-address-input')).toHaveValue(/\?redirected=1$/);
      }
      expect(app.pageErrors).toEqual([]);
    } finally { await server.close(); }
  });
}
