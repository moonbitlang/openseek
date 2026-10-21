import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

const childSession = `${sessionA}-sr-1`;
const rawRecords = [
  { version: 1, id: sessionA, system_prompt: 'Original system prompt </script> 🌙' },
  { sequence: 17, ts: 1000, item: { kind: 'user', payload: { content: 'Original question </script> 🌙' } } },
  { sequence: 19, ts: 1001, item: { kind: 'assistant', payload: { tool_calls: [{ id: 'original-call', name: 'mbtx', arguments: '{"source":"println(2)"}' }] } } },
  { sequence: 23, ts: 1002, item: { kind: 'tool_result', payload: { tool_call_id: 'original-call', content: 'Original tool output', is_error: false } } },
  { sequence: 24, ts: 1003, item: { kind: 'future_event', payload: { retained: true } } },
].map(record => JSON.stringify(record)).join('\n') + '\n';
const childRecords = JSON.stringify({ version: 1, id: childSession, system_prompt: 'Original child system prompt' }) + '\n';
const dataset = {
  '/api/sessions': JSON.stringify([
    { key: 'session-0', id: sessionA, root: `cloud://sessions/${sessionA}`, root_label: 'Cloud', is_marker: true, last_active: null, first_prompt: 'Original question' },
    { key: 'session-1', id: childSession, root: `cloud://sessions/${sessionA}`, root_label: 'Cloud', is_marker: true, last_active: null, first_prompt: '' },
  ]),
  '/api/sessions/session-0': JSON.stringify({ found: true, events: rawRecords, events_bytes: Buffer.byteLength(rawRecords) }),
  '/api/sessions/session-1': JSON.stringify({ found: true, events: childRecords, events_bytes: Buffer.byteLength(childRecords) }),
};
const snapshot = { json: JSON.stringify(dataset) };
snapshot.html = `<!doctype html><html><body><script>window.__OPENSEEK_DATA__ = ${snapshot.json.replaceAll('<', '\\u003c')};</script></body></html>`;

async function setup(page, { desktop = false } = {}) {
  const cloud = new CloudHarness(page, { desktop });
  const uploads = [];
  cloud.histories.set(sessionA, { generating: false, messages: [
    { task_id: 'task', kind: 'user', data: { content: 'Visible Cloud question </script>' }, created_at: 1000 },
    { task_id: 'task', kind: 'tool_call', data: { id: 'call', name: 'mbtx', arguments: '{"source":"println(2)"}' }, created_at: 1001 },
    { task_id: 'task', kind: 'tool_result', data: { tool_call_id: 'call', tool_name: 'mbtx', content: '2', is_error: false }, created_at: 1002 },
    { task_id: 'task', kind: 'assistant_message', data: { content: 'Visible answer' }, created_at: 1003 },
    { task_id: 'task', kind: 'task_finished', data: { status: 'completed', result: { output: { answer: 'Visible answer' } } }, created_at: 1004 },
  ] });
  cloud.exportSnapshots.set(sessionA, snapshot);
  await cloud.install();
  await page.route(`${authOrigin}/v2/shares`, route => {
    uploads.push(route.request().url());
    return route.abort('failed');
  });
  await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Export', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Export conversation', exact: true });
  await expect(dialog).toBeVisible();
  return { cloud, uploads, dialog };
}

test('Cloud downloads the original server snapshot and shares without a host export bridge', async ({ page }) => {
  const { cloud, uploads, dialog } = await setup(page);
  await expect(dialog).toContainText('Anyone with the link can view it for 7 days');
  const beforeHistory = cloud.requests.filter(request => request.path.endsWith('/messages')).length;
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(`${authOrigin}/v1/shares/sh_fixture`);
  const shares = cloud.requests.filter(request => request.path.endsWith('/share'));
  expect(shares).toHaveLength(1);
  expect(shares[0].headers.authorization).toBe('Bearer ts_fixture-123');
  expect(JSON.parse(shares[0].body)).toEqual({ idempotency_key: expect.any(String) });
  expect(cloud.requests.filter(request => request.path.endsWith('/messages'))).toHaveLength(beforeHistory);
  expect(uploads).toEqual([]);
  const pending = page.waitForEvent('download');
  await dialog.getByRole('button', { name: 'Download', exact: true }).click();
  const downloaded = await pending;
  expect(downloaded.suggestedFilename()).toBe('conversation.html');
  const html = await readFile(await downloaded.path(), 'utf8');
  expect(html).toBe(snapshot.html);
  const embedded = JSON.parse(html.match(/window\.__OPENSEEK_DATA__ = (.*);<\/script>/)[1]);
  expect(embedded).toEqual(dataset);
  expect(JSON.parse(embedded['/api/sessions/session-0']).events).toBe(rawRecords);
  expect(JSON.parse(embedded['/api/sessions/session-1']).events).toBe(childRecords);
  expect(html).not.toContain('Visible answer');
  expect(cloud.requests.filter(request => request.path.endsWith('/messages'))).toHaveLength(beforeHistory);
  const exports = cloud.requests.filter(request => request.path.endsWith('/export'));
  expect(exports).toHaveLength(1);
  expect(exports[0].method).toBe('GET');
  expect(exports[0].headers.authorization).toBe('Bearer ts_fixture-123');
  expect(cloud.hostRequests.filter(request => ['session.snapshot', 'session.export', 'session.share', 'account.session'].includes(request.method))).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const status of [401, 409, 503]) {
  test(`Cloud share ${status} ${status === 401 ? 'expires the account' : 'preserves it'}`, async ({ page }) => {
    const { cloud, uploads, dialog } = await setup(page);
    cloud.shareStatus = status;
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    if (status === 401) {
      await expect(dialog).toBeHidden();
      await expect(cloud.row(sessionA)).toBeHidden();
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
    } else {
      await expect(dialog).toContainText(status === 409
        ? 'This conversation has no complete original log to export.'
        : 'Cloud answered HTTP 503');
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
      await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
    }
    expect(uploads).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('desktop Cloud downloads use the window save dialog and preserve cancel, save and failure outcomes', async ({ page }) => {
  let reply = { opened: false };
  let failure = null;
  const { cloud, uploads, dialog } = await setup(page, { desktop: true });
  const original = cloud.device.replyFor.bind(cloud.device);
  cloud.device.replyFor = async request => {
    if (request.method !== 'session.snapshot_save') return original(request);
    if (failure) throw new Error(failure);
    return reply;
  };
  const download = dialog.getByRole('button', { name: 'Download', exact: true });
  const saves = () => cloud.hostRequests.filter(request => request.method === 'session.snapshot_save');
  await download.click();
  await expect.poll(() => saves().length).toBe(1);
  await expect(download).toBeEnabled();
  await expect(dialog).not.toContainText("couldn't");
  expect(saves()[0].params.session).toBe(sessionA);
  expect(saves()[0].params.html).toBe(snapshot.html);
  expect(saves()[0].params).not.toHaveProperty('path');
  reply = { path: '/exports/cloud.html', opened: false };
  await download.click();
  await expect(dialog).toContainText("couldn't open it automatically");
  failure = 'could not save the conversation export: disk full';
  await download.click();
  await expect(dialog).toContainText('disk full');
  await expect(download).toBeEnabled();
  expect(cloud.hostRequests.filter(request => request.method === 'session.export')).toEqual([]);
  expect(uploads).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a disconnected Cloud share is not automatically resubmitted', async ({ page }) => {
  const { cloud, uploads, dialog } = await setup(page);
  cloud.disconnectShare = true;
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog).toContainText('Cloud is unreachable');
  const shares = () => cloud.requests.filter(request => request.path.endsWith('/share'));
  expect(shares()).toHaveLength(1);
  const oldKey = JSON.parse(shares()[0].body).idempotency_key;
  cloud.disconnectShare = false;
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toBeVisible();
  expect(shares()).toHaveLength(2);
  expect(JSON.parse(shares()[1].body).idempotency_key).not.toBe(oldKey);
  expect(uploads).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const status of [401, 404, 409, 503]) {
  test(`Cloud export ${status} preserves existing account and error handling`, async ({ page }) => {
    const { cloud, dialog } = await setup(page);
    cloud.exportStatus = status;
    const downloads = [];
    page.on('download', download => downloads.push(download));
    const beforeHistory = cloud.requests.filter(request => request.path.endsWith('/messages')).length;
    await dialog.getByRole('button', { name: 'Download', exact: true }).click();
    if (status === 401) {
      await expect(dialog).toBeHidden();
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
    } else {
      await expect(dialog).toContainText(status === 409
        ? 'This conversation has no complete original log to export.'
        : `Cloud answered HTTP ${status}`);
      await expect(dialog).toBeVisible();
      await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_fixture-123');
    }
    expect(downloads).toEqual([]);
    expect(cloud.requests.filter(request => request.path.endsWith('/messages'))).toHaveLength(beforeHistory);
    expect(cloud.hostRequests.filter(request => request.method === 'session.snapshot_save')).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

for (const failure of ['malformed', 'disconnected']) {
  test(`Cloud export rejects a ${failure} snapshot without rebuilding visible history`, async ({ page }) => {
    const { cloud, dialog } = await setup(page, { desktop: true });
    if (failure === 'malformed') cloud.exportSnapshots.set(sessionA, { html: snapshot.html });
    else cloud.exportOffline = true;
    const beforeHistory = cloud.requests.filter(request => request.path.endsWith('/messages')).length;
    await dialog.getByRole('button', { name: 'Download', exact: true }).click();
    await expect(dialog).toContainText(failure === 'malformed' ? 'Cloud returned an invalid response' : 'Cloud is unreachable');
    await expect(dialog.getByRole('button', { name: 'Download', exact: true })).toBeEnabled();
    expect(cloud.hostRequests.filter(request => request.method === 'session.snapshot_save')).toEqual([]);
    expect(cloud.requests.filter(request => request.path.endsWith('/messages'))).toHaveLength(beforeHistory);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}
