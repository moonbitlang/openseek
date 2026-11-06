import { test, expect } from './support/test.js';
import { writeFile, symlink } from 'node:fs/promises';
import { join } from 'node:path';
import { StaticPreviewHarness } from './support/static_preview_harness.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

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
    expect((await page.request.get(url)).status()).toBe(404);
    expect(errors).toEqual([]);
  } finally { await server.close(); }
});

test('real HTTP preview refuses symlink escapes, encoded traversal, foreign Host and writes', async ({ page }) => {
  test.setTimeout(120_000);
  const server = await new StaticPreviewHarness().start();
  try {
    const { url } = await server.open();
    const base = url.slice(0, -'pages/index.html'.length);
    for (const path of ['%2e%2e/%2e%2e/etc/passwd', '%2fetc/passwd', '..%5csecret.txt', 'missing.json']) {
      expect([403, 404]).toContain((await page.request.get(base + path)).status());
    }
    if (process.platform !== 'win32') {
      await symlink('/etc/passwd', join(server.root, 'assets/escape.txt'));
      expect((await page.request.get(base + 'assets/escape.txt')).status()).toBe(403);
    }
    expect((await page.request.get(url, { headers: { Host: 'rebound.example' } })).status()).toBe(403);
    expect((await page.request.post(url, { data: 'write' })).status()).toBe(405);
    expect((await page.request.get(new URL('/v1/devices', url).href)).status()).toBe(404);
  } finally { await server.close(); }
});

async function installLocalWindow(page, app, server) {
  await app.install();
  await page.exposeFunction('previewHostRequest', async request => {
    app.requests.push(request);
    if (request.method === 'app.system_appearance') return { dark: false };
    if (request.method === 'browser.preview') return server.open(request.params.id);
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
    window.__MoonBit__ = { getTitlebarArea: async () => null, app: events, events,
      openseek: new Proxy({}, { get: (_, method) => async params => {
        if (method === 'host.connect') for (const callback of listeners.get('openseek.agent.connected') || []) callback({ payload: { protocol: 5 } });
        return window.previewHostRequest({ method, params });
      } }),
    };
  });
  await page.goto('/index.html');
  await app.openSession();
}

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
        await expect(page.locator('#browser-address-input')).toHaveValue(/^http:\/\/127\.0\.0\.1:\d+\/[^/]+\/pages\/index.html$/);
        const request = app.requests.find(request => request.method === 'browser.preview');
        expect(request.params).toMatchObject({ root: '/workspace', path: '/workspace/index.HTML', session: 'session-1' });
        const url = await page.locator('#browser-address-input').inputValue();
        await page.locator('.editor-tab.active .tab-close').click();
        await expect.poll(async () => (await page.request.get(url)).status()).toBe(404);
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
      }
      expect(app.pageErrors).toEqual([]);
    } finally { await server.close(); }
  });
}
