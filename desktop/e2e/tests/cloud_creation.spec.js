import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

const creations = cloud => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions');

for (const desktop of [false, true]) {
  test(`${desktop ? 'desktop' : 'browser'} new Cloud keeps old conversation actions out of its empty page`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop });
    await cloud.install(); await cloud.goto(); await cloud.open();
    await cloud.create();
    await expect(page.locator('main h1')).toHaveText('New chat');
    await expect(page.locator('.conversation-open[aria-current="true"]')).toHaveCount(0);
    await expect(page.locator('main .topbar .panel-toggle')).toHaveCount(0);
    await expect(cloud.row(sessionC)).toHaveCount(0);
    await page.locator('#task').fill('Unsubmitted Cloud draft');
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
    expect(creations(cloud)).toHaveLength(0);
  });
}

test('first Cloud creation locks duplicate submissions and sends the captured message once', async ({ page }) => {
  const cloud = new CloudHarness(page);
  let finish;
  cloud.pauseCreate = new Promise(resolve => { finish = resolve; });
  await cloud.install(); await cloud.goto(); await cloud.create();
  await page.locator('#task').fill('Create then send');
  await page.locator('#task').press('Enter');
  await expect.poll(() => creations(cloud).length).toBe(1);
  await expect(page.locator('#task')).toBeDisabled();
  await expect(page.locator('.section-primary-action[aria-label="New chat"]')).toBeDisabled();
  expect(cloud.postCount).toBe(0);
  finish();
  await expect(cloud.row(sessionC)).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('#task')).toHaveValue('');
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.postCount).toBe(1);
  const actions = cloud.requests.filter(request => request.method === 'POST');
  expect(actions.map(request => request.path)).toEqual(['/v1/sessions', `/v1/sessions/${sessionC}/commands`]);
  expect(JSON.parse(actions[1].body)).toEqual({ command: { command: 'prompt', content: 'Create then send' } });
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
  await (await history).finished();
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

test('first Cloud admission preserves later typing in the shared composer', async ({ page }) => {
  const cloud = new CloudHarness(page);
  let admit;
  cloud.pauseSend = new Promise(resolve => { admit = resolve; });
  await cloud.install(); await cloud.goto(); await cloud.create();
  await page.locator('#task').fill('Initial submission');
  await page.locator('#task').press('Enter');
  await expect(cloud.row(sessionC)).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Later typing');
  admit();
  await expect(page.locator('#transcript').getByText('Initial submission', { exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Later typing');
  await cloud.open(sessionB);
  await cloud.open(sessionC);
  await expect(page.locator('#task')).toHaveValue('Later typing');
  expect(creations(cloud)).toHaveLength(1);
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
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect(heading).toHaveText('New chat');
  await expect(page.locator('#task')).toHaveValue('Keep the Cloud blank draft');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
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
