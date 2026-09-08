import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

class ReasoningHarness extends DesktopBrowserHarness {
  runs = [];

  start(session = 'session-1', run = 'run-1') {
    this.notify('agent.started', {
      run_id: run, session, session_root: '/workspace/.openseek',
      model: 'deepseek-v4-pro', max_steps: 1000,
    });
    this.event({ event: 'agent_step', step: 1 }, session, run);
  }

  event(event, session = 'session-1', run = 'run-1') {
    this.notify('agent.event', { run_id: run, session, event });
  }

  replyFor(request) {
    if (request.method === 'agent.runs') {
      return { runs: this.runs, settled: [], approvals: [] };
    }
    const result = super.replyFor(request);
    if (request.method === 'session.load') {
      return { ...result, session: { ...result.session, id: request.params.session } };
    }
    return result;
  }
}

test('reasoning appends preserve the container and do not refresh historical content', async ({ page }) => {
  const app = new ReasoningHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  app.start();
  app.event({ event: 'reasoning_delta', content: 'Starting: ' });
  const live = page.locator('#live-reasoning-host .activity-thinking-live');
  await expect(live).toHaveText('Starting: ');

  // Observe the real boundary rather than replacing the renderer. A content
  // refresh disconnects and re-observes #stream; live text must never do so.
  await page.evaluate(() => {
    const stream = document.getElementById('stream');
    window.reasoningProbe = {
      host: document.getElementById('live-reasoning-host'),
      body: document.querySelector('.activity-thinking-live'),
      reobserved: 0, historicalMutations: 0,
    };
    const observe = MutationObserver.prototype.observe;
    MutationObserver.prototype.observe = function (target, options) {
      if (target === stream) window.reasoningProbe.reobserved++;
      return observe.call(this, target, options);
    };
    const observer = new MutationObserver(records => {
      window.reasoningProbe.historicalMutations += records.length;
    });
    // Use the original method so the probe does not count its own installation.
    observe.call(observer, stream, { subtree: true, childList: true, characterData: true });
  });

  const fragment = '思考🙂 <script>literal text</script>\n'.repeat(60);
  let content = 'Starting: ';
  for (let frame = 0; frame < 5; frame++) {
    for (let chunk = 0; chunk < 10; chunk++) {
      app.event({ event: 'reasoning_delta', content: fragment });
      content += fragment;
    }
    await expect(live).toHaveText(content);
  }
  expect(await page.evaluate(() => ({
    sameHost: window.reasoningProbe.host === document.getElementById('live-reasoning-host'),
    sameBody: window.reasoningProbe.body === document.querySelector('.activity-thinking-live'),
    reobserved: window.reasoningProbe.reobserved,
    historicalMutations: window.reasoningProbe.historicalMutations,
  }))).toEqual({ sameHost: true, sameBody: true, reobserved: 0, historicalMutations: 0 });
  await expect(live.locator('script')).toHaveCount(0);

  // A normal root update still reconciles the container, preserving the
  // browser-owned body and the user's disclosure state.
  await page.locator('#live-reasoning-host summary').click();
  await app.openQuickOpen();
  await page.keyboard.press('Escape');
  await expect(page.locator('#live-reasoning-host details')).not.toHaveAttribute('open');
  expect(await page.evaluate(() => window.reasoningProbe.body ===
    document.querySelector('.activity-thinking-live'))).toBe(true);

  app.event({ event: 'reasoning_message', content: '**Completed thought**' });
  await expect(page.locator('#live-reasoning-host')).toBeEmpty();
  await expect(page.locator('#stream .activity-thinking strong', {
    hasText: 'Completed thought',
  })).toHaveCount(1);
  app.event({ event: 'reasoning_delta', content: 'late fragment' });
  // A later normal event provides an ordering barrier for the late fragment.
  app.event({ event: 'assistant_delta', content: 'Answer after thought' });
  await expect(page.locator('#stream')).toContainText('Answer after thought');
  await expect(page.locator('#live-reasoning-host')).toBeEmpty();

  app.event({ event: 'agent_step', step: 2 });
  app.event({ event: 'reasoning_delta', content: 'Next step' });
  await expect(live).toHaveText('Next step');
  // The first assistant fragment may precede the complete reasoning event.
  app.event({ event: 'assistant_delta', content: 'An early answer' });
  await expect(page.locator('#live-reasoning-host')).toBeEmpty();
  await expect(page.locator('#stream .activity-thinking')).toHaveText('Next step');
  await expect(page.locator('#stream')).toContainText('An early answer');

  app.event({ event: 'agent_step', step: 3 });
  app.event({ event: 'reasoning_delta', content: 'Interrupted thought' });
  await expect(live).toHaveText('Interrupted thought');
  app.event({ event: 'agent_aborted', reason: 'User stopped the run' });
  await expect(page.locator('#live-reasoning-host')).toBeEmpty();
  expect(app.pageErrors).toEqual([]);
});

test('reasoning restores after remount and keeps simultaneous conversations separate', async ({ page }) => {
  const app = new ReasoningHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Second reasoning fixture', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  await app.openSession();
  app.start();
  app.start('session-2', 'run-2');
  app.event({ event: 'reasoning_delta', content: 'First thought' });
  app.event({ event: 'reasoning_delta', content: 'Second thought' }, 'session-2', 'run-2');
  const live = page.locator('#live-reasoning-host .activity-thinking-live');
  await expect(live).toHaveText('First thought');

  await page.getByText('Second reasoning fixture', { exact: true }).first().click();
  await expect(live).toHaveText('Second thought');
  app.event({ event: 'reasoning_delta', content: ' in background' });
  app.event({ event: 'reasoning_delta', content: ' in foreground' }, 'session-2', 'run-2');
  await expect(live).toHaveText('Second thought in foreground');
  await app.openSession();
  await expect(live).toHaveText('First thought in background');

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.locator('#live-reasoning-host')).toHaveCount(0);
  app.event({ event: 'reasoning_delta', content: ' while hidden' });
  await app.openSession();
  await expect(live).toHaveText('First thought in background while hidden');
  expect(app.pageErrors).toEqual([]);
});

test('reasoning follows the tail until the reader scrolls up', async ({ page }) => {
  const app = new ReasoningHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  app.start();
  const initial = 'A growing thought\n'.repeat(250);
  app.event({ event: 'reasoning_delta', content: initial });
  const live = page.locator('#live-reasoning-host .activity-thinking-live');
  const transcript = page.locator('#transcript');
  await expect(live).toHaveText(initial);
  await expect.poll(() => transcript.evaluate(el =>
    el.scrollHeight - el.scrollTop - el.clientHeight)).toBeLessThanOrEqual(4);

  await transcript.evaluate(el => { el.scrollTop = 0; });
  await expect(page.getByRole('button', { name: 'Jump to latest' })).toBeVisible();
  app.event({ event: 'reasoning_delta', content: 'New line\n'.repeat(50) });
  await expect(live).toContainText('New line');
  expect(await transcript.evaluate(el => el.scrollTop)).toBeLessThanOrEqual(4);
  await page.getByRole('button', { name: 'Jump to latest' }).click();
  await expect.poll(() => transcript.evaluate(el =>
    el.scrollHeight - el.scrollTop - el.clientHeight)).toBeLessThanOrEqual(4);
  expect(app.pageErrors).toEqual([]);
});

for (const commitFirst of [false, true]) {
  test(`reasoning completion and history converge with commitFirst=${commitFirst}`, async ({ page }) => {
    const app = new ReasoningHarness(page);
    await app.install();
    await app.goto();
    await app.openSession();
    app.start();
    app.event({ event: 'reasoning_delta', content: 'A provisional prefix' });
    await expect(page.locator('.activity-thinking-live')).toHaveText('A provisional prefix');
    const sequence = app.sessionEvents.at(-1).sequence + 1;
    const event = {
      sequence,
      item: {
        kind: 'assistant',
        payload: { content: '', reasoning_content: 'A complete durable thought', tool_calls: [] },
      },
    };
    app.sessionEvents.push(event);
    if (!commitFirst) {
      app.event({ event: 'reasoning_message', content: 'A complete durable thought' });
      await expect(page.locator('#stream .activity-thinking', {
        hasText: 'A complete durable thought',
      })).toHaveCount(1);
    }
    app.notify('session.event', {
      session: 'session-1', session_root: '/workspace/.openseek', sequence, event,
    });
    await expect(page.locator('#stream .activity-thinking', {
      hasText: 'A complete durable thought',
    })).toHaveCount(1);
    if (commitFirst) {
      // A durable arrival alone must not truncate a still-live prefix.
      await expect(page.locator('.activity-thinking-live')).toHaveText('A provisional prefix');
      app.event({ event: 'reasoning_message', content: 'A complete durable thought' });
    }
    await expect(page.locator('#live-reasoning-host')).toBeEmpty();
    await expect(page.locator('#stream .activity-thinking', {
      hasText: 'A complete durable thought',
    })).toHaveCount(1);
    expect(app.pageErrors).toEqual([]);
  });
}

test('retired socket callbacks cannot recreate or clear the current reasoning preview', async ({ page }) => {
  // Keep the actual callbacks installed by the product. Replaying them models
  // events queued before retirement, including after a same-device reconnect.
  const app = new ReasoningHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  // Wrap after navigation so Playwright's WebSocket routing is already set up.
  await page.evaluate(() => {
    const BrowserWebSocket = window.WebSocket;
    window.reasoningSockets = [];
    window.WebSocket = class extends BrowserWebSocket {
      constructor(...args) {
        super(...args);
        window.reasoningSockets.push(this);
      }
    };
  });
  const loads = app.requests.filter(request => request.method === 'session.load').length;
  app.socket.close();
  await expect.poll(() => page.evaluate(() => window.reasoningSockets.length)).toBe(1);
  await expect.poll(() => app.requests.filter(request => request.method === 'session.load').length)
    .toBeGreaterThan(loads);
  app.start();
  // The run survives this connection gap. Returning an empty runs snapshot
  // would tell the application that it finished, contradicting later deltas.
  app.runs = [{
    run_id: 'run-1', session: 'session-1', session_root: '/workspace/.openseek',
    model: 'deepseek-v4-pro', max_steps: 1000,
  }];
  app.event({ event: 'reasoning_delta', content: 'old connection' });
  const live = page.locator('#live-reasoning-host .activity-thinking-live');
  await expect(live).toHaveText('old connection');

  const loadsBeforeRetirement = app.requests.filter(request => request.method === 'session.load').length;
  await page.evaluate(async () => {
    const socket = window.reasoningSockets[0];
    const message = socket.onmessage.bind(socket);
    const close = socket.onclose.bind(socket);
    window.retiredReasoningCallbacks = { message, close };
    // Run close and a queued notification in the same task, before the retry
    // timer can install a replacement. Closing the real socket then cleans up
    // the test transport; its second close notification must be harmless.
    close(new CloseEvent('close'));
    socket.close();
    message(new MessageEvent('message', { data: JSON.stringify({
      jsonrpc: '2.0', method: 'agent.event', params: {
        run_id: 'run-1', session: 'session-1',
        event: { event: 'reasoning_delta', content: 'late after close' },
      },
    }) }));
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
  await expect(live).toHaveCount(0);

  await expect.poll(() => page.evaluate(() => window.reasoningSockets.length)).toBe(2);
  // agent.connected is sent by the existing fixture on each fresh socket;
  // wait for the resulting reload before starting the replacement stream.
  await expect.poll(() => app.requests.filter(request => request.method === 'session.load').length)
    .toBeGreaterThan(loadsBeforeRetirement);
  app.start();
  app.event({ event: 'reasoning_delta', content: 'current connection' });
  await expect(live).toHaveText('current connection');
  await page.evaluate(async () => {
    const { message, close } = window.retiredReasoningCallbacks;
    for (const event of [
      { event: 'reasoning_delta', content: 'stale append' },
      { event: 'reasoning_message', content: 'stale finish' },
    ]) {
      message(new MessageEvent('message', { data: JSON.stringify({
        jsonrpc: '2.0', method: 'agent.event', params: {
          run_id: 'run-1', session: 'session-1', event,
        },
      }) }));
    }
    message(new MessageEvent('message', { data: JSON.stringify({
      jsonrpc: '2.0', method: 'agent.connected', params: { stage: 'serving' },
    }) }));
    close(new CloseEvent('close'));
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
  await expect(live).toHaveText('current connection');
  expect(app.pageErrors).toEqual([]);
});
