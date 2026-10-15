import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const prUrl = 'https://github.com/example/project/pull/42';
const branchUrl = 'https://github.com/example/project/tree/feature/example';
const otherUrl = 'https://github.com/other/project/tree/feature/example';
const pr = {
  number: 42, title: 'Example pull request', state: 'open', draft: false,
  url: prUrl, base: 'main', additions: 24, deletions: 3, changed_files: 2,
  checks: { passed: 3, failed: 0, pending: 1 }, head_url: branchUrl,
};

test('session PR associations merge the current checkout, survive lookup failures and remove safely', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  let bindings = [{ url: branchUrl }, { url: prUrl }, { url: otherUrl }];
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    switch (request.method) {
      case 'git.branch': return { branch: 'feature/example' };
      case 'git.pull_request': return { branch: 'feature/example', pull_request: pr };
      case 'session.pr_list': return { bindings: structuredClone(bindings) };
      case 'git.pr_detail': return request.params.url === prUrl
        ? { pull_request: pr }
        : {};
      case 'session.pr_remove':
        bindings = bindings.filter(item => item.url !== request.params.url);
        app.notify('session.pr_changed', { session: request.params.session });
        return { bindings: structuredClone(bindings) };
      default: return fallback(request);
    }
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const rows = page.locator('.session-pr-row');
  await expect(rows).toHaveCount(2);
  const current = rows.filter({ hasText: '#42' });
  await expect(current.locator('.session-pr-current')).toHaveText('Current');
  await expect(current.locator('.session-pr-diff')).toHaveText('+24−3');
  await expect(current.locator('.session-pr-checks')).toHaveClass(/pending/);
  await expect(page.locator('.composer-git')).toHaveCount(0);
  // Unrelated same-named branches remain distinct.
  await expect(rows.filter({ has: page.locator(`a[href="${otherUrl}"]`) })).toHaveCount(1);

  const task = page.locator('#task');
  await task.fill('Keep this draft');
  await task.focus();
  const failedUrl = 'https://github.com/example/project/pull/43';
  bindings = [...bindings, { url: failedUrl }];
  app.rpcErrors.set('git.pr_detail', 'GitHub is offline');
  app.notify('session.pr_changed', { session: 'session-1' });
  await expect(rows.filter({ hasText: '#43' }).locator('.session-pr-error')).toContainText('Status unavailable');
  await expect(task).toHaveValue('Keep this draft');
  await expect(task).toBeFocused();
  // Recover and capture the actual changed UI using demo data only.
  app.rpcErrors.delete('git.pr_detail');
  app.notify('session.pr_changed', { session: 'session-1' });
  await expect(rows).toHaveCount(3);
  await expect(current.locator('.session-pr-error')).toHaveCount(0);
  await page.locator('.session-pr-bindings').screenshot({ path: testInfo.outputPath('session-pr-bindings.png') });

  await current.locator('.session-pr-remove').click();
  await expect(rows).toHaveCount(3);
  await expect(current.locator('.session-pr-remove')).toHaveCount(0);
  await expect(current.locator('.session-pr-current')).toBeVisible();
  await expect(page.locator('.composer-git')).toHaveCount(0);
  expect(bindings).toEqual([{ url: otherUrl }, { url: failedUrl }]);
  expect(app.pageErrors).toEqual([]);
});

test('an older list response cannot undo a newer binding notification', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  let bindings = [{ url: prUrl }];
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.pr_list'
    ? { bindings: structuredClone(bindings) } : fallback(request);
  await app.install();
  await app.goto();
  await app.openSession();
  await expect(page.locator('.session-pr-row')).toHaveCount(1);
  app.rpcDelays.set('session.pr_list', 400);
  const before = app.requests.filter(r => r.method === 'session.pr_list').length;
  app.notify('session.pr_changed', { session: 'session-1' });
  await expect.poll(() => app.requests.filter(r => r.method === 'session.pr_list').length).toBeGreaterThan(before);
  bindings = [];
  app.rpcDelays.delete('session.pr_list');
  app.notify('session.pr_changed', { session: 'session-1' });
  await expect(page.locator('.session-pr-row')).toHaveCount(0);
  await page.waitForTimeout(500);
  await expect(page.locator('.session-pr-row')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});


test('unified rows follow the reference layout and retain the unbound checkout', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const samples = [
    { number: 1944, branch: 'claude/desktop-mcp-capabilities-a03b87', state: 'open', additions: 2474, deletions: 71 },
    { number: 1970, branch: 'claude/serve-mcp-snapshot', state: 'open', draft: true, additions: 981, deletions: 68 },
    { number: 1942, branch: 'claude/desktop-mcp-config', state: 'merged', additions: 50, deletions: 386 },
    { number: 1943, branch: 'claude/mcp-status-json', state: 'closed', additions: 261, deletions: 1 },
  ].map(item => ({ ...pr, ...item, url: `https://github.com/example/openseek/pull/${item.number}`, head_url: `https://github.com/example/openseek/tree/${item.branch}`, checks: { passed: 3, failed: 0, pending: 0 } }));
  let bindings = samples.map(item => ({ url: item.url }));
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'git.branch') return { branch: samples[0].branch };
    if (request.method === 'git.pull_request') return { branch: samples[0].branch, pull_request: samples[0] };
    if (request.method === 'session.pr_list') return { bindings: structuredClone(bindings) };
    if (request.method === 'git.pr_detail') {
      const item = samples.find(item => item.url === request.params.url);
      return item ? { pull_request: item } : {};
    }
    return fallback(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-Hans'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  const rows = page.locator('.session-pr-row');
  await expect(rows).toHaveCount(4);
  const merged = page.locator('.session-pr-row.merged');
  await expect(merged.locator('.session-pr-state')).toHaveText('已合并');
  await expect(merged.locator('.session-pr-diff, .session-pr-checks')).toHaveCount(0);
  await expect(rows.first().locator('.session-pr-diff')).toHaveText('+2,474−71');
  await expect(rows.first().locator('.session-pr-branch')).toHaveText(samples[0].branch);
  await expect(page.locator('.composer-git')).toHaveCount(0);
  const layout = await rows.first().evaluate(row => {
    const number = row.querySelector('.session-pr-number').getBoundingClientRect();
    const repo = row.querySelector('.session-pr-repo').getBoundingClientRect();
    const branch = row.querySelector('.session-pr-branch').getBoundingClientRect();
    const diff = row.querySelector('.session-pr-diff');
    return { ordered: number.right < repo.left && repo.right < branch.left, height: row.getBoundingClientRect().height, bordered: getComputedStyle(diff).borderTopWidth };
  });
  expect(layout.ordered).toBe(true);
  expect(layout.height).toBe(40);
  expect(layout.bordered).toBe('1px');
  await expect(merged).toHaveCSS('background-color', 'rgb(229, 221, 245)');
  await page.locator('.session-pr-bindings').screenshot({ path: testInfo.outputPath('session-pr-reference.png') });
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.locator('.session-pr-bindings').screenshot({ path: testInfo.outputPath('session-pr-dark.png') });
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await rows.first().locator('.session-pr-checks').click();
  await expect(page.locator('.session-pr-check-menu a')).toHaveAttribute('href', samples[0].url + '/checks');
  await rows.first().locator('.session-pr-checks').click();
  await page.locator('.session-pr-toggle').click();
  await expect(rows).toHaveCount(0);
  await page.locator('.session-pr-toggle').click();
  await expect(rows).toHaveCount(4);
  await page.setViewportSize({ width: 480, height: 800 });
  await expect(merged.locator('.session-pr-state')).toBeVisible();
  expect(await page.locator('.session-pr-bindings').evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true);
  bindings = [];
  app.notify('session.pr_changed', { session: 'session-1' });
  await expect(rows).toHaveCount(1);
  await expect(rows.locator('.session-pr-current')).toHaveText('当前');
  await expect(rows.locator('.session-pr-remove')).toHaveCount(0);
  await expect(page.locator('.composer-git')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});


test('the current unpublished branch and partial local diff appear without MCP or bindings', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'git.branch') return {
      branch: 'local/unpublished',
      diffstat: { added: 8, removed: 2, files: 1, partial: true },
    };
    if (request.method === 'git.pull_request') return {};
    return fallback(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const row = page.locator('.session-pr-row');
  await expect(row).toHaveCount(1);
  await expect(row.locator('.session-pr-branch')).toHaveText('local/unpublished');
  await expect(row.locator('.session-pr-current')).toHaveText('Current');
  await expect(row.locator('.session-pr-diff')).toHaveText('+8−2');
  await expect(row.locator('.session-pr-partial')).toHaveText('Partial count');
  await expect(row.locator('a, .session-pr-remove')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('binding a new PR upgrades the current published branch without another checkout probe', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  let bindings = [];
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'git.branch') return { branch: 'feature/example' };
    if (request.method === 'git.pull_request') return {
      branch: 'feature/example',
      compare_url: 'https://github.com/example/project/compare/feature/example?expand=1',
    };
    if (request.method === 'session.pr_list') return { bindings: structuredClone(bindings) };
    if (request.method === 'git.pr_detail') return request.params.url === prUrl ? { pull_request: pr } : {};
    if (request.method === 'session.pr_remove') {
      bindings = bindings.filter(item => item.url !== request.params.url);
      return { bindings: structuredClone(bindings) };
    }
    return fallback(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const row = page.locator('.session-pr-row');
  await expect(row.locator('a')).toHaveAttribute('href', branchUrl);
  const probes = app.requests.filter(r => r.method === 'git.pull_request').length;
  bindings = [{ url: prUrl }, { url: branchUrl }];
  app.notify('session.pr_changed', { session: 'session-1' });
  // Wait for metadata to merge the PR into the current row, not merely for
  // the initial branch-only row or the temporary explicit PR placeholder.
  await expect(row.filter({ hasText: '#42' }).locator('.session-pr-current')).toBeVisible();
  await expect(row).toHaveCount(1);
  expect(app.requests.filter(r => r.method === 'git.pull_request').length).toBe(probes);
  await row.locator('.session-pr-remove').click();
  await expect(row).toHaveCount(1);
  await expect(row.locator('a')).toHaveAttribute('href', branchUrl);
  await expect(row.locator('.session-pr-remove')).toHaveCount(0);
  expect(bindings).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});
