import { test, expect } from './support/test.js';
import { LocalConsoleHarness, browserAccount } from './support/local_console_harness.js';
import { sessionA } from './support/cloud_harness.js';

async function openLocalWork(page, local) {
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await local.device.openSession();
  await expect(page.locator('#task')).toBeEnabled();
}

const storedAccount = page => page.evaluate(() => JSON.parse(localStorage.getItem('seekmoon.account.v1')));

test('local Console shows account storage failures and retries without reconnecting the local host', async ({ page, baseURL }, testInfo) => {
  const local = new LocalConsoleHarness(page, baseURL);
  await local.install();
  await page.addInitScript(() => {
    window.accountStorageUnavailable = true;
    const original = Storage.prototype.getItem;
    Storage.prototype.getItem = function(key) {
      if (window.accountStorageUnavailable && key === 'seekmoon.account.v1') {
        throw new Error('Fixture storage unavailable');
      }
      return original.call(this, key);
    };
  });
  await local.goto();
  const home = page.locator('.cloud-home');
  await expect(home.getByText(/Could not read account storage:/)).toBeVisible();
  await expect(home.getByRole('button', { name: 'Sign in with GitHub' })).toHaveCount(0);
  await expect.poll(() => local.localSockets.length).toBe(1);
  await page.screenshot({ path: testInfo.outputPath('account-storage-error.png') });
  await page.evaluate(() => { window.accountStorageUnavailable = false; });
  await home.getByRole('button', { name: 'Try again', exact: true }).click();
  await expect(home.getByText(/Could not read account storage:/)).toHaveCount(0);
  await expect(home.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  await openLocalWork(page, local);
  expect(local.localSockets).toHaveLength(1);
  expect(local.device.pageErrors).toEqual([]);
});

test('local Console signs in independently and keeps its account across reload and Desktop auth changes', async ({ page, baseURL }) => {
  const local = new LocalConsoleHarness(page, baseURL);
  await local.install();
  await local.goto();
  await expect(page.locator('.cloud-home').getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  await openLocalWork(page, local);
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(local.row(sessionA)).toBeVisible();
  expect(local.localRequests.some(request => request.path === '/v2/auth/login')).toBe(true);
  expect(await storedAccount(page)).toEqual(browserAccount);
  await page.reload();
  await expect(local.row(sessionA)).toBeVisible();
  await expect.poll(() => local.localSockets.length).toBeGreaterThan(0);
  local.device.socket.send(JSON.stringify({ jsonrpc: '2.0', method: 'auth.changed', params: {
    connected: true, user: { login: 'different-desktop-user', avatar_url: '' },
  } }));
  await local.open();
  await page.locator('#task').fill('Cloud with my independent browser account');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => local.postCount).toBe(1);
  const requests = local.requests.filter(request => request.side === 'cloud');
  expect(requests.every(request => request.headers.authorization === `Bearer ${browserAccount.token}`)).toBe(true);
  await expect(page.locator('#transcript')).toContainText('您好 🌙 — calculation complete.');
  expect(await storedAccount(page)).toEqual(browserAccount);
  expect(local.localRequests.filter(request => request.path.startsWith('/v1/')).every(request => !request.headers.authorization)).toBe(true);
  expect(local.localSockets.every(url => new URL(url).search === '')).toBe(true);
  expect(local.device.ticketRequests).toEqual([]);
  expect(local.device.pageErrors).toEqual([]);
});

test('local Console logout clears only Cloud account state and preserves local work', async ({ page, baseURL }) => {
  const local = new LocalConsoleHarness(page, baseURL);
  await local.install();
  await local.goto();
  await page.locator('.cloud-home').getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(local.row(sessionA)).toBeVisible();
  await openLocalWork(page, local);
  await page.locator('#task').fill('Keep this local draft');
  const sockets = local.localSockets.length;
  local.logoutStatus = 503;
  await page.locator('.console-account').getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByText('the relay answered HTTP 503', { exact: true })).toBeVisible();
  expect(await storedAccount(page)).toEqual(browserAccount);
  local.logoutStatus = 204;
  await page.locator('.console-account').getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.locator('.console-account')).toHaveCount(0);
  expect(await storedAccount(page)).toBeNull();
  await expect(page.locator('#task')).toHaveValue('Keep this local draft');
  expect(local.localSockets).toHaveLength(sockets);
  expect(local.localRequests.filter(request => request.path === '/v2/auth/logout').every(request =>
    request.headers.authorization === `Bearer ${browserAccount.token}`)).toBe(true);
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await expect(local.row(sessionA)).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();
});

test('a fresh browser opens the local host directly without a Cloud account or cookie', async ({ page, baseURL }) => {
  const local = new LocalConsoleHarness(page, baseURL);
  await local.install();
  await page.context().clearCookies();
  await local.goto('/device/host/chat');
  await openLocalWork(page, local);
  expect(await storedAccount(page)).toBeNull();
  expect(await page.context().cookies()).toEqual([]);
  await page.reload();
  await openLocalWork(page, local);
  expect(local.localSockets.length).toBeGreaterThan(0);
  expect(local.device.ticketRequests).toEqual([]);
  expect(local.device.pageErrors).toEqual([]);
});
