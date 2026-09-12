import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const root = '/Users/test/Library/Application Support/SeekMoon/workspaces';
const workspace = `${root}/Unnamed workspace`;
const chatsHeader = page => page.locator('.section-heading').filter({ has: page.getByRole('button', { name: 'Chats', exact: true }) });

async function expectInChats(row) {
  await expect(row).toBeVisible();
  expect(await row.evaluate(element => {
    let previous = element.previousElementSibling;
    while (previous && !previous.classList.contains('section-heading')) previous = previous.previousElementSibling;
    return previous?.querySelector('.section-disclosure')?.textContent;
  })).toBe('Chats');
}

test('Chats creates directly without a picker and restores titled chats outside Projects', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = [];
  app.liveSessions = [];
  app.sessionEvents = [];
  await page.emulateMedia({ colorScheme: 'dark' });
  await app.install();
  await app.goto();
  const create = chatsHeader(page).getByRole('button', { name: 'New chat', exact: true });
  await expect(create).toBeEnabled();
  app.rpcDelays.set('fs.create_unnamed_workspace', 300);
  await create.click();
  await expect(chatsHeader(page).getByRole('button', { name: 'Creating chat…' })).toBeDisabled();
  await expect(page.getByRole('dialog', { name: 'Add a project' })).toHaveCount(0);
  await expect.poll(() => app.requests.find(request => request.method === 'workspace.add'))
    .toMatchObject({ params: { path: workspace } });
  expect(app.requests.filter(request => request.method === 'fs.create_unnamed_workspace')).toHaveLength(1);
  expect(app.requests.some(request => request.method === 'fs.browse')).toBe(false);
  app.notify('workspace.changed', { workspaces: app.workspaces, chat_root: root });
  await expectInChats(page.locator('.conversation-row').filter({ hasText: /^New chat$/ }));
  await expect(page.locator('.workspace-row')).toHaveCount(0);
  await expect(page.locator('.empty-title')).toHaveText('What should we build?');

  const title = 'Help me organize these notes';
  app.sessionEvents = [{ sequence: 1, item: { kind: 'user', payload: { content: title } } }];
  await page.locator('#task').fill(title);
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')).toBeTruthy();
  const start = app.requests.find(request => request.method === 'agent.start');
  await expectInChats(page.locator('.conversation-row').filter({ hasText: title }));
  app.liveSessions = [{ id: start.params.session, title, updated_at_ms: 1 }];
  app.sessionGroups = sessions => ({ groups: [{ workspace, name: 'Unnamed workspace', session_root: `${workspace}/.openseek`, sessions, error: '' }] });
  await page.reload();
  await expectInChats(page.locator('.conversation-row').filter({ hasText: title }));
  await expect(page.locator('.workspace-row')).toHaveCount(0);
  await page.screenshot({ path: test.info().outputPath('chats-sidebar.png') });
  expect(app.pageErrors).toEqual([]);
});

test('Chats creation errors allow retry without changing the selected project', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('fs.create_unnamed_workspace', 'disk full');
  await app.install();
  await app.goto();
  const create = chatsHeader(page).getByRole('button', { name: 'New chat', exact: true });
  await create.click();
  await expect(page.getByText(/Cannot create chat:.*disk full/)).toBeVisible();
  await expect(create).toBeEnabled();
  await expect(page.locator('.empty-title')).toHaveText('What should we build in workspace?');
  expect(app.requests.some(request => request.method === 'workspace.add')).toBe(false);
  app.rpcErrors.delete('fs.create_unnamed_workspace');
  await create.click();
  await expect.poll(() => app.requests.find(request => request.method === 'workspace.add'))
    .toMatchObject({ params: { path: workspace } });
  expect(app.pageErrors).toEqual([]);
});

test('a user project named Unnamed workspace remains in Projects', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/Users/test/Projects/Unnamed workspace'];
  await app.install();
  await app.goto();
  await expect(page.getByRole('button', { name: 'Unnamed workspace', exact: true })).toBeVisible();
  await expect(chatsHeader(page)).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
