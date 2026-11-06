import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('shell panel control closes expanded panels and a file opened from quick open', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const toggle = page.locator('.right-panel-toggle');
  const original = await toggle.elementHandle();
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  const expand = page.locator('#panel-expand');
  await expand.click();
  await expect(page.locator('#panel-expand')).toBeVisible();
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await app.openQuickOpen();
  await page.locator('#quick-open-list [data-path="src/main.mbt"]').click();
  await expect(toggle).toBeVisible();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  expect(await original.evaluate(node => node.isConnected)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});
