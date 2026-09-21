import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('new-tab popup shares select surface and supports keyboard dismissal', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  const select = page.getByRole('listbox', { name: 'Model' });
  await expect(select).toBeVisible();
  const selectStyle = await select.evaluate(element => {
    const style = getComputedStyle(element);
    return [style.padding, style.border, style.borderRadius, style.backgroundColor, style.boxShadow];
  });
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await app.openSession();
  await app.openReview();
  const trigger = page.getByTitle('New tab', { exact: true });
  const menu = page.getByRole('menu', { name: 'New tab' });
  await trigger.click();
  await expect(menu).toBeVisible();
  expect(await menu.evaluate(element => element.matches(':popover-open'))).toBe(true);
  expect(await menu.evaluate(element => {
    const style = getComputedStyle(element);
    return [style.padding, style.border, style.borderRadius, style.backgroundColor, style.boxShadow];
  })).toEqual(selectStyle);
  await expect(menu.getByRole('menuitem')).toHaveText([
    'SearchSearch text across the workspace',
    'FilesOpen a file from the workspace',
    'ReviewReview changed files and diffs',
    'GitHubBrowse pull requests and issues',
    'WorkflowsSubagents this conversation delegated to',
    'JobsFollow background commands and their logs',
  ]);
  await expect(menu.getByRole('menuitem', { name: 'Search', exact: true })).toBeFocused();
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    await menu.screenshot({ path: testInfo.outputPath('launcher-surface-' + colorScheme + '.png') });
  }
  await page.keyboard.press('End');
  await expect(menu.getByRole('menuitem', { name: 'Jobs', exact: true })).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(menu.getByRole('menuitem', { name: 'Search', exact: true })).toBeFocused();
  await page.keyboard.press('ArrowUp');
  await expect(menu.getByRole('menuitem', { name: 'Jobs', exact: true })).toBeFocused();
  await page.keyboard.press('Home');
  await page.keyboard.press('ArrowDown');
  await expect(menu.getByRole('menuitem', { name: 'Files', exact: true })).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(menu).toHaveCount(0);
  await expect(trigger).toBeFocused();
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');
  await trigger.click();
  await menu.getByRole('menuitem', { name: 'Jobs', exact: true }).click();
  await expect(page.locator('.jobs-panel')).toBeVisible();
  await expect(menu).toHaveCount(0);
  await trigger.click();
  await trigger.click();
  await expect(menu).toHaveCount(0);
  await trigger.click();
  // The click that dismisses the menu must still activate the panel control.
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  await expect(menu).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Restore panel', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

for (const viewport of [{ width: 900, height: 600 }, { width: 420, height: 320 }]) {
  test('new-tab popup fits viewport ' + viewport.width, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    // Open the fixture before narrowing; the phone layout hides navigation.
    await page.setViewportSize(viewport);
    await page.getByTitle('New tab', { exact: true }).click();
    const menu = page.getByRole('menu', { name: 'New tab' });
    await expect(menu).toBeVisible();
    const bounds = await menu.boundingBox();
    expect(bounds.x).toBeGreaterThanOrEqual(0);
    expect(bounds.y).toBeGreaterThanOrEqual(0);
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
    expect(bounds.y + bounds.height).toBeLessThanOrEqual(viewport.height);
    expect(await menu.evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    await menu.getByRole('menuitem', { name: 'Jobs', exact: true }).click();
    await expect(page.locator('.jobs-panel')).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}
