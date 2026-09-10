import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('transcript directory link reopens Files beside the current Workflows tab', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'src', is_dir: true }];
  app.directoryEntries['/workspace/src'] = [{ name: 'main.mbt', is_dir: false }];
  app.sessionEvents[1].item.payload.content = '[Source directory](./src/)';
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'host.open_path'
    ? { opened: false, directory_target: { path: 'src' } }
    : replyFor(request);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByRole('button', { name: /^Workflows / }).click();
  await page.getByRole('button', { name: 'Hide workspace navigator' }).click();
  await page.getByRole('button', { name: 'Collapse right panel' }).click();
  await page.getByRole('button', { name: 'Source directory', exact: true }).click();
  await expect(page.getByRole('tab', { name: 'Files', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('.file-tree-pane').getByText('main.mbt', { exact: true })).toBeVisible();
  await expect(page.locator('.workflow-panel')).toBeVisible();
  await expect(page.locator('.editor-tab')).toHaveCount(1);
  await expect(page.locator('.editor-tab')).toHaveClass(/active/);
  expect(app.pageErrors).toEqual([]);
});

test('failed Search refresh replaces retained review content with a visible notice and retries', async ({ page }) => {
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
  await page.getByRole('button', { name: /View diff: src\/main\.mbt/ }).click();
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
  await page.getByRole('button', { name: 'Diff view' }).click();
  await expect(page.locator('#diff-editor-host')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('workspace navigation preserves tabs and each file owns its Content/Diff view', async ({ page }) => {
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
  const tabs = page.locator('.editor-tab');
  await expect(tabs).toHaveCount(0);
  const navigator = page.getByRole('tablist', { name: 'Explorer views' });
  const fileView = page.getByRole('group', { name: 'File view' });
  await page.getByRole('button', { name: /View diff: src\/main\.mbt/ }).click();
  await fileView.getByRole('button', { name: 'Content view' }).click();
  await page.getByRole('button', { name: 'Next changed file' }).click();
  await expect(fileView.getByRole('button', { name: 'Diff view' })).toHaveAttribute('aria-pressed', 'true');
  await tabs.filter({ hasText: 'main.mbt' }).click();
  await expect(fileView.getByRole('button', { name: 'Content view' })).toHaveAttribute('aria-pressed', 'true');
  await fileView.getByRole('button', { name: 'Diff view' }).click();
  for (const name of ['Files', 'Search', 'Changes']) {
    await navigator.getByRole('tab', { name: new RegExp(`^${name}`) }).click();
    await expect(tabs).toHaveCount(2);
    await expect(tabs.filter({ hasText: 'main.mbt' })).toHaveClass(/active/);
    await expect(fileView.getByRole('button', { name: 'Diff view' })).toHaveAttribute('aria-pressed', 'true');
  }
  // Search currently reveals ranges in Content; retaining the comparison
  // gives the same file an explicit return path to Diff.
  await navigator.getByRole('tab', { name: 'Search' }).click();
  await page.getByRole('textbox', { name: 'Search', exact: true }).fill('working');
  await page.getByTitle('Open src/main.mbt:2', { exact: true }).click();
  await expect(tabs).toHaveCount(2);
  await expect(fileView.getByRole('button', { name: 'Content view' })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#viewer-host')).toContainText('working tree');
  await fileView.getByRole('button', { name: 'Diff view' }).click();
  await expect(page.locator('#diff-editor-host')).toBeVisible();

  const header = await page.locator('.workspace-panel-header').boundingBox();
  const bar = await page.locator('.editor-tabsbar').boundingBox();
  const tree = await page.locator('.file-tree-pane').boundingBox();
  expect(Math.abs(header.y + header.height - bar.y)).toBeLessThan(1);
  expect(Math.abs(tree.y - bar.y)).toBeLessThan(1);
  expect(Math.abs(header.x + header.width - tree.x - tree.width)).toBeLessThan(1);
  await page.getByRole('button', { name: 'Hide workspace navigator' }).click();
  await expect(navigator).toBeHidden();
  await expect(fileView).toBeVisible();
  await page.getByRole('button', { name: 'Collapse right panel' }).click();
  await expect(page.locator('.editor')).toBeHidden();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Show workspace navigator' })).toBeVisible();
  await expect(tabs).toHaveCount(2);
  await page.getByRole('button', { name: 'Show workspace navigator' }).click();
  await expect(page.getByTitle('Open src/main.mbt:2', { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

for (const layout of ['right-sidebar', 'bottom-panel', 'narrow']) {
  test(`empty navigator and resource views remain reachable in ${layout}`, async ({ page }) => {
    if (layout === 'narrow') await page.setViewportSize({ width: 390, height: 850 });
    await page.addInitScript(layout => localStorage.setItem('openseek.tree_layout', layout), layout);
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await app.goto();
    if (layout === 'narrow') await page.getByRole('button', { name: 'Show sidebar', exact: true }).click();
    await app.openSession();
    await app.openReview();
    await expect(page.locator('.editor-tab')).toHaveCount(0);
    await page.getByRole('button', { name: /View diff: src\/main\.mbt/ }).click();
    await expect(page.getByRole('group', { name: 'File view' })).toBeVisible();
    if (layout === 'narrow') {
      await page.getByRole('button', { name: 'Show workspace navigator' }).click();
    }
    await expect(page.getByRole('tab', { name: /^Changes/ })).toBeVisible();
    await page.getByRole('button', { name: 'Hide workspace navigator' }).click();
    await expect(page.getByRole('group', { name: 'File view' })).toBeVisible();
    const viewer = await page.locator('.viewer-stack').boundingBox();
    expect(viewer.height).toBeGreaterThan(100);
    expect(viewer.width).toBeGreaterThan(200);
    await page.getByTitle('New tab', { exact: true }).click();
    await page.getByRole('button', { name: /^Workflows / }).click();
    await expect(page.locator('.workflow-panel')).toBeVisible();
    await page.getByRole('button', { name: 'Show workspace navigator' }).click();
    await expect(page.getByRole('tab', { name: /^Changes/ })).toBeVisible();
    if (layout === 'narrow') {
      await expect(page.locator('.workflow-panel')).toBeHidden();
      await page.getByRole('button', { name: 'Hide workspace navigator' }).click();
    }
    await expect(page.locator('.workflow-panel')).toBeVisible();
    await expect(page.locator('.editor-tab')).toHaveCount(2);
    expect(app.pageErrors).toEqual([]);
  });
}

test('comparison filters support native checkbox pointer and keyboard input', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByRole('button', { name: /View diff: src\/main\.mbt/ }).click();
  const comments = page.getByRole('checkbox', { name: 'Ignore comments' });
  await expect(comments).toBeDisabled();
  await expect(comments).not.toBeChecked();
  await page.getByRole('button', { name: 'Token diff', exact: true }).click();
  await expect(comments).toBeChecked();
  await comments.click();
  await expect(comments).not.toBeChecked();
  await comments.focus();
  await page.keyboard.press('Space');
  await expect(comments).toBeChecked();
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await expect(comments).toBeDisabled();
  await expect(comments).not.toBeChecked();
  await page.getByRole('button', { name: 'Tree diff', exact: true }).click();
  await expect(comments).toBeChecked();
  expect(app.pageErrors).toEqual([]);
});
