import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const mode of ['Line', 'Token', 'Tree']) {
  test(`${mode} continuous navigation crosses files in both directions and wraps`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const baseline = ['fn first() -> Int { 1 }', ...Array.from({ length: 8 }, (_, i) => `fn same_${i}() -> Int { ${i} }`), 'fn last() -> Int { 2 }', ''].join('\n\n');
    for (const path of ['src/main.mbt', 'src/lib.mbt']) {
      app.gitFilesByRevision[app.gitBaseline][path] = baseline;
      app.workingFiles[path] = baseline.replace('first() -> Int { 1 }', 'first() -> Int { 10 }').replace('last() -> Int { 2 }', 'last() -> Int { 20 }');
    }
    app.rpcDelays.set('git.original_file', 150);
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    const changes = page.locator('#review-changes-body');
    const main = changes.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ });
    const lib = changes.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ });
    await main.click();
    await page.getByRole('button', { name: `${mode} diff`, exact: true }).click();
    const navigation = page.getByRole('group', { name: 'Diff change navigation' });
    const position = navigation.locator('.review-hunk-position');
    await expect(navigation).toHaveCount(1);
    await expect(page.locator('.file-tree-pane').getByRole('group', { name: 'Changed file navigation' })).toHaveCount(1);
    await expect(position).toHaveText('Change 1 of 2');
    // Backward entry into an uncached file must survive its asynchronous read
    // and land on the last change, not the normal first-change initialization.
    await navigation.getByRole('button', { name: 'Previous change', exact: true }).click();
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 2 of 2');
    await expect(navigation.locator('.review-nav-position')).toHaveText('File 2 of 2');
    await page.keyboard.press('Shift+F7');
    await expect(position).toHaveText('Change 1 of 2');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await page.keyboard.press('Shift+F7');
    await expect(main).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 2 of 2');
    await page.keyboard.press('F7');
    await expect(lib).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 2');
    await navigation.getByRole('button', { name: 'Next change', exact: true }).click();
    await expect(position).toHaveText('Change 2 of 2');
    await page.keyboard.press('F7');
    await expect(main).toHaveAttribute('aria-current', 'page');
    await expect(position).toHaveText('Change 1 of 2');
    expect(app.pageErrors).toEqual([]);
  });
}

for (const mode of ['Line', 'Tree']) {
  test(`${mode} empty comparisons can still navigate to the next file`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.workingFiles['src/main.mbt'] = app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'];
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    const changes = page.locator('#review-changes-body');
    await changes.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
    await page.getByRole('button', { name: `${mode} diff`, exact: true }).click();
    await page.getByRole('button', { name: 'Next change', exact: true }).click();
    await expect(changes.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ })).toHaveAttribute('aria-current', 'page');
    await expect(page.locator('.review-hunk-position')).toHaveText('Change 1 of 1');
    expect(app.pageErrors).toEqual([]);
  });
}
