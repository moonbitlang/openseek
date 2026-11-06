import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const prediction = (text = 'Commit the fix') => ({
  version: 1, source_sequence: 2,
  outcome: { kind: 'completed', text, input_tokens: 40, output_tokens: 8 },
});

class PredictionHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.predictionRecord = null;
    this.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture' } } },
      { sequence: 2, item: { kind: 'terminal', payload: { kind: 'finished', message: 'The fix is ready and tests pass.' } } },
    ];
  }
  replyFor(request) {
    if (request.method === 'session.load') {
      return { ...super.replyFor(request), prediction: this.predictionRecord };
    }
    return super.replyFor(request);
  }
  async finish() {
    this.notify('agent.started', { run_id: 'prediction-run', session: 'session-1', session_root: '/workspace/.openseek', model: 'deepseek-v4-flash', max_steps: 1000 });
    await expect(this.page.locator('#stop')).toBeVisible();
    this.notify('agent.finished', { run_id: 'prediction-run', status: 'finished', answer: 'The fix is ready and tests pass.', exit_code: 0 });
  }
  publish(record = prediction()) {
    this.predictionRecord = record;
    this.notify('agent.prediction', { session: 'session-1', prediction: record });
  }
  assertNoPredictionRequests() {
    expect(this.requests.filter(r => ['agent.predict', 'agent.cancel_prediction'].includes(r.method))).toEqual([]);
    expect(this.pageErrors).toEqual([]);
  }
}

async function open(page) {
  const app = new PredictionHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  return app;
}

test('accepting and clearing restores the broadcast suggestion without requests', async ({ page }) => {
  const app = await open(page);
  await app.finish();
  app.publish();
  const input = page.locator('#task');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await expect(input).toHaveValue('');
  await input.focus();
  await input.press('Shift+Tab');
  await expect(input).toHaveValue('');
  await input.focus();
  await input.press('Tab');
  await expect(input).toHaveValue('Commit the fix');
  await expect(input).toBeFocused();
  await input.fill('');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  app.assertNoPredictionRequests();
});

test('whitespace preserves the draft and lets Tab move focus', async ({ page }) => {
  const app = await open(page);
  await app.finish();
  app.publish();
  const input = page.locator('#task');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  for (const text of ['   ', '\n', '\t', '\u3000']) {
    await input.fill(text);
    await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
    await input.press('Tab');
    await expect(input).toHaveValue(text);
    await expect(input).not.toBeFocused();
    await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
    if (text !== '\u3000') await expect(page.locator('#send')).toHaveCount(0);
  }
  await input.fill('');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await input.press('Tab');
  await expect(input).toHaveValue('Commit the fix');
  app.assertNoPredictionRequests();
});

test('reopening restores the persisted broadcast without a prediction request', async ({ page }) => {
  const app = await open(page);
  await app.finish();
  app.publish();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', 'Commit the fix');
  await page.reload();
  await app.openSession();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', 'Commit the fix');
  await expect(page.locator('#task')).toHaveValue('');
  app.assertNoPredictionRequests();
});
