import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// These cases exercise the detailed transcript's reasoning and tool cards.
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('openseek.minimal_transcript', 'false'));
});

test('Codex partial output and result-only calls retain pending status until completion', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{
    id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium',
    supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }],
  }];
  await app.install();
  await app.goto();
  await page.locator('#openseek-model-picker, #codex-model-picker, #model').click();
  await page.locator('[role="option"][data-value="codex:gpt-5.4-codex"]').click();
  await expect.poll(() => app.requests.some(request => request.method === 'codex.draft.open')).toBe(true);
  await expect(page.locator('#codex-model-picker')).toHaveAttribute('data-value', 'codex:gpt-5.4-codex');
  await page.locator('#task').fill('Check tool status');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(request => request.method === 'codex.turn.start')).toBe(true);
  const turn = { threadId: 'codex-thread-e2e', turnId: 'codex-turn-e2e' };
  for (const type of ['commandExecution', 'fileChange']) {
    const item = type === 'commandExecution'
      ? { type, id: 'command', command: 'moon test', aggregatedOutput: 'Tests still running' }
      : { type, id: 'change' }; // No recorded arguments: the result owns this status.
    app.notify('codex.notification', {
      generation: 1, method: 'item/started',
      params: { ...turn, item: { ...item, status: 'inProgress' } },
    });
    const row = page.locator(type === 'commandExecution' ? '.tool-call-summary' : '.tool-result-summary').last();
    await expect(row.locator('[data-tool-status="pending"]')).toBeVisible();
    await row.click();
    await expect(page.locator('.tool-result').last()).toContainText(type === 'commandExecution' ? 'Tests still running' : 'inProgress');
    app.notify('codex.notification', {
      generation: 1, method: 'item/completed',
      params: { ...turn, item: { ...item, status: 'completed' } },
    });
    await expect(row.locator('[data-tool-status="succeeded"]')).toBeVisible();
    await expect(row.locator('.tool-status-spinner')).toHaveCount(0);
  }
  expect(app.pageErrors).toEqual([]);
});

test('tool success and failure preserve each call’s selected inputs and independent status', { tag: '@motion' }, async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const outcomes = [
    { id: 'success-call', isError: false, description: 'Successful check' },
    { id: 'failure-call', isError: true, description: 'Failing check' },
  ];
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture tool status' } } },
    { sequence: 2, item: { kind: 'assistant', payload: {
      content: '',
      tool_calls: [
        ...outcomes.map(({ id, description }) => ({
          id, name: 'mbtx', arguments: JSON.stringify({ source: 'fn main { println("status") }', description }),
        })),
        { id: 'bodyless-call', name: 'shell', arguments: '{}' },
      ],
    } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  const calls = page.locator('#transcript details.tool-call');
  await expect(calls).toHaveCount(2);
  await expect(calls.locator('[data-tool-status="pending"]')).toHaveCount(2);
  const spinner = calls.first().locator('.tool-status-spinner');
  expect(await spinner.evaluate(node => node.getAnimations().some(animation =>
    animation.playState === 'running' && animation.effect.getTiming().iterations === Infinity))).toBe(true);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(spinner).toHaveCSS('animation-name', 'none');
  await page.emulateMedia({ reducedMotion: 'no-preference' });

  for (const [index, { id, isError, description }] of outcomes.entries()) {
    const call = calls.nth(index);
    const summary = call.locator('.tool-call-summary');
    await expect(summary.locator('[data-tool-status="pending"]')).toBeVisible();
    await summary.click();
    await call.locator('label[data-tool-tab="original-json"]').click();
    const originalJson = call.locator('input[data-tool-tab-input="original-json"]');
    await expect(originalJson).toBeChecked();
    const sequence = 3 + index;
    app.notify('session.event', {
      session: 'session-1', session_root: '/workspace/.openseek', sequence,
      event: { sequence, item: { kind: 'tool_result', payload: {
        tool_call_id: id, tool_name: 'mbtx',
        content: isError ? 'Command failed' : 'status', is_error: isError,
        ...(isError ? { brief: 'mbtx build' } : {}),
      } } },
    });
    await expect(summary).toContainText(description);
    await expect(summary.locator(`[data-tool-status="${isError ? 'failed' : 'succeeded'}"]`)).toBeVisible();
    await expect(summary.locator('[data-tool-status="pending"]')).toHaveCount(0);
    await expect(call).toHaveAttribute('open', '');
    await expect(originalJson).toBeChecked();
    const results = page.locator('#transcript .tool-result');
    await expect(results).toHaveCount(index + 1);
    await expect(results.last().locator('[data-tool-status]:not([data-tool-status="snapshot"])')).toHaveCount(0);
    if (isError) {
      await expect(summary).toContainText('build');
      await expect(results.last().locator('.tool-stage-build')).toBeVisible();
    }
    await expect(page.locator('.tool-call-label').locator('[data-tool-status="pending"]')).toBeVisible();
  }
  // The second result must not overwrite the first call's outcome or tab choice.
  await expect(calls.first().locator('[data-tool-status="succeeded"]')).toBeVisible();
  await expect(calls.first().locator('input[data-tool-tab-input="original-json"]')).toBeChecked();
  expect(app.pageErrors).toEqual([]);
});
