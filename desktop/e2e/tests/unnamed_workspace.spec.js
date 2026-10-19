import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

const root = '/Users/test/Library/Application Support/SeekMoon/workspaces';
const chatsHeader = page => page.locator('.section-heading').filter({ has: page.getByRole('button', { name: 'Cloud', exact: true }) });
const sidebarMode = (page, name) => page.getByRole('group', { name: 'Sidebar list' }).getByRole('button', { name, exact: true });

function localHistory(app) {
  app.workspaces = ['/workspace', `${root}/history`];
  app.liveSessions = [{ id: 'legacy-chat', title: 'Legacy local chat', updated_at_ms: 100 }];
  app.sessionGroups = sessions => ({ groups: [{
    workspace: `${root}/history`, name: 'Unnamed workspace', session_root: `${root}/history/.openseek`, error: '', sessions,
  }] });
}

for (const legacy of [false, true]) {
  test(`signed-out Chat offers sign-in without creating a conversation${legacy ? ' and retains local history' : ''}`, async ({ page }, testInfo) => {
    const cloud = new CloudHarness(page, { desktop: true, cached: false });
    if (legacy) localHistory(cloud.device);
    await cloud.install();
    await cloud.goto();
    if (legacy) {
      await page.locator('.conversation-row[title="legacy-chat"]').click();
      await expect(page.locator('#transcript')).toContainText('Browser result');
      await page.locator('#task').fill('Keep my local draft');
    }
    await expect(page.locator('#task')).toBeVisible();
    const title = await page.locator('main > .topbar h1').textContent();
    const hint = page.locator('aside').getByText('Sign in to view Cloud conversations', { exact: true });
    await expect(hint).toBeVisible();
    const cloudFolder = page.locator('aside').getByRole('button', { name: 'Cloud', exact: true });
    const localFolder = page.locator('aside').getByRole('button', { name: 'Local', exact: true });
    await expect(cloudFolder).toHaveAttribute('aria-expanded', 'true');
    await expect(localFolder).toHaveAttribute('aria-expanded', 'true');
    if (legacy) {
      const local = page.locator('.conversation-row[title="legacy-chat"]');
      await cloudFolder.click();
      await expect(hint).toHaveCount(0);
      await expect(local).toBeVisible();
      await localFolder.click();
      await expect(local).toHaveCount(0);
      await expect(cloudFolder).toHaveAttribute('aria-expanded', 'false');
      await localFolder.click();
      await cloudFolder.click();
      await expect(hint).toBeVisible();
    }
    const signIn = page.locator('aside').getByRole('button', { name: 'Sign in', exact: true });
    expect(await signIn.evaluate(button => {
      const range = document.createRange();
      range.selectNodeContents(button);
      return range.getClientRects().length;
    })).toBe(1);
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toEqual([]);
    await page.screenshot({ path: testInfo.outputPath(`signed-out-chat-${legacy ? 'local-history' : 'empty'}.png`) });
    await signIn.click();
    await expect(cloud.row(sessionA)).toBeVisible();
    await expect(hint).toHaveCount(0);
    await expect(page.locator('main > .topbar h1')).toHaveText(title);
    if (legacy) await expect(page.locator('#task')).toHaveValue('Keep my local draft');
    expect(cloud.hostRequests.filter(request => request.method === 'auth.connect')).toHaveLength(1);
    expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('signed-in Chat with no Cloud history keeps an empty list', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  cloud.sessionIds = [];
  await cloud.install();
  await page.goto('https://openseek-api.moonbitlang.cn/console/index.html?device=device-a');
  await sidebarMode(page, 'Chat').click();
  await expect.poll(() => cloud.requests.some(request => request.method === 'GET' && request.path === '/v1/sessions')).toBe(true);
  await expect(page.locator('aside').getByRole('button', { name: 'Sign in', exact: true })).toHaveCount(0);
  await expect(page.locator('aside .conversation-row')).toHaveCount(0);
  await expect(page.locator('aside .section-disclosure')).toHaveText(['Cloud', 'Local', 'Archived chats']);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a user project named Unnamed workspace remains in Projects', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/Users/test/Projects/Unnamed workspace'];
  await app.install();
  await app.goto();
  await expect(page.getByRole('button', { name: 'Unnamed workspace', exact: true })).toBeVisible();
  await expect(chatsHeader(page)).toHaveCount(0);
  const launchMode = page.locator('button.composer-worktree');
  await expect(launchMode).toHaveText('Local');
  await launchMode.click();
  await expect(launchMode).toHaveText('Worktree');
  await launchMode.click();
  await expect(launchMode).toHaveText('Local');
  expect(app.pageErrors).toEqual([]);
});

test('existing local Chats load, export, archive, restore and continue without a Cloud account', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true, cached: false });
  const app = cloud.device;
  localHistory(app);
  await cloud.install();
  await cloud.goto();
  await sidebarMode(page, 'Work').click();
  await expect(page.getByRole('button', { name: 'workspace', exact: true })).toBeVisible();
  await sidebarMode(page, 'Chat').click();
  const row = page.locator('.conversation-row[title="legacy-chat"]');
  await row.click();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  expect(cloud.hostRequests.find(request => request.method === 'session.load')).toMatchObject({
    params: { session: 'legacy-chat', workspace: `${root}/history` },
  });
  await page.getByRole('button', { name: 'Export conversation', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Export conversation', exact: true });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Close export dialog', exact: true }).click();
  await row.hover();
  await row.getByRole('button', { name: 'Conversation actions' }).click();
  await page.getByRole('menuitem', { name: 'Archive', exact: true }).click();
  await page.locator('.section-heading', { hasText: 'Archived chats (1)' }).click();
  await row.click();
  await expect(page.getByText('Archived conversation · Read only', { exact: true })).toBeVisible();
  await row.hover();
  await row.getByTitle('Restore this conversation to the sidebar').click();
  await expect.poll(() => cloud.hostRequests.some(request => request.method === 'session.unarchive')).toBe(true);
  await page.evaluate(workspace => window.desktopEvent('openseek.session.changed', {
    change: 'unarchived', session: 'legacy-chat', workspace,
  }), `${root}/history`);
  await expect(page.getByRole('button', { name: 'Archived chats', exact: true })).toBeVisible();
  await row.click();
  await expect(page.getByText('Archived conversation · Read only', { exact: true })).toHaveCount(0);
  await page.locator('#task').fill('Continue this local conversation');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.hostRequests.find(request => request.method === 'agent.start')).toMatchObject({
    params: { session: 'legacy-chat', workspace: `${root}/history` },
  });
  await expect(chatsHeader(page).getByRole('button', { name: 'New chat', exact: true })).toBeEnabled();
  expect(cloud.hostRequests.some(request => request.method === 'fs.create_unnamed_workspace')).toBe(false);
  expect(cloud.accountSignedIn).toBe(false);
  expect(cloud.requests.filter(request => request.side === 'cloud')).toEqual([]);
  expect(app.workspaces).toContain(`${root}/history`);
  expect(app.liveSessions).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('local Chat drafts survive Cloud navigation and sign-out while new Chats remain Cloud', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page, { desktop: true });
  localHistory(cloud.device);
  await cloud.install();
  await cloud.goto();
  const local = page.locator('.conversation-row[title="legacy-chat"]');
  await cloud.open();
  await expect(page.getByRole('button', { name: /^Show terminal/ })).toHaveCount(0);
  await local.click();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await expect(page.getByRole('button', { name: /^Show terminal/ })).toBeVisible();
  await page.locator('#task').fill('Keep this local draft');
  await page.screenshot({ path: testInfo.outputPath('cloud-and-existing-local-chats.png') });
  await cloud.open();
  await expect(page.getByRole('button', { name: /^Show terminal/ })).toHaveCount(0);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect(cloud.row(sessionA)).toHaveCount(0);
  await local.click();
  await expect(page.locator('#task')).toHaveValue('Keep this local draft');
  expect(cloud.accountSignedIn).toBe(false);
  await page.screenshot({ path: testInfo.outputPath('local-chat-after-sign-out.png') });
  await page.getByRole('button', { name: 'New chat', exact: true }).click();
  await expect.poll(() => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(1);
  await local.click();
  await expect(page.locator('#task')).toHaveValue('Keep this local draft');
  const shortcut = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta+N' : 'Control+N');
  await sidebarMode(page, 'Work').click();
  await page.keyboard.press(shortcut);
  await expect.poll(() => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(2);
  await expect(page.locator('main > .topbar h1')).toHaveText('New chat');
  await local.click();
  await sidebarMode(page, 'Work').click();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.keyboard.press(shortcut);
  await expect.poll(() => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(3);
  await expect(page.locator('main > .topbar h1')).toHaveText('New chat');
  await sidebarMode(page, 'Work').click();
  await page.keyboard.press(shortcut);
  await expect.poll(() => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(4);
  await sidebarMode(page, 'Work').click();
  const project = page.locator('.workspace-row', { hasText: 'workspace' });
  await project.hover();
  await project.getByTitle('New conversation in this project').click();
  await expect(page.locator('main > .topbar .topbar-workspace-label')).toHaveText('workspace');
  await sidebarMode(page, 'Chat').click();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.keyboard.press(shortcut);
  await expect(page.locator('main > .topbar .topbar-workspace-label')).toHaveText('workspace');
  await expect(page.locator('#task')).toHaveValue('');
  expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(4);
  expect(cloud.hostRequests.some(request => request.method === 'fs.create_unnamed_workspace')).toBe(false);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('chat storage failure is visible while ordinary projects still load and can be added', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.chatRoot = { error: 'permission denied' };
  await app.install();
  await app.goto();
  await expect(page.getByText('Chats storage unavailable: permission denied', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'workspace', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Add a project', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Add a project' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Add project', exact: true })).toBeEnabled();
  await page.keyboard.press('Enter');
  await expect.poll(() => app.requests.find(request => request.method === 'workspace.add')).toMatchObject({ params: { path: '/Users/test' } });
  app.notify('workspace.changed', { workspaces: app.workspaces, chat_root: app.chatRoot });
  await expect(page.getByRole('button', { name: 'test', exact: true })).toBeVisible();
  app.notify('workspace.changed', { workspaces: app.workspaces, chat_root: root });
  await expect(page.getByText('Chats storage unavailable: permission denied', { exact: true })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});
