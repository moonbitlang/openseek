import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('message approvals survive idle reload and turn completion, and advance independently', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push(
    { id: 'target-first', title: 'Test B', updated_at_ms: 0 },
    { id: 'target-second', title: 'Test C', updated_at_ms: 0 },
  );
  const body = 'Benchmark is running. Continue read-only work.\n<script>plain text</script>';
  let generation = 1;
  let approvals = ['first', 'second'].map(id => ({
    id: `message-${id}`, session: 'session-1', run_id: null,
    tool_name: 'session.send', detail: `target-${id}`,
    body, answered: false,
  }));
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'agent.runs') {
      return { runs: [], settled: [], approval_generation: generation, approvals };
    }
    if (request.method === 'agent.approval') {
      expect(request.params.run_id ?? null).toBeNull();
      approvals = approvals.filter(item => item.id !== request.params.id);
      app.notify('agent.approvals', { generation: ++generation, approvals });
      return { delivered: true };
    }
    return replyFor(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.composer-approval');
  await expect(card).toContainText('Send to “Test B”');
  await expect(card.locator('.composer-notice-text')).toHaveAttribute('title', 'target-first');
  await expect(card).not.toContainText('session.send');
  await expect(card.locator('.composer-approval-message')).toHaveCSS('font-family', await page.locator('body').evaluate(node => getComputedStyle(node).fontFamily));
  expect(await card.locator('.composer-approval-body').textContent()).toBe(body);
  await expect(card.locator('script')).toHaveCount(0);

  await page.reload();
  await app.openSession();
  await expect(card).toContainText('Send to “Test B”');
  await page.locator('#task').fill('Continue the current task');
  await page.locator('#send').click();
  app.notify('agent.event', {
    session: 'session-1', run_id: 'run-e2e',
    event: { event: 'agent_finished', answer: 'Done' },
  });
  app.notify('agent.finished', { run_id: 'run-e2e', status: 'finished', answer: 'Done' });
  await expect(card).toContainText('Send to “Test B”');
  const screenshot = testInfo.outputPath('pending-message-after-turn.png');
  await card.screenshot({ path: screenshot });
  await testInfo.attach('Message approval after turn completion', { path: screenshot, contentType: 'image/png' });

  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card).toContainText('Send to “Test C”');
  await card.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(card).toHaveCount(0);
  expect(app.requests.filter(item => item.method === 'agent.approval').map(item => ({
    id: item.params.id, allow: item.params.allow,
  }))).toEqual([
    { id: 'message-first', allow: true },
    { id: 'message-second', allow: false },
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('a running engine approval takes priority over a background message approval', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await page.locator('#task').fill('Start');
  await page.locator('#send').click();
  const message = {
    id: 'msg-background', session: 'session-1', run_id: null,
    tool_name: 'session.send', detail: 'target-chat', body: 'Exact message', answered: false,
  };
  const engine = {
    id: 'engine-approval', session: 'session-1', run_id: 'run-e2e',
    tool_name: 'mbtx', detail: 'Run command', body: 'command', answered: false,
  };
  app.notify('agent.approvals', { generation: 1, approvals: [engine, message] });
  const card = page.locator('.composer-approval');
  await expect(card).toContainText('mbtx');
  await expect(card.getByRole('button', { name: 'Allow once', exact: true })).toBeVisible();
  // Replaying a snapshot must not mutate it or duplicate either question.
  app.notify('agent.approvals', { generation: 1, approvals: [engine, message] });
  await expect(card).toHaveCount(1);
  app.notify('agent.approvals', { generation: 2, approvals: [message] });
  await expect(card).toContainText('Send to “target-chat”');
  expect(app.pageErrors).toEqual([]);
});

test('received messages and delivery results render tagged context live and after reload', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const text = '这是跨会话审批测试，请确认收到。\n`inline code` <script>plain text</script>';
  const message = `<agent_message source_session="chat-A" message_id="msg-1">\n${text}\n</agent_message>`;
  const result = '<session_message_result message_id="msg-2" request_id="request-2" target="chat-B" status="sent">\n\n</session_message_result>';
  const event = (sequence, content) => ({ sequence, ts: 1792050660000, item: { kind: 'user', payload: { content } } });
  app.sessionEvents = [event(1, message)];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
  const received = page.locator('.session-message').first();
  await expect(received.locator('.session-message-source')).toHaveText('Message from another conversation');
  await expect(received.locator('.session-message-source')).toHaveAttribute('title', 'chat-A');
  await expect(received.locator('.msg-content')).toHaveText(text.replaceAll('`', ''));
  await expect(received.locator('script')).toHaveCount(0);
  await expect(page.locator('#stream')).not.toContainText('source_session=');
  await expect(page.locator('#stream')).not.toContainText('user approved');
  const next = event(2, result);
  app.sessionEvents.push(next);
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 2, event: next });
  await expect(page.locator('.session-message-source').last()).toHaveText('Message sent');
  const screenshot = testInfo.outputPath('received-session-message.png');
  await page.locator('#stream').screenshot({ path: screenshot });
  await testInfo.attach('Received session message', { path: screenshot, contentType: 'image/png' });
  await page.reload();
  await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
  await expect(page.locator('.session-message')).toHaveCount(2);
  await expect(received.locator('.msg-content')).toHaveText(text.replaceAll('`', ''));
  await expect(page.locator('.session-message-source').last()).toHaveText('Message sent');
  expect(app.pageErrors).toEqual([]);
});

for (const running of [false, true]) {
  test(`delivery feedback failures remain session-scoped with an ${running ? 'active' : 'idle'} sender`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.liveSessions.push({ id: 'session-2', title: 'Another conversation', updated_at_ms: 2 });
    const replyFor = app.replyFor.bind(app);
    app.replyFor = request => {
      const reply = replyFor(request);
      if (request.method === 'session.load') {
        reply.session.id = request.params.session;
      }
      return reply;
    };
    await app.install();
    await app.goto();
    await app.openSession();
    if (running) {
      await page.locator('#task').fill('Continue the task');
      await page.locator('#send').click();
      await expect(page.locator('#stop')).toBeVisible();
    }
    await page.locator('.conversation-row[title="session-2"]').click();
    await expect(page.locator('main > .topbar h1')).toHaveText('Another conversation');
    const status = page.locator('main > .topbar .run-status');
    const before = await status.textContent();
    app.notify('agent.event', {
      session: 'session-1', run_id: null,
      event: { event: 'session_error', error: 'Could not deliver message result: the sender is unavailable' },
    });
    await expect(page.getByText('the engine could not save an item to this session: Could not deliver message result: the sender is unavailable', { exact: true })).toBeVisible();
    await expect(status).toHaveText(before);
    await expect(page.locator('#stop')).toBeHidden();
    await page.locator('.conversation-row[title="session-1"]').click();
    if (running) {
      await expect(page.locator('#stop')).toBeVisible();
    } else {
      await expect(page.locator('#stop')).toBeHidden();
    }
    expect(app.pageErrors).toEqual([]);
  });
}
