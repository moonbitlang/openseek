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

// Ordinary and expanded panels are covered by dock_tab_actions.spec.js.
// Keep the short viewport here to exercise vertical overflow.
test('new-tab popup fits a short narrow viewport', async ({ page }) => {
  const viewport = { width: 420, height: 320 };
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  // Open the fixture before narrowing; the phone layout hides navigation.
  await page.setViewportSize(viewport);
  await page.locator('#dock-new-tab').click();
  const menu = page.locator('#dock-new-tab-menu');
  await expect(menu).toBeVisible();
  const bounds = await menu.boundingBox();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.y).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(viewport.height);
  expect(await menu.evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
  await menu.locator('[data-dock-action="jobs"]').click();
  await expect(page.locator('.jobs-panel')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
