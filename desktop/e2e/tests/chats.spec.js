import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

const root = '/Users/test/Library/Application Support/SeekMoon/workspaces';
const sidebarMode = (page, name) => page.getByRole('group', { name: 'Sidebar list' }).getByRole('button', { name, exact: true });

function localHistory(app) {
  app.workspaces = ['/workspace', `${root}/history`];
  app.liveSessions = [{ id: 'legacy-chat', title: 'Legacy local chat', updated_at_ms: 100 }];
  app.sessionGroups = sessions => ({ groups: [{
    workspace: `${root}/history`, name: 'Unnamed workspace', session_root: `${root}/history/.openseek`, error: '', sessions,
  }] });
}

for (const legacy of [false, true]) {
  test(`Chat signs in and opens conversations directly (retired history=${legacy})`, async ({ page }, testInfo) => {
    const cloud = new CloudHarness(page, { desktop: true, cached: false });
    if (legacy) localHistory(cloud.device);
    await cloud.install();
    await cloud.goto();
    const hint = page.locator('aside').getByText('Sign in to view conversations', { exact: true });
    await expect(hint).toBeVisible();
    await page.locator('aside').getByRole('button', { name: 'Sign in', exact: true }).click();
    await cloud.open();
    await expect(hint).toHaveCount(0);
    await expect(page.locator('#task')).toBeVisible();
    await expect(page.locator('aside .section-label')).toHaveText(['Chats']);
    const row = cloud.row(sessionA);
    await expect(row).toBeInViewport();
    await row.hover();
    await page.getByRole('button', { name: 'Conversation actions' }).click();
    await page.getByRole('menuitem', { name: 'Archive', exact: true }).click();
    await expect(row).toHaveCount(0);
    await cloud.openArchived(sessionA);
    await expect(page.locator('.archived-read-only-text')).toBeVisible();
    await page.screenshot({ path: testInfo.outputPath('chats-flat-archive.png') });
    if (legacy) {
      await sidebarMode(page, 'Work').click();
      await expect(page.getByRole('button', { name: 'workspace', exact: true })).toBeVisible();
      expect(cloud.device.workspaces).toContain(`${root}/history`);
      expect(cloud.device.liveSessions).toHaveLength(1);
    }
    expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('an empty Chat list starts a draft without creating a session', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page, { desktop: true });
  cloud.sessionIds = [];
  await cloud.install();
  await page.goto('https://openseek-api.moonbitlang.cn/console/index.html?device=device-a');
  await sidebarMode(page, 'Chat').click();
  await expect.poll(() => cloud.requests.some(request => request.method === 'GET' && request.path === '/v1/sessions')).toBe(true);
  await cloud.create();
  await page.locator('#task').fill('An unsent chat draft');
  await page.screenshot({ path: testInfo.outputPath('chats-flat-draft.png') });
  expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a project draft survives Chat navigation and account sign-out', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  await cloud.install();
  await cloud.goto();
  await sidebarMode(page, 'Work').click();
  await cloud.device.openSession();
  await page.locator('#task').fill('Keep this project draft');
  await sidebarMode(page, 'Chat').click();
  await cloud.open();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await page.getByRole('dialog', { name: 'Settings', exact: true })
    .getByRole('button', { name: 'Dismiss', exact: true }).click();
  await sidebarMode(page, 'Work').click();
  await cloud.device.openSession();
  await expect(page.locator('#task')).toHaveValue('Keep this project draft');
  await page.locator('#send').click();
  await expect.poll(() => cloud.hostRequests.find(request => request.method === 'agent.start')?.params.task).toBe('Keep this project draft');
  expect(cloud.requests.some(request => request.method === 'POST' && request.path.endsWith('/commands'))).toBe(false);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('retired standalone history cannot be reopened through its old URL', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  localHistory(app);
  app.rpcDelays.set('workspace.list', 300);
  await app.install();
  await page.goto('/device/device-a/chat/session/legacy-chat');
  await expect(page.locator('.navigation-notice')).toContainText('no longer exists');
  expect(app.requests.some(request => request.method === 'session.load' && request.params.session === 'legacy-chat')).toBe(false);
  expect(app.workspaces).toContain(`${root}/history`);
  expect(app.pageErrors).toEqual([]);
});

test('a user project named Unnamed workspace remains a project', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/Users/test/Projects/Unnamed workspace'];
  await app.install();
  await app.goto();
  await expect(page.getByRole('button', { name: 'Unnamed workspace', exact: true })).toBeVisible();
  const launchMode = page.locator('button.composer-worktree');
  await expect(launchMode).toHaveText('Local');
  await launchMode.click();
  await expect(launchMode).toHaveText('Worktree');
  expect(app.pageErrors).toEqual([]);
});

test('project history retries a failed directory snapshot without losing its destination', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('workspace.list', 'Directory unavailable');
  await app.install();
  await page.goto('/device/device-a/chat/session/session-1');
  const notice = page.locator('.navigation-notice');
  await expect(notice).toContainText('Directory unavailable');
  expect(app.requests.some(request => request.method === 'session.load')).toBe(false);
  app.rpcErrors.delete('workspace.list');
  await notice.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await expect(page).toHaveURL(/chat\/session\/session-1$/);
  expect(app.pageErrors).toEqual([]);
});
