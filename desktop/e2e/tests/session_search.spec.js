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

test('search uses titles without category tabs and Enter on Close does not open a result', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  installSearch(app);
  const input = await openSearch(page, app);
  await input.fill('Unicode');
  await expect(page.locator('.session-search-result')).toHaveCount(2);
  await expect(page.locator('.session-search-filters')).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'session.search').every(r => !('scope' in r.params))).toBe(true);
  const before = app.requests.filter(r => r.method === 'session.load').length;
  await page.getByRole('button', { name: 'Close search' }).focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#session-search-dialog')).not.toBeVisible();
  expect(app.requests.filter(r => r.method === 'session.load')).toHaveLength(before);
  expect(app.pageErrors).toEqual([]);
});

test('search shares Quick Open styling and fits smaller windows in Chinese', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await page.addInitScript(() => localStorage.setItem('openseek.language', 'zh-Hans'));
  const replyFor = app.replyFor.bind(app);
  const titles = ['Unicode 属性覆盖评估', '整理工作区文档', 'TUI 库设计方案', 'Desktop capabilities via MCP', 'Fork UI for desktop assistant messages', 'Unicode 字符数组表示', '终端渲染与文本选择', 'MoonBit 标准库迁移'];
  app.replyFor = request => request.method === 'session.search'
    ? { hits: titles.map((title, index) => ({ session: `demo-${index}`, workspace: index % 2 ? '/projects/moonbit' : '/projects/openseek', title: title.includes('Unicode') ? title : `Unicode · ${title}`, archived: false, updated_at_ms: 100 - index })), errors: [], has_more: false }
    : replyFor(request);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  const surfaceStyle = locator => locator.evaluate(element => {
    const style = getComputedStyle(element);
    const box = element.getBoundingClientRect();
    return { width: box.width, top: box.top, border: style.border, radius: style.borderRadius, background: style.backgroundColor, shadow: style.boxShadow };
  });
  const inputStyle = locator => locator.evaluate(element => {
    const style = getComputedStyle(element);
    return { font: style.font, color: style.color, padding: style.padding, outline: style.outlineStyle };
  });
  const rowStyle = locator => locator.evaluate(element => {
    const style = getComputedStyle(element);
    return { height: element.getBoundingClientRect().height, padding: style.padding, radius: style.borderRadius, gap: style.gap, color: style.color, background: style.backgroundColor };
  });
  const quickOpenRowStyle = await rowStyle(page.locator('.quick-open-backdrop .quick-open-row.selected'));
  const quickOpenInputStyle = await inputStyle(page.locator('#quick-open-input'));
  const quickOpenStyle = await surfaceStyle(page.locator('.quick-open-backdrop .quick-open-dialog'));
  const quickOpenInputHeight = (await page.locator('.quick-open-backdrop .quick-open-input-wrap').boundingBox()).height;
  await page.screenshot({ path: 'test-results/quick-open-reference-zh.png' });
  await page.locator('#quick-open-input').press('Escape');
  const sidebar = page.locator('aside');
  const searchBox = page.locator('.sidebar-search');
  const sidebarBounds = await sidebar.boundingBox();
  const searchBounds = await searchBox.boundingBox();
  expect(searchBounds.height).toBe(26);
  expect(searchBounds.x - sidebarBounds.x).toBe(10);
  expect(sidebarBounds.x + sidebarBounds.width - searchBounds.x - searchBounds.width).toBe(11);
  await page.screenshot({ path: 'test-results/session-search-sidebar-zh.png', clip: { x: 0, y: 0, width: sidebarBounds.width, height: 300 } });
  await page.locator('.sidebar-search').click();
  await page.getByRole('textbox', { name: '搜索会话标题' }).fill('unicode');
  await expect(page.locator('.session-search-result')).toHaveCount(8);
  const dialog = page.locator('#session-search-dialog');
  expect(await surfaceStyle(dialog)).toEqual(quickOpenStyle);
  expect(await inputStyle(page.locator('#session-search-input'))).toEqual(quickOpenInputStyle);
  expect(await rowStyle(page.locator('.session-search-result.selected'))).toEqual(quickOpenRowStyle);
  expect((await dialog.locator('.quick-open-input-wrap').boundingBox()).height).toBe(quickOpenInputHeight);
  await expect(dialog).toHaveCSS('padding', '0px');
  expect((await dialog.boundingBox()).height).toBeLessThanOrEqual(400);
  expect(await page.locator('.session-search-results').evaluate(element => element.scrollHeight > element.clientHeight)).toBe(true);
  await page.setViewportSize({ width: 1120, height: 760 });
  expect((await dialog.boundingBox()).height).toBeLessThanOrEqual(400);
  await page.screenshot({ path: 'test-results/session-search-reference-zh.png' });
  await page.setViewportSize({ width: 800, height: 650 });
  const box = await dialog.boundingBox();
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(800);
  await page.setViewportSize({ width: 600, height: 400 });
  const compact = await dialog.boundingBox();
  expect(compact.y).toBe(16);
  expect(compact.y + compact.height).toBeLessThanOrEqual(384);
  await expect(page.getByRole('button', { name: '显示已归档会话' })).toBeInViewport();
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
