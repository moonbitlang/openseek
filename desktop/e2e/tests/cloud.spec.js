import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

for (const desktop of [false, true]) {

  test(`${desktop ? 'desktop' : 'browser'} creates Cloud on first send through the existing composer and unified account`, async ({ page, context }) => {
    const cloud = new CloudHarness(page, { desktop, cached: false });
    cloud.device.hostSettings.has_deepseek_key = false;
    await context.addCookies([{ name: 'session', value: 'fixture-account', url: authOrigin }]);
    await cloud.install();
    await cloud.goto();
    await cloud.create();
    await expect(page.getByRole('menuitem', { name: 'Local', exact: true })).toHaveCount(0);
    expect(cloud.device.requests.some(request => request.method === 'fs.create_unnamed_workspace')).toBe(false);
    expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
    await page.locator('#task').fill('Calculate 1 + 1');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(page.locator('#transcript').getByText('您好 🌙 — calculation complete.', { exact: true })).toHaveCount(1);
    await expect(page.locator('#task')).toHaveValue('');
    expect(cloud.exchangeCount).toBe(0);
    const send = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/commands'));
    expect(JSON.parse(send.body)).toEqual({ command: { command: 'prompt', content: 'Calculate 1 + 1' } });
    expect(cloud.hostRequests.filter(request => request.method === 'cloud.key')).toEqual([]);
    expect(send.headers.cookie).toBeUndefined();
    expect(send.headers.authorization).toMatch(/^Bearer ts_fixture-/);
    expect(cloud.requests.filter(request => request.path.startsWith('/v1/auth/cloud/'))).toEqual([]);
    expect(cloud.hostRequests.filter(request => request.method === 'cloud.authorize')).toEqual([]);
    expect(await page.evaluate(() => localStorage.getItem('seekmoon.cloud.token.v1'))).toBeNull();
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('Cloud list retry recovers after a network failure without resending or losing the draft', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.listOffline = true;
  await cloud.install();
  await page.goto(`${authOrigin}/console/index.html?device=device-a`);
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  const sidebar = page.locator('aside');
  await expect(sidebar.getByText('Couldn’t load chats', { exact: true })).toBeVisible();
  await cloud.create();
  const draft = page.locator('#task');
  await draft.fill('Keep this draft while reconnecting');
  const draftURL = page.url();

  cloud.listOffline = false;
  let release;
  cloud.pauseList = new Promise(resolve => { release = resolve; });
  const reads = () => cloud.requests.filter(request =>
    request.method === 'GET' && request.path === '/v1/sessions');
  const previousReads = reads().length;
  const retry = sidebar.getByRole('button', { name: 'Retry', exact: true });
  await retry.focus();
  await retry.press('Enter');
  try {
    await expect(sidebar).toContainText('Loading chats…');
    await expect(retry).toBeDisabled();
    await expect.poll(() => reads().length).toBe(previousReads + 1);
  } finally {
    release();
  }
  await expect(cloud.row(sessionA)).toBeVisible();
  await expect(retry).toHaveCount(0);
  await expect(page).toHaveURL(draftURL);
  await expect(draft).toHaveValue('Keep this draft while reconnecting');
  expect(reads().at(-1).headers.authorization).toBe('Bearer ts_fixture-123');
  expect(cloud.exchangeCount).toBe(0);
  expect(cloud.requests.filter(request => request.side === 'cloud' && request.method === 'POST')).toEqual([]);
});

test('browser account sign-out clears Cloud and never signs out the computer', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Account', exact: true }).click();
  const section = page.getByRole('region', { name: 'Account', exact: true });
  await section.getByRole('button', { name: 'Sign out', exact: true }).click();
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.cloud.token.v1'))).toBeNull();
  await expect(cloud.row(sessionA)).toBeHidden();
  expect(cloud.requests.filter(request => request.path === '/v2/auth/logout')).toHaveLength(1);
  expect(cloud.hostRequests.filter(request => request.method === 'auth.disconnect')).toEqual([]);
});

