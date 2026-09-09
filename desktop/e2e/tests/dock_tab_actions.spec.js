import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openTabs(page, names) {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = names.map(name => `src/${name}.mbt`);
  for (const path of app.searchFiles) app.workingFiles[path] = 'fn main {}\n';
  await app.install();
  await app.goto();
  await app.openSession();
  for (const name of names) {
    await app.openQuickOpen();
    await page.locator('#quick-open-input').fill(name);
    await page.getByRole('option', { name: new RegExp(`${name}\\.mbt`) }).click();
  }
  return app;
}

for (const [action, remaining, active] of [
  ['Close Others', ['bravo.mbt'], 'bravo.mbt'],
  ['Close to the Left', ['bravo.mbt', 'charlie.mbt', 'Review Changes'], 'Review Changes'],
  ['Close to the Right', ['alpha.mbt', 'bravo.mbt'], 'bravo.mbt'],
]) {
  test(`${action} is relative to the context tab, across file and picker tabs`, async ({ page }) => {
    const app = await openTabs(page, ['alpha', 'bravo', 'charlie']);
    await app.openReview();
    await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
    const tabs = page.locator('.editor-tab');
    await tabs.filter({ hasText: 'bravo.mbt' }).click({ button: 'right' });
    await expect(page.locator('.editor-tab.active')).toContainText('Review Changes');
    const menu = page.getByRole('menu', { name: 'Tab actions' });
    await expect(menu).toBeVisible();
    await menu.getByRole('menuitem', { name: action, exact: true }).click();
    await expect(menu).toBeHidden();
    await expect(tabs.locator('.tab-name')).toHaveText(remaining);
    await expect(page.locator('.editor-tab.active')).toContainText(active);
    await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
    await expect(page.getByRole('button', { name: 'Restore panel', exact: true })).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

test('tab menu disables empty ranges and supports keyboard dismissal and Close All', async ({ page }) => {
  const app = await openTabs(page, ['alpha', 'bravo']);
  const tabs = page.locator('.editor-tab');
  const menu = page.getByRole('menu', { name: 'Tab actions' });
  await tabs.first().click({ button: 'right' });
  await expect(menu.getByRole('menuitem', { name: 'Close to the Left' })).toBeDisabled();
  await expect(menu.getByRole('menuitem', { name: 'Close to the Right' })).toBeEnabled();
  await page.keyboard.press('Escape');
  await tabs.last().focus();
  await page.keyboard.press('Shift+F10');
  await expect(menu).toBeVisible();
  await expect(menu.getByRole('menuitem', { name: 'Close to the Right' })).toBeDisabled();
  await page.keyboard.press('Escape');
  await expect(tabs.last()).toBeFocused();
  await page.keyboard.press('Shift+F10');
  await menu.getByRole('menuitem', { name: 'Close Others', exact: true }).click();
  await expect(tabs).toHaveCount(1);
  await tabs.first().click({ button: 'right' });
  for (const name of ['Close Others', 'Close to the Left', 'Close to the Right']) {
    await expect(menu.getByRole('menuitem', { name, exact: true })).toBeDisabled();
  }
  await menu.getByRole('menuitem', { name: 'Close All', exact: true }).click();
  await expect(tabs).toHaveCount(0);
  await expect(page.locator('.dock-launcher')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('tab and sidebar menus replace each other without changing selection', async ({ page }) => {
  const app = await openTabs(page, ['alpha', 'bravo']);
  const first = page.locator('.editor-tab').first();
  const workspace = page.locator('.workspace-row').first();
  await first.click({ button: 'right' });
  await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeVisible();
  await workspace.click({ button: 'right', position: { x: 24, y: 16 } });
  await expect(page.getByRole('menu', { name: 'Workspace actions' })).toBeVisible();
  await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeHidden();
  await first.click({ button: 'right' });
  await expect(page.getByRole('menu', { name: 'Workspace actions' })).toBeHidden();
  await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeVisible();
  await expect(page.locator('.editor-tab.active')).toContainText('bravo.mbt');
  await page.getByRole('menuitem', { name: 'Close', exact: true }).click();
  await expect(page.locator('.editor-tab .tab-name')).toHaveText(['bravo.mbt']);
  await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});
