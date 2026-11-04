import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('dialogs remain reachable in narrow and native titlebars', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  await expect(dialog).toBeVisible();
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 844 });
    await expect(dialog.getByRole('button', { name: 'Dismiss', exact: true })).toBeInViewport();
    expect(await dialog.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
    await page.screenshot({ path: testInfo.outputPath(`settings-${width}.png`) });
  }
  await dialog.getByRole('button', { name: 'Dismiss', exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 844 });
  await expect(page.locator('.sidebar-backdrop')).toHaveCount(0);
  await expect.poll(() => page.locator('.app').evaluate(node => node.getAnimations().length)).toBe(0);
  await page.evaluate(() => {
    document.documentElement.style.setProperty('--native-titlebar-left', '84px');
    document.documentElement.style.setProperty('--native-titlebar-height', '28px');
    document.querySelector('.app').style.setProperty('--sidebar-width', '220px');
  });
  const toggle = await page.locator('.sidebar-toggle').boundingBox();
  const mode = await page.locator('.sidebar-mode').boundingBox();
  expect(toggle.x).toBeGreaterThanOrEqual(84);
  expect(mode.x).toBeGreaterThanOrEqual(toggle.x + toggle.width);
  const sidebar = await page.locator('aside').boundingBox();
  expect(mode.x + mode.width).toBeLessThanOrEqual(sidebar.x + sidebar.width);
  await page.screenshot({ path: testInfo.outputPath('native-titlebar.png') });
  expect(app.pageErrors).toEqual([]);
});
