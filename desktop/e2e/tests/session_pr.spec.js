import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const prUrl = 'https://github.com/example/project/pull/42';
const branchUrl = 'https://github.com/example/project/tree/feature/example';
const otherUrl = 'https://github.com/other/project/tree/feature/example';
const pr = {
  number: 42, title: 'Example pull request', state: 'open', draft: false,
  url: prUrl, base: 'main', additions: 24, deletions: 3, changed_files: 2,
  checks: { passed: 3, failed: 0, pending: 1 },
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
      case 'session.pr_detail': return request.params.url === prUrl
        ? { detail: { pull_request: pr, head_url: branchUrl } }
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
  await expect(current.locator('.session-pr-current')).toHaveCount(0);
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
  app.rpcErrors.set('session.pr_detail', 'GitHub is offline');
  app.notify('session.pr_changed', { session: 'session-1' });
  await expect(rows.filter({ hasText: '#43' }).locator('.session-pr-error')).toContainText('Status unavailable');
  await expect(task).toHaveValue('Keep this draft');
  await expect(task).toBeFocused();
  // Recover and capture the actual changed UI using demo data only.
  app.rpcErrors.delete('session.pr_detail');
  app.notify('session.pr_changed', { session: 'session-1' });
  await expect(rows).toHaveCount(3);
  await expect(current.locator('.session-pr-error')).toHaveCount(0);
  await page.locator('.session-pr-bindings').screenshot({ path: testInfo.outputPath('session-pr-bindings.png') });

  await current.locator('.session-pr-remove').click();
  await expect(rows).toHaveCount(2);
  await expect(rows.filter({ hasText: '#42' })).toHaveCount(0);
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


test('binding rows follow the reference layout and unbound checkout PRs stay hidden', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const samples = [
    { number: 1944, branch: 'claude/desktop-mcp-capabilities-a03b87', state: 'open', additions: 2474, deletions: 71 },
    { number: 1970, branch: 'claude/serve-mcp-snapshot', state: 'open', additions: 981, deletions: 68 },
    { number: 1942, branch: 'claude/desktop-mcp-config', state: 'merged', additions: 50, deletions: 386 },
    { number: 1943, branch: 'claude/mcp-status-json', state: 'closed', additions: 261, deletions: 1 },
  ].map(item => ({ ...pr, ...item, url: `https://github.com/example/openseek/pull/${item.number}`, checks: { passed: 3, failed: 0, pending: 0 } }));
  let bindings = samples.map(item => ({ url: item.url }));
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'git.branch') return { branch: 'old-checkout' };
    if (request.method === 'git.pull_request') return { branch: 'old-checkout', pull_request: { ...pr, number: 45, state: 'merged', url: 'https://github.com/example/openseek/pull/45' } };
    if (request.method === 'session.pr_list') return { bindings: structuredClone(bindings) };
    if (request.method === 'session.pr_detail') {
      const item = samples.find(item => item.url === request.params.url);
      return item ? { detail: { pull_request: item, head_url: `https://github.com/example/openseek/tree/${item.branch}` } } : {};
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
  await expect(rows).toHaveCount(0);
  await expect(page.locator('.composer-git')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});
