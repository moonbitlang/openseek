import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('switching editors reveals the active file inside collapsed directories', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [
    { name: 'src', is_dir: true },
    { name: 'README.md', is_dir: false },
  ];
  app.directoryEntries['/workspace/src'] = [{ name: 'main.mbt', is_dir: false }];
  app.workingFiles['src/main.mbt'] = 'fn main {}\n';
  app.workingFiles['README.md'] = '# Workspace\n';
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  const tree = page.getByRole('tree', { name: 'Workspace files' });
  const src = tree.getByRole('treeitem', { name: 'src', exact: true });
  const main = tree.getByRole('treeitem', { name: 'main.mbt', exact: true });
  await src.click();
  await main.click();
  await page.getByTitle('Show file tree', { exact: true }).click();
  await tree.getByRole('treeitem', { name: 'README.md', exact: true }).click();
  await src.click();
  await expect(main).toHaveCount(0);
  await page.locator('.editor-tabs .editor-tab', { hasText: 'main.mbt' }).click();
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  await expect(main).toHaveAttribute('aria-selected', 'true');
  await expect(tree.locator(':focus')).toHaveCount(0);
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  await expect(main).toBeVisible();
  await expect(main).toHaveAttribute('aria-selected', 'true');
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  expect(app.pageErrors).toEqual([]);
});

test('Quick Open centers the revealed file and centers again when Files becomes visible', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'src', is_dir: true }];
  app.directoryEntries['/workspace/src'] = [{ name: 'nested', is_dir: true }];
  app.directoryEntries['/workspace/src/nested'] = Array.from({ length: 80 }, (_, index) => ({
    name: `file_${String(index).padStart(2, '0')}.mbt`, is_dir: false,
  }));
  app.searchFiles = ['src/nested/file_40.mbt'];
  app.workingFiles['src/nested/file_40.mbt'] = 'fn main {}\n';
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  const files = page.getByRole('tab', { name: 'Files', exact: true });
  await files.click();
  const tree = page.getByRole('tree', { name: 'Workspace files' });
  await app.openQuickOpen();
  await page.getByRole('option', { name: /file_40\.mbt/ }).click();
  await page.getByTitle('Show file tree', { exact: true }).click();
  const row = tree.getByRole('treeitem', { name: 'file_40.mbt', exact: true });
  const scrollport = page.locator('.workspace-file-list');
  await expect(row).toHaveAttribute('aria-selected', 'true');
  await expect(row).toBeInViewport();
  await expect.poll(async () => {
    const item = await row.boundingBox();
    const viewport = await scrollport.boundingBox();
    return Math.abs(item.y + item.height / 2 - viewport.y - viewport.height / 2);
  }).toBeLessThanOrEqual(1);
  await expect(tree.locator(':focus')).toHaveCount(0);
  expect(await scrollport.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  for (const path of ['/workspace/src', '/workspace/src/nested']) {
    expect(app.requests.filter(request => request.method === 'fs.read_directory' && request.params?.path === path)).toHaveLength(1);
  }
  // Ordinary focus updates must respect a manual scroll away from the editor.
  await scrollport.evaluate(element => { element.scrollTop = 0; });
  await files.focus();
  await expect(row).not.toBeInViewport();
  await expect(scrollport).toHaveJSProperty('scrollTop', 0);
  await page.getByRole('tab', { name: 'Search', exact: true }).click();
  await files.click();
  await expect(row).toBeInViewport();
  await expect.poll(async () => {
    const item = await row.boundingBox();
    const viewport = await scrollport.boundingBox();
    return Math.abs(item.y + item.height / 2 - viewport.y - viewport.height / 2);
  }).toBeLessThanOrEqual(1);
  await expect(files).toBeFocused();
  // Folding the active file's ancestor is intentional until the next reveal.
  const src = tree.getByRole('treeitem', { name: 'src', exact: true });
  await src.click();
  await expect(row).toHaveCount(0);
  await files.focus();
  await expect(src).toHaveAttribute('aria-expanded', 'false');
  expect(app.pageErrors).toEqual([]);
});

test('a late directory reply cannot reveal an editor that is no longer active', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [
    { name: 'src', is_dir: true }, { name: 'README.md', is_dir: false },
  ];
  app.directoryEntries['/workspace/src'] = [{ name: 'main.mbt', is_dir: false }];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  const tree = page.getByRole('tree', { name: 'Workspace files' });
  const readme = tree.getByRole('treeitem', { name: 'README.md', exact: true });
  await expect(readme).toBeVisible();
  // Delay only the directory response, so the newer editor can win first.
  app.rpcDelays.set('fs.read_directory', 1000);
  await app.openQuickOpen();
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  await page.getByTitle('Show file tree', { exact: true }).click();
  await expect.poll(() => app.requests.some(request => request.method === 'fs.read_directory' && request.params?.path === '/workspace/src')).toBe(true);
  await readme.click();
  const main = tree.getByRole('treeitem', { name: 'main.mbt', exact: true });
  await expect(main).toBeVisible();
  await expect(readme).toHaveAttribute('aria-selected', 'true');
  await expect(readme).toHaveAttribute('tabindex', '0');
  await expect(main).toHaveAttribute('aria-selected', 'false');
  await expect(page.locator('.editor-tab.active')).toContainText('README.md');
  expect(app.pageErrors).toEqual([]);
});

test('a failed ancestor listing stops until the next explicit reveal', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'src', is_dir: true }];
  app.directoryEntries['/workspace/src'] = [{ name: 'main.mbt', is_dir: false }];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  const files = page.getByRole('tab', { name: 'Files', exact: true });
  await files.click();
  const tree = page.getByRole('tree', { name: 'Workspace files' });
  const src = tree.getByRole('treeitem', { name: 'src', exact: true });
  await expect(src).toBeVisible();
  app.rpcErrors.set('fs.read_directory', 'Directory unavailable');
  await app.openQuickOpen();
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  await page.getByTitle('Show file tree', { exact: true }).click();
  await expect(page.locator('.file-panel-error')).toContainText('Directory unavailable');
  // Tree focus dispatches unrelated updates; these must not retry the failure.
  await src.focus();
  await files.focus();
  await src.focus();
  expect(app.requests.filter(request => request.method === 'fs.read_directory' && request.params?.path === '/workspace/src')).toHaveLength(1);
  app.rpcErrors.delete('fs.read_directory');
  await page.getByRole('tab', { name: 'Search', exact: true }).click();
  await files.click();
  await expect(tree.getByRole('treeitem', { name: 'main.mbt', exact: true })).toHaveAttribute('aria-selected', 'true');
  expect(app.requests.filter(request => request.method === 'fs.read_directory' && request.params?.path === '/workspace/src')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('Files scrolls below the view tabs and keeps desktop row height on narrow screens', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = Array.from({ length: 80 }, (_, index) => ({
    name: `file_${String(index).padStart(2, '0')}_with_a_very_long_deployment_configuration_name_for_truncation.mbt`,
    is_dir: false,
  }));
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  const tabs = page.getByRole('tablist', { name: 'Explorer views' });
  await tabs.getByRole('tab', { name: 'Files', exact: true }).click();
  const tree = page.locator('.workspace-file-list');
  // The first row starts directly below the view tabs, without a second title.
  expect((await tree.locator('.tree-file').first().boundingBox()).y - (await tree.boundingBox()).y).toBe(4);
  const desktopRowHeight = (await tree.locator('.tree-file').first().boundingBox()).height;
  const tabsBefore = await tabs.boundingBox();
  await tree.locator('.tree-file').last().scrollIntoViewIfNeeded();
  expect(await tree.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  expect(await tabs.boundingBox()).toEqual(tabsBefore);
  await tabs.getByRole('tab', { name: 'Search', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Search', exact: true })).toBeVisible();
  await expect(tree).toHaveCount(0);
  await tabs.getByRole('tab', { name: 'Files', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 760 });
  await expect(tree).toBeVisible();
  await expect.poll(async () => (await tree.locator('.tree-file').first().boundingBox()).height).toBe(desktopRowHeight);
  expect(await tree.evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
  await expect.poll(() => tree.locator('.tree-name').first().evaluate(element => element.scrollWidth > element.clientWidth)).toBe(true);
  await page.locator('.file-tree-pane').screenshot({ path: testInfo.outputPath('files-narrow.png') });
  expect(app.pageErrors).toEqual([]);
});

test('file tree exposes hierarchy and one keyboard entry with directional navigation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [
    { name: 'src', is_dir: true },
    { name: 'README.md', is_dir: false },
  ];
  app.directoryEntries['/workspace/src'] = [
    { name: 'nested', is_dir: true },
    { name: 'main.mbt', is_dir: false },
  ];
  app.directoryEntries['/workspace/src/nested'] = [{ name: 'child.mbt', is_dir: false }];
  app.workingFiles['src/main.mbt'] = 'fn main {}\n';
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview();
  const files = page.getByRole('tab', { name: 'Files', exact: true });
  await files.click();
  const tree = page.getByRole('tree', { name: 'Workspace files' });
  const src = tree.getByRole('treeitem', { name: 'src', exact: true });
  const readme = tree.getByRole('treeitem', { name: 'README.md', exact: true });
  await expect(src).toBeVisible();
  await files.press('Tab');
  await expect(src).toBeFocused();
  await expect(src).toHaveAttribute('aria-level', '1');
  await expect(src).toHaveAttribute('aria-setsize', '2');
  await expect(src).toHaveAttribute('aria-expanded', 'false');
  await src.press('Control+Alt+ArrowRight');
  await expect(src).toHaveAttribute('aria-expanded', 'false');
  await src.press('ArrowRight');
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  await expect(src).toBeFocused();
  const nested = tree.getByRole('treeitem', { name: 'nested', exact: true });
  await expect(nested).toBeVisible();
  await src.press('ArrowRight');
  await expect(nested).toBeFocused();
  await expect(nested).toHaveAttribute('aria-level', '2');
  await nested.press('Enter');
  const child = tree.getByRole('treeitem', { name: 'child.mbt', exact: true });
  await expect(child).toBeVisible();
  await nested.press('ArrowRight');
  await expect(child).toBeFocused();
  await child.press('ArrowLeft');
  await expect(nested).toBeFocused();
  await nested.press('ArrowLeft');
  await expect(child).toHaveCount(0);
  await expect(nested).toBeFocused();
  await nested.press('ArrowDown');
  const main = tree.getByRole('treeitem', { name: 'main.mbt', exact: true });
  await expect(main).toBeFocused();
  await expect(main).toHaveAttribute('aria-selected', 'false');
  await main.press('Enter');
  await page.getByTitle('Show file tree', { exact: true }).click();
  await expect(main).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('.editor-tabs .editor-tab.active')).toContainText('main.mbt');
  await main.focus();
  await main.press('End');
  await expect(readme).toBeFocused();
  await readme.press('Home');
  await expect(src).toBeFocused();
  // Focus changes before Rabbita renders the new roving tab stop. Counting
  // one tab stop alone can still observe README's previous tabindex=0.
  await expect(src).toHaveAttribute('tabindex', '0');
  await expect(tree.locator('[role="treeitem"][tabindex="0"]')).toHaveCount(1);
  await src.press('Tab');
  await expect(tree.locator(':focus')).toHaveCount(0);
  await page.keyboard.press('Shift+Tab');
  await expect(src).toBeFocused();
  // A filesystem refresh preserves the focused path despite positional DOM reuse.
  await main.focus();
  await expect.poll(() => app.requests.filter(request => request.method === 'fs.watch').length).toBeGreaterThan(0);
  const notifyChange = (events) => {
    const watch = app.requests.filter(request => request.method === 'fs.watch').at(-1);
    app.notify('fs.changed', { root: '/workspace', generation: watch.params.generation, baseline: false, events });
  };
  app.directoryEntries['/workspace/src'] = [{ name: 'main.mbt', is_dir: false }];
  notifyChange([{ kind: 'remove', path: 'src/nested' }]);
  await expect(nested).toHaveCount(0);
  await expect(main).toBeFocused();
  app.directoryEntries['/workspace/src'] = [];
  notifyChange([{ kind: 'remove', path: 'src/main.mbt' }]);
  await expect(main).toHaveCount(0);
  await expect(src).toBeFocused();
  // An update must not pull focus back from controls outside the tree.
  await files.focus();
  app.directoryEntries['/workspace'] = [];
  notifyChange([{ kind: 'remove', path: 'src' }, { kind: 'remove', path: 'README.md' }]);
  await expect(src).toHaveCount(0);
  await expect(files).toBeFocused();
  await files.press('Tab');
  await expect(tree).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

for (const layout of ['right-sidebar', 'bottom-panel']) {
  test(`${layout} file tree distinguishes temporary opening from a pinned tree and releases narrow-screen space`, async ({ page }) => {
    await page.addInitScript(layout => localStorage.setItem('openseek.tree_layout', layout), layout);
    const app = new DesktopBrowserHarness(page);
    app.directoryEntries['/workspace'] = [
      { name: 'a.mbt', is_dir: false },
      { name: 'b.mbt', is_dir: false },
    ];
    app.workingFiles['a.mbt'] = 'fn main {}\n';
    app.workingFiles['b.mbt'] = 'fn main {}\n';
    await app.install();
    await app.goto();
    await app.openSession();
    const tree = page.getByRole('tree', { name: 'Workspace files' });
    for (const name of ['a.mbt', 'b.mbt']) {
      await app.openReview();
      await page.getByRole('tab', { name: 'Files', exact: true }).click();
      await expect(tree).toBeVisible();
      await tree.getByRole('treeitem', { name, exact: true }).click();
      await expect(page.locator('.editor-tab.active')).toContainText(name);
      await expect(tree).toBeHidden();
    }
    await page.getByTitle('Show file tree', { exact: true }).click();
    await tree.getByRole('treeitem', { name: 'a.mbt', exact: true }).click();
    await expect(tree).toBeVisible();
    await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
    await page.getByRole('button', { name: 'Show panel', exact: true }).click();
    await expect(tree).toBeVisible();
    await page.getByTitle('Hide file tree', { exact: true }).click();
    await expect(tree).toBeHidden();

    await page.setViewportSize({ width: 390, height: 760 });
    const expectFullViewer = async () => {
      await expect(tree).toBeHidden();
      await expect.poll(() => page.locator('.viewer-stack').evaluate(element => {
        const body = element.parentElement.getBoundingClientRect();
        const viewer = element.getBoundingClientRect();
        return Math.max(Math.abs(body.width - viewer.width), Math.abs(body.height - viewer.height));
      })).toBeLessThanOrEqual(1);
    };
    await expectFullViewer();
    await page.getByTitle('Show file tree', { exact: true }).click();
    await expect(tree).toBeVisible();
    await page.getByTitle('Hide file tree', { exact: true }).click();
    await expectFullViewer();
    await page.getByTitle('Show file tree', { exact: true }).click();
    await tree.getByRole('treeitem', { name: 'b.mbt', exact: true }).click();
    await expect(page.locator('.editor-tab.active')).toContainText('b.mbt');
    await expectFullViewer();
    expect(app.pageErrors).toEqual([]);
  });
}

for (const target of ['group_40', 'group_40/nested']) {
  test(`directory link ${target} focuses and reveals its destination after loading and on repeated clicks`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.directoryEntries['/workspace'] = Array.from({ length: 80 }, (_, index) => ({
      name: `group_${String(index).padStart(2, '0')}`, is_dir: true,
    }));
    app.directoryEntries['/workspace/group_40'] = [{ name: 'nested', is_dir: true }];
    app.directoryEntries['/workspace/group_40/nested'] = [{ name: 'child.mbt', is_dir: false }];
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture directory' } } },
      { sequence: 2, item: { kind: 'assistant', payload: {
        content: `[Target directory](./${target}/)`,
      } } },
    ];
    const replyFor = app.replyFor.bind(app);
    app.replyFor = request => request.method === 'host.open_path'
      ? { opened: false, directory_target: { path: target } }
      : replyFor(request);
    app.rpcDelays.set('fs.read_directory', 300);
    await app.install();
    await app.goto();
    await app.openSession();
    const link = page.locator('.transcript').getByRole('button', { name: 'Target directory' });
    const tree = page.getByRole('tree', { name: 'Workspace files' });
    const destination = tree.getByRole('treeitem', { name: target.split('/').at(-1), exact: true });
    const scrollport = page.locator('.workspace-file-list');
    await link.click();
    await expect(destination).toBeFocused();
    await expect(destination).toBeInViewport();
    await expect(destination).toHaveAttribute('aria-expanded', 'true');
    await expect(tree.getByRole('treeitem', { name: target.includes('/') ? 'child.mbt' : 'nested', exact: true })).toBeVisible();
    const reads = app.requests.filter(request => request.method === 'fs.read_directory').length;
    await scrollport.evaluate(element => { element.scrollTop = 0; });
    await expect(destination).not.toBeInViewport();
    await link.click();
    await expect(destination).toBeFocused();
    await expect(destination).toBeInViewport();
    expect(app.requests.filter(request => request.method === 'fs.read_directory')).toHaveLength(reads);
    expect(app.pageErrors).toEqual([]);
  });
}

test('a repeated directory link retries failed listings without rereading cached directories', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'src', is_dir: true }];
  app.directoryEntries['/workspace/src'] = [{ name: 'nested', is_dir: true }];
  app.directoryEntries['/workspace/src/nested'] = [{ name: 'child.mbt', is_dir: false }];
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture directory' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '[Target directory](./src/nested/)' } } },
  ];
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'host.open_path'
    ? { opened: false, directory_target: { path: 'src/nested' } }
    : replyFor(request);
  await app.install();
  await app.goto();
  await app.openSession();
  // Cache the root listing, then fail both the target and its ancestor.
  await app.openReview();
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  const tree = page.getByRole('tree', { name: 'Workspace files' });
  await expect(tree.getByRole('treeitem', { name: 'src', exact: true })).toBeVisible();
  app.rpcErrors.set('fs.read_directory', 'Directory unavailable');
  const link = page.locator('.transcript').getByRole('button', { name: 'Target directory' });
  const reads = path => app.requests.filter(request => request.method === 'fs.read_directory' && request.params?.path === path).length;
  await link.click();
  await expect(page.locator('.file-panel-error')).toContainText('Directory unavailable');
  await expect.poll(() => reads('/workspace/src/nested')).toBe(1);
  // Unrelated focus updates must not automatically retry.
  await tree.getByRole('treeitem', { name: 'src', exact: true }).focus();
  await page.getByRole('tab', { name: 'Files', exact: true }).focus();
  expect(reads('/workspace/src')).toBe(1);
  expect(reads('/workspace/src/nested')).toBe(1);
  const rootReads = reads('/workspace');
  app.rpcErrors.delete('fs.read_directory');
  await link.click();
  const destination = tree.getByRole('treeitem', { name: 'nested', exact: true });
  await expect(destination).toBeFocused();
  await expect(tree.getByRole('treeitem', { name: 'child.mbt', exact: true })).toBeVisible();
  await expect(page.locator('.file-panel-error')).toBeHidden();
  expect(reads('/workspace')).toBe(rootReads);
  expect(reads('/workspace/src')).toBe(2);
  expect(reads('/workspace/src/nested')).toBe(2);
  await link.click();
  await expect(destination).toBeFocused();
  expect(reads('/workspace/src')).toBe(2);
  expect(reads('/workspace/src/nested')).toBe(2);
  expect(app.pageErrors).toEqual([]);
});
