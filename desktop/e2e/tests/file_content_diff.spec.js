import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('one file tab retains its identity across File, diff modes, and repeated opens', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  const tabs = page.locator('.editor-tab');
  const main = tabs.filter({ hasText: 'main.mbt' });
  await expect(tabs).toHaveCount(1);
  const originalTab = await main.elementHandle();

  await app.openReview();
  await page.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  const view = page.getByRole('toolbar', { name: 'Review mode' });
  await expect(view.getByRole('button')).toHaveText(['File', 'Line', 'Token', 'Tree']);
  await expect(tabs).toHaveCount(1);
  await expect(view.getByRole('button', { name: 'Token diff' })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.semantic-review[data-mode="token"]')).toBeVisible();
  const baselineReads = app.requests.filter(request => request.method === 'git.original_file').length;

  for (const name of ['File view', 'Line diff', 'File view', 'Tree diff', 'File view', 'Token diff', 'File view']) {
    await view.getByRole('button', { name }).click();
    await expect(view.getByRole('button', { name })).toHaveAttribute('aria-pressed', 'true');
    await expect(tabs).toHaveCount(1);
    expect(await originalTab.evaluate(node => node.isConnected)).toBe(true);
  }
  expect(app.requests.filter(request => request.method === 'git.original_file')).toHaveLength(baselineReads);

  // Opening another review must not replace the first file's chosen surface.
  await page.getByRole('button', { name: 'Show file tree', exact: true }).click();
  await page.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ }).click();
  await expect(tabs).toHaveCount(2);
  await expect(view.getByRole('button', { name: 'Token diff' })).toHaveAttribute('aria-pressed', 'true');
  await main.click();
  await expect(view.getByRole('button', { name: 'File view' })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText(/fn\s+main/);

  await view.getByRole('button', { name: 'Token diff' }).click();
  await app.openQuickOpen();
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  await expect(tabs).toHaveCount(2);
  await expect(view.getByRole('button', { name: 'File view' })).toHaveAttribute('aria-pressed', 'true');
  await view.getByRole('button', { name: 'Token diff' }).click();
  await expect(page.locator('.semantic-review[data-mode="token"]')).toBeVisible();
  expect(await originalTab.evaluate(node => node.isConnected)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});
