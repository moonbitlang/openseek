import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

const sessionURL = id => `${authOrigin}/cloud/session/${id}`;
const creations = cloud => cloud.requests.filter(r => r.side === 'cloud' && r.path === '/v1/sessions' && r.method === 'POST');

test('Cloud home refresh is passive and first send promotes the draft URL to its session', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await page.goto(`${authOrigin}/cloud`);
  await expect(page.locator('.cloud-home')).toBeVisible();
  await expect(page.locator('.cloud-home button')).toHaveText('New chat');
  await page.reload();
  await expect(page.locator('.cloud-home button')).toHaveText('New chat');
  expect(creations(cloud)).toEqual([]);
  await page.screenshot({ path: testInfo.outputPath('cloud-home.png'), fullPage: true });
  await page.locator('.cloud-home button').click();
  await expect(page).toHaveURL(new RegExp(`^${authOrigin}/cloud/draft/[^/]+$`));
  expect(creations(cloud)).toEqual([]);
  await page.locator('#task').fill('First Cloud message');
  await page.locator('#task').press('Enter');
  await expect(page).toHaveURL(sessionURL(sessionC));
  expect(creations(cloud)).toHaveLength(1);
  await page.goBack();
  await expect(page).toHaveURL(`${authOrigin}/cloud`);
  await expect(page.locator('.cloud-home')).toBeVisible();
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud session direct access and refresh do not depend on catalog membership or a device', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.sessionIds = [];
  cloud.histories.set(sessionA, { messages: [{ id: 1, task_id: 'old-task', kind: 'assistant_message', data: { content: 'Deep linked history' }, created_at: 1000 }], generating: false, outcome: null });
  await cloud.install();
  await page.goto(sessionURL(sessionA));
  await expect(page.locator('#transcript')).toContainText('Deep linked history');
  await expect(page.locator('#task')).toBeDisabled();
  cloud.sessionIds = [sessionA];
  await page.reload();
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Temporary draft');
  await page.reload();
  await expect(page.locator('#transcript')).toContainText('Deep linked history');
  await expect(page.locator('#task')).toHaveValue('');
  expect(creations(cloud)).toEqual([]);
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud login returns to the exact deep link without creating a session', async ({ page }) => {
  const cloud = new CloudHarness(page, { cached: false });
  await cloud.install();
  const destination = `${sessionURL(sessionA)}?source=shared`;
  await page.goto(destination);
  const login = page.locator('.cloud-home').getByRole('button', { name: /Sign in.*GitHub/i });
  await expect(login).toBeVisible();
  const request = page.waitForRequest(request => new URL(request.url()).pathname === '/v2/auth/login');
  await login.click();
  expect(new URL((await request).url()).searchParams.get('return_to')).toBe(`/cloud/session/${sessionA}?source=shared`);
  await expect(page).toHaveURL(destination);
  await expect(page.locator('#task')).toBeVisible();
  expect(creations(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const status of [403, 404, 503]) {
  test(`Cloud deep-link HTTP ${status} stays distinct and never creates a replacement`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    cloud.historyStatus = status;
    await cloud.install();
    await page.goto(sessionURL(sessionA));
    if (status === 404) {
      await expect(page.locator('.navigation-notice')).toContainText('no longer exists');
    } else {
      await expect(page.locator('.conversation-load-state')).toContainText(`HTTP ${status}`);
      cloud.historyStatus = 200;
      await page.getByRole('button', { name: 'Retry', exact: true }).click();
      await expect(page.locator('#task')).toBeVisible();
    }
    await expect(page).toHaveURL(sessionURL(sessionA));
    expect(creations(cloud)).toEqual([]);
    expect(cloud.device.ticketRequests).toHaveLength(0);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('late Cloud history cannot replace a newer URL selection', async ({ page }) => {
  const cloud = new CloudHarness(page);
  let release;
  cloud.pauseHistory = new Promise(resolve => { release = resolve; });
  await cloud.install();
  await page.goto(sessionURL(sessionA));
  await expect.poll(() => cloud.requests.some(r => r.path === `/v1/sessions/${sessionA}/messages`)).toBe(true);
  cloud.pauseHistory = null;
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await cloud.open(sessionB);
  release();
  await expect(page).toHaveURL(sessionURL(sessionB));
  await expect(page.locator('main h1')).toHaveText('Cloud fixture B');
  expect(creations(cloud)).toEqual([]);
});

test('malformed Cloud destinations show invalid route rather than creating a session', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await page.goto(`${authOrigin}/cloud/session/extra/path`);
  await expect(page.locator('.navigation-notice')).toContainText('address is invalid');
  expect(creations(cloud)).toEqual([]);
});


test('Cloud landing remains selected while a retained device connects', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await page.goto(`${authOrigin}/cloud?device=device-a`);
  await expect(page.locator('.cloud-home')).toBeVisible();
  await expect.poll(() => cloud.device.requests.some(request => request.method === 'session.list')).toBe(true);
  await expect(page.locator('.cloud-home')).toBeVisible();
  await expect(page.locator('#task')).toHaveCount(0);
  expect(creations(cloud)).toEqual([]);
});

test('a Cloud URL is reauthorized after account change without retaining the old transcript', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, { messages: [{ id: 1, task_id: 'private-task', kind: 'assistant_message', data: { content: 'First account history' }, created_at: 1000 }], generating: false, outcome: null });
  await cloud.install();
  await page.goto(sessionURL(sessionA));
  await expect(page.locator('#transcript')).toContainText('First account history');
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.locator('.cloud-home button')).toHaveText('Sign in with GitHub');
  await expect(page.getByText('First account history', { exact: true })).toHaveCount(0);
  cloud.userId = '456';
  cloud.historyStatus = 403;
  await page.locator('.cloud-home button').click();
  await expect(page.locator('.conversation-load-state')).toContainText('HTTP 403');
  await expect(page).toHaveURL(sessionURL(sessionA));
  await expect(page.getByText('First account history', { exact: true })).toHaveCount(0);
  expect(cloud.requests.filter(r => r.path === `/v1/sessions/${sessionA}/messages`).at(-1).headers.authorization).toBe('Bearer ts_fixture-456');
  expect(creations(cloud)).toEqual([]);
});

for (const archived of [false, true]) {
  test(`Cloud direct link waits for delayed ${archived ? 'archived' : 'live'} metadata before enabling editing`, async ({ page }) => {
    const cloud = new CloudHarness(page);
    if (archived) cloud.archived.add(sessionA);
    cloud.histories.set(sessionA, { messages: [{ task_id: 'old', kind: 'assistant_message', data: { content: 'Readable before metadata' }, created_at: 1000 }], generating: false });
    let release;
    cloud.pauseList = new Promise(resolve => { release = resolve; });
    await cloud.install();
    await page.goto(sessionURL(sessionA));
    await expect(page.locator('#transcript')).toContainText('Readable before metadata');
    await expect(page.locator('#task')).toBeDisabled();
    release();
    if (archived) {
      await expect(page.locator('.archived-read-only')).toBeVisible();
      await expect(page.locator('#task')).toHaveCount(0);
    } else {
      await expect(page.locator('#task')).toBeEnabled();
    }
    expect(creations(cloud)).toEqual([]);
  });
}

test('Cloud direct link keeps history readable but editing disabled after catalog failure', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.listStatus = 503;
  cloud.histories.set(sessionA, { messages: [{ task_id: 'old', kind: 'assistant_message', data: { content: 'Readable despite metadata failure' }, created_at: 1000 }], generating: false });
  await cloud.install();
  await page.goto(sessionURL(sessionA));
  await expect(page.locator('#transcript')).toContainText('Readable despite metadata failure');
  await expect(page.locator('#task')).toBeDisabled();
  await expect(page.getByText('Cloud answered HTTP 503. Try again.', { exact: true })).toBeVisible();
  expect(creations(cloud)).toEqual([]);
});
