import { test, expect } from './support/test.js';
import { CloudHarness, cloudOrigin, sessionA, sessionB } from './support/cloud_harness.js';

test('desktop reopens cached Cloud turns offline and revalidates them after restart', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
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
  const seed = (id, title, answer) => cloud.histories.set(id, {
    generating: false,
    messages: [
      { task_id: id, kind: 'user', data: { content: title }, created_at: 1000 },
      { task_id: id, kind: 'assistant_message', data: { content: answer }, created_at: 1001 },
    ],
  });
  seed(sessionA, 'Cached question A', 'Saved reply A');
  seed(sessionB, 'Cached question B', 'Saved reply B');
  await cloud.install();
  await cloud.goto();
  await cloud.open(sessionA);
  await cloud.open(sessionB);
  await expect.poll(() => files.size).toBe(2);
  const etag = files.get(sessionA).etag;

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
  await cloud.row(sessionB).click();
  await expect(transcript.getByText('Saved reply B')).toBeVisible();
  await expect(transcript).toContainText('Cloud is unreachable');
  releaseHistory();
  releaseList();
  const unchanged = await firstRead.response();
  expect(unchanged.status()).toBe(304);
  expect(files.get(sessionA).etag).toBe(etag);

  await expect(page.locator('#conversation-load-retry')).toBeVisible();
  cloud.listStatus = 200;
  await page.unroute(offlineHistory, offlineRead);
  await page.locator('#conversation-load-retry').click();
  await expect(cloud.row(sessionA)).toHaveText('Cloud fixture A');
  await cloud.open(sessionA);
  await expect(transcript.getByText('Saved reply A')).toBeVisible();

  seed(sessionA, 'Cached question A', 'Updated reply A');
  await cloud.open(sessionB);
  await cloud.open(sessionA);
  await expect(transcript.getByText('Updated reply A')).toBeVisible();
  await expect.poll(() => files.get(sessionA).etag).not.toBe(etag);
  expect(files.get(sessionA).messages.at(-1).data.content).toBe('Updated reply A');

  const row = cloud.rowContainer(sessionA);
  await row.hover();
  await row.locator('[id$=":actions-trigger"]').click();
  await page.locator('[role=menuitem][data-action=delete]:visible').click();
  await page.locator('#delete-chat-confirm').click();
  await expect.poll(() => files.has(sessionA)).toBe(false);
  expect(files.has(sessionB)).toBe(true);
  expect(cloud.requests.some(request => request.method === 'DELETE' && request.path === `/v1/sessions/${sessionA}`)).toBe(true);
  expect(cloud.device.pageErrors).toEqual([]);
});
