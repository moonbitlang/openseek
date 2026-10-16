import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const entry of ['deep link', 'host base']) {
  test(`packaged assets retain their base across navigation and reload: ${entry}`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture assets' } } },
      { sequence: 2, item: { kind: 'assistant', payload: { content: '```mermaid\nflowchart LR\nAsset --> Loaded\n```' } } },
    ];
    await app.install();
    if (entry === 'host base') {
      // Proton prepends its own root base before running application scripts.
      await page.route('**/index.html*', async route => {
        const response = await route.fetch();
        const origin = new URL(route.request().url()).origin;
        await route.fulfill({ response, body: (await response.text()).replace(
          '<head>', `<head><base href="${origin}/">`,
        ) });
      });
    }
    const assets = [];
    page.on('response', response => {
      if (['script', 'stylesheet', 'font'].includes(response.request().resourceType())) {
        assets.push({ url: response.url(), status: response.status() });
      }
    });
    await page.goto(entry === 'deep link' ? '/device/device-a/settings' : '/index.html?device=device-a');
    const assetBase = await page.locator('meta[name="seekmoon-asset-base"]').getAttribute('content');
    expect(assetBase).toMatch(/^\/assets\/v[^/]+\/$/);
    await expect.poll(() => page.evaluate(() => new URL(document.baseURI).pathname)).toBe(assetBase);
    await expect(page.locator('base')).toHaveCount(1);
    await app.openSession();
    await expect(page.locator('.chat-mermaid svg')).toContainText('Loaded');
    await page.reload();
    await expect(page.locator('.chat-mermaid svg')).toContainText('Loaded');
    expect(await page.evaluate(() => new URL(document.baseURI).pathname)).toBe(assetBase);
    expect(assets.some(asset => asset.url.endsWith('/frontend.js'))).toBe(true);
    expect(assets.some(asset => asset.url.endsWith('/mermaid.esm.min.mjs'))).toBe(true);
    for (const asset of assets) {
      expect(new URL(asset.url).pathname).toMatch(new RegExp(`^${assetBase.replaceAll('.', '\\.')}`));
      expect(asset.status).toBe(200);
    }
    expect(app.pageErrors).toEqual([]);
  });
}
