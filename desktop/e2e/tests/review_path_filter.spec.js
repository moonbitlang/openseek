import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Review filters changed paths live, clears, and preserves the open diff', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.gitChanges.push({ path: 'docs/guide.md', index_status: ' ', worktree_status: 'M', kind: 'modified' });
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  const changes = page.locator('#review-changes-body');
  const input = page.getByRole('textbox', { name: 'Filter changed files by path' });
  const rows = changes.locator('.change-row');
  await expect(rows).toHaveCount(3);
  await changes.locator('[data-path="src/main.mbt"]').click();
  const activeTab = page.locator('.editor-tab.active');
  await expect(activeTab).toContainText('main.mbt');
  await input.fill('SRC/');
  await expect(rows).toHaveCount(2);
  await expect(page.getByRole('status')).toHaveText('Showing 2 of 3 files');
  await expect(input).toBeFocused();
  await changes.locator('[data-path="src/main.mbt"]').press('ArrowDown');
  await expect(changes.locator('[data-path="src/lib.mbt"]')).toBeFocused();
  await expect(activeTab).toContainText('main.mbt');
  await page.keyboard.press('Enter');
  await expect(activeTab).toContainText('lib.mbt');
  await input.fill('docs/');
  await expect(rows).toHaveCount(1);
  await expect(rows).toContainText('guide.md');
  await expect(activeTab).toContainText('lib.mbt');
  await input.fill('does-not-exist');
  await expect(rows).toHaveCount(0);
  await expect(changes.getByText('No files match these filters.', { exact: true })).toBeVisible();
  await input.press('Escape');
  await expect(rows).toHaveCount(3);
  await expect(input).toBeFocused();
  await input.fill('.mbt');
  await expect(rows).toHaveCount(2);
  await page.getByRole('button', { name: 'Clear file filters' }).click();
  await expect(rows).toHaveCount(3);
  await expect(input).toHaveValue('');
  await expect(input).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

test('Review combines extension checkboxes with paths and clears both filters', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.gitChanges.push(
    { path: 'docs/guide.md', index_status: ' ', worktree_status: 'M', kind: 'modified' },
    { path: 'LICENSE', index_status: ' ', worktree_status: 'M', kind: 'modified' },
  );
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  const changes = page.locator('#review-changes-body');
  const input = page.getByRole('textbox', { name: 'Filter changed files by path' });
  const rows = changes.locator('.change-row');
  const trigger = page.getByRole('button', { name: 'Filter by file extension' });
  const menu = page.getByRole('dialog', { name: 'File types', exact: true });
  await expect(rows).toHaveCount(4);
  await expect(trigger).toHaveAccessibleName("Filter by file extension, all file types");
  await expect(trigger).toHaveAccessibleDescription("Filtering working tree");
  await expect(input).toHaveAccessibleDescription("Filtering working tree");
  await trigger.click();
  await expect(menu).toBeVisible();
  await expect(menu.getByRole('checkbox', { name: '.mbt', exact: true })).toBeChecked();
  await expect(menu.getByRole('checkbox', { name: '.md', exact: true })).toBeChecked();
  await expect(menu.getByRole('checkbox', { name: 'No extension', exact: true })).toBeChecked();
  await expect(menu.locator('.review-type-option').filter({ hasText: '.mbt' })).toContainText('2');
  await menu.getByRole('checkbox', { name: '.md', exact: true }).uncheck();
  await expect(menu).toBeVisible();
  await expect(rows).toHaveCount(3);
  await menu.getByRole('checkbox', { name: 'No extension', exact: true }).uncheck();
  await expect(rows).toHaveCount(2);
  await expect(trigger).toHaveAccessibleName('Filter by file extension, .mbt');
  await menu.getByRole('checkbox', { name: '.mbt', exact: true }).focus();
  await page.keyboard.press('Escape');
  await expect(menu).toBeHidden();
  await expect(trigger).toBeFocused();
  await input.fill('docs/');
  await expect(rows).toHaveCount(0);
  await trigger.click();
  await menu.getByRole('checkbox', { name: '.md', exact: true }).check();
  await expect(rows).toHaveCount(1);
  await expect(rows).toContainText('guide.md');
  await trigger.click();
  await expect(menu).toBeHidden();
  await trigger.click();
  await expect(menu).toBeVisible();
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    await page.screenshot({ path: testInfo.outputPath(`file-filters-${colorScheme}.png`) });
  }
  await page.setViewportSize({ width: 390, height: 760 });
  await expect(menu).toBeVisible();
  const bounds = await menu.boundingBox();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
  await input.click();
  await expect(menu).toBeHidden();
  await page.getByRole('button', { name: 'Clear file filters' }).click();
  await expect(rows).toHaveCount(4);
  await expect(input).toHaveValue('');
  await trigger.click();
  await menu.getByRole('checkbox', { name: '.mbt', exact: true }).uncheck();
  await menu.getByRole('checkbox', { name: '.md', exact: true }).uncheck();
  await menu.getByRole('checkbox', { name: 'No extension', exact: true }).uncheck();
  await expect(rows).toHaveCount(0);
  await expect(trigger).toContainText('none');
  expect(app.pageErrors).toEqual([]);
});

test('shared filters follow the expanded commit even with no working changes', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.gitChanges = [];
  const reply = app.replyFor.bind(app);
  app.replyFor = request => {
    const result = reply(request);
    if (request.method === 'git.commit_changes') {
      return { ...result, changes: request.params.commit === app.gitHead ? [
        { path: 'docs/new.md', original_path: 'old/readme.md', status: 'renamed', kind: 'file' },
        { path: 'LICENSE', status: 'added', kind: 'file' },
      ] : [{ path: 'config.json', status: 'modified', kind: 'file' }] };
    }
    return result;
  };
  app.rpcDelays.set('git.commit_changes', 250);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  const input = page.getByRole('textbox', { name: 'Filter changed files by path' });
  const types = page.getByRole('button', { name: 'Filter by file extension' });
  const menu = page.getByRole('dialog', { name: 'File types', exact: true });
  const scope = page.locator('.review-filter-scope');
  const history = page.getByRole('tree', { name: 'Git commit history' });
  const head = history.getByRole('treeitem', { name: /Cover Desktop Git flows/ });
  const merge = history.getByRole('treeitem', { name: /Merge fixture lanes/ });
  const historicalFiles = history.locator('.git-history-file');
  await expect(scope).toHaveText('Filtering working tree');
  await head.click();
  await expect(scope).toHaveText('Filtering commit cccccccc');
  await expect(input).toHaveAccessibleDescription('Filtering commit cccccccc');
  await expect(types).toHaveAccessibleDescription('Filtering commit cccccccc');
  await expect(types).toBeDisabled();
  await expect(historicalFiles).toHaveCount(2);
  await types.click();
  await expect(menu.getByRole('checkbox', { name: '.md', exact: true })).toBeChecked();
  await expect(menu.getByRole('checkbox', { name: '.mbt', exact: true })).toHaveCount(0);
  await menu.getByRole('checkbox', { name: 'No extension', exact: true }).uncheck();
  await expect(historicalFiles).toHaveCount(1);
  await input.fill('OLD/');
  await expect(historicalFiles).toContainText('docs/new.md');
  await expect(page.getByRole('status')).toHaveText('Showing 1 of 2 files');
  await historicalFiles.click();
  await expect(page.locator('.editor-tab.active')).toContainText('new.md (cccccccc)');
  await input.fill('no-match');
  await expect(historicalFiles).toHaveCount(0);
  await expect(history.getByText('No files match these filters.', { exact: true })).toBeVisible();
  await expect(page.locator('.editor-tab.active')).toContainText('new.md (cccccccc)');
  await page.getByRole('button', { name: 'Clear file filters' }).click();
  await merge.click();
  await expect(types).toBeDisabled();
  await expect(historicalFiles).toHaveCount(1);
  await types.click();
  await expect(menu.getByRole('checkbox', { name: '.json', exact: true })).toBeChecked();
  await expect(menu.getByRole('checkbox', { name: '.md', exact: true })).toHaveCount(0);
  await input.click();
  await merge.click();
  await expect(scope).toHaveText('Filtering working tree');
  await expect(historicalFiles).toHaveCount(0);
  // The toolbar stays accessible when the working Changes section is collapsed.
  await page.locator('#review-changes-section .review-section-header').click();
  await expect(input).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
