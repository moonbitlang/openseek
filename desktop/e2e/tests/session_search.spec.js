import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

function installSearch(app) {
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method !== 'session.search') return replyFor(request);
    const query = request.params.query.toLowerCase();
    const live = [
      { session: 'session-1', workspace: '/workspace', title: 'Unicode support', archived: false, updated_at_ms: 3 },
      { session: 'body-only', workspace: '/workspace', title: 'Terminal rendering', archived: false, updated_at_ms: 2 },
      { session: 'title-only', workspace: '/workspace', title: 'Unicode terminal notes', archived: false, updated_at_ms: 1 },
    ];
    const archived = { session: 'archived-1', workspace: '/workspace', title: 'Earlier Unicode discussion', archived: true, updated_at_ms: 1 };
    return {
      hits: [...live, ...(request.params.include_archived ? [archived] : [])]
        .filter(hit => hit.title.toLowerCase().includes(query)),
      errors: [], has_more: false,
    };
  };
}

async function openSearch(page, app) {
  await app.install();
  await app.goto();
  await page.locator('.sidebar-search').click();
  const input = page.getByRole('textbox', { name: 'Search conversation titles' });
  await expect(input).toBeFocused();
  return input;
}

test('search titles only, exclude body matches, and open a result missing from the sidebar', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  installSearch(app);
  const input = await openSearch(page, app);
  await input.pressSequentially('Unicode');
  const results = page.locator('.session-search-result');
  await expect(results).toHaveCount(2);
  await expect(results.nth(1)).toContainText('Unicode terminal notes');
  await expect(results.filter({ hasText: 'Terminal rendering' })).toHaveCount(0);
  await expect(results.nth(1).locator('strong')).toHaveText('Unicode');
  await expect(input).toBeFocused();
  await page.screenshot({ path: 'test-results/session-search-reference.png' });
  await input.press('ArrowDown');
  await expect(results.nth(1)).toHaveClass(/selected/);
  await input.press('Enter');
  await expect(page.locator('#session-search-dialog')).not.toBeVisible();
  await expect.poll(() => app.requests.some(r => r.method === 'session.load' && r.params.session === 'title-only' && r.params.workspace === '/workspace')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('archived switch, no results, empty query, and Escape', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  installSearch(app);
  const input = await openSearch(page, app);
  await input.fill('unicode');
  await expect(page.locator('.session-search-result')).toHaveCount(2);
  await page.getByRole('button', { name: 'Show archived conversations' }).click();
  await expect(page.locator('.session-search-result')).toHaveCount(3);
  await page.locator('.session-search-result').nth(2).click();
  await expect.poll(() => app.requests.some(r => r.method === 'session.load_archived' && r.params.session === 'archived-1')).toBe(true);
  await page.locator('.sidebar-search').click();
  await input.fill('no matching text');
  await expect(page.getByText('No matching conversations', { exact: true })).toBeVisible();
  await input.fill('');
  await expect(page.locator('.session-search-result')).toHaveCount(0);
  await input.press('Escape');
  await expect(page.locator('#session-search-dialog')).not.toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('late results cannot replace a newer search or reopen a closed dialog', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  installSearch(app);
  const input = await openSearch(page, app);
  app.rpcDelays.set('session.search', 1000);
  await input.fill('Unicode');
  await expect.poll(() => app.requests.filter(r => r.method === 'session.search').length).toBe(1);
  app.rpcDelays.set('session.search', 0);
  await input.fill('notes');
  await expect(page.locator('.session-search-result')).toHaveCount(1);
  await page.waitForTimeout(1100);
  await expect(page.locator('.session-search-result')).toHaveCount(1);
  app.rpcDelays.set('session.search', 600);
  await input.fill('terminal');
  await expect.poll(() => app.requests.filter(r => r.method === 'session.search').length).toBe(3);
  await input.press('Escape');
  await page.waitForTimeout(700);
  await expect(page.locator('#session-search-dialog')).not.toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('transport errors and partial store failures stay visible and can be retried', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  installSearch(app);
  app.rpcErrors.set('session.search', 'store unavailable');
  const input = await openSearch(page, app);
  await input.fill('Unicode');
  await expect(page.locator('.session-search-results')).toContainText('store unavailable');
  app.rpcErrors.delete('session.search');
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.search'
    ? { ...replyFor(request), errors: ['/other: permission denied'], has_more: true }
    : replyFor(request);
  await input.fill('unicode ');
  await expect(page.locator('.session-search-result')).toHaveCount(2);
  await expect(page.getByText('Some conversations could not be searched')).toBeVisible();
  await page.getByText('Some conversations could not be searched').click();
  await expect(page.getByText('/other: permission denied')).toBeVisible();
  await expect(page.getByText('Showing the 100 most recent results. Narrow your search.')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('keyboard navigation scrolls selected results without losing query focus', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.search'
    ? { hits: Array.from({ length: 40 }, (_, index) => ({ session: `row-${index}`, workspace: '/workspace', title: `Matching conversation ${index}`, archived: false })), errors: [], has_more: false }
    : replyFor(request);
  const input = await openSearch(page, app);
  await input.fill('query');
  await expect(page.locator('.session-search-result')).toHaveCount(40);
  for (let i = 0; i < 25; i++) await input.press('ArrowDown');
  const selected = page.locator('#session-search-result-25');
  await expect(selected).toHaveClass(/selected/);
  await expect(input).toBeFocused();
  const row = await selected.boundingBox();
  const list = await page.locator('.session-search-results').boundingBox();
  expect(row.y).toBeGreaterThanOrEqual(list.y);
  expect(row.y + row.height).toBeLessThanOrEqual(list.y + list.height + 1);
  expect(app.pageErrors).toEqual([]);
});

test('result navigation preserves the query caret and IME confirmation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  installSearch(app);
  const input = await openSearch(page, app);
  await input.fill('unicode');
  const rows = page.locator('.session-search-result');
  await expect(rows).toHaveCount(2);
  await input.press('ArrowDown');
  await expect(rows.nth(1)).toHaveClass(/selected/);
  await input.press('ArrowUp');
  await expect(rows.nth(0)).toHaveClass(/selected/);
  await input.press('x');
  await expect(input).toHaveValue('unicodex');
  await input.fill('unicode');
  await expect(rows).toHaveCount(2);
  await input.dispatchEvent('keydown', { key: 'Enter', code: 'Enter', isComposing: true, bubbles: true });
  await expect(input).toBeFocused();
  await expect(page.locator('#session-search-dialog')).toBeVisible();
  expect(app.requests.some(r => r.method === 'session.load')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('session search owns focus until dismissal before Quick Open can open', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  installSearch(app);
  await app.install();
  await app.goto();
  await app.openSession();
  await page.locator('.sidebar-search').click();
  const input = page.locator('#session-search-input');
  const command = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta' : 'Control');
  for (const key of ['p', 't']) {
    await input.press(`${command}+${key}`);
    await expect(input).toBeFocused();
    await expect(page.locator('.quick-open-backdrop')).toHaveCount(0);
  }
  await input.press('Escape');
  await expect(page.locator('#session-search-dialog')).not.toBeVisible();
  await expect(page.locator('.quick-open-backdrop')).toHaveCount(0);
  await app.openQuickOpen();
  await expect(page.locator('#quick-open-input')).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});
