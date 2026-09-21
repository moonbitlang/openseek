import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('PR Markdown resolves hosted links and opens images only on an explicit click', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const originalReply = app.replyFor.bind(app);
  const url = 'https://github.com/owner/project/pull/42';
  const item = { number: 42, title: 'Hosted Markdown', url, author: 'contributor', draft: false };
  const remoteRequests = [];
  await page.context().route('https://**/*', route => {
    remoteRequests.push(route.request().url());
    return route.fulfill({ contentType: 'text/html', body: '<title>Explicit image navigation</title>' });
  });
  app.replyFor = request => {
    if (request.method === 'github.list') return {
      repository: 'owner/project', repository_url: 'https://github.com/owner/project',
      has_more: false, items: request.params.kind === 'issues' ? [] : [item],
    };
    if (request.method === 'github.pull_request') return {
      item, state: 'OPEN', mergeable: 'MERGEABLE', base: 'main', head: 'feature',
      body: [
        '[Guide](../blob/main/README.md)', '[Discussion](#discussion)',
        '![Relative screenshot](docs/shot.png)', '![Remote screenshot](https://image.example.test/tracker.png)',
        '[Local file](file:///tmp/private.txt)', '[Unsafe script](javascript:alert(1))',
      ].join('\n\n'),
      additions: 1, deletions: 0, changed_files: 1, checks: [], comments: [],
      created_at: '2026-09-21T00:00:00Z', reviewers: [], assignees: [], labels: [],
    };
    return originalReply(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  await page.locator('.github-pulls').getByRole('button', { name: /^Hosted Markdown,/ }).click();
  const body = page.locator('.github-description .markdown');
  await expect(body.getByRole('link', { name: 'Guide', exact: true }))
    .toHaveAttribute('href', 'https://github.com/owner/project/blob/main/README.md');
  await expect(body.getByRole('link', { name: 'Discussion', exact: true })).toHaveAttribute('href', url + '#discussion');
  await expect(body.getByRole('link', { name: 'Open image: Relative screenshot', exact: true }))
    .toHaveAttribute('href', 'https://github.com/owner/project/pull/docs/shot.png');
  await expect(body.locator('img, .transcript-image, .file-link')).toHaveCount(0);
  await expect(body.getByRole('link', { name: 'Local file', exact: true })).toHaveCount(0);
  await expect(body.getByRole('link', { name: 'Unsafe script', exact: true })).toHaveCount(0);
  expect(remoteRequests).toEqual([]);
  const popupPromise = page.waitForEvent('popup');
  const navigationPromise = page.context().waitForEvent('request', {
    predicate: request => request.url() === 'https://image.example.test/tracker.png',
  });
  await body.getByRole('link', { name: 'Open image: Remote screenshot', exact: true }).click();
  const popup = await popupPromise;
  await navigationPromise;
  await popup.close();
  expect(remoteRequests).toEqual(['https://image.example.test/tracker.png']);
  expect(app.requests.filter(request => request.method === 'fs.read_file' && request.params?.path === 'docs/shot.png')).toEqual([]);
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
