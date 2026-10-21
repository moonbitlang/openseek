import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('project host yields its right-aligned slot to pointer and keyboard actions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  const row = page.locator('.workspace-row').filter({
    has: page.getByRole('button', { name: 'workspace', exact: true }),
  });
  const host = row.locator('.workspace-host');
  const disclosure = row.getByRole('button', { name: 'workspace', exact: true });
  const menu = row.locator('.workspace-menu-button');
  const newChat = row.getByTitle('New conversation in this project');
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
  await expect(page.getByRole('menuitem', { name: 'Workspace settings' })).toBeVisible();
  await expect(host).toBeHidden();
  await expect(menu).toBeVisible();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  await expect(page.getByRole('dialog', { name: 'Workspace settings' })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
