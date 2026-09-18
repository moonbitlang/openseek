import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('reopening a deleted review keeps Diff without reading the missing file', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.gitChanges = [{ path: 'src/main.mbt', index_status: ' ', worktree_status: 'D', kind: 'deleted' }];
  app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = 'fn main { println("deleted baseline") }\n';
  delete app.workingFiles['src/main.mbt'];
  app.rpcErrors.set('fs.read_file', 'file not found');
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  const line = page.getByRole('button', { name: 'Line diff', exact: true });
  await line.click();
  const diff = page.locator('#diff-editor-host');
  await expect(diff).toBeVisible();
  await expect(diff).toContainText('deleted baseline');

  await app.openQuickOpen();
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  await expect(line).toHaveAttribute('aria-pressed', 'true');
  await expect(diff).toBeVisible();
  await expect(diff).toContainText('deleted baseline');
  await expect(page.locator('.editor-tab')).toHaveCount(1);
  expect(app.requests.filter(request => request.method === 'fs.read_file')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

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
  const view = page.getByRole('group', { name: 'File view' });
  const algorithm = page.getByRole('toolbar', { name: 'Comparison algorithm' });
  await expect(view.getByRole('button')).toHaveText(['Content', 'Diff']);
  await expect(tabs).toHaveCount(1);
  await expect(algorithm.getByRole('button', { name: 'Token diff' })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.semantic-review[data-mode="token"]')).toBeVisible();
  const baselineReads = app.requests.filter(request => request.method === 'git.original_file').length;

  for (const name of ['Content view', 'Line diff', 'Content view', 'Tree diff', 'Content view', 'Token diff', 'Content view']) {
    if (name !== 'Content view') {
      await view.getByRole('button', { name: 'Diff view' }).click();
    }
    const control = name === 'Content view' ? view : algorithm;
    await control.getByRole('button', { name }).click();
    await expect(control.getByRole('button', { name })).toHaveAttribute('aria-pressed', 'true');
    await expect(tabs).toHaveCount(1);
    expect(await originalTab.evaluate(node => node.isConnected)).toBe(true);
  }
  expect(app.requests.filter(request => request.method === 'git.original_file')).toHaveLength(baselineReads);

  // Opening another review must not replace the first file's chosen surface.
  await page.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ }).click();
  await expect(tabs).toHaveCount(2);
  await expect(algorithm.getByRole('button', { name: 'Token diff' })).toHaveAttribute('aria-pressed', 'true');
  await main.click();
  await expect(view.getByRole('button', { name: 'Content view' })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText(/fn\s+main/);

  await view.getByRole('button', { name: 'Diff view' }).click();
  await algorithm.getByRole('button', { name: 'Token diff' }).click();
  await app.openQuickOpen();
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  await expect(tabs).toHaveCount(2);
  await expect(view.getByRole('button', { name: 'Content view' })).toHaveAttribute('aria-pressed', 'true');
  await view.getByRole('button', { name: 'Diff view' }).click();
  await algorithm.getByRole('button', { name: 'Token diff' }).click();
  await expect(page.locator('.semantic-review[data-mode="token"]')).toBeVisible();
  expect(await originalTab.evaluate(node => node.isConnected)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('Search read failures retain the same file comparison and can retry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.textSearchMatches = [{
    path: 'src/main.mbt', line_number: 2,
    preview: '  println("working tree")', preview_start_column: 1,
    ranges: [{ start_column: 12, end_column: 19 }],
  }];
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await expect(page.locator('#diff-editor-host')).toContainText('working tree');
  await page.getByRole('tab', { name: 'Search', exact: true }).click();
  await page.getByRole('textbox', { name: 'Search', exact: true }).fill('working');
  app.rpcErrors.set('fs.read_file', 'permission denied');
  const result = page.getByTitle('Open src/main.mbt:2', { exact: true });
  await result.click();
  await expect(page.getByText('Working unavailable · baseline', { exact: true })).toBeVisible();
  await expect(page.locator('#viewer-host')).not.toContainText('working tree');
  await expect(page.locator('.editor-tab')).toHaveCount(1);

  app.rpcErrors.delete('fs.read_file');
  await result.click();
  await expect(page.getByText('Working unavailable · baseline', { exact: true })).toBeHidden();
  await expect(page.locator('#viewer-host')).toContainText('working tree');
  await expect(page.getByRole('button', { name: 'Content view' })).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('button', { name: 'Diff view', exact: true }).click();
  await expect(page.locator('#diff-editor-host')).toBeVisible();
  await expect(page.locator('.editor-tab')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});
