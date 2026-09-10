import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Codex partial output and result-only calls retain pending status until completion', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{
    id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium',
    supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }],
  }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  await expect.poll(() => app.requests.some(request => request.method === 'codex.draft.open')).toBe(true);
  await page.locator('#task').fill('Check tool status');
  await page.getByTitle('Send', { exact: true }).click();
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
    await expect(row.getByRole('img', { name: 'Tool in progress' })).toBeVisible();
    await row.click();
    await expect(page.locator('.tool-result').last()).toContainText(type === 'commandExecution' ? 'Tests still running' : 'inProgress');
    app.notify('codex.notification', {
      generation: 1, method: 'item/completed',
      params: { ...turn, item: { ...item, status: 'completed' } },
    });
    await expect(row.getByRole('img', { name: 'Tool succeeded' })).toBeVisible();
    await expect(row.locator('.tool-status-spinner')).toHaveCount(0);
  }
  expect(app.pageErrors).toEqual([]);
});

for (const isError of [false, true]) {
  test(`tool status changes from a spinner to ${isError ? 'failure' : 'success'} without closing its inputs`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture tool status' } } },
      { sequence: 2, item: { kind: 'assistant', payload: {
        content: '',
        tool_calls: [
          { id: 'status-call', name: 'mbtx', arguments: JSON.stringify({
            source: 'fn main { println("status") }', description: 'Check tool status',
          }) },
          { id: 'bodyless-call', name: 'shell', arguments: '{}' },
        ],
      } } },
    ];
    await app.install();
    await app.goto();
    await app.openSession();
    const call = page.locator('#transcript details.tool-call');
    const summary = call.locator('.tool-call-summary');
    await expect(summary.getByRole('img', { name: 'Tool in progress' })).toBeVisible();
    await expect(page.locator('.tool-call-label').getByRole('img', { name: 'Tool in progress' })).toBeVisible();
    const spinner = summary.locator('.tool-status-spinner');
    // Inspect a live animation, not only a CSS class that could remain static.
    expect(await spinner.evaluate(node => node.getAnimations().some(animation =>
      animation.playState === 'running' && animation.effect.getTiming().iterations === Infinity))).toBe(true);
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await expect(spinner).toHaveCSS('animation-name', 'none');
    await page.emulateMedia({ reducedMotion: 'no-preference' });

    await summary.click();
    await call.getByText('Original JSON', { exact: true }).click();
    const originalJson = call.locator('.tool-call-tab-input').nth(1);
    await expect(originalJson).toBeChecked();
    app.notify('session.event', {
      session: 'session-1', session_root: '/workspace/.openseek', sequence: 3,
      event: { sequence: 3, item: { kind: 'tool_result', payload: {
        tool_call_id: 'status-call', tool_name: 'mbtx',
        content: isError ? 'Command failed' : 'status', is_error: isError,
        brief: isError ? 'Check failed' : 'Check succeeded',
      } } },
    });
    const status = summary.getByRole('img', { name: isError ? 'Tool failed' : 'Tool succeeded' });
    await expect(status).toBeVisible();
    await expect(status.locator('svg')).toHaveCount(1);
    await expect(summary.locator('.tool-status-spinner')).toHaveCount(0);
    await expect(call).toHaveAttribute('open', '');
    await expect(originalJson).toBeChecked();
    // Output has its own fold, but must not duplicate the request's state icon.
    await expect(page.locator('.tool-result')).toHaveCount(1);
    await expect(page.locator('.tool-result .tool-status')).toHaveCount(0);
    await expect(page.locator('.tool-call-label .tool-status-spinner')).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}
