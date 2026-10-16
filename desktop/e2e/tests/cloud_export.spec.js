import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

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
  await cloud.install();
  await page.route(`${authOrigin}/v2/shares`, route => {
    uploads.push(route.request().url());
    return route.abort('failed');
  });
  await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Export conversation', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Export conversation', exact: true });
  await expect(dialog).toBeVisible();
  return { cloud, uploads, dialog };
}

test('Cloud export stays at the trailing edge of the shared header with a long title', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.titles.set(sessionA, 'A long Cloud conversation title that must leave room for the export button. '.repeat(4));
  await cloud.install();
  await cloud.goto();
  await cloud.open();
  const header = page.locator('main > .topbar');
  const button = header.getByRole('button', { name: 'Export conversation', exact: true });
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 900 });
    if (width === 390) {
      await expect(page.getByRole('button', { name: 'Show sidebar', exact: true })).toBeVisible();
      await expect(page.locator('aside')).toBeHidden();
    }
    await expect(button).toBeInViewport();
    await expect.poll(() => header.evaluate(header => {
      const title = header.querySelector('h1');
      const button = header.querySelector('button');
      const trailing = header.getBoundingClientRect().right - parseFloat(getComputedStyle(header).paddingRight);
      return Math.abs(button.getBoundingClientRect().right - trailing) < 1 && title.scrollWidth > title.clientWidth;
    })).toBe(true);
    await button.click();
    const dialog = page.getByRole('dialog', { name: 'Export conversation', exact: true });
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Close export dialog', exact: true }).click();
    await page.screenshot({ path: testInfo.outputPath(`cloud-export-header-${width}.png`) });
  }
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud shares and downloads a standalone visible-history snapshot without a host export bridge', async ({ page }) => {
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
  expect(html).toContain('Visible answer');
  expect(html).not.toContain('question </script>');
  expect(cloud.hostRequests.filter(request => ['session.snapshot', 'session.export', 'session.share', 'account.session'].includes(request.method))).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const status of [401, 503]) {
  test(`Cloud share ${status} ${status === 401 ? 'expires the account' : 'preserves it'}`, async ({ page }) => {
    const { cloud, uploads, dialog } = await setup(page);
    cloud.shareStatus = status;
    await dialog.getByRole('button', { name: 'Share', exact: true }).click();
    if (status === 401) {
      await expect(dialog).toBeHidden();
      await expect(cloud.row(sessionA)).toBeHidden();
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
    } else {
      await expect(dialog).toContainText('Cloud answered HTTP 503');
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
  expect(saves()[0].params.html).toContain('Visible Cloud question');
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
