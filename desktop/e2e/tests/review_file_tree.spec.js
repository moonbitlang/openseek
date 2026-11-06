import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Review tree supports keyboard folding and independent tri-state review checkboxes', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  const tree = page.locator('#review-file-tree');
  const src = tree.locator('[role="treeitem"][data-path="src"]');
  const main = tree.locator('[role="treeitem"][data-path="src/main.mbt"]');
  const lib = tree.locator('[role="treeitem"][data-path="src/lib.mbt"]');
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
  await page.locator('#file-tree-toggle').click();
  await expect(page.locator('.editor-tab.active')).toContainText('main.mbt');
  await expect(page.locator('#review-file-toggle')).toBeVisible();
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
  const input = page.locator('#review-path-filter-input');
  await input.fill('main');
  await expect(main).toBeVisible();
  await expect(lib).toBeHidden();
  await srcCheck.click();
  // The checkbox returns focus to its row after rendering. Let that land
  // before focusing the filter, or it takes focus from the filter mid-press.
  await expect(src).toBeFocused();
  await input.press('Escape');
  await expect(lib).toBeVisible();
  await expect(srcCheck).toHaveAttribute('aria-checked', 'mixed');
  await expect(lib.getByRole('checkbox')).not.toBeChecked();
  // A live Git refresh can insert rows before the focused DOM node. Focus
  // must continue to identify the same Git row after positional DOM patching.
  await main.focus();
  app.gitChanges.unshift({ path: 'new/file.mbt', kind: 'added', index_status: 'A', worktree_status: ' ' });
  await expect(tree.locator('[role="treeitem"][data-path="new"]')).toBeVisible({ timeout: 10_000 });
  await expect(main).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});
