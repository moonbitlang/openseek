import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('new-tab popup launches Jobs and yields to the panel action', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  const trigger = page.locator('#dock-new-tab');
  const menu = page.locator('#dock-new-tab-menu');
  await trigger.click();
  await expect(menu).toBeVisible();
  await menu.locator('[data-dock-action="jobs"]').click();
  await expect(page.locator('.jobs-panel')).toBeVisible();
  await expect(menu).toHaveCount(0);
  await trigger.click();
  // The click that dismisses the menu must still activate the panel control.
  await page.locator('#panel-expand').click();
  await expect(menu).toHaveCount(0);
  await expect(page.locator('#panel-expand[aria-pressed="true"]')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
