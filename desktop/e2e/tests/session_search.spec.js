import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openSearch(page, app) {
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  const input = page.getByRole('textbox', { name: 'Search conversations', exact: true });
  await expect(input).toHaveAttribute('placeholder', 'Search');
  await input.focus();
  return input;
}

function fixture(page) {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions = [
    { id: 'session-1', title: 'Unicode support', updated_at_ms: 3 },
    { id: 'body-only', title: 'Terminal rendering', updated_at_ms: 2 },
    { id: 'title-only', title: 'Unicode terminal notes', updated_at_ms: 1 },
  ];
  app.archivedSessions = [{ id: 'archived-1', title: 'Earlier Unicode discussion', updated_at_ms: 1 }];
  return app;
}

// Folded sections, projects and sub-runs keep their rows mounted. Count only
// titles exposed to the reader, including while the content box animates.
const rows = page => page.locator(
  'aside .sidebar-group-content .conversation-open',
).and(page.getByRole('button'));

test('inline title search reuses project rows and keeps results when opening unloaded history', async ({ page }) => {
  const app = fixture(page);
  const input = await openSearch(page, app);
  await input.fill('Unicode');
  // Archived conversations are on Settings' archived page, not in search.
  await expect(rows(page)).toHaveCount(2);
  await expect(rows(page).filter({ hasText: 'Earlier Unicode discussion' })).toHaveCount(0);
  await expect(rows(page).filter({ hasText: 'Terminal rendering' })).toHaveCount(0);
  await expect(rows(page).filter({ hasText: 'Unicode terminal notes' }).locator('strong')).toHaveText('Unicode');
  await expect(page.locator('dialog[open]')).toHaveCount(0);
  await expect(input).toBeFocused();
  await input.press('ArrowDown');
  await expect(page.locator('.conversation-row.search-selected')).toContainText('Unicode terminal notes');
  await input.press('Enter');
  await expect.poll(() => app.requests.some(r => r.method === 'session.load' && r.params.session === 'title-only')).toBe(true);
  await expect(input).toHaveValue('Unicode');
  await expect(rows(page)).toHaveCount(2);
  expect(app.requests.some(r => r.method === 'session.search')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('clear and Escape restore the normal list and keep typing focus; switching modes clears', async ({ page }) => {
  const app = fixture(page);
  const input = await openSearch(page, app);
  await input.fill('no matching text');
  await expect(page.getByText('No matching conversations', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Clear search', exact: true }).click();
  await expect(input).toHaveValue('');
  await expect(input).toBeFocused();
  await expect(rows(page)).toHaveCount(3);
  await input.fill('unicode');
  await input.press('Escape');
  await expect(input).toHaveValue('');
  await expect(input).toBeFocused();
  await input.fill('unicode');
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await expect(input).toHaveValue('');
  await input.fill('unicode');
  await expect(rows(page)).toHaveCount(0);
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await expect(input).toHaveValue('');
  expect(app.pageErrors).toEqual([]);
});

test('all matching rows bypass compact previews and the old global limit; keyboard selection scrolls', async ({ page }) => {
  const app = fixture(page);
  app.liveSessions = Array.from({ length: 125 }, (_, i) => ({ id: `row-${i}`, title: `Matching conversation ${i}`, updated_at_ms: 125 - i }));
  app.archivedSessions = [];
  const input = await openSearch(page, app);
  await page.locator('.workspace-disclosure').click();
  await expect(rows(page)).toHaveCount(0);
  await input.fill('conversation 124');
  await expect(rows(page)).toHaveCount(1);
  await expect(rows(page)).toHaveText('Matching conversation 124');
  await input.fill('matching');
  await expect(rows(page)).toHaveCount(125);
  for (let i = 0; i < 25; i++) await input.press('ArrowDown');
  const selected = page.locator('.conversation-row.search-selected .conversation-open');
  await expect(selected).toHaveText('Matching conversation 25');
  await expect(input).toBeFocused();
  const row = await selected.boundingBox();
  const list = await page.locator('.sidebar-main').boundingBox();
  expect(row.y).toBeGreaterThanOrEqual(list.y);
  expect(row.y + row.height).toBeLessThanOrEqual(list.y + list.height + 1);
  await input.dispatchEvent('keydown', { key: 'Enter', code: 'Enter', isComposing: true, bubbles: true });
  expect(app.requests.some(r => r.method === 'session.load')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});
