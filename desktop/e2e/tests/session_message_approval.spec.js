import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('message approvals survive idle reload and turn completion, and advance independently', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const body = 'Benchmark is running. Continue read-only work.\n<script>plain text</script>';
  let generation = 1;
  let approvals = ['first', 'second'].map(id => ({
    id: `message-${id}`, session: 'session-1', run_id: null,
    tool_name: 'session.send', detail: `Send to target-${id}; may start or steer its task`,
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
  await expect(card).toContainText('target-first');
  expect(await card.locator('.composer-approval-body').textContent()).toBe(body);
  await expect(card.locator('script')).toHaveCount(0);

  await page.reload();
  await app.openSession();
  await expect(card).toContainText('target-first');
  await page.locator('#task').fill('Continue the current task');
  await page.locator('#send').click();
  app.notify('agent.event', {
    session: 'session-1', run_id: 'run-e2e',
    event: { event: 'agent_finished', answer: 'Done' },
  });
  app.notify('agent.finished', { run_id: 'run-e2e', status: 'finished', answer: 'Done' });
  await expect(card).toContainText('target-first');
  const screenshot = testInfo.outputPath('pending-message-after-turn.png');
  await card.screenshot({ path: screenshot });
  await testInfo.attach('Message approval after turn completion', { path: screenshot, contentType: 'image/png' });

  await card.getByRole('button', { name: 'Allow once', exact: true }).click();
  await expect(card).toContainText('target-second');
  await card.getByRole('button', { name: 'Deny', exact: true }).click();
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
    tool_name: 'session.send', detail: 'Send to another conversation', body: 'Exact message', answered: false,
  };
  const engine = {
    id: 'engine-approval', session: 'session-1', run_id: 'run-e2e',
    tool_name: 'mbtx', detail: 'Run command', body: 'command', answered: false,
  };
  app.notify('agent.approvals', { generation: 1, approvals: [engine, message] });
  const card = page.locator('.composer-approval');
  await expect(card).toContainText('mbtx');
  // Replaying a snapshot must not mutate it or duplicate either question.
  app.notify('agent.approvals', { generation: 1, approvals: [engine, message] });
  await expect(card).toHaveCount(1);
  app.notify('agent.approvals', { generation: 2, approvals: [message] });
  await expect(card).toContainText('session.send');
  expect(app.pageErrors).toEqual([]);
});
