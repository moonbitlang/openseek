import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test.beforeEach(async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
});

test('browser diagnostics do not replace the application', async ({ page }) => {
  const warnings = [];
  page.on('console', message => {
    if (message.type() === 'warning') warnings.push(message.text());
  });
  await page.evaluate(() => window.dispatchEvent(new ErrorEvent('error', {
    message: 'ResizeObserver loop completed with undelivered notifications.',
  })));
  await expect(page.locator('#frontend-crash')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Hide sidebar', exact: true })).toBeVisible();
  expect(warnings).toContain('ResizeObserver loop completed with undelivered notifications.');
});

test('the first exception wins, renders text safely, and can reload', async ({ page }) => {
  await page.evaluate(() => {
    const error = new Error('<img src=x onerror="window.injected=true">');
    error.stack = 'original stack: ' + error.message;
    window.dispatchEvent(new ErrorEvent('error', { error }));
    window.dispatchEvent(new ErrorEvent('error', { error: new Error('later error') }));
  });
  await expect(page).toHaveTitle('SeekMoon stopped unexpectedly');
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(page.locator('#frontend-crash-detail')).toHaveText(
    'original stack: <img src=x onerror="window.injected=true">',
  );
  await expect(page.locator('#frontend-crash img')).toHaveCount(0);
  expect(await page.evaluate(() => window.injected)).toBeUndefined();
  await page.getByRole('button', { name: 'Reload', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Hide sidebar', exact: true })).toBeVisible();
  await expect(page.locator('#frontend-crash')).toHaveCount(0);
});

for (const [kind, expected] of [
  ['string', 'rejected <tag>'],
  ['object', '{\n  "message": "rejected object"\n}'],
  ['circular', '[object Object]'],
  ['undefined', 'Unknown JavaScript error'],
  ['empty', 'Unknown JavaScript error'],
  ['error-without-stack', 'TypeError: missing stack'],
]) {
  test(`unhandled rejection formats ${kind}`, async ({ page }) => {
    await page.evaluate(kind => {
      let reason;
      if (kind === 'string') reason = 'rejected <tag>';
      if (kind === 'object') reason = { message: 'rejected object' };
      if (kind === 'circular') {
        reason = {};
        reason.self = reason;
      }
      if (kind === 'empty') reason = '';
      if (kind === 'error-without-stack') {
        reason = new TypeError('missing stack');
        reason.stack = '';
      }
      window.dispatchEvent(new PromiseRejectionEvent('unhandledrejection', {
        promise: Promise.resolve(), reason,
      }));
    }, kind);
    await expect(page.locator('#frontend-crash-detail')).toHaveText(expected);
  });
}

test('fallback presentation remains readable without the application stylesheet', async ({ page }) => {
  await page.evaluate(() => {
    document.querySelectorAll('link[rel="stylesheet"], style:not(#openseek-crash-page-style)')
      .forEach(element => element.remove());
    window.dispatchEvent(new ErrorEvent('error', { error: new Error('stylesheet unavailable') }));
  });
  await expect(page.getByRole('heading', { name: 'SeekMoon stopped unexpectedly' })).toBeVisible();
  await expect(page.locator('#frontend-crash')).toHaveCSS('display', 'grid');
  await expect(page.getByRole('button', { name: 'Reload', exact: true })).toHaveCSS('cursor', 'pointer');
});
