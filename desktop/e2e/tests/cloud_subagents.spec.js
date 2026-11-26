import { test, expect } from './support/test.js';
import { CloudHarness, cloudOrigin, sessionA, sessionB } from './support/cloud_harness.js';

const title = 'Subagent transcripts';

function history(id, question) {
  return { records: [
    { version: 1, id, system_prompt: 'Child system prompt' },
    { sequence: 2, ts: 1000, item: { kind: 'user', payload: { content: question } } },
    { sequence: 5, ts: 1001, item: { kind: 'future_record', payload: {} } },
    { sequence: 7, ts: 1002, item: { kind: 'assistant', payload: { content: 'Child answer' } } },
  ] };
}

test('open saved Cloud children on demand from the list and the parent tool card', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('openseek.minimal_transcript', 'false'));
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, { generating: false, messages: [
    { task_id: 'parent', kind: 'user', created_at: 1, data: { content: 'Parent question' } },
    { task_id: 'parent', kind: 'tool_call', created_at: 2, data: { id: 'r', name: 'review', arguments: '{}' } },
    { task_id: 'parent', kind: 'tool_result', created_at: 3, data: { tool_call_id: 'r', tool_name: 'review', content: 'Done', brief: 'review sr-2 (1 finding)', is_error: false } },
  ] });
  await cloud.install();
  const base = `${cloudOrigin}/v1/sessions/${sessionA}/subagents`;
  const child = `${sessionA}-sr-2`;
  const calls = [];
  await page.route(base + '**', async route => {
    const request = route.request();
    calls.push([request.url(), request.method(), await request.headerValue('authorization')]);
    return route.fulfill({ json: request.url() === base ? { subagents: [child, sessionA + '-sr-10'] } : history(child, 'Child question') });
  });
  await cloud.goto(); await cloud.open();
  await page.locator('#task').fill('Unsent parent draft');
  expect(calls).toEqual([]);
  await page.getByRole('button', { name: title, exact: true }).click();
  const dialog = page.getByRole('dialog', { name: /Subagent transcripts/ });
  await expect(dialog.getByRole('button', { name: /^sr-/ })).toHaveText(['sr-2', 'sr-10']);
  await dialog.getByRole('button', { name: 'sr-2', exact: true }).click();
  await expect(dialog).toContainText('Child question');
  await expect(dialog).toContainText('Child answer');
  await expect(dialog.getByRole('textbox')).toHaveCount(0);
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Unsent parent draft');
  const chip = page.locator('#transcript .subrun-chip');
  await chip.locator('xpath=ancestor::details[1]/summary').click();
  await chip.click();
  await expect(dialog).toContainText('Child question');
  expect(calls).toEqual([base, base + '/' + child, base + '/' + child].map(url => [url, 'GET', 'Bearer ts_fixture-123']));
  expect(cloud.hostRequests.some(r => r.method === 'session.load' && r.params.session === child)).toBe(false);
});

test('archived Cloud parents can retry the list and read their children', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.archived.add(sessionB);
  await cloud.install();
  const base = `${cloudOrigin}/v1/sessions/${sessionB}/subagents`;
  const child = sessionB + '-sr-1';
  let attempts = 0;
  await page.route(base, route => {
    attempts++;
    if (attempts === 1) return route.fulfill({ status: 503, json: { error: 'unavailable' } });
    return route.fulfill({ json: { subagents: attempts === 2 ? [] : [child] } });
  });
  await page.route(base + '/' + child, route => route.fulfill({ json: history(child, 'Archived child') }));
  await cloud.goto();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Archive', exact: true }).click();
  await page.getByRole('tabpanel', { name: 'Archive' }).getByRole('button', { name: /^Cloud fixture B/ }).click();
  const open = page.getByRole('button', { name: title, exact: true });
  const dialog = page.getByRole('dialog', { name: /Subagent transcripts/ });
  await open.click();
  await dialog.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(dialog).toContainText('No saved subagents.');
  await page.keyboard.press('Escape');
  await open.click();
  await dialog.getByRole('button', { name: 'sr-1', exact: true }).click();
  await expect(dialog).toContainText('Archived child');
});

test('a late transcript response cannot replace the selected child', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  const base = `${cloudOrigin}/v1/sessions/${sessionA}/subagents`;
  const first = sessionA + '-sr-1';
  const second = sessionA + '-sr-2';
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  await page.route(base, route => route.fulfill({ json: { subagents: [first, second] } }));
  await page.route(base + '/' + first, async route => {
    await pending;
    await route.fulfill({ json: history(first, 'Earlier selection') });
  });
  await page.route(base + '/' + second, route => route.fulfill({ json: history(second, 'Current selection') }));
  await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: title, exact: true }).click();
  const dialog = page.getByRole('dialog', { name: /Subagent transcripts/ });
  const requested = page.waitForRequest(base + '/' + first);
  await dialog.getByRole('button', { name: 'sr-1' }).click();
  await requested;
  await dialog.getByRole('button', { name: title, exact: true }).click();
  await dialog.getByRole('button', { name: 'sr-2' }).click();
  await expect(dialog).toContainText('Current selection');
  const finished = page.waitForEvent('requestfinished', request => request.url() === base + '/' + first);
  release();
  await finished;
  await expect(dialog).toContainText('Current selection');
  await expect(dialog).not.toContainText('Earlier selection');
});
