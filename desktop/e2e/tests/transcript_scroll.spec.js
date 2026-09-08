import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Enough turns to make the transcript scroll in the default viewport.
function longSessionEvents(prefix) {
  const events = [];
  let sequence = 1;
  for (let turn = 1; turn <= 60; turn += 1) {
    events.push({
      sequence,
      ts: 1_781_144_350_123 + sequence * 1_000,
      item: {
        kind: 'user',
        payload: { content: `${prefix} question ${turn}` },
      },
    });
    sequence += 1;
    events.push({
      sequence,
      ts: 1_781_144_350_123 + sequence * 1_000,
      item: {
        kind: 'assistant',
        payload: { content: `${prefix} answer ${turn}` },
      },
    });
    sequence += 1;
  }
  return events;
}

async function openConversation(page, title, firstQuestion) {
  await page.getByText(title, { exact: true }).first().click();
  await page.locator('.transcript .msg-content', { hasText: firstQuestion }).first().waitFor();
}

function distanceFromBottom(transcript) {
  return transcript.evaluate(node =>
    node.scrollHeight - node.scrollTop - node.clientHeight);
}

async function waitUntilScrollable(transcript) {
  await expect.poll(() => transcript.evaluate(node =>
    node.scrollHeight - node.clientHeight)).toBeGreaterThan(1000);
}

test('sending re-pins a transcript the reader had scrolled up', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = longSessionEvents('First fixture:');
  await app.install();
  await app.goto();
  await openConversation(page, 'Rabbita browser fixture', /^First fixture: question 1$/);

  const transcript = page.locator('#transcript');
  await waitUntilScrollable(transcript);
  await transcript.evaluate(node => { node.scrollTop = 0; });
  await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(0);

  await page.locator('#task').fill('Run the browser E2E turn');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'agent.start')).toBe(true);
  await expect.poll(() => distanceFromBottom(transcript)).toBeLessThanOrEqual(4);

  // The pin must survive the jump: streamed content keeps the tail in view.
  const heightBeforeStream = await transcript.evaluate(node => node.scrollHeight);
  app.notify('agent.started', {
    run_id: 'run-e2e',
    session: 'session-1',
    session_root: '/workspace/.openseek',
    model: 'deepseek-v4-pro',
    max_steps: 1000,
  });
  app.notify('agent.event', {
    run_id: 'run-e2e',
    session: 'session-1',
    event: {
      event: 'assistant_delta',
      content: Array.from({ length: 40 }, (_, line) => `Streamed line ${line}`).join('\n\n'),
    },
  });
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight))
    .toBeGreaterThan(heightBeforeStream);
  await expect.poll(() => distanceFromBottom(transcript)).toBeLessThanOrEqual(4);
  expect(app.pageErrors).toEqual([]);
});

test('returning to a conversation restores where the reader left it', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const first = longSessionEvents('First fixture:');
  const second = longSessionEvents('Second fixture:');
  app.liveSessions.push({
    id: 'session-2',
    title: 'Second browser fixture',
    updated_at_ms: 2,
  });
  const replyFor = app.replyFor.bind(app);
  app.replyFor = (request) => {
    if (request.method === 'session.load') {
      const id = request.params?.session;
      const events = id === 'session-2' ? second : first;
      return {
        session: { version: 1, id, events },
        watermark: events.at(-1).sequence,
      };
    }
    return replyFor(request);
  };
  await app.install();
  await app.goto();
  await openConversation(page, 'Rabbita browser fixture', /^First fixture: question 1$/);

  const transcript = page.locator('#transcript');
  await waitUntilScrollable(transcript);
  await transcript.evaluate(node => { node.scrollTop = 600; });
  await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(600);

  await page.locator('.conversation-row[title="session-2"]').click();
  await page.locator('.transcript .msg-content', { hasText: /^Second fixture: question 1$/ }).waitFor();
  // A conversation opened for the first time starts at its tail.
  await expect.poll(() => distanceFromBottom(transcript)).toBeLessThanOrEqual(4);

  await page.locator('.conversation-row[title="session-1"]').click();
  await page.locator('.transcript .msg-content', { hasText: /^First fixture: question 1$/ }).waitFor();
  await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(600);
  expect(app.pageErrors).toEqual([]);
});
