import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const document = value => `# Diff fixture\n\nThe fn keyword and "literal" value ${value} are documentation.\n\n\`\`\`mbt\nfn answer() -> Int { ${value} }\n\`\`\`\n`;

function markdownFixture(page, path) {
  const app = new DesktopBrowserHarness(page);
  app.gitChanges = [{ path, index_status: ' ', worktree_status: 'M', kind: 'modified' }];
  app.workingFiles[path] = document(43);
  app.gitFilesByRevision[app.gitBaseline][path] = document(41);
  app.gitFilesByRevision[app.gitMerge][path] = document(41);
  app.gitFilesByRevision[app.gitHead][path] = document(42);
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'git.commit_changes'
    ? { commit: app.gitHead, parent: app.gitMerge, changes: [{ path, status: 'modified', kind: 'file' }] }
    : reply(request);
  return app;
}

async function expectMarkdownSource(diff, value) {
  await expect(diff).toBeVisible();
  await expect(diff).toContainText('# Diff fixture');
  await expect(diff).toContainText(`value ${value} are documentation.`);
  await expect(diff).toContainText('```mbt');
  // Inspect rendered token colors on both sides, not the model's language ID.
  // Diff insertion/deletion backgrounds remain independent of syntax colors.
  const tokens = diff.locator('.view-lines span[class*="mtk"]');
  await expect(tokens.first()).toBeVisible();
  await expect.poll(() => tokens.evaluateAll(nodes =>
    [...new Set(nodes.filter(node => node.textContent.trim()).map(node => getComputedStyle(node).color))].length,
  )).toBe(1);
}

for (const path of ['README.mbt.md', 'README.md', 'GUIDE.MBT.MD']) {
  test(`${path} review keeps Markdown literal and restores rich File view`, async ({ page }) => {
    const app = markdownFixture(page, path);
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    await page.getByRole('treeitem', { name: `View diff: ${path}` }).click();
    const diff = page.locator('#diff-editor-host');
    await expectMarkdownSource(diff, 43);
    await page.getByRole('button', { name: 'File view', exact: true }).click();
    const markdown = page.locator('#markdown-viewer-host');
    await expect(markdown.getByRole('heading', { name: 'Diff fixture' })).toBeVisible();
    await expect(markdown).toContainText('fn answer()');
    await expect(diff).toBeHidden();
    await page.getByRole('button', { name: 'Line diff', exact: true }).click();
    await expectMarkdownSource(diff, 43);
    expect(app.pageErrors).toEqual([]);
  });

  test(`${path} Git history keeps Markdown literal on both sides`, async ({ page }) => {
    const app = markdownFixture(page, path);
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    const history = page.getByRole('tree', { name: 'Git commit history' });
    await history.getByRole('treeitem', { name: /Cover Desktop Git flows/ }).click();
    await history.getByRole('treeitem', { name: new RegExp(path.replaceAll('.', '\\.')) }).click();
    await expectMarkdownSource(page.locator('#diff-editor-host'), 42);
    await expect(page.locator('.editor-tab.active')).toContainText(`${path} (cccccccc)`);
    expect(app.pageErrors).toEqual([]);
  });
}

test('MoonBit source diffs retain syntax highlighting', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  const tokens = page.locator('#diff-editor-host .view-lines span[class*="mtk"]');
  await expect(tokens.first()).toBeVisible();
  await expect.poll(() => tokens.evaluateAll(nodes =>
    [...new Set(nodes.filter(node => node.textContent.trim()).map(node => getComputedStyle(node).color))].length,
  )).toBeGreaterThan(1);
  expect(app.pageErrors).toEqual([]);
});
