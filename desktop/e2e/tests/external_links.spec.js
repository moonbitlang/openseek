import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const [name, options] of [
  ['left click', {}],
  ['Ctrl/Cmd click', { modifiers: ['ControlOrMeta'] }],
  ['middle click', { button: 'middle' }],
]) {
  test(`browser transcript opens a new tab on ${name}`, async ({ page, context }) => {
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture link' } } },
      { sequence: 2, item: { kind: 'assistant', payload: {
        content: '[External docs](https://example.test/docs)',
      } } },
    ];
    await context.route('https://example.test/docs', route => route.fulfill({
      contentType: 'text/html', body: '<title>External docs</title>',
    }));
    await app.install();
    await app.goto();
    await app.openSession();
    const originalURL = page.url();
    const popupPromise = context.waitForEvent('page', { timeout: 5000 });
    await page.locator('.transcript').getByRole('link', { name: 'External docs' }).click(options);
    const popup = await popupPromise;
    await expect(popup).toHaveURL('https://example.test/docs');
    expect(page.url()).toBe(originalURL);
    expect(app.requests.filter(request =>
      request.method === 'shell.open_external' || request.method === 'browser.open')).toEqual([]);
    expect(app.pageErrors).toEqual([]);
    await popup.close();
  });
}
