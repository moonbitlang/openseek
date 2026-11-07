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

const archivedRow = (page, title) => page.getByRole('tabpanel', { name: 'Archive', exact: true }).locator('.archived-chat-row').filter({ hasText: title });

test('archived chats live in Settings with filter, read-only open, restore and delete', async ({ page }) => {
  const app = fixture(page);
  await app.install();
  await app.goto();
  const workUrl = page.url();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Archive', exact: true }).click();
  await expect(page).toHaveURL(workUrl);
  const main = page.locator('#management-dialog');
  const archived = main.getByRole('tabpanel', { name: 'Archive', exact: true });

  const filter = main.getByRole('searchbox', { name: 'Filter archived chats', exact: true });
  await filter.fill('TRIP');
  await expect(main.getByRole('button', { name: 'Trip plan', exact: true })).toBeVisible();
  await expect(main.getByRole('button', { name: 'Parser notes', exact: true })).toHaveCount(0);
  await filter.fill('parser');
  await main.getByRole('tab', { name: 'General', exact: true }).click();
  await main.getByRole('tab', { name: 'Archive', exact: true }).click();
  await expect(filter).toHaveValue('');
  await filter.fill('parser');

  await main.getByRole('button', { name: 'Parser notes', exact: true }).click();
  await expect(page.locator('#task')).toHaveCount(0);
  await expect.poll(() => app.requests.some(r => r.method === 'session.load_archived' && r.params.session === 'work-archive')).toBe(true);
  await expect(main).not.toBeVisible();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Archive', exact: true }).click();
  await expect(archived).toBeVisible();
  // Each visit starts unfiltered.
  await expect(filter).toHaveValue('');
  await expect(main.getByRole('button', { name: 'Trip plan', exact: true })).toBeVisible();

  await archivedRow(page, 'Parser notes').getByRole('button', { name: 'Restore', exact: true }).click();
  await expect(archivedRow(page, 'Parser notes')).toHaveCount(0);
  await expect.poll(() => app.requests.filter(r => r.method === 'session.unarchive').map(r => r.params.session)).toEqual(['work-archive']);

  await archivedRow(page, 'Trip plan').getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Delete permanently', exact: true })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button', { name: 'Delete permanently', exact: true })).toHaveCount(0);
  await expect(main).toBeVisible();
  await archivedRow(page, 'Trip plan').getByRole('button', { name: 'Delete', exact: true }).click();
  await page.getByRole('button', { name: 'Delete permanently', exact: true }).click();
  expect(app.requests.filter(r => r.method === 'session.delete_archived').map(r => r.params.session)).toEqual(['notes-archive']);
  await main.getByRole('tab', { name: 'General', exact: true }).click();
  await expect(main.getByRole('tabpanel', { name: 'General', exact: true })).toBeVisible();
  await main.getByRole('button', { name: 'Dismiss', exact: true }).click();
  await expect(main).not.toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
