import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

const root = '/Users/test/Library/Application Support/SeekMoon/workspaces';

function localHistory(app) {
  app.workspaces = ['/workspace', `${root}/history`];
  app.liveSessions = [{ id: 'legacy-chat', title: 'Legacy local chat', updated_at_ms: 100 }];
  app.sessionGroups = sessions => ({ groups: [{
    workspace: `${root}/history`, name: 'Unnamed workspace', session_root: `${root}/history/.openseek`, error: '', sessions,
  }] });
}

for (const legacy of [false, true]) {
  test(`Chat signs in and opens conversations directly (retired history=${legacy})`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop: true, cached: false });
    if (legacy) localHistory(cloud.device);
    await cloud.install();
    await cloud.goto();
    const hint = page.locator('[id="placeholder:cloud-sign-in"]');
    await expect(hint).toBeVisible();
    await page.locator('[id="placeholder:cloud-sign-in:action"]').click();
    await cloud.open();
    await expect(hint).toHaveCount(0);
    await expect(page.locator('#task')).toBeVisible();
    await expect(page.locator('aside .section-label')).toHaveText(['Chats']);
    const row = cloud.row(sessionA);
    await row.hover();
    await cloud.rowContainer(sessionA).locator('[id$=":actions-trigger"]').click();
    await page.locator('[role="menuitem"][data-action="archive"]:visible').click();
    await expect(row).toHaveCount(0);
    await cloud.openArchived(sessionA);
    await expect(page.locator('.archived-read-only-text')).toBeVisible();
    if (legacy) {
      await page.locator('#sidebar-work-mode').click();
      await expect(cloud.device.projectControl('/workspace', 'disclosure')).toBeVisible();
      expect(cloud.device.workspaces).toContain(`${root}/history`);
      expect(cloud.device.liveSessions).toHaveLength(1);
    }
    expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('an empty Chat list starts a draft without creating a session', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  cloud.sessionIds = [];
  await cloud.install();
  await page.goto('https://openseek-api.moonbitlang.cn/console/index.html?device=device-a');
  await page.locator('#sidebar-chat-mode').click();
  await expect.poll(() => cloud.requests.some(request => request.method === 'GET' && request.path === '/v1/sessions')).toBe(true);
  await cloud.create();
  await page.locator('#task').fill('An unsent chat draft');
  expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a project draft survives Chat navigation and account sign-out', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  await cloud.install();
  await cloud.goto();
  await page.locator('#sidebar-work-mode').click();
  await cloud.device.openSession();
  await page.locator('#task').fill('Keep this project draft');
  await page.locator('#sidebar-chat-mode').click();
  await cloud.open();
  await page.locator('#sidebar-settings').click();
  await page.locator('#settings-sign-out').click();
  await page.locator('#management-dialog')
    .locator('[data-slot="dialog-close"]').click();
  await page.locator('#sidebar-work-mode').click();
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
  expect(app.pageErrors).toEqual([]);
});

test('a user project named Unnamed workspace remains a project', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/Users/test/Projects/Unnamed workspace'];
  await app.install();
  await app.goto();
  await expect(app.projectControl(app.workspaces[0], 'disclosure')).toBeVisible();
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
  await notice.locator('#navigation-retry').click();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await expect(page).toHaveURL(/chat\/session\/session-1$/);
  expect(app.pageErrors).toEqual([]);
});
