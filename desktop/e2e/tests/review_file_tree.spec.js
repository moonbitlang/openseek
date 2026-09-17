import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Review tree supports keyboard folding and independent tri-state review checkboxes', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  const tree = page.getByRole('tree', { name: 'Changed files', exact: true });
  const src = tree.getByRole('treeitem', { name: 'src', exact: true });
  const main = tree.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ });
  const lib = tree.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ });
  const srcCheck = src.getByRole('checkbox');
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  await src.focus();
  await src.press('ArrowLeft');
  await expect(main).toBeHidden();
  await expect(src).toBeFocused();
  await src.press('ArrowRight');
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  await src.press('ArrowRight');
  await expect(main).toBeFocused();
  await main.press(' ');
  await expect(main.getByRole('checkbox')).toBeChecked();
  await expect(srcCheck).toHaveAttribute('aria-checked', 'mixed');
  expect(app.requests.some(request => request.method === 'git.original_file')).toBe(false);
  await expect(main).toHaveAttribute('aria-selected', 'false');
  await expect(main).toBeFocused();
  await main.press('Enter');
  await expect(page.locator('.editor-tab.active')).toContainText('main.mbt');
  await expect(page.getByRole('button', { name: 'Mark file unreviewed', exact: true })).toBeVisible();
  await lib.getByRole('checkbox').click();
  await expect(srcCheck).toBeChecked();
  await expect(page.locator('.editor-tab.active')).toContainText('main.mbt');
  await expect(lib).toBeFocused();
  await srcCheck.click();
  await expect(srcCheck).not.toBeChecked();
  await expect(main.getByRole('checkbox')).not.toBeChecked();
  await expect(lib.getByRole('checkbox')).not.toBeChecked();
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  await src.press('ArrowLeft');
  const input = page.getByRole('textbox', { name: 'Filter changed files by path' });
  await input.fill('main');
  await expect(main).toBeVisible();
  await expect(lib).toBeHidden();
  await srcCheck.click();
  await input.press('Escape');
  await expect(lib).toBeVisible();
  await expect(srcCheck).toHaveAttribute('aria-checked', 'mixed');
  await expect(lib.getByRole('checkbox')).not.toBeChecked();
  // A live Git refresh can insert rows before the focused DOM node. Focus
  // must continue to identify the same Git row after positional DOM patching.
  await main.focus();
  app.gitChanges.unshift({ path: 'new/file.mbt', kind: 'added', index_status: 'A', worktree_status: ' ' });
  await expect(tree.getByRole('treeitem', { name: 'new', exact: true })).toBeVisible({ timeout: 10_000 });
  await expect(main).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

test('Review tree keeps compact paths and readable filenames in a narrow pane', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.gitChanges = [
    { path: 'desktop/backend/internal/host/open_ops.mbt', kind: 'modified', index_status: ' ', worktree_status: 'M' },
    { path: 'desktop/backend/internal/host/protocol.mbt', kind: 'modified', index_status: ' ', worktree_status: 'M' },
    { path: 'desktop/e2e/tests/external_file_poll.spec.js', kind: 'added', index_status: 'A', worktree_status: ' ' },
    ...Array.from({ length: 30 }, (_, i) => ({ path: `desktop/frontend/fileeditor/file_${i}.mbt`, kind: 'modified', index_status: ' ', worktree_status: 'M' })),
    { path: 'README.md', kind: 'deleted', index_status: 'D', worktree_status: ' ' },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  const tree = page.getByRole('tree', { name: 'Changed files', exact: true });
  const host = tree.getByRole('treeitem', { name: 'desktop/backend/internal/host', exact: true });
  const open = tree.locator('[data-path="desktop/backend/internal/host/open_ops.mbt"]');
  await expect(host.locator('.change-path')).toHaveText('backend/internal/host');
  await expect(open.locator('.change-path')).toHaveText('open_ops.mbt');
  await expect(open).toHaveAttribute('aria-level', '3');
  expect((await open.boundingBox()).height).toBe(24);
  expect((await open.locator('.change-path').boundingBox()).width).toBeGreaterThan(100);
  expect(await tree.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true);
  await tree.locator('[data-path="README.md"]').scrollIntoViewIfNeeded();
  expect(await page.locator('#review-changes-body').evaluate(el => el.scrollTop)).toBeGreaterThan(0);
  await host.scrollIntoViewIfNeeded();
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    await page.locator('.file-tree-pane').screenshot({ path: testInfo.outputPath(`review-tree-${colorScheme}.png`) });
  }
  await host.click();
  await expect(open).toBeHidden();
  await expect(tree.locator('[data-path="desktop/e2e/tests/external_file_poll.spec.js"]')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
