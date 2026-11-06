import { test, expect } from './support/test.js';
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
  await page.locator('[role="treeitem"][data-path="src/main.mbt"]').click();
  const line = page.locator('[data-diff-mode="line"]');
  await line.click();
  const diff = page.locator('#diff-editor-host');
  await expect(diff).toBeVisible();
  await expect(diff).toContainText('deleted baseline');

  await app.openQuickOpen();
  await page.locator('#quick-open-list [data-path="src/main.mbt"]').click();
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
  await page.locator('#quick-open-list [data-path="src/main.mbt"]').click();
  const tabs = page.locator('.editor-tab');
  const main = page.locator('.editor-tab[data-path="/workspace/src/main.mbt"]');
  await expect(tabs).toHaveCount(1);
  const originalTab = await main.elementHandle();

  await app.openReview();
  await page.locator('[role="treeitem"][data-path="src/main.mbt"]').click();
  const view = page.locator('#review-mode-toolbar');
  await expect(view.getByRole('button')).toHaveText(['File', 'Line', 'Token', 'Tree']);
  await expect(tabs).toHaveCount(1);
  await expect(view.locator('[data-diff-mode="token"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.semantic-review[data-mode="token"]')).toBeVisible();
  const baselineReads = app.requests.filter(request => request.method === 'git.original_file').length;

  for (const mode of ['file', 'line', 'file', 'tree', 'file', 'token', 'file']) {
    const button = view.locator(mode === 'file' ? '[data-review-mode="file"]' : `[data-diff-mode="${mode}"]`);
    await button.click();
    await expect(button).toHaveAttribute('aria-pressed', 'true');
    await expect(tabs).toHaveCount(1);
    expect(await originalTab.evaluate(node => node.isConnected)).toBe(true);
  }
  expect(app.requests.filter(request => request.method === 'git.original_file')).toHaveLength(baselineReads);

  // Opening another review must not replace the first file's chosen surface.
  await page.locator('#file-tree-toggle').click();
  await page.locator('[role="treeitem"][data-path="src/lib.mbt"]').click();
  await expect(tabs).toHaveCount(2);
  await expect(view.locator('[data-diff-mode="token"]')).toHaveAttribute('aria-pressed', 'true');
  await main.click();
  await expect(view.locator('[data-review-mode="file"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText(/fn\s+main/);

  await view.locator('[data-diff-mode="token"]').click();
  await app.openQuickOpen();
  await page.locator('#quick-open-list [data-path="src/main.mbt"]').click();
  await expect(tabs).toHaveCount(2);
  await expect(view.locator('[data-review-mode="file"]')).toHaveAttribute('aria-pressed', 'true');
  await view.locator('[data-diff-mode="token"]').click();
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
  await page.locator('[role="treeitem"][data-path="src/main.mbt"]').click();
  await page.locator('[data-diff-mode="line"]').click();
  await expect(page.locator('#diff-editor-host')).toContainText('working tree');
  await page.locator('#file-tree-toggle').click();
  await page.locator('#explorer-search-tab').click();
  await page.locator('#workspace-search-input').fill('working');
  app.rpcErrors.set('fs.read_file', 'permission denied');
  const result = page.locator('.search-preview-line[data-path="src/main.mbt"][data-line="2"]');
  await result.click();
  await expect(page.locator('.review-badge[role="status"]')).toBeVisible();
  await expect(page.locator('#viewer-host')).not.toContainText('working tree');
  await expect(page.locator('.editor-tab')).toHaveCount(1);

  app.rpcErrors.delete('fs.read_file');
  await result.click();
  await expect(page.locator('.review-badge[role="status"]')).toBeHidden();
  await expect(page.locator('#viewer-host')).toContainText('working tree');
  await expect(page.locator('[data-review-mode="file"]')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('[data-diff-mode="line"]').click();
  await expect(page.locator('#diff-editor-host')).toBeVisible();
  await expect(page.locator('.editor-tab')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});
