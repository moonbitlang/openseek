import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

function fixture(page) {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/workspace', '/notes'];
  app.liveSessions = [
    { id: 'session-1', title: 'Rabbita browser fixture', workspace: '/workspace', updated_at_ms: 3 },
  ];
  app.archivedSessions = [
    { id: 'work-archive', title: 'Parser notes', workspace: '/workspace', updated_at_ms: 2 },
    { id: 'notes-archive', title: 'Trip plan', workspace: '/notes', updated_at_ms: 1 },
  ];
  app.sessionGroups = sessions => ({ groups: app.workspaces.map(workspace => ({
    workspace, name: workspace.split('/').at(-1), session_root: `${workspace}/.openseek`,
    sessions: sessions.filter(session => session.workspace === workspace), error: '',
  })) });
  return app;
}

const archivedRow = (page, id, root = '/workspace') => page.locator(`[id="archived-chat:conversation:openseek.archived:remote.device-a:${id}:${root}"]`);

test('archived chats live in Settings with filter, read-only open, restore and delete', async ({ page }) => {
  const app = fixture(page);
  await app.install();
  await app.goto();
  await expect(page.getByRole('complementary')).not.toContainText('Archived');
  const workUrl = page.url();
  await page.locator('#sidebar-settings').click();
  await expect(page.locator('#archived-chats-manage').locator('..').locator('..').locator('.setting-name')).toHaveText('2 archived conversations');
  await page.locator('#archived-chats-manage').click();
  await expect(page).toHaveURL(workUrl);
  const main = page.locator('#management-dialog');
  await expect(main).toHaveAccessibleName('Archived chats');
  await expect(main.locator('.management-page').getByRole('heading', { level: 2 })).toHaveText(['workspace', 'notes']);

  const filter = main.locator('#archived-chats-filter');
  await filter.fill('TRIP');
  await expect(archivedRow(page, 'notes-archive', '/notes').locator('[data-action="open"]')).toBeVisible();
  await expect(archivedRow(page, 'work-archive').locator('[data-action="open"]')).toHaveCount(0);
  await filter.fill('nothing');
  await expect(main.locator('.archived-chats-empty')).toBeVisible();
  await filter.fill('parser');

  await archivedRow(page, 'work-archive').locator('[data-action="open"]').click();
  await expect(page.locator('.archived-read-only-text')).toBeVisible();
  await expect(page.locator('#task')).toHaveCount(0);
  await expect.poll(() => app.requests.some(r => r.method === 'session.load_archived' && r.params.session === 'work-archive')).toBe(true);
  await expect(main).not.toBeVisible();
  await page.locator('#sidebar-settings').click();
  await page.locator('#archived-chats-manage').click();
  await expect(main).toHaveAccessibleName('Archived chats');
  // Each visit starts unfiltered.
  await expect(filter).toHaveValue('');
  await expect(archivedRow(page, 'notes-archive', '/notes').locator('[data-action="open"]')).toBeVisible();

  await archivedRow(page, 'work-archive').locator('[data-action="restore"]').click();
  await expect(archivedRow(page, 'work-archive')).toHaveCount(0);
  await expect.poll(() => app.requests.filter(r => r.method === 'session.unarchive').map(r => r.params.session)).toEqual(['work-archive']);

  await archivedRow(page, 'notes-archive', '/notes').locator('[data-action="delete"]').click();
  await expect(page.locator('#delete-chat-confirm')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#delete-chat-confirm')).toBeHidden();
  await expect(main).toBeVisible();
  await archivedRow(page, 'notes-archive', '/notes').locator('[data-action="delete"]').click();
  await page.locator('#delete-chat-confirm').click();
  await expect(main.locator('.archived-chats-empty')).toBeVisible();
  expect(app.requests.filter(r => r.method === 'session.delete_archived').map(r => r.params.session)).toEqual(['notes-archive']);
  await expect(main).toHaveAccessibleName('Archived chats');

  await main.locator('#archived-chats-back').click();
  await expect(main).toHaveAccessibleName('Settings');
  await expect(page.locator('#archived-chats-manage').locator('..').locator('..').locator('.setting-name')).toHaveText('0 archived conversations');
  expect(app.pageErrors).toEqual([]);
});

test('a long archived title truncates and keeps its actions in view', async ({ page }) => {
  const app = fixture(page);
  app.archivedSessions = [
    { id: 'long-archive', title: 'Explain '.repeat(60).trim(), workspace: '/workspace', updated_at_ms: 2 },
  ];
  await app.install();
  await app.goto();
  await page.locator('#sidebar-settings').click();
  await page.locator('#archived-chats-manage').click();
  const main = page.locator('#management-dialog');
  const scroller = main.locator('.archived-chats-page');
  await expect(scroller.locator('.archived-chat-row')).toHaveCount(1);
  expect(await scroller.evaluate(node => node.scrollWidth - node.clientWidth)).toBe(0);
  const viewport = page.viewportSize();
  for (const action of ['restore', 'delete']) {
    const box = await main.locator(`[data-action="${action}"]`).boundingBox();
    expect(box.x + box.width).toBeLessThanOrEqual(viewport.width);
  }
  expect(app.pageErrors).toEqual([]);
});
