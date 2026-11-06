import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('project host yields its right-aligned slot to pointer and keyboard actions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  const row = app.projectRow('/workspace');
  const host = row.locator('.workspace-host');
  const disclosure = app.projectControl('/workspace', 'disclosure');
  const menu = row.locator('.workspace-menu-button');
  const newChat = app.projectControl('/workspace', 'new-conversation');
  await expect(row.locator('[data-slot="context-menu-trigger"] .workspace-disclosure')).toBeVisible();
  await expect(host).toHaveText('Test Mac');
  await expect(menu).toBeHidden();
  await expect(newChat).toBeHidden();
  const idle = await row.boundingBox();
  const hostBounds = await host.boundingBox();
  expect(idle.x + idle.width - hostBounds.x - hostBounds.width).toBeCloseTo(8, 0);
  const titleBounds = await disclosure.boundingBox();

  await row.hover();
  await expect(host).toBeHidden();
  await expect(menu).toBeVisible();
  await expect(newChat).toBeVisible();
  expect(await disclosure.boundingBox()).toEqual(titleBounds);
  expect(await row.boundingBox()).toEqual(idle);
  await disclosure.click();
  await page.mouse.move(1400, 850);
  await expect(host).toBeVisible();
  await expect(menu).toBeHidden();

  // A keyboard user can reach both controls; moving into the floating menu
  // must not bring host text back underneath the still-open trigger.
  await disclosure.focus();
  await page.keyboard.press('Tab');
  await expect(menu).toBeFocused();
  await expect(host).toBeHidden();
  await page.keyboard.press('Tab');
  await expect(newChat).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await page.keyboard.press('Enter');
  await expect(page.getByRole('menu').locator('[data-action="settings"]')).toBeVisible();
  await expect(host).toBeHidden();
  await expect(menu).toBeVisible();
  await page.getByRole('menu').locator('[data-action="settings"]').click();
  await expect(page.locator('#workspace-settings-dialog')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
