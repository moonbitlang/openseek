import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const entry of ['deep link', 'host base']) {
  test(`packaged assets stay under /assets/ across navigation and reload: ${entry}`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture assets' } } },
      { sequence: 2, item: { kind: 'assistant', payload: { content: '```mermaid\nflowchart LR\nAsset --> Loaded\n```' } } },
    ];
    await app.install();
    if (entry === 'host base') {
      // Proton prepends its own root base before running application scripts;
      // root-absolute resource paths do not depend on it.
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
    await expect(page.locator('base')).toHaveCount(entry === 'deep link' ? 0 : 1);
    if (entry === 'deep link') {
      await page.getByRole('dialog', { name: 'Settings', exact: true })
        .getByRole('button', { name: 'Dismiss', exact: true }).click();
    }
    await app.openSession();
    await expect(page.locator('.chat-mermaid svg')).toContainText('Loaded');
    await page.reload();
    await expect(page.locator('.chat-mermaid svg')).toContainText('Loaded');
    expect(assets.some(asset => asset.url.endsWith('/assets/frontend.js'))).toBe(true);
    expect(assets.some(asset => asset.url.endsWith('/assets/mermaid/mermaid.esm.min.mjs'))).toBe(true);
    for (const asset of assets) {
      expect(new URL(asset.url).pathname).toMatch(/^\/assets\//);
      expect(asset.status).toBe(200);
    }
    expect(app.pageErrors).toEqual([]);
  });
}
