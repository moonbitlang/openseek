import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('GitHub inventory, PR details and checkout follow live language changes', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const fallback = app.replyFor.bind(app);
  const item = { number: 42, title: 'Keep this PR title', url: 'https://github.com/owner/project/pull/42', author: 'contributor', draft: false };
  app.replyFor = request => {
    if (request.method === 'github.list') return {
      repository: 'owner/project', repository_url: 'https://github.com/owner/project', has_more: false,
      items: request.params.kind === 'issues' ? [] : [item],
    };
    if (request.method === 'github.pull_request') return {
      item, state: 'OPEN', mergeable: 'MERGEABLE', base: 'main', head: 'feature',
      body_html: '<p>Keep the original description.</p>', additions: 2, deletions: 1, changed_files: 1,
      checks: [
        { name: 'Build', state: 'SUCCESS' },
        { name: 'Test', state: 'SUCCESS' },
        { name: 'Lint', state: 'IN_PROGRESS' },
      ],
      comments: [], created_at: '2026-01-02T00:00:00Z',
      reviewers: [{ name: 'reviewer', state: 'APPROVED' }], assignees: [], labels: [],
    };
    if (request.method === 'github.checkout') return { status: 'uncommitted_changes' };
    return fallback(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  const panel = page.locator('.github-panel');
  await panel.locator('.github-item-open').click();
  const languages = [
    { tag: 'zh-Hans', pulls: '拉取请求', reviews: '审阅者', approved: '已批准', checks: '2 项检查成功，1 项检查等待中', files: '1 个文件已更改', checkout: '在本地检出 PR #42', hint: '浏览拉取请求和议题', newTab: '新建标签页' },
    { tag: 'zh-Hant', pulls: '提取要求', reviews: '審閱者', approved: '已核准', checks: '2 項檢查成功，1 項檢查等待中', files: '1 個檔案已變更', checkout: '在本機簽出 PR #42', hint: '瀏覽提取要求和議題', newTab: '新建標籤頁' },
    { tag: 'ja', pulls: 'プルリクエスト', reviews: 'レビュアー', approved: '承認済み', checks: '成功のチェック 2 件、保留中のチェック 1 件', files: '1 個のファイルを変更', checkout: 'PR #42 をローカルにチェックアウト', hint: 'プルリクエストと Issue を表示', newTab: '新しいタブ' },
    { tag: 'es', pulls: 'Solicitudes de incorporación', reviews: 'Revisores', approved: 'Aprobado', checks: '2 comprobaciones correctas y 1 comprobación pendiente', files: '1 archivo modificado', checkout: 'Obtener la PR #42 localmente', hint: 'Explorar solicitudes de incorporación e incidencias', newTab: 'Nueva pestaña' },
    { tag: 'en', pulls: 'Pull Requests', reviews: 'Reviewers', approved: 'Approved', checks: '2 successful checks and 1 pending check', files: '1 changed file', checkout: 'Check out PR #42 locally', hint: 'Browse pull requests and issues', newTab: 'New tab' },
  ];
  for (const locale of languages) {
    await page.evaluate(tag => {
      Object.defineProperty(navigator, 'languages', { configurable: true, value: [tag] });
      window.dispatchEvent(new Event('languagechange'));
    }, locale.tag);
    await expect(page.locator('html')).toHaveAttribute('lang', locale.tag);
    await expect(panel.getByRole('button', { name: locale.pulls, exact: true })).toBeVisible();
    await expect(panel.getByRole('heading', { name: locale.reviews, exact: true })).toBeVisible();
    await expect(panel.locator('.github-review-state')).toHaveText(locale.approved);
    await expect(panel.locator('.github-check-summary')).toHaveText(locale.checks);
    await expect(panel.getByText(locale.files, { exact: true })).toBeVisible();
    await expect(panel.getByRole('button', { name: locale.checkout, exact: true })).toBeAttached();
    await expect(panel.locator('.github-detail-title')).toHaveText('Keep this PR title #42');
    await expect(panel.locator('.github-description .markdown')).toHaveText('Keep the original description.');
    await expect(panel.locator('.github-merge-description code')).toHaveText(locale.tag === 'en' ? ['main', 'feature'] : ['feature', 'main']);
    await page.getByTitle(locale.newTab, { exact: true }).click();
    await expect(page.getByRole('menuitem', { name: 'GitHub', exact: true })).toContainText(locale.hint);
    await page.keyboard.press('Escape');
  }
  await page.setViewportSize({ width: 1050, height: 768 });
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-Hans'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  const checkout = panel.getByRole('button', { name: '在本地检出 PR #42', exact: true });
  await checkout.click();
  const dialog = page.getByRole('dialog', { name: '检出 PR #42 前有未提交的更改', exact: true });
  await expect(dialog.getByRole('button', { name: '暂存更改', exact: true })).toBeFocused();
  await expect(dialog).toContainText('丢弃会永久删除已跟踪文件的更改。未跟踪文件会保留。');
  await page.screenshot({ path: testInfo.outputPath('github-checkout-zh.png') });
  await page.keyboard.press('Escape');
  await expect(checkout).toBeFocused();
  await page.screenshot({ path: testInfo.outputPath('github-panel-zh.png') });
  expect(app.requests.filter(request => request.method === 'github.pull_request')).toHaveLength(1);
  expect(app.requests.filter(request => request.method === 'github.checkout').map(request => request.params.changes)).toEqual(['ask']);
  expect(app.pageErrors).toEqual([]);
});

test('GitHub dock keeps both inventories scrollable and disclosures keyboard accessible', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const originalReply = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method !== 'github.list') return originalReply(request);
    const { kind } = request.params;
    return {
      repository: 'owner/project', repository_url: 'https://github.com/owner/project', has_more: false,
      items: Array.from({ length: 30 }, (_, i) => ({
        number: i + 1, title: `${kind} ${i + 1} — a long title that must stay within the panel bounds`,
        url: `https://github.com/owner/project/${kind === 'issues' ? 'issues' : 'pull'}/${i + 1}`,
        author: 'contributor', avatar_url: 'https://avatars.githubusercontent.com/u/1?s=32', draft: kind !== 'issues' && i === 0,
      })),
    };
  };
  await page.route('https://avatars.githubusercontent.com/**', route => route.fulfill({
    contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="#729ac4"/></svg>',
  }));
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menu', { name: 'New tab', exact: true }).getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  const panel = page.locator('.github-panel');
  await expect(panel).toBeVisible();
  await expect(page.locator('.editor-tab.active')).toContainText('GitHub');
  await expect(panel.locator('.github-pulls .github-item')).toHaveCount(30);
  await expect(panel.locator('.github-issues .github-item')).toHaveCount(30);
  await expect(panel.locator('.github-avatar-image')).toHaveCount(60);
  await expect.poll(() => panel.locator('.github-item').first().evaluate(row => {
    const avatar = row.querySelector('.github-avatar').getBoundingClientRect();
    const title = row.querySelector('.github-item-title').getBoundingClientRect();
    return row.getBoundingClientRect().height <= 28 && avatar.width === 16 && avatar.height === 16 &&
      title.left > avatar.right && Math.abs(title.top + title.height / 2 - avatar.top - avatar.height / 2) < 1;
  })).toBe(true);
  const created = panel.getByRole('button', { name: 'Created By Me', exact: true });
  await expect(created).toHaveAttribute('aria-expanded', 'false');
  await created.focus();
  await page.keyboard.press('Enter');
  await expect(created).toHaveAttribute('aria-expanded', 'true');
  await expect(panel.locator('.github-pulls .github-item')).toHaveCount(60);
  await page.keyboard.press('Space');
  await expect(created).toHaveAttribute('aria-expanded', 'false');
  for (const width of [1440, 1050]) {
    await page.setViewportSize({ width, height: 800 });
    await expect.poll(() => panel.evaluate(element => {
      const sections = [...element.querySelectorAll('.github-section-body')];
      return sections.length === 2 && sections.every(section =>
        section.clientHeight > 80 && section.scrollHeight > section.clientHeight &&
        section.scrollWidth <= section.clientWidth + 1);
    })).toBe(true);
    await expect(panel.getByRole('button', { name: 'Issues', exact: true })).toBeInViewport();
  }
  const issues = panel.locator('.github-issues .github-section-body');
  await issues.hover();
  await page.mouse.wheel(0, 1200);
  await expect.poll(() => issues.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  expect(await panel.locator('.github-pulls .github-section-body').evaluate(element => element.scrollTop)).toBe(0);
  await panel.getByRole('button', { name: 'Pull Requests', exact: true }).click();
  await expect(panel.locator('.github-pulls .github-section-body')).toHaveCount(0);
  await expect(issues).toBeVisible();
  expect(app.requests.filter(request => request.method === 'github.list').map(request => request.params.cwd))
    .toEqual(['/workspace', '/workspace', '/workspace']);
  expect(app.pageErrors).toEqual([]);
});

test('avatar errors retain the inventory and retry clears the warning', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const originalReply = app.replyFor.bind(app);
  let avatarFailed = true;
  app.replyFor = request => {
    if (request.method !== 'github.list') return originalReply(request);
    return {
      repository: 'owner/project', repository_url: 'https://github.com/owner/project', has_more: false,
      avatar_error: avatarFailed ? 'Could not load GitHub avatars: offline' : undefined,
      items: [{ number: 42, title: 'Review the implementation', url: 'https://github.com/owner/project/pull/42',
        author: 'contributor', draft: false }],
    };
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  const pulls = page.locator('.github-pulls');
  await expect(pulls.locator('.github-item')).toHaveCount(1);
  await expect(pulls.getByRole('alert')).toContainText('offline');
  avatarFailed = false;
  await pulls.getByRole('button', { name: 'Retry avatars', exact: true }).click();
  await expect(pulls.getByRole('alert')).toHaveCount(0);
  await expect(pulls.locator('.github-item')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('PR checkout supports keyboard choices, failure notifications and opens Review on success', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const originalReply = app.replyFor.bind(app);
  let current = { branch: 'main', has_open_pull_request: false };
  app.replyFor = request => {
    if (request.method === 'github.checkout_status') return current;
    if (request.method === 'github.checkout') {
      if (request.params.changes === 'ask') return { status: 'uncommitted_changes' };
      if (request.params.changes === 'carry') return { status: 'error',
        message: 'Your local changes would be overwritten. Commit or stash them before switching branches.',
        details: 'error: Your local changes would be overwritten by checkout:\n\tsrc/main.mbt\nAborting' };
      current = { branch: 'contributor/feature', pull_request_url: 'https://github.com/owner/project/pull/42', has_open_pull_request: true };
      return { status: 'success', branch: current.branch };
    }
    if (request.method !== 'github.list') return originalReply(request);
    return {
      repository: 'owner/project', repository_url: 'https://github.com/owner/project', has_more: false,
      items: [{ number: 42, title: 'A pull request with a long title to leave room for checkout',
        url: `https://github.com/owner/project/${request.params.kind === 'issues' ? 'issues' : 'pull'}/42`,
        draft: false }],
    };
  };
  app.rpcDelays.set('github.checkout', 500);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menu', { name: 'New tab', exact: true }).getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  const panel = page.locator('.github-panel');
  const row = panel.locator('.github-pulls .github-item');
  const checkout = row.getByRole('button', { name: 'Check out PR #42 locally', exact: true });
  await expect(panel.locator('.github-issues .github-checkout')).toHaveCount(0);
  await row.locator('.github-item-open').focus();
  await page.keyboard.press('Tab');
  await expect(checkout).toBeFocused();
  await expect(checkout).toHaveCSS('opacity', '1');
  const bounds = await row.evaluate(element => {
    const row = element.getBoundingClientRect();
    const title = element.querySelector('.github-item-title').getBoundingClientRect();
    const action = element.querySelector('.github-checkout').getBoundingClientRect();
    return { fits: title.right <= action.left && action.right <= row.right, height: row.height };
  });
  expect(bounds).toEqual({ fits: true, height: 26 });
  await page.keyboard.press('Enter');
  await expect(row.getByRole('button', { name: 'Checking out PR #42…', exact: true })).toBeDisabled();
  const dialog = page.getByRole('dialog', { name: 'Uncommitted changes before checking out PR #42' });
  const stash = dialog.getByRole('button', { name: 'Stash changes', exact: true });
  await expect(stash).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(dialog.getByRole('button', { name: 'Cancel', exact: true })).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(checkout).toBeFocused();
  await checkout.click();
  await dialog.getByRole('button', { name: 'Try checkout anyway', exact: true }).click();
  const notification = page.locator('.github-checkout-notification');
  await expect(notification).toHaveAttribute('role', 'alert');
  await expect(notification).toContainText('Commit or stash');
  await expect(page.locator('.editor-tab.active')).toContainText('GitHub');
  await expect(checkout).toBeEnabled();
  await notification.getByRole('button', { name: 'Show details', exact: true }).click();
  await expect(notification.locator('pre')).toContainText('src/main.mbt');
  const placement = await notification.evaluate(element => {
    const bounds = element.getBoundingClientRect();
    return bounds.right <= innerWidth && bounds.bottom <= innerHeight && !element.closest('.github-panel');
  });
  expect(placement).toBe(true);
  await notification.getByRole('button', { name: 'Dismiss checkout notification' }).click();
  await expect(notification).toHaveCount(0);
  const branchRequests = app.requests.filter(request => request.method === 'git.branch').length;
  await checkout.click();
  await stash.click();
  await expect(page.locator('.editor-tab.active')).toContainText('main.mbt');
  await expect(page.locator('.github-checkout-notification')).toHaveCount(0);
  await expect.poll(() => app.requests.filter(request => request.method === 'git.branch').length).toBeGreaterThan(branchRequests);
  await page.locator('.editor-tab').filter({ hasText: 'GitHub' }).click();
  await expect(row.locator('.github-current')).toHaveAttribute('title', 'Currently checked out');
  await expect(row.getByRole('button', { name: 'Update checkout for PR #42', exact: true })).toBeEnabled();
  await expect(row.locator('.github-item-open')).toHaveAccessibleName(/Currently checked out/);
  expect(app.requests.filter(request => request.method === 'github.checkout').map(request => request.params))
    .toEqual(['ask', 'ask', 'carry', 'ask', 'stash'].map(changes => ({
      cwd: '/workspace', repository_url: 'https://github.com/owner/project', number: 42, changes, update: false,
    })));
  expect(app.requests.some(request => request.method === 'github.pull_request')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});
