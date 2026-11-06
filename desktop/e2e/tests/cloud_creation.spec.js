import { test, expect } from './support/test.js';
import { CloudHarness, cloudOrigin, sessionA, sessionC } from './support/cloud_harness.js';

const creations = cloud => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions');

test('Cloud chat connection errors stay in the chat that triggered them', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  const message = 'Cloud is unreachable. Check your connection and try again.';
  const sidebar = page.locator('aside');
  const task = page.locator('#task');
  await cloud.install(); await cloud.goto();

  const history = url => url.origin === cloudOrigin && url.pathname === `/v1/sessions/${sessionA}/messages`;
  const disconnectHistory = route => route.request().method() === 'GET' ? route.abort('failed') : route.fallback();
  await page.route(history, disconnectHistory);
  await cloud.row(sessionA).click();
  await expect(page.locator('.conversation-load-state')).toContainText(message);
  await expect(sidebar).not.toContainText(message);
  await page.unroute(history, disconnectHistory);
  await page.getByRole('button', { name: 'Retry', exact: true }).click();

  const command = url => url.origin === cloudOrigin && url.pathname === `/v1/sessions/${sessionA}/commands`;
  const disconnectPost = route => route.request().method() === 'POST' ? route.abort('failed') : route.fallback();
  await page.route(command, disconnectPost);
  await task.fill('Keep this failed send');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript')).toContainText(message);
  await expect(sidebar).not.toContainText(message);
  await expect(task).toHaveValue('Keep this failed send');

  await cloud.create();
  await page.route(`${cloudOrigin}/v1/sessions`, disconnectPost);
  await task.fill('Keep this failed creation');
  await task.press('Enter');
  await expect(page.locator('#transcript')).toContainText(message);
  await expect(sidebar).not.toContainText(message);
  await expect(task).toHaveValue('Keep this failed creation');
  await page.unroute(`${cloudOrigin}/v1/sessions`, disconnectPost);
  await task.press('Enter');
  await expect(page.locator('#transcript')).toContainText('Keep this failed creation');
  await expect(page.locator('#transcript')).not.toContainText(message);
});

test('a first-send rejection preserves the input and retries the existing Cloud session', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.sendStatus = 503;
  cloud.sendErrorBody = 'server model credentials are not configured';
  await cloud.install(); await cloud.goto(); await cloud.create();
  let releaseHistory;
  cloud.pauseHistory = new Promise(resolve => { releaseHistory = resolve; });
  await page.locator('#task').fill('Keep this initial input');
  await page.locator('#task').press('Enter');
  await expect(page.getByRole('main')).toContainText('Cloud model credentials are not configured');
  const history = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === `/v1/sessions/${sessionC}/messages`);
  releaseHistory();
  expect((await history).status()).toBe(200);
  await expect(page.getByRole('main')).toContainText('Cloud model credentials are not configured');
  await expect(page.locator('#task')).toHaveValue('Keep this initial input');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  cloud.sendStatus = 202;
  await page.locator('#task').fill('Edited retry');
  await page.locator('#task').press('Enter');
  await expect(page.locator('#transcript').getByText('Edited retry', { exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('');
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.postCount).toBe(2);
});

test('Cloud blank stays selected across sidebar browsing, shortcuts and Settings above Work', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  const sidebar = name => page.getByRole('group', { name: 'Sidebar list' }).getByRole('button', { name, exact: true });
  const model = page.getByRole('button', { name: 'Model', exact: true });
  const heading = page.locator('main > .topbar h1');
  const shortcut = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta+N' : 'Control+N');
  await cloud.install(); await cloud.goto();
  await sidebar('Work').click();
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(page.locator('main > .topbar .topbar-workspace-label')).toHaveText('workspace');
  await sidebar('Chat').click(); await cloud.open();
  await sidebar('Work').click();
  await page.keyboard.press(shortcut);
  await expect(sidebar('Chat')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#task').fill('Keep the Cloud blank draft');
  await sidebar('Work').click();
  await expect(heading).toHaveText('New chat');
  await expect(model).toBeDisabled();
  await page.keyboard.press(shortcut);
  await expect(sidebar('Chat')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#task')).toHaveValue('Keep the Cloud blank draft');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Dismiss', exact: true }).click();
  await expect(heading).toHaveText('New chat');
  await expect(page.locator('#task')).toHaveValue('Keep the Cloud blank draft');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Dismiss', exact: true }).click();
  await sidebar('Work').click();
  await page.keyboard.press(shortcut);
  await expect(sidebar('Chat')).toHaveAttribute('aria-pressed', 'true');
  await expect(model).toBeDisabled();
  await expect(page.locator('#task')).toHaveValue('Keep the Cloud blank draft');
  expect(creations(cloud)).toHaveLength(0);
  await sidebar('Work').click();
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(model).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('');
  expect(cloud.device.pageErrors).toEqual([]);
});
