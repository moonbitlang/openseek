import { test, expect } from './support/test.js';
import { historyCacheRows } from './support/cloud_history_cache.js';
import { CloudHarness, cloudOrigin, sessionA, sessionB, settledResponse } from './support/cloud_harness.js';

for (const desktop of [true, false]) {
  test(`${desktop ? 'desktop files' : 'browser IndexedDB'} reopen cached Cloud turns offline and revalidate them after restart`, async ({ page }) => {
    const cloud = new CloudHarness(page, { desktop });
    const files = new Map();
    cloud.historyCache = ({ action, session, page: history }) => {
      if (action === 'write') files.set(session, history);
      if (action === 'remove') files.delete(session);
      if (action === 'read') return { kind: 'page', page: files.get(session) ?? null };
      if (action === 'list') return {
        kind: 'entries',
        entries: Array.from(files, ([session, page]) => ({ session, label: page.messages[0].data.content })),
      };
      return { kind: 'done' };
    };
    const cache = async () => desktop ? files : new Map((await historyCacheRows(page)).map(row => [row.session, row.page]));
    const seed = (id, title, answer) => cloud.histories.set(id, {
      generating: false,
      messages: [
        { task_id: id, kind: 'user', data: { content: title }, created_at: 1000 },
        { task_id: id, kind: 'assistant_message', data: { content: answer }, created_at: 1001 },
      ],
    });
    seed(sessionA, 'Cached question A', 'Saved reply A');
    seed(sessionB, 'Cached question B', 'Saved reply B');
    cloud.histories.get(sessionA).settings = { model: 'deepseek-v4-pro', thinking: 'max' };
    await cloud.install();
    await cloud.goto();
    await cloud.open(sessionA);
    await cloud.open(sessionB);
    await expect.poll(async () => (await cache()).size).toBe(2);
    const etag = (await cache()).get(sessionA).etag;
    expect((await cache()).get(sessionA).settings).toEqual({ model: 'deepseek-v4-pro', thinking: 'max' });

    let releaseList;
    cloud.pauseList = new Promise(resolve => { releaseList = resolve; });
    cloud.listStatus = 503;
    const offlineHistory = url => url.origin === cloudOrigin && url.pathname === `/v1/sessions/${sessionB}/messages`;
    const offlineRead = route => route.request().method() === 'GET' ? route.abort('failed') : route.fallback();
    await page.route(offlineHistory, offlineRead);
    await cloud.goto();
    await expect(cloud.row(sessionA)).toHaveText('Cached question A');
    let releaseHistory;
    cloud.pauseHistory = new Promise(resolve => { releaseHistory = resolve; });
    const historyPath = `/v1/sessions/${sessionA}/messages`;
    const read = page.waitForRequest(request => new URL(request.url()).pathname === historyPath && request.method() === 'GET');
    await cloud.row(sessionA).click();
    const firstRead = await read;
    expect(await firstRead.headerValue('if-none-match')).toBe(etag);
    const transcript = page.locator('#transcript');
    await expect(transcript.getByText('Saved reply A')).toBeVisible();
    await expect(page.locator('.composer').getByRole('button', {name: 'Model', exact: true})).toHaveText('DeepSeek Pro');
    await expect(page.locator('.composer').getByRole('button', {name: 'Reasoning effort', exact: true})).toHaveText('Max');
    await cloud.row(sessionB).click();
    await expect(transcript.getByText('Saved reply B')).toBeVisible();
    await expect(transcript).toContainText('Cloud is unreachable');
    releaseHistory();
    releaseList();
    const unchanged = await firstRead.response();
    expect(unchanged.status()).toBe(304);
    expect((await cache()).get(sessionA).etag).toBe(etag);

    await expect(page.getByRole('button', { name: 'Retry', exact: true })).toBeVisible();
    cloud.listStatus = 200;
    await page.unroute(offlineHistory, offlineRead);
    await page.getByRole('button', { name: 'Retry', exact: true }).click();
    await expect(cloud.row(sessionA)).toHaveText('Cloud fixture A');
    await cloud.open(sessionA);
    await expect(transcript.getByText('Saved reply A')).toBeVisible();

    seed(sessionA, 'Cached question A', 'Updated reply A');
    await cloud.open(sessionB);
    await cloud.open(sessionA);
    await expect(transcript.getByText('Updated reply A')).toBeVisible();
    await expect.poll(async () => (await cache()).get(sessionA).etag).not.toBe(etag);
    expect(JSON.stringify((await cache()).get(sessionA).session.events)).toContain('Updated reply A');

    const row = cloud.rowContainer(sessionA);
    await row.hover();
    await row.getByRole('button', { name: 'Conversation actions', exact: true }).click();
    await page.getByRole('menuitem', { name: 'Delete…', exact: true }).click();
    await page.getByRole('button', { name: 'Delete permanently', exact: true }).click();
    await expect.poll(async () => (await cache()).has(sessionA)).toBe(false);
    expect((await cache()).has(sessionB)).toBe(true);
    expect(cloud.requests.some(request => request.method === 'DELETE' && request.path === `/v1/sessions/${sessionA}`)).toBe(true);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

async function changeCacheRows(page, corrupt) {
  await page.evaluate(corrupt => new Promise((resolve, reject) => {
    const request = indexedDB.open('seekmoon.cloud-history.v1', 1);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const tx = db.transaction('pages', 'readwrite');
      const store = tx.objectStore('pages');
      store.getAll().onsuccess = event => {
        for (const row of event.target.result) {
          // Alternate scopes deliberately use identical session identifiers.
          const other = { ...row.page, session: { events: [
            { sequence: 1, item: { kind: 'assistant', payload: { content: 'Other scope secret' } } },
          ] } };
          store.put({ ...row, page: other, origin: 'https://another-cloud.example' });
          store.put({ ...row, page: other, user: '456' });
          if (corrupt) store.put({ ...row, page: { broken: true } });
        }
      };
      tx.oncomplete = () => { db.close(); resolve(); };
      tx.onerror = () => { db.close(); reject(tx.error); };
    };
  }), corrupt);
}

test('logout clears only its account and fences a delayed history response before the next login', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, { messages: [
    { task_id: 'one', kind: 'assistant_message', data: { content: 'Old account answer' }, created_at: 1 },
  ], generating: false });
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  await expect.poll(async () => (await historyCacheRows(page)).length).toBe(1);
  await changeCacheRows(page, false);
  await cloud.open(sessionB);
  cloud.histories.set(sessionA, { messages: [
    { task_id: 'late', kind: 'assistant_message', data: { content: 'Late old-account answer' }, created_at: 2 },
  ], generating: false });
  let release;
  cloud.pauseHistory = new Promise(resolve => { release = resolve; });
  const delayedResponse = settledResponse(page, response => new URL(response.url()).pathname.endsWith(`${sessionA}/messages`));
  const delayed = page.waitForRequest(request => new URL(request.url()).pathname.endsWith(`${sessionA}/messages`));
  await cloud.open(sessionA);
  await delayed;
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Account', exact: true }).click();
  const account = page.getByRole('region', { name: 'Account', exact: true });
  await account.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(account.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();
  await expect.poll(async () => (await historyCacheRows(page)).filter(row => row.origin === cloudOrigin && row.user === '123').length).toBe(0);
  release();
  expect((await delayedResponse).status()).toBe(200);
  cloud.pauseHistory = null;
  cloud.userId = '789';
  cloud.histories.set(sessionA, { messages: [
    { task_id: 'new', kind: 'assistant_message', data: { content: 'New account answer' }, created_at: 3 },
  ], generating: false });
  await account.getByRole('button', { name: 'Sign in', exact: true }).click();
  await cloud.open(sessionA);
  await expect(page.locator('#transcript')).toContainText('New account answer');
  await expect(page.locator('#transcript')).not.toContainText('Old account answer');
  await expect.poll(async () => (await historyCacheRows(page)).filter(row => row.user === '789').length).toBe(1);
  const rows = await historyCacheRows(page);
  expect(rows.filter(row => row.origin === cloudOrigin && row.user === '123')).toEqual([]);
  expect(rows.filter(row => row.origin !== cloudOrigin || row.user === '456')).toHaveLength(2);
  expect(JSON.stringify(rows)).not.toContain('ts_fixture');
  expect(cloud.device.pageErrors).toEqual([]);
});
