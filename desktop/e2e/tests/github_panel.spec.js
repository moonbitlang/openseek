import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

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
