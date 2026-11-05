import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

const sessionURL = id => `${authOrigin}/cloud/session/${id}`;
const creations = cloud => cloud.requests.filter(r => r.side === 'cloud' && r.path === '/v1/sessions' && r.method === 'POST');

test('Cloud home opens the composer and creates a session only on first send', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await page.goto(`${authOrigin}/cloud`);
  const composer = page.locator('#task');
  await expect(composer).toBeEnabled();
  await expect(page).toHaveURL(`${authOrigin}/cloud`);
  await page.reload();
  await expect(composer).toBeEnabled();
  await expect(page).toHaveURL(`${authOrigin}/cloud`);
  expect(creations(cloud)).toEqual([]);
  await page.screenshot({ path: testInfo.outputPath('cloud-home.png'), fullPage: true });
  await composer.fill('First Cloud message');
  expect(creations(cloud)).toEqual([]);
  await composer.press('Enter');
  await expect(page).toHaveURL(sessionURL(sessionC));
  expect(creations(cloud)).toHaveLength(1);
  await page.goBack();
  await expect(page).toHaveURL(`${authOrigin}/cloud`);
  await expect(composer).toBeEnabled();
  await expect(composer).toHaveValue('');
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

test('Cloud home opens the composer after sign-in', async ({ page }) => {
  const cloud = new CloudHarness(page, { cached: false });
  await cloud.install();
  await page.goto(`${authOrigin}/cloud`);
  const login = page.locator('main').getByRole('button', { name: 'Sign in with GitHub' });
  await expect(login).toBeVisible();
  await expect(page.locator('#task')).toHaveCount(0);
  await login.click();
  await expect(page.locator('#task')).toBeEnabled();
  await expect(page).toHaveURL(`${authOrigin}/cloud`);
  expect(creations(cloud)).toEqual([]);
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

// Statuses other than 404 share one retryable failure path.
for (const status of [404, 503]) {
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

test('Cloud revisits show cached history during conditional reads and pick up another device’s message', async ({ page, context }) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, {
    messages: [{ task_id: 'original', kind: 'user', data: { content: 'Cached Cloud message' }, created_at: 1000 }],
    generating: false,
  });
  await cloud.install();
  await cloud.goto();
  const historyPath = `/v1/sessions/${sessionA}/messages`;
  const reads = () => cloud.requests.filter(r => r.method === 'GET' && r.path === historyPath);
  const historyResponse = () => page.waitForResponse(r => r.request().method() === 'GET' && new URL(r.url()).pathname.endsWith(historyPath));
  const transcript = page.locator('#transcript');
  const composer = page.locator('#task');
  const first = historyResponse();
  await cloud.open(sessionA);
  const firstTag = (await first).headers().etag;
  expect(firstTag).toBeTruthy();
  await expect(transcript).toContainText('Cached Cloud message');
  await cloud.open(sessionB);

  let release;
  cloud.pauseHistory = new Promise(resolve => { release = resolve; });
  const revalidated = historyResponse();
  try {
    await cloud.open(sessionA);
    await expect(transcript).toContainText('Cached Cloud message');
    await composer.fill('Keep this local draft');
    await expect(page.locator('#send')).toBeEnabled();
    await expect.poll(() => reads().length).toBe(2);
    await cloud.open(sessionB);
    await cloud.open(sessionA);
    await expect(transcript).toContainText('Cached Cloud message');
    await expect(composer).toHaveValue('Keep this local draft');
    await expect(page.locator('#send')).toBeEnabled();
    expect(reads()).toHaveLength(2);
    expect(reads()[1].headers['if-none-match']).toBe(firstTag);
  } finally {
    cloud.pauseHistory = null;
    release();
  }
  expect((await revalidated).status()).toBe(304);
  await cloud.open(sessionB);

  const otherPage = await context.newPage();
  try {
    const other = new CloudHarness(otherPage);
    other.histories = cloud.histories;
    await other.install();
    await other.goto();
    await other.open(sessionA);
    await otherPage.locator('#task').fill('Added from another device');
    await otherPage.locator('#send').click();
    await expect(otherPage.locator('#transcript')).toContainText('calculation complete.');
  } finally {
    await otherPage.close();
  }
  const changed = historyResponse();
  await cloud.open(sessionA);
  const updated = await changed;
  expect(updated.status()).toBe(200);
  expect(updated.headers().etag).not.toBe(firstTag);
  expect(reads()[2].headers['if-none-match']).toBe(firstTag);
  await expect(transcript).toContainText('Added from another device');
  await expect(composer).toHaveValue('Keep this local draft');
  await cloud.open(sessionB);
  const current = historyResponse();
  await cloud.open(sessionA);
  expect((await current).status()).toBe(304);
  expect(reads()[3].headers['if-none-match']).toBe(updated.headers().etag);
  await expect(transcript).toContainText('Added from another device');
});

test('Cloud cached revisits keep the draft editable while waiting for the first snapshot', async ({ page }) => {
  const cloud = new CloudHarness(page);
  const path = `/v1/sessions/${sessionA}/events`;
  const observations = () => cloud.requests.filter(r => r.path === path);
  await cloud.install();
  await cloud.goto();
  await cloud.open(sessionA);
  const task = page.locator('#task');
  await task.fill('Keep this prompt');
  await expect(page.locator('#send')).toBeEnabled();
  await cloud.open(sessionB);

  let release;
  cloud.pauseSessionEvents = new Promise(resolve => { release = resolve; });
  try {
    await cloud.open(sessionA);
    await expect.poll(() => observations().length).toBe(2);
    await expect(task).toBeEditable();
    await expect(task).toHaveValue('Keep this prompt');
    await expect(page.locator('#send')).toBeDisabled();
    await task.press('Enter');
    expect(cloud.postCount).toBe(0);
  } finally {
    cloud.pauseSessionEvents = null;
    release();
  }
  await expect(page.locator('#send')).toBeEnabled();
  await expect(task).toHaveValue('Keep this prompt');
});

test('Cloud catches up after an old conditional response spans an observation gap', async ({ page }) => {
  const cloud = new CloudHarness(page);
  const oldMessage = { task_id: 'original', kind: 'user', data: { content: 'Before switching' }, created_at: 1000 };
  const path = `/v1/sessions/${sessionA}/messages`;
  const reads = () => cloud.requests.filter(r => r.method === 'GET' && r.path === path);
  cloud.histories.set(sessionA, { messages: [oldMessage], generating: false });
  await cloud.install();
  await cloud.goto();
  await cloud.open(sessionA);
  const transcript = page.locator('#transcript');
  const task = page.locator('#task');
  await expect(transcript).toContainText('Before switching');
  await task.fill('Keep this draft across the gap');
  await expect(page.locator('#send')).toBeEnabled();
  await cloud.open(sessionB);

  let release;
  cloud.pauseHistory = new Promise(resolve => { release = resolve; });
  const unchanged = page.waitForResponse(r => new URL(r.url()).pathname === path && r.status() === 304);
  try {
    await cloud.open(sessionA);
    await expect(page.locator('#send')).toBeEnabled();
    await expect.poll(() => reads().length).toBe(2);
    await cloud.open(sessionB);
    cloud.histories.set(sessionA, {
      messages: [oldMessage, { task_id: 'remote', kind: 'user', data: { content: 'Added during the gap' }, created_at: 2000 }],
      generating: false,
    });
    const snapshot = cloud.controlState(sessionA);
    cloud.controlSnapshots.set(sessionA, { ...snapshot, task_id: 'remote', seq: snapshot.seq + 3 });

    await cloud.open(sessionA);
    await expect(page.locator('#send')).toBeEnabled();
    await expect(transcript).toContainText('Before switching');
    expect(reads()).toHaveLength(2);
  } finally {
    cloud.pauseHistory = null;
    release();
  }
  await unchanged;
  await expect(transcript).toContainText('Added during the gap');
  await expect(task).toHaveValue('Keep this draft across the gap');
  expect(reads()).toHaveLength(3);
  expect(reads()[2].headers['if-none-match']).toBe(reads()[1].headers['if-none-match']);
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
  let releaseRoster;
  const rosterReady = new Promise(resolve => { releaseRoster = resolve; });
  await page.route('**/v2/devices', async route => {
    await rosterReady;
    await route.fallback();
  });
  await page.goto(`${authOrigin}/cloud?device=device-a`);
  const composer = page.locator('#task');
  try {
    await expect(composer).toBeEnabled();
    await composer.fill('Cloud draft while the device connects');
  } finally {
    releaseRoster();
  }
  await expect.poll(() => cloud.device.requests.some(request => request.method === 'session.list')).toBe(true);
  await expect(composer).toBeEnabled();
  await expect(composer).toHaveValue('Cloud draft while the device connects');
  await expect(page.locator('main h1')).toHaveText('New chat');
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
  const reauthorized = cloud.requests.filter(r => r.path === `/v1/sessions/${sessionA}/messages`).at(-1);
  expect(reauthorized.headers.authorization).toBe('Bearer ts_fixture-456');
  expect(reauthorized.headers['if-none-match']).toBeUndefined();
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
  await expect(page.locator('aside').getByText('Couldn’t load chats', { exact: true })).toBeVisible();
  expect(creations(cloud)).toEqual([]);
});

test('Cloud keeps displayed history when a background read fails during a send', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.manualTasks = true;
  cloud.histories.set(sessionA, {
    messages: [{
      task_id: 'old-task', kind: 'user', data: { content: 'Earlier Cloud message' }, created_at: 1000,
    }],
    generating: false,
  });
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  const transcript = page.locator('#transcript');
  await expect(transcript.getByText('Earlier Cloud message', { exact: true })).toBeVisible();

  cloud.historyStatus = 503;
  await page.locator('#task').fill('Start a new turn');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.getByText(/HTTP 503/).first()).toBeVisible();
  await expect(transcript.getByText('Earlier Cloud message', { exact: true })).toBeVisible();
  const path = testInfo.outputPath('cloud-history-refresh-error.png');
  await transcript.screenshot({ path });
  await testInfo.attach('History remains visible after a failed background read', { path, contentType: 'image/png' });

  cloud.historyStatus = 200;
  await cloud.finishTask();
  await expect(transcript.getByText('Earlier Cloud message', { exact: true })).toBeVisible();
  await expect(transcript.getByText('Start a new turn', { exact: true })).toBeVisible();
});
