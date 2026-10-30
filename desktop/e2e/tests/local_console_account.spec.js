import { test, expect } from '@playwright/test';
import { LocalConsoleHarness, localAccount } from './support/local_console_harness.js';
import { sessionA, sessionB } from './support/cloud_harness.js';

const staleAccount = localAccount('stale-browser');
const sessionReads = local => local.localRequests.filter(request => request.path === '/v1/auth/session');
const cloudRequests = local => local.requests.filter(request => request.side === 'cloud');

async function expectLocalHost(page, local) {
  await expect.poll(() => local.localSockets.length).toBeGreaterThan(0);
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await local.device.openSession();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await expect(page.locator('#task')).toBeEnabled();
}

async function expectNoStoredAccount(page) {
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
}

function expectOnlyLocalHostTransport(local) {
  expect(local.localRequests.some(request => request.path === '/v1/devices')).toBe(true);
  expect(local.localSockets.every(url => new URL(url).pathname === '/v1/devices/host/ws')).toBe(true);
  expect(local.localSockets.every(url => new URL(url).search === '')).toBe(true);
  expect(local.device.ticketRequests).toEqual([]);
  expect(local.requests.filter(request => request.side === 'api')).toEqual([]);
  expect(local.unexpectedRequests).toEqual([]);
  expect(local.device.pageErrors).toEqual([]);
}

test('local Console inherits the Desktop account for Cloud while keeping its launch-authorized host', async ({ page, baseURL }) => {
  const account = localAccount();
  const local = new LocalConsoleHarness(page, baseURL, account);
  await local.install({ staleAccount });
  await local.goto('/cloud');
  await expect(local.row(sessionA)).toBeVisible();
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(0);
  await local.open();
  await page.locator('#task').fill('Cloud through the Desktop account');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => local.postCount).toBe(1);
  const prompt = cloudRequests(local).find(request => request.method === 'POST' && request.path.endsWith('/commands'));
  expect(prompt.headers.authorization).toBe(`Bearer ${account.token}`);
  expect(cloudRequests(local).every(request => request.headers.authorization === `Bearer ${account.token}`)).toBe(true);
  expect(sessionReads(local).every(request => request.headers.authorization === undefined)).toBe(true);
  expect(sessionReads(local).every(request => request.headers.cookie.includes(`${local.cookieName}=fixture-launch-session`))).toBe(true);
  expect(local.document).toContain('<meta name="seekmoon-local-console" />');
  expect(local.document).not.toContain(account.token);
  expect(local.document).not.toContain(staleAccount.token);
  await expectNoStoredAccount(page);
  await expectLocalHost(page, local);
  // /cloud carries no device id in its URL. A full reload must retain host.
  await local.goto('/cloud');
  await page.reload();
  await expect(local.row(sessionA)).toBeVisible();
  await expectLocalHost(page, local);
  await expectNoStoredAccount(page);
  expectOnlyLocalHostTransport(local);
});

test('a signed-out Desktop keeps local Work usable and asks for Desktop sign-in before Cloud', async ({ page, baseURL }) => {
  const local = new LocalConsoleHarness(page, baseURL, null);
  await local.install({ staleAccount });
  await local.goto('/device/host/chat');
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(0);
  await expectLocalHost(page, local);
  await page.locator('#task').fill('Local work without an account');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => local.device.requests.filter(request => request.method === 'agent.start').length).toBe(1);
  await local.goto('/cloud');
  const home = page.locator('.cloud-home');
  await expect(home).toBeVisible();
  await expect(home.getByRole('button', { name: 'New chat', exact: true })).toHaveCount(0);
  // This must explain the account owner without starting a browser OAuth flow.
  await expect(page.getByText('Sign in to Desktop, then refresh to use Cloud.', { exact: true }).first()).toBeVisible();
  expect(cloudRequests(local)).toEqual([]);
  await expectNoStoredAccount(page);
  await expectLocalHost(page, local);
  expectOnlyLocalHostTransport(local);
});

test('local Console Refresh and reload replace the inherited account without retaining old Cloud state or browser tokens', async ({ page, baseURL }) => {
  const alice = localAccount('alice');
  const bob = localAccount('bob');
  const local = new LocalConsoleHarness(page, baseURL, alice);
  local.histories.set(sessionA, { generating: false, outcome: null, messages: [
    { task_id: 'alice-private', kind: 'assistant_message', data: { content: 'Private Alice history' }, created_at: 1000 },
  ] });
  await local.install({ staleAccount });
  await local.goto('/cloud');
  await local.open();
  await expect(page.locator('#transcript')).toContainText('Private Alice history');
  const aliceRow = local.row(sessionA);
  await page.locator('#task').fill('Private Alice draft');
  const beforeRefresh = sessionReads(local).length;
  local.setAccount(bob);
  local.sessionIds = [sessionB];
  local.histories.set(sessionA, { messages: [], generating: false, outcome: null });
  await page.evaluate(account => localStorage.setItem('seekmoon.account.v1', JSON.stringify(account)), staleAccount);
  await page.locator('.console-account').getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(beforeRefresh);
  await expect(page.getByText('Private Alice history', { exact: true })).toHaveCount(0);
  await expect(aliceRow).toHaveCount(0);
  await expect(local.row(sessionB)).toBeVisible();
  await local.open(sessionB);
  await expect(page.locator('#task')).toHaveValue('');
  const beforeBobSend = local.requests.length;
  await page.locator('#task').fill('Bob sends with the current Desktop account');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => local.postCount).toBe(1);
  const switched = local.requests.slice(beforeBobSend).filter(request => request.side === 'cloud');
  expect(switched.some(request => request.headers.authorization === `Bearer ${bob.token}`)).toBe(true);
  expect(switched.every(request => request.headers.authorization !== `Bearer ${alice.token}` && request.headers.authorization !== `Bearer ${staleAccount.token}`)).toBe(true);
  await expectNoStoredAccount(page);
  await expect(page.locator('#transcript')).toContainText('您好 🌙 — calculation complete.');
  await expect(page.getByRole('button', { name: 'Stop', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('');

  local.setAccount(null);
  await page.evaluate(account => localStorage.setItem('seekmoon.account.v1', JSON.stringify(account)), staleAccount);
  const beforeReload = sessionReads(local).length;
  const beforeSignedOut = cloudRequests(local).length;
  await page.reload();
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(beforeReload);
  await expect(page.getByText('Private Alice history', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Cloud fixture B', { exact: true })).toHaveCount(0);
  expect(cloudRequests(local).length).toBe(beforeSignedOut);
  await expectNoStoredAccount(page);
  await expectLocalHost(page, local);
  expectOnlyLocalHostTransport(local);
});


test('local Console follows Desktop auth.changed events without replacing its connected host or local draft', async ({ page, baseURL }) => {
  const alice = localAccount('event-alice');
  const local = new LocalConsoleHarness(page, baseURL, null);
  await local.install({ staleAccount });
  await local.goto('/device/host/chat');
  await expectLocalHost(page, local);
  await page.locator('#task').fill('Unsent local draft survives Desktop account changes');
  const socket = local.device.socket;
  const socketCount = local.localSockets.length;
  const beforeSignIn = sessionReads(local).length;

  // Changing the endpoint alone is insufficient: the actual host WS event
  // must drive the automatic handoff, without Refresh or page navigation.
  local.accountChanged(alice);
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(beforeSignIn);
  await expect(page.locator('.console-login')).toHaveText('@event-alice');
  await expect(page.locator('#task')).toHaveValue('Unsent local draft survives Desktop account changes');
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toHaveAttribute('aria-current', 'true');
  expect(local.device.socket).toBe(socket);
  expect(local.localSockets).toHaveLength(socketCount);
  await expectNoStoredAccount(page);

  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await local.open();
  const accountRow = local.row(sessionA);
  await page.locator('#task').fill('Cloud draft owned by the signed-in account');
  const beforeSignOut = sessionReads(local).length;
  local.accountChanged(null);
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(beforeSignOut);
  await expect(accountRow).toHaveCount(0);
  await expect(page.getByText('Sign in to Desktop, then refresh to use Cloud.', { exact: true }).first()).toBeVisible();
  await expect(page.locator('.console-login')).toHaveCount(0);
  expect(local.device.socket).toBe(socket);
  expect(local.localSockets).toHaveLength(socketCount);
  expect(local.hostNotifications).toEqual([
    { jsonrpc: '2.0', method: 'auth.changed', params: { connected: true } },
    { jsonrpc: '2.0', method: 'auth.changed', params: { connected: false } },
  ]);
  await expectNoStoredAccount(page);
  await expectLocalHost(page, local);
  await expect(page.locator('#task')).toHaveValue('Unsent local draft survives Desktop account changes');
  expectOnlyLocalHostTransport(local);
});


test('local Console reloads its current Cloud session when Desktop rotates a token for the same account', async ({ page, baseURL }) => {
  const original = localAccount('rotating-account');
  const rotated = { ...original, token: 'ts_local-fixture-rotated-current-account' };
  const local = new LocalConsoleHarness(page, baseURL, original);
  local.histories.set(sessionA, { generating: false, outcome: null, messages: [
    { task_id: 'retained-cloud-history', kind: 'assistant_message', data: { content: 'Current Cloud session history' }, created_at: 1000 },
  ] });
  await local.install(); await local.goto('/cloud'); await local.open();
  await expect(page.locator('#transcript')).toContainText('Current Cloud session history');
  await expect.poll(() => local.localSockets.length).toBeGreaterThan(0);
  const socket = local.device.socket;
  const socketCount = local.localSockets.length;
  const currentURL = page.url();
  const beforeRotation = local.requests.length;
  const beforeSessionRead = sessionReads(local).length;

  local.accountChanged(rotated);
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(beforeSessionRead);
  await expect.poll(() => local.requests.slice(beforeRotation).filter(request =>
    request.side === 'cloud' && request.path === `/v1/sessions/${sessionA}/messages` &&
    request.headers.authorization === `Bearer ${rotated.token}`).length).toBeGreaterThan(0);
  await expect(page).toHaveURL(currentURL);
  await expect(local.row(sessionA)).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('#transcript')).toContainText('Current Cloud session history');
  await expect(page.locator('#task')).toBeEnabled();
  const beforeSend = local.requests.length;
  await page.locator('#task').fill('Send after the same-account token refresh');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => local.postCount).toBe(1);
  const prompt = local.requests.slice(beforeSend).find(request =>
    request.side === 'cloud' && request.method === 'POST' && request.path.endsWith('/commands'));
  expect(prompt.headers.authorization).toBe(`Bearer ${rotated.token}`);
  await expect(page.locator('#transcript')).toContainText('您好 🌙 — calculation complete.');
  await expect(page.getByRole('button', { name: 'Stop', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('');
  expect(local.device.socket).toBe(socket);
  expect(local.localSockets).toHaveLength(socketCount);
  await expectNoStoredAccount(page);
  await expectLocalHost(page, local);
  expectOnlyLocalHostTransport(local);
});

test('an unauthorized local Console browser requests a Desktop launch instead of treating the account as signed out', async ({ page, baseURL }) => {
  const local = new LocalConsoleHarness(page, baseURL, localAccount());
  await local.install({ staleAccount });
  await page.context().clearCookies();
  await local.goto('/device/host/chat');
  await expect(page.getByText('Open the Local Console from Desktop to authorize this browser.', { exact: true }).first()).toBeVisible();
  await expect(page.getByText('Sign in to Desktop, then refresh to use Cloud.', { exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toHaveCount(0);
  expect(local.localSockets).toEqual([]);
  expect(local.device.ticketRequests).toEqual([]);
  expect(cloudRequests(local)).toEqual([]);
  expect(local.requests.filter(request => request.side === 'api')).toEqual([]);
  expect(sessionReads(local).length).toBeGreaterThan(0);
  expect(sessionReads(local).every(request => !request.headers.cookie?.includes(`${local.cookieName}=fixture-launch-session`))).toBe(true);
  expect(local.unexpectedRequests).toEqual([]);
  expect(local.device.pageErrors).toEqual([]);
  await expectNoStoredAccount(page);
});


test('a failed Desktop account read preserves local Work and shows a retryable Cloud error', async ({ page, baseURL }) => {
  const account = localAccount('recoverable-account');
  const local = new LocalConsoleHarness(page, baseURL, account);
  local.sessionStatus = 503;
  await local.install({ staleAccount }); await local.goto('/cloud');
  const home = page.locator('.cloud-home');
  await expect(home.getByRole('alert')).toHaveText('the Desktop account check answered HTTP 503');
  await expect(home.getByRole('button', { name: 'Refresh', exact: true })).toBeVisible();
  await expect(home.getByText('Sign in to Desktop, then refresh to use Cloud.', { exact: true })).toHaveCount(0);
  expect(cloudRequests(local)).toEqual([]);
  await expectLocalHost(page, local);
  expect(local.localRequests.some(request => request.path === '/v1/auth/me')).toBe(true);

  const beforeReloadSockets = local.localSockets.length;
  await local.goto('/cloud');
  await expect(home.getByRole('alert')).toContainText('HTTP 503');
  await expect.poll(() => local.localSockets.length).toBeGreaterThan(beforeReloadSockets);
  const socket = local.device.socket;
  const sockets = local.localSockets.length;
  const beforeRetry = sessionReads(local).length;
  local.sessionStatus = 200;
  await home.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect.poll(() => sessionReads(local).length).toBeGreaterThan(beforeRetry);
  await expect(local.row(sessionA)).toBeVisible();
  await expect(home.getByRole('alert')).toHaveCount(0);
  await local.open();
  await page.locator('#task').fill('Cloud after Desktop account recovery');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => local.postCount).toBe(1);
  const prompt = cloudRequests(local).find(request => request.method === 'POST' && request.path.endsWith('/commands'));
  expect(prompt.headers.authorization).toBe(`Bearer ${account.token}`);
  await expect(page.locator('#transcript')).toContainText('您好 🌙 — calculation complete.');
  await expect(page.getByRole('button', { name: 'Stop', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('');
  expect(local.device.socket).toBe(socket);
  expect(local.localSockets).toHaveLength(sockets);
  await expectNoStoredAccount(page);
  expectOnlyLocalHostTransport(local);
});
