import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('new-tab popup and empty launcher share Codicons without changing actions', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  const menu = page.locator('.dock-menu');
  await expect(menu).toBeVisible();
  const labels = await menu.locator('.dock-launcher-name').allTextContents();
  // Browse is available only when the current renderer supports browser tabs.
  expect(labels.filter(label => label !== 'Browse')).toEqual([
    'Search', 'Files', 'Review', 'Workflows', 'Jobs',
  ]);
  const paths = [];
  for (const label of labels) {
    const row = menu.getByRole('button', { name: new RegExp('^' + label + ' ') });
    const icon = row.locator('.icon');
    await expect(icon).toHaveAttribute('aria-hidden', 'true');
    const svg = icon.locator('svg');
    await expect(svg).toHaveAttribute('fill', 'currentColor');
    await expect(svg).toHaveAttribute('viewBox', '0 0 16 16');
    await expect(svg.locator('path')).toHaveCount(1);
    const path = await svg.locator('path').getAttribute('d');
    expect(path.length).toBeGreaterThan(0);
    paths.push(path);
  }
  expect(new Set(paths).size).toBe(labels.length);
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    await menu.screenshot({ path: testInfo.outputPath('launcher-' + colorScheme + '.png') });
  }
  await menu.getByRole('button', { name: /^Files / }).click();
  await expect(menu).toBeHidden();
  await expect(page.getByRole('tab', { name: 'Files', exact: true })).toHaveAttribute('aria-selected', 'true');
  await page.getByTitle('New tab', { exact: true }).click();
  await menu.getByRole('button', { name: /^Workflows / }).click();
  await expect(page.locator('.editor-tab.active')).toContainText('Workflows');
  await page.getByTitle('New tab', { exact: true }).click();
  await menu.getByRole('button', { name: /^Jobs / }).click();
  await expect(page.locator('.jobs-panel')).toBeVisible();
  await page.getByRole('button', { name: 'Close all tabs', exact: true }).click();
  const launcher = page.locator('.dock-launcher');
  await expect(launcher).toBeVisible();
  expect(await launcher.locator('.dock-launcher-name').allTextContents()).toEqual(labels);
  expect(await launcher.locator('.icon path').evaluateAll(elements => elements.map(element => element.getAttribute('d'))))
    .toEqual(paths);
  expect(app.pageErrors).toEqual([]);
});
