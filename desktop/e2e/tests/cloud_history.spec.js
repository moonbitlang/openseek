import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { CloudHarness, authOrigin, sessionA, sessionB } from './support/cloud_harness.js';

const png = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url)).toString('base64');
const image = { type: 'image', media_type: 'image/png', data: png };
const sessionURL = `${authOrigin}/cloud/session/${sessionA}`;
const user = (task, content, created_at) => ({ task_id: task, kind: 'user', data: { content }, created_at });

test('Cloud history recalls text from image messages in order and skips image-only or empty prompts', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, {
    messages: [
      user('plain', 'An older plain question', 1000),
      user('mixed', [{ type: 'text', text: 'Review ' }, image, { type: 'text', text: 'the attached image' }], 1001),
      user('image-only', [image], 1002),
      user('empty', '  ', 1003),
    ],
    generating: false,
  });
  await cloud.install();
  await page.goto(sessionURL);
  const task = page.locator('#task');
  const caption = page.locator('.composer-mode-chip');

  for (const reload of [false, true]) {
    if (reload) await page.reload();
    await expect(task).toBeEnabled();
    await task.press('ArrowUp');
    await expect(task).toHaveValue('Review the attached image');
    await expect(caption).toHaveText('History 2/2');
    await expect(page.locator('.composer-image')).toHaveCount(0);
    await task.press('Home');
    await task.press('ArrowUp');
    await expect(task).toHaveValue('An older plain question');
    await expect(caption).toHaveText('History 1/2');
    await task.press('End');
    await task.press('ArrowDown');
    await expect(task).toHaveValue('Review the attached image');
    await task.press('End');
    await task.press('ArrowDown');
    await expect(task).toHaveValue('');
    await expect(caption).toHaveCount(0);
  }

  await task.fill('Keep my unsent draft');
  await task.press('Home');
  await task.press('ArrowUp');
  await expect(task).toHaveValue('Keep my unsent draft');
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud rich-message history restores file mention chips without exposing the wire envelope or old image', async ({ page }) => {
  const cloud = new CloudHarness(page);
  const prompt = 'Update the heading\n\n<user_mentions>\n<file path="src/index.html"/>\n</user_mentions>';
  cloud.histories.set(sessionA, {
    messages: [user('with-file-and-image', [{ type: 'text', text: prompt }, image], 1000)],
    generating: false,
  });
  await cloud.install();
  await page.goto(sessionURL);
  const task = page.locator('#task');
  await expect(task).toBeEnabled();
  await task.press('ArrowUp');
  await expect(task).toHaveValue('Update the heading');
  await expect(page.locator('.composer .mention-chip')).toContainText('index.html');
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await expect(page.locator('.composer-mode-chip')).toHaveText('History 1/1');
  await task.press('End');
  await task.press('ArrowDown');
  await expect(task).toHaveValue('');
  await expect(page.locator('.composer .mention-chip')).toHaveCount(0);
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud reads one turn at a time, preserves the viewport, and revalidates only the latest page', async ({ page }) => {
  const cloud = new CloudHarness(page);
  const makeTurn = (index, label) => {
    const sequence = index * 3 + 1;
    const task = `turn-${index}`;
    return {
      messages: [{ ...user(task, label, sequence), id: sequence, engine_sequence: sequence }],
      events: [
        { sequence, item: { kind: 'user', payload: { content: label } } },
        { sequence: sequence + 1, item: { kind: 'assistant', payload: {
          content: Array.from({ length: 70 }, (_, line) => `${label} detail ${line + 1}`).join('\n\n'),
        } } },
        { sequence: sequence + 2, item: { kind: 'terminal', payload: { kind: 'finished' } } },
      ],
    };
  };
  const turns = [makeTurn(0, 'First question'), makeTurn(1, 'Second question'), makeTurn(2, 'Third question')];
  cloud.historyTurns.set(sessionA, turns);
  await cloud.install();
  const requests = [];
  const historyPath = `/v1/sessions/${sessionA}/messages`;
  const matches = request => request.method() === 'GET' && new URL(request.url()).pathname === historyPath;
  page.on('request', request => { if (matches(request)) requests.push(request); });
  const historyResponse = () => page.waitForResponse(response => matches(response.request()));
  const first = historyResponse();
  await page.goto(sessionURL);
  const firstTag = (await first).headers().etag;
  const transcript = page.locator('#transcript');
  const bubbles = transcript.locator('.msg.user .msg-content');
  await expect(bubbles).toHaveText(['Third question']);
  expect(requests.map(request => new URL(request.url()).search)).toEqual(['?limit=1']);

  // Pause the page after the viewport has moved to the boundary so we can
  // compare the same rendered turn before and after the prepend.
  let release;
  cloud.pauseHistory = new Promise(resolve => { release = resolve; });
  const third = transcript.locator('#turn-s7');
  const response = historyResponse();
  let before;
  try {
    await expect.poll(() => transcript.evaluate(element => element.scrollTop)).toBeGreaterThan(4);
    await transcript.evaluate(element => { element.scrollTop = 0; });
    await expect.poll(() => requests.length).toBe(2);
    before = (await third.boundingBox()).y;
    await transcript.hover();
    await page.mouse.wheel(0, -400);
    expect(requests).toHaveLength(2);
  } finally {
    cloud.pauseHistory = null;
    release();
  }
  expect((await response).status()).toBe(200);
  await expect(bubbles).toHaveText(['Second question', 'Third question']);
  await expect.poll(async () => Math.abs((await third.boundingBox()).y - before)).toBeLessThan(2);

  await transcript.evaluate(element => { element.scrollTop = 0; });
  await expect(bubbles).toHaveText(['First question', 'Second question', 'Third question']);
  await transcript.evaluate(element => { element.scrollTop = 0; });
  await transcript.hover();
  await page.mouse.wheel(0, -400);
  expect(requests.map(request => new URL(request.url()).search)).toEqual([
    '?limit=1', '?limit=1&offset=1', '?limit=1&offset=0',
  ]);

  await cloud.open(sessionB);
  const unchanged = historyResponse();
  await cloud.open(sessionA);
  expect((await unchanged).status()).toBe(304);
  expect(await requests.at(-1).headerValue('if-none-match')).toBe(firstTag);
  await expect(bubbles).toHaveCount(3);
  await page.locator('#task').fill('Keep the local draft');
  await expect(page.locator('#send')).toBeEnabled();

  // Keep the live answer visible until the terminal event makes the new
  // turn durable. The latest page must retain earlier turns exactly once.
  const started = historyResponse();
  await cloud.emitSessionEvent(sessionA, 'task_started', {}, { task: 'turn-3' });
  await started;
  const answer = transcript.getByText('Fourth question detail 1', { exact: true });
  await cloud.emitSessionEvent(sessionA, 'assistant_delta', { content: 'Fourth question detail 1' }, { task: 'turn-3' });
  await expect(answer).toHaveCount(1);
  turns.push(makeTurn(3, 'Fourth question'));
  const refreshed = historyResponse();
  await cloud.emitSessionEvent(sessionA, 'task_finished', { status: 'completed' }, { task: 'turn-3' });
  const updated = await refreshed;
  expect(updated.status()).toBe(200);
  expect(new URL(updated.url()).search).toBe('?limit=1');
  await expect(bubbles).toHaveText(['First question', 'Second question', 'Third question', 'Fourth question']);
  await expect(answer).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('Keep the local draft');
});

test('Cloud can page upward when the latest turn fits without a scrollbar', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.historyTurns.set(sessionA, ['Earlier question', 'Latest question'].map((text, index) => ({
    messages: [user(`task-${index}`, text, index + 1)],
    events: [],
  })));
  await cloud.install();
  const queries = [];
  page.on('request', request => {
    const url = new URL(request.url());
    if (request.method() === 'GET' && url.pathname === `/v1/sessions/${sessionA}/messages`) {
      queries.push(url.search);
    }
  });
  await page.goto(sessionURL);
  const transcript = page.locator('#transcript');
  const bubbles = transcript.locator('.msg.user .msg-content');
  await expect(bubbles).toHaveText(['Latest question']);
  expect(await transcript.evaluate(element => element.scrollHeight === element.clientHeight)).toBe(true);
  expect(queries).toEqual(['?limit=1']);
  let release;
  cloud.pauseHistory = new Promise(resolve => { release = resolve; });
  const oldResponse = page.waitForResponse(response => new URL(response.url()).searchParams.get('offset') === '0');
  try {
    await transcript.hover();
    await page.mouse.wheel(0, -200);
    await expect.poll(() => queries.length).toBe(2);
    await cloud.row(sessionB).click();
    await expect(cloud.row(sessionB)).toHaveAttribute('aria-current', 'true');
  } finally {
    cloud.pauseHistory = null;
    release();
  }
  await (await oldResponse).finished();
  await cloud.open(sessionA);
  await expect(bubbles).toHaveText(['Latest question']);
  await transcript.hover();
  await page.mouse.wheel(0, -200);
  await expect(bubbles).toHaveText(['Earlier question', 'Latest question']);
  expect(queries).toEqual(['?limit=1', '?limit=1&offset=0', '?limit=1', '?limit=1&offset=0']);
});
