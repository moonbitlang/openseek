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

const archivedRow = (page, title) => page.getByRole('dialog', { name: 'Archived chats', exact: true }).locator('.archived-chat-row').filter({ hasText: title });

test('archived chats live in Settings with filter, read-only open, restore and delete', async ({ page }) => {
  const app = fixture(page);
  await app.install();
  await app.goto();
  await expect(page.getByRole('complementary')).not.toContainText('Archived');
  const workUrl = page.url();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByText('2 archived conversations', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Manage', exact: true }).click();
  await expect(page).toHaveURL(workUrl);
  const main = page.locator('#management-dialog');
  await expect(main.locator('.topbar-title')).toHaveText('Archived chats');
  await expect(main.getByRole('heading', { level: 2 })).toHaveText(['workspace', 'notes']);

  const filter = main.getByRole('searchbox', { name: 'Filter archived chats', exact: true });
  await filter.fill('TRIP');
  await expect(main.getByRole('button', { name: 'Trip plan', exact: true })).toBeVisible();
  await expect(main.getByRole('button', { name: 'Parser notes', exact: true })).toHaveCount(0);
  await filter.fill('nothing');
  await expect(main.getByText('No archived chats match.', { exact: true })).toBeVisible();
  await filter.fill('parser');

  await main.getByRole('button', { name: 'Parser notes', exact: true }).click();
  await expect(page.getByText('Archived conversation · Read only', { exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveCount(0);
  await expect.poll(() => app.requests.some(r => r.method === 'session.load_archived' && r.params.session === 'work-archive')).toBe(true);
  await expect(main).not.toBeVisible();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Manage', exact: true }).click();
  await expect(main.locator('.topbar-title')).toHaveText('Archived chats');
  // Each visit starts unfiltered.
  await expect(filter).toHaveValue('');
  await expect(main.getByRole('button', { name: 'Trip plan', exact: true })).toBeVisible();

  await archivedRow(page, 'Parser notes').getByRole('button', { name: 'Restore', exact: true }).click();
  await expect(archivedRow(page, 'Parser notes')).toHaveCount(0);
  await expect.poll(() => app.requests.filter(r => r.method === 'session.unarchive').map(r => r.params.session)).toEqual(['work-archive']);

  await archivedRow(page, 'Trip plan').getByRole('button', { name: 'Delete', exact: true }).click();
  await page.getByRole('button', { name: 'Delete permanently', exact: true }).click();
  await expect(main.getByText('No archived chats.', { exact: true })).toBeVisible();
  expect(app.requests.filter(r => r.method === 'session.delete_archived').map(r => r.params.session)).toEqual(['notes-archive']);
  await expect(main.locator('.topbar-title')).toHaveText('Archived chats');

  await main.getByRole('button', { name: 'Back to settings', exact: true }).click();
  await expect(main.locator('.topbar-title')).toHaveText('Settings');
  await expect(page.getByText('0 archived conversations', { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('a long archived title truncates and keeps its actions in view', async ({ page }) => {
  const app = fixture(page);
  app.archivedSessions = [
    { id: 'long-archive', title: 'Explain '.repeat(60).trim(), workspace: '/workspace', updated_at_ms: 2 },
  ];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Manage', exact: true }).click();
  const main = page.getByRole('dialog', { name: 'Archived chats', exact: true });
  const scroller = main.locator('.archived-chats-page');
  await expect(scroller.locator('.archived-chat-row')).toHaveCount(1);
  expect(await scroller.evaluate(node => node.scrollWidth - node.clientWidth)).toBe(0);
  const viewport = page.viewportSize();
  for (const name of ['Restore', 'Delete']) {
    const box = await main.getByRole('button', { name, exact: true }).boundingBox();
    expect(box.x + box.width).toBeLessThanOrEqual(viewport.width);
  }
  expect(app.pageErrors).toEqual([]);
});
