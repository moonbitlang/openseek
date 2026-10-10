import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function setup(page) {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Second conversation', updated_at_ms: 2 });
  app.workingFiles['src/main.mbt'] = Array.from({ length: 200 }, (_, i) => `let value_${i} = ${i}`).join('\n');
  app.directoryEntries['/workspace'] = [{ name: 'src', is_dir: true }];
  app.directoryEntries['/workspace/src'] = [{ name: 'main.mbt', is_dir: false }];
  await app.install();
  await app.goto();
  await app.openSession();
  return app;
}

const selectConversation = (page, id) => page.locator(`.conversation-row[title="${id}"]`).click();
async function openFile(page, app) {
  await app.openQuickOpen();
  await page.getByRole('option', { name: /src\/main\.mbt/ }).click();
  await expect(page.locator('#viewer-host .view-lines')).toBeVisible();
}

// The viewer virtualizes its scroll plane; the rendered source line, rather
// than native scrollTop, records the user's actual reading position.
test('same-path tabs keep each conversation viewport and closing only clears its owner', async ({ page }) => {
  const app = await setup(page);
  const top = async () => Number((await page.locator('#viewer-host .view-line').first().innerText()).match(/value_(\d+)/)[1]);
  const wheel = async amount => {
    await page.locator('#viewer-host [data-view-part="editor-scrollable"]').hover();
    await page.mouse.wheel(0, amount);
  };
  await openFile(page, app);
  await wheel(400);
  await expect.poll(top).toBeGreaterThan(10);
  const firstTop = await top();
  await selectConversation(page, 'session-2');
  await openFile(page, app);
  await expect.poll(top).toBe(0);
  await wheel(900);
  await expect.poll(top).toBeGreaterThan(40);
  const secondTop = await top();
  await selectConversation(page, 'session-1');
  await expect.poll(top).toBe(firstTop);
  await selectConversation(page, 'session-2');
  await expect.poll(top).toBe(secondTop);
  await page.locator('.editor-tab.active .tab-close').click();
  await openFile(page, app);
  await expect.poll(top).toBe(0);
  await selectConversation(page, 'session-1');
  await expect.poll(top).toBe(firstTop);
  expect(app.pageErrors).toEqual([]);
});

test('search query restores per conversation and reruns against fresh results', async ({ page }) => {
  const app = await setup(page);
  const search = async () => {
    const shortcut = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
    await page.keyboard.press(shortcut);
  };
  const query = page.getByRole('textbox', { name: 'Search', exact: true });
  await search();
  await query.fill('first query');
  await expect.poll(() => app.requests.filter(r => r.method === 'fs.search_text').length).toBeGreaterThan(0);
  await selectConversation(page, 'session-2');
  await search();
  await expect(query).toHaveValue('');
  await query.fill('second query');
  await expect.poll(() => app.requests.filter(r => r.method === 'fs.search_text').length).toBeGreaterThan(1);
  const before = app.requests.filter(r => r.method === 'fs.search_text').length;
  await selectConversation(page, 'session-1');
  await expect(query).toHaveValue('first query');
  await expect.poll(() => app.requests.filter(r => r.method === 'fs.search_text').length).toBeGreaterThan(before);
  await selectConversation(page, 'session-2');
  await expect(query).toHaveValue('second query');
  expect(app.pageErrors).toEqual([]);
});

test('expanded directories return after switching conversations', async ({ page }) => {
  const app = await setup(page);
  await app.openReview();
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  const tree = page.getByRole('tree', { name: 'Workspace files' });
  const src = tree.getByRole('treeitem', { name: 'src', exact: true });
  await src.click();
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  await selectConversation(page, 'session-2');
  await app.openReview();
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await expect(src).toHaveAttribute('aria-expanded', 'false');
  await selectConversation(page, 'session-1');
  await expect(src).toHaveAttribute('aria-expanded', 'true');
  await expect(tree.getByRole('treeitem', { name: 'main.mbt', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
