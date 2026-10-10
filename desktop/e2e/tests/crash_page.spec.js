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

// Formatting branches run in crash_page's JS unit test; keep the browser
// event wiring and literal-text rendering covered here.
test('unhandled rejection shows a crash page without interpreting HTML', async ({ page }) => {
  await page.evaluate(() => window.dispatchEvent(new PromiseRejectionEvent('unhandledrejection', {
    promise: Promise.resolve(), reason: 'rejected <tag>',
  })));
  await expect(page.getByRole('heading', { name: 'SeekMoon stopped unexpectedly' })).toBeVisible();
  const detail = page.locator('#frontend-crash-detail');
  await expect(detail).toHaveText('rejected <tag>');
  await expect(detail.locator('tag')).toHaveCount(0);
});

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
